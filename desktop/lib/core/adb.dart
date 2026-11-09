import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class BeamException implements Exception {
  final String message;
  final String details;
  const BeamException(this.message, [this.details = '']);
  @override
  String toString() => message;
}

class Device {
  final String serial, state, model;
  const Device(this.serial, this.state, this.model);
  bool get ready => state == 'device';
  bool get wireless =>
      serial.contains(':') || serial.contains('_adb-tls-connect');
  String get label => model.replaceAll('_', ' ');
}

class Service {
  final String name, type, address;
  const Service(this.name, this.type, this.address);
  bool get pairing => type.contains('pairing');
  String get host => address.startsWith('[')
      ? address.substring(0, address.indexOf(']') + 1)
      : address.substring(0, address.lastIndexOf(':'));
}

class RemoteFile {
  final String path, name;
  final bool directory, link;
  final int size;
  final String modified;
  const RemoteFile(
    this.path,
    this.name,
    this.directory,
    this.link,
    this.size,
    this.modified,
  );
}

String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
String safeRemotePath(String path, {bool destructive = false}) {
  if (!path.startsWith('/') || path.contains('\u0000') || path.contains('\n')) {
    throw const BeamException('Use an absolute device path.');
  }
  final normalized = p.posix.normalize(path);
  const roots = [
    '/',
    '/sdcard',
    '/storage',
    '/storage/emulated',
    '/storage/emulated/0',
    '/system',
    '/vendor',
    '/data',
    '/data/media',
    '/data/media/0',
  ];
  if (destructive && roots.contains(normalized)) {
    throw const BeamException(
      'This location is protected. Select a file or subfolder.',
    );
  }
  return normalized;
}

List<Device> parseDevices(String output) => output
    .split('\n')
    .where(
      (line) =>
          line.trim().isNotEmpty &&
          !line.startsWith('List ') &&
          !line.startsWith('*'),
    )
    .map((line) {
      final parts = line.trim().split(RegExp(r'\s+'));
      final model = parts.where((s) => s.startsWith('model:')).firstOrNull;
      return Device(
        parts.first,
        parts.length > 1 ? parts[1] : 'unknown',
        model?.substring(6) ?? parts.first,
      );
    })
    .toList();

List<Service> parseServices(String output) {
  final result = <Service>[];
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 3 &&
        parts[1].contains('_adb-tls-') &&
        parts[2].contains(':')) {
      result.add(
        Service(parts[0], parts[1].replaceAll(RegExp(r'\.$'), ''), parts[2]),
      );
    }
  }
  return result;
}

class CommandTask {
  final Process process;
  final Future<String> output;
  bool cancelled = false;
  CommandTask(this.process, this.output);
  Future<void> cancel() async {
    cancelled = true;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }
}

class Adb {
  String executable = 'adb';
  String scrcpy = 'scrcpy';
  String server = '';
  String serverVersion = '';
  final Set<Process> _owned = {};
  bool closed = false;

  Future<void> initialize({String? customPath}) async {
    final roots = [
      p.dirname(Platform.resolvedExecutable),
      Directory.current.path,
      p.dirname(Directory.current.path),
      if (Platform.environment['BEAMADB_HOME'] != null)
        Platform.environment['BEAMADB_HOME']!,
    ];
    final platform = Platform.isWindows ? 'windows' : 'linux';
    final suffix = Platform.isWindows ? '.exe' : '';
    for (final root in roots) {
      final dir = p.join(root, 'bin', 'scrcpy', platform);
      if (File(p.join(dir, 'adb$suffix')).existsSync()) {
        executable = p.join(dir, 'adb$suffix');
        scrcpy = p.join(dir, 'scrcpy$suffix');
        server = p.join(dir, 'scrcpy-server');
        break;
      }
    }
    if (customPath != null && customPath.isNotEmpty) executable = customPath;
    await run(['version']);
    try {
      final r = await Process.run(scrcpy, [
        '--version',
      ]).timeout(const Duration(seconds: 5));
      serverVersion =
          RegExp(r'scrcpy (\S+)').firstMatch(r.stdout.toString())?.group(1) ??
          '';
    } catch (_) {
      /* Device management remains usable without media tools. */
    }
  }

  Future<Process> spawn(List<String> args) async {
    if (closed) throw const BeamException('The application is shutting down.');
    try {
      final process = await Process.start(executable, args, runInShell: false);
      _owned.add(process);
      unawaited(process.exitCode.then((_) => _owned.remove(process)));
      return process;
    } on ProcessException catch (e) {
      throw BeamException(
        'ADB could not start. Check the tool path in Settings.',
        e.message,
      );
    }
  }

  Future<CommandTask> start(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
    void Function(String)? onOutput,
  }) async {
    final process = await spawn(args);
    final chunks = <String>[];
    void collect(String chunk) {
      chunks.add(chunk);
      if (chunks.length > 5000) chunks.removeAt(0);
      onOutput?.call(chunk);
    }

    final outDone = Completer<void>();
    final errDone = Completer<void>();
    final out = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          collect,
          onDone: () => outDone.complete(),
          onError: outDone.completeError,
        );
    final err = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          collect,
          onDone: () => errDone.complete(),
          onError: errDone.completeError,
        );
    late CommandTask task;
    final result = () async {
      try {
        final code = await process.exitCode.timeout(timeout);
        await Future.wait([outDone.future, errDone.future]).timeout(timeout);
        if (task.cancelled) {
          throw const BeamException(
            'Operation cancelled. Partial output may remain.',
          );
        }
        final text = chunks.join().trim();
        if (code != 0) throw explainError(text, code);
        validateCommandResult(args, text);
        return text;
      } on TimeoutException {
        process.kill();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        process.kill(ProcessSignal.sigkill);
        throw BeamException(
          'The device did not respond in time. Check its connection and retry.',
          chunks.join(),
        );
      } finally {
        await out.cancel();
        await err.cancel();
      }
    }();
    task = CommandTask(process, result);
    return task;
  }

  Future<String> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async => (await start(args, timeout: timeout)).output;
  Future<String> shell(
    String device,
    String command, {
    Duration timeout = const Duration(seconds: 20),
  }) => run(['-s', device, 'shell', command], timeout: timeout);
  Future<List<Device>> devices() async =>
      parseDevices(await run(['devices', '-l']));
  Future<List<Service>> services() async =>
      parseServices(await run(['mdns', 'services']));

  Future<void> connect(String address) async {
    validateAddress(address);
    final result = await run(['connect', address]);
    if (RegExp(
          r'failed|cannot|unable|refused|error',
          caseSensitive: false,
        ).hasMatch(result) ||
        !result.contains('connected to')) {
      throw BeamException(
        'Could not connect. Verify the connection port and Wi-Fi network.',
        result,
      );
    }
    final list = await devices();
    if (!list.any((d) => d.serial == address && d.ready)) {
      throw BeamException(
        'Connection requested, but the device is not ready. Check authorization on the phone.',
        result,
      );
    }
  }

  Future<void> pair(String address, String code) async {
    validateAddress(address);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const BeamException('Enter the six-digit pairing code.');
    }
    final result = await run(['pair', address, code]);
    if (!result.contains('Successfully paired')) {
      throw BeamException(
        'Pairing failed. Generate a fresh code on the phone.',
        result,
      );
    }
  }

  Future<List<RemoteFile>> listFiles(String device, String path) async {
    path = safeRemotePath(path);
    // NUL-delimited records preserve spaces, quotes and newlines in filenames.
    final command =
        'for f in ${shellQuote(path)}/* ${shellQuote(path)}/.[!.]* ${shellQuote(path)}/..?*; do '
        '[ -e "\$f" ] || [ -L "\$f" ] || continue; '
        'stat -c "%F|%s|%Y" -- "\$f" || exit; printf "%s\\0" "\$f"; done';
    // First verify directory access: an empty glob must not conceal a permission error.
    await shell(
      device,
      'test -d ${shellQuote(path)} && ls -d ${shellQuote(path)} >/dev/null && test -r ${shellQuote(path)}',
    );
    final output = await shell(device, command);
    final files = <RemoteFile>[];
    for (final record in output.split('\u0000')) {
      if (record.trim().isEmpty) continue;
      final newline = record.indexOf('\n');
      if (newline < 0) continue;
      final fields = record.substring(0, newline).split('|');
      if (fields.length != 3) continue;
      final full = record.substring(newline + 1);
      files.add(
        RemoteFile(
          full,
          p.posix.basename(full),
          fields[0] == 'directory',
          fields[0] == 'symbolic link',
          int.tryParse(fields[1]) ?? 0,
          fields[2],
        ),
      );
    }
    files.sort(
      (a, b) => a.directory == b.directory
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.directory
          ? -1
          : 1,
    );
    return files;
  }

  Future<void> delete(String device, String path) async {
    path = safeRemotePath(path, destructive: true);
    final resolved = (await shell(
      device,
      'readlink -f ${shellQuote(path)}',
    )).trim();
    safeRemotePath(resolved, destructive: true);
    await shell(device, 'rm -rf -- ${shellQuote(path)}');
  }

  Future<void> close() async {
    closed = true;
    for (final process in _owned.toList()) {
      process.kill();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final process in _owned.toList()) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}

void validateAddress(String address) {
  if (!RegExp(
    r'^(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9_.-]+):\d{1,5}$',
  ).hasMatch(address)) {
    throw const BeamException(
      'Enter an address and port, such as 192.168.1.12:37123.',
    );
  }
  final port = int.parse(address.substring(address.lastIndexOf(':') + 1));
  if (port < 1 || port > 65535) {
    throw const BeamException('Port must be between 1 and 65535.');
  }
}

BeamException explainError(String detail, int code) {
  final lower = detail.toLowerCase();
  String message =
      'The operation failed (exit $code). Review the details and retry.';
  if (lower.contains('unauthorized')) {
    message = 'Unlock your phone and approve USB debugging.';
  } else if (lower.contains('offline') ||
      lower.contains('no devices') ||
      lower.contains('not found')) {
    message = 'The device is unavailable. Reconnect it and try again.';
  } else if (lower.contains('permission denied')) {
    message = 'Android denied access to this location or operation.';
  } else if (lower.contains('no space left')) {
    message = 'Storage is full. Free some space and retry.';
  } else if (lower.contains('install_failed')) {
    message =
        'Android could not install this app. See the installation reason below.';
  }
  return BeamException(message, detail);
}

void validateCommandResult(List<String> args, String output) {
  final command = args.join(' ');
  final install =
      args.contains('install') ||
      args.contains('install-multiple') ||
      args.contains('uninstall');
  final instrumentation = command.contains('am instrument');
  if ((install && RegExp(r'Failure\s*\[').hasMatch(output)) ||
      (instrumentation &&
          RegExp(
            r'FAILURES!!!|INSTRUMENTATION_FAILED|INSTRUMENTATION_ABORTED|shortMsg=|Process crashed|INSTRUMENTATION_RESULT:.*Error',
          ).hasMatch(output))) {
    throw BeamException(
      instrumentation
          ? 'The test run failed. Review the test output.'
          : 'Android rejected the app operation.',
      output,
    );
  }
}
