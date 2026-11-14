import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mirror_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'adb.dart';
import 'friendly_error.dart';
import 'media_session.dart';

class LinkSetupProgress {
  final int step;
  final String status;
  final bool isDone;
  final String? error;

  const LinkSetupProgress({
    required this.step,
    required this.status,
    this.isDone = false,
    this.error,
  });
}

class Activity {
  final String title;
  final String device;
  final DateTime time = DateTime.now();
  String state = 'Running', detail = '';
  Future<void> Function()? cancel;
  Activity(this.title, this.device);
}

class PhoneSummary {
  final String id, name;
  final List<Device> connections;
  final String? battery, lastSeen;
  const PhoneSummary(
    this.id,
    this.name,
    this.connections,
    this.battery,
    this.lastSeen,
  );
  bool get online => connections.any((d) => d.ready);
  Device? get preferred {
    final ready = connections.where((d) => d.ready).toList()
      ..sort((a, b) => a.routePriority.compareTo(b.routePriority));
    return ready.firstOrNull ?? connections.firstOrNull;
  }
}

class AppStore extends ChangeNotifier {
  final Adb adb;
  AppStore({Adb? adb}) : adb = adb ?? Adb();
  List<Device> devices = [];
  final Map<String, Map<String, String>> savedPhones = {};
  final Map<String, String> phoneRoutes = {};
  final Map<String, String> removedPhones = {};
  List<PhoneSummary> get phones {
    final groups = <String, List<Device>>{};
    for (final d in devices) {
      final id = phoneRoutes[d.serial] ?? d.serial;
      if (!removedPhones.containsKey(id)) {
        groups.putIfAbsent(id, () => []).add(d);
      }
    }
    for (final id in savedPhones.keys) {
      if (!removedPhones.containsKey(id)) groups.putIfAbsent(id, () => []);
    }
    final result = groups.entries.map((entry) {
      final saved = savedPhones[entry.key] ?? {};
      return PhoneSummary(
        entry.key,
        saved['name'] ??
            saved['model'] ??
            entry.value.firstOrNull?.label ??
            entry.key,
        entry.value,
        saved['battery'],
        saved['lastSeen'],
      );
    }).toList();
    result.sort((a, b) {
      final status = (b.online ? 1 : 0) - (a.online ? 1 : 0);
      return status != 0 ? status : a.name.compareTo(b.name);
    });
    return result;
  }

  Future<void> savePhones() async {
    await preferences?.setString(
      'phoneRoster',
      jsonEncode({
        'phones': savedPhones,
        'routes': phoneRoutes,
        'removed': removedPhones,
      }),
    );
  }

  Future<void> renamePhone(String id, String name) async {
    savedPhones.putIfAbsent(id, () => {})['name'] = name.trim();
    await savePhones();
    emit();
  }

  final Map<String, String> linkSetup = {};
  final Map<String, LinkSetupProgress> linkProgress = {};
  final Set<String> _onboarding = {};
  final Map<String, DateTime> _removalAttempts = {};
  bool get autoSetup => preferences?.getBool('autoSetup') ?? false;
  Future<void> setAutoSetup(bool value) async {
    await preferences?.setBool('autoSetup', value);
    emit();
  }

  bool isPhoneLinked(PhoneSummary phone) {
    if (phone.connections.any((d) => d.relay)) return true;
    for (final entry in phoneRoutes.entries) {
      if (entry.key.startsWith('127.0.0.1:') && entry.value == phone.id) {
        return true;
      }
    }
    return false;
  }

  void markInternetVerified(String serial) {
    if (!serial.startsWith('127.0.0.1:')) return;
    final identity = phoneRoutes[serial];
    if (identity == null || removedPhones.containsKey(identity)) return;
    for (final route in phoneRoutes.entries.where(
      (entry) => entry.value == identity,
    )) {
      if (!_onboarding.contains(route.key)) {
        linkSetup[route.key] = 'Internet connection verified';
      }
    }
  }

  Future<void> setupPhone(
    String serial, {
    bool retry = false,
    void Function(LinkSetupProgress)? onProgress,
  }) async {
    if (serial.startsWith('127.0.0.1:') || _onboarding.contains(serial)) return;
    if (!retry && linkSetup.containsKey(serial)) {
      if (!removedPhones.containsKey(phoneRoutes[serial])) return;
      final last = _removalAttempts[serial];
      if (last != null && DateTime.now().difference(last).inSeconds < 30) {
        return;
      }
    }
    if (removedPhones.containsKey(phoneRoutes[serial])) {
      _removalAttempts[serial] = DateTime.now();
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    var script = File('$exeDir/remote/onboard.py');
    if (!await script.exists()) {
      script = File('remote/onboard.py');
    }
    final root =
        Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    if (!await script.exists() ||
        !await File('$root/beamadb-link/invite.json').exists()) {
      const msg = 'Relay not configured. Set up in Connect device → Remote.';
      linkSetup[serial] = msg;
      final prog = const LinkSetupProgress(
        step: 1,
        status: msg,
        error: msg,
      );
      linkProgress[serial] = prog;
      onProgress?.call(prog);
      emit();
      return;
    }
    _onboarding.add(serial);
    linkSetup[serial] = 'Starting permanent Link setup…';
    final initialProg = const LinkSetupProgress(
      step: 1,
      status: 'Checking device connection & authorization…',
    );
    linkProgress[serial] = initialProg;
    onProgress?.call(initialProg);
    emit();

    try {
      final process = await Process.start('python3', [
        script.path,
        '--serial',
        serial,
        '--adb',
        adb.executable,
      ]);

      String lastOutput = '';
      String errorOutput = '';

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((err) => errorOutput += '$err\n');

      await for (final line in process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        lastOutput = line;
        if (line.startsWith('STEP:')) {
          final parts = line.split(':');
          final step = int.tryParse(parts[1]) ?? 1;
          final msg = parts.sublist(2).join(':');
          final prog = LinkSetupProgress(step: step, status: msg);
          linkProgress[serial] = prog;
          linkSetup[serial] = msg;
          onProgress?.call(prog);
          emit();
        } else if (line.startsWith('DONE:')) {
          final msg = line.substring(5);
          final prog = LinkSetupProgress(step: 6, status: msg, isDone: true);
          linkProgress[serial] = prog;
          linkSetup[serial] = 'Internet connection verified';
          onProgress?.call(prog);
          emit();
        }
      }

      final exitCode = await process.exitCode;
      final removedId = phoneRoutes[serial];
      if (removedPhones.containsKey(removedId)) {
        removedPhones[removedId!] = lastOutput.trim();
        await savePhones();
      }

      if (exitCode == 0) {
        linkSetup[serial] = 'Internet connection verified';
        final prog = const LinkSetupProgress(
          step: 6,
          status: 'Permanent Link is active!',
          isDone: true,
        );
        linkProgress[serial] = prog;
        onProgress?.call(prog);
        await refresh();
      } else {
        final errText = errorOutput.trim().isNotEmpty
            ? errorOutput
            : (lastOutput.trim().isNotEmpty ? lastOutput : 'Setup failed');
        final friendly = FriendlyError.parse(errText, 'Link Setup Incomplete');
        final prog = LinkSetupProgress(
          step: linkProgress[serial]?.step ?? 1,
          status: friendly.description,
          error: friendly.summary,
        );
        linkProgress[serial] = prog;
        linkSetup[serial] = friendly.description;
        onProgress?.call(prog);
      }
    } catch (e) {
      final friendly = FriendlyError.parse(e, 'Link Setup Error');
      final prog = LinkSetupProgress(
        step: 1,
        status: friendly.description,
        error: friendly.summary,
      );
      linkProgress[serial] = prog;
      linkSetup[serial] = friendly.description;
      onProgress?.call(prog);
    } finally {
      _onboarding.remove(serial);
      emit();
    }
  }

  bool get connectionNotifications =>
      preferences?.getBool('connectionNotifications') ?? true;
  Future<void> setConnectionNotifications(bool enabled) async {
    final root =
        Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    final folder = Directory('$root/beamadb-link');
    await folder.create(recursive: true);
    final temporary = File('${folder.path}/notifications.json.tmp');
    await temporary.writeAsString(jsonEncode({'enabled': enabled}));
    await temporary.rename('${folder.path}/notifications.json');
    await preferences?.setBool('connectionNotifications', enabled);
    emit();
  }

  Future<void> removePhone(PhoneSummary phone) async {
    await operation('Remove ${phone.name}', (item) async {
      if (!phoneRoutes.containsValue(phone.id)) {
        throw const BeamException(
          'Connect this phone first so its identity can be verified.',
        );
      }
      final route =
          phone.connections
              .where((d) => d.ready && !d.serial.startsWith('127.0.0.1:'))
              .firstOrNull ??
          phone.connections.where((d) => d.ready).firstOrNull;
      for (final connection in phone.connections) {
        await mirrors[connection.serial]?.stop();
        for (final session in sessions.values.where(
          (s) => s.device == connection.serial,
        )) {
          await session.stop();
        }
      }
      final script =
          '${File(Platform.resolvedExecutable).parent.path}/remote/remove_device.py';
      final result = await Process.run('python3', [
        script,
        '--identity',
        phone.id,
        '--adb',
        adb.executable,
        if (route != null) ...['--serial', route.serial],
      ]);
      if (result.exitCode != 0) throw BeamException('${result.stdout}'.trim());
      final note = '${result.stdout}'.trim();
      removedPhones[phone.id] = note;
      savedPhones.remove(phone.id);
      for (final connection in phone.connections) {
        linkSetup.remove(connection.serial);
        if (connection.serial == selected) selected = null;
      }
      item.detail = note;
      await savePhones();
      emit();
    }, target: phone.name);
  }

  List<Service> discovered = [];
  String? selected;
  String? startupError;
  String? discoveryError;
  bool initialized = false, scanning = false, disposed = false;
  final List<Activity> activities = [];
  final Map<String, MediaSession> sessions = {};
  final Map<String, MirrorWindow> mirrors = {};
  final Set<String> _openingMirrors = {};

  Future<void> openMirror({
    int quality = 1920,
    int fps = 60,
    int bitrate = 8000000,
    bool stayAwake = true,
  }) async {
    final serial = selected;
    if (serial == null || !ready) return;
    reconcileSelection();
    final mirrorSerial = selected ?? serial;
    if (mirrorSerial != serial) select(mirrorSerial);
    final identity = phoneRoutes[mirrorSerial];
    final existing =
        mirrors[mirrorSerial] ??
        mirrors.values
            .where(
              (mirror) =>
                  mirror.open &&
                  identity != null &&
                  phoneRoutes[mirror.device] == identity,
            )
            .firstOrNull;
    if (existing?.open == true) {
      existing!.command('focus');
      return;
    }
    if (!_openingMirrors.add(mirrorSerial)) return;
    try {
      await operation('Open screen mirror', (_) async {
        final process = await Process.start(
          Platform.resolvedExecutable,
          [
            '--session',
            mirrorSerial,
            'screen',
            '--mirror-options=${base64Url.encode(utf8.encode(jsonEncode({'quality': quality, 'fps': fps, 'bitrate': bitrate, 'stayAwake': stayAwake})))}',
          ],
          environment: {
            'BEAMADB_HOME':
                Platform.environment['BEAMADB_HOME'] ??
                Directory.current.parent.path,
          },
        );
        final mirror = MirrorWindow(mirrorSerial, process);
        mirrors[mirrorSerial] = mirror;
        cleanups.add(mirror.stop);
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              mirror.update(line);
              emit();
            });
        unawaited(process.stderr.drain<void>());
        unawaited(
          process.exitCode.then((code) {
            mirror.open = false;
            if (code != 0 && mirror.status != 'Failed') {
              mirror.status = 'Failed';
              mirror.detail = 'Mirror window closed unexpectedly (exit $code).';
            } else if (mirror.status != 'Failed') {
              mirror.status = 'Stopped';
            }
            cleanups.remove(mirror.stop);
            emit();
          }),
        );
      });
    } finally {
      _openingMirrors.remove(mirrorSerial);
    }
  }

  final Set<Future<void> Function()> cleanups = {};
  final Map<String, Map<String, String>> metadata = {};
  final Map<String, DateTime> _metadataAt = {};
  final Set<String> _metadataPending = {};
  ThemeMode themeMode = ThemeMode.system;
  bool reducedMotion = false;
  bool get ready => device?.ready ?? false;
  Device? get device => devices.where((d) => d.serial == selected).firstOrNull;
  SharedPreferences? preferences;
  Timer? _timer;

  Future<void> initialize() async {
    try {
      preferences = await SharedPreferences.getInstance();
      try {
        final roster =
            jsonDecode(preferences?.getString('phoneRoster') ?? '{}') as Map;
        for (final entry in ((roster['phones'] ?? {}) as Map).entries) {
          savedPhones[entry.key as String] = Map<String, String>.from(
            entry.value as Map,
          );
        }
        removedPhones.addAll(
          Map<String, String>.from((roster['removed'] ?? {}) as Map),
        );
        phoneRoutes.addAll(
          Map<String, String>.from((roster['routes'] ?? {}) as Map),
        );
      } catch (_) {
        /* Ignore malformed saved device data. */
      }
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == preferences?.getString('theme'),
        orElse: () => ThemeMode.system,
      );
      reducedMotion = preferences?.getBool('reducedMotion') ?? false;
      await adb.initialize(customPath: preferences?.getString('adbPath'));
      initialized = true;
      startupError = null;
      await refresh();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    } catch (e) {
      startupError = '$e';
    }
    emit();
  }

  void emit() {
    if (!disposed) notifyListeners();
  }

  void select(String serial) {
    selected = serial;
    emit();
    unawaited(loadMetadata(serial));
  }

  // Keep selection on the same physical phone when its network transport changes.
  void reconcileSelection() {
    if (selected == null) {
      selected =
          devices.where((d) => d.ready).firstOrNull?.serial ??
          devices.firstOrNull?.serial;
      return;
    }
    final identity = phoneRoutes[selected];
    if (identity == null) return;
    final routes =
        devices
            .where((d) => d.ready && phoneRoutes[d.serial] == identity)
            .toList()
          ..sort((a, b) => a.routePriority.compareTo(b.routePriority));
    if (routes.isNotEmpty) selected = routes.first.serial;
  }

  final Set<String> _routeChecks = {};
  final Set<String> _unresponsiveRoutes = {};
  Future<void> verifyLocalRoute(String serial) async {
    final identity = phoneRoutes[serial];
    if (identity == null || !_routeChecks.add(serial)) return;
    try {
      final found = await adb.shell(
        serial,
        'getprop ro.serialno',
        timeout: const Duration(seconds: 3),
      );
      if (found.trim() != identity) {
        throw const BeamException('Device identity changed');
      }
      _unresponsiveRoutes.remove(serial);
    } catch (_) {
      _unresponsiveRoutes.add(serial);
      devices = devices
          .map(
            (d) =>
                d.serial == serial ? Device(d.serial, 'offline', d.model) : d,
          )
          .toList();
      reconcileSelection();
      emit();
    } finally {
      _routeChecks.remove(serial);
    }
  }

  final Map<String, DateTime> _localDiscoveryAt = {};
  final Set<String> _localDiscoveryPending = {};
  Future<void> discoverLocalRoute(String relaySerial) async {
    final identity = phoneRoutes[relaySerial];
    if (identity == null ||
        removedPhones.containsKey(identity) ||
        !_localDiscoveryPending.add(relaySerial)) {
      return;
    }
    try {
      final last = _localDiscoveryAt[relaySerial];
      if (last != null && DateTime.now().difference(last).inSeconds < 20) {
        return;
      }
      _localDiscoveryAt[relaySerial] = DateTime.now();
      final info = await adb.shell(
        relaySerial,
        'ip -o -4 addr show wlan0; getprop service.adb.tcp.port; getprop service.adb.tls.port',
        timeout: const Duration(seconds: 4),
      );
      final ip = RegExp(r'inet ([0-9.]+)/').firstMatch(info)?.group(1);
      final ports = info
          .split('\n')
          .map((line) => int.tryParse(line.trim()))
          .whereType<int>()
          .where((port) => port > 1024 && port <= 65535)
          .toList();
      if (ip == null || ports.isEmpty) return;
      final port = ports.contains(45885) ? 45885 : ports.last;
      final address = '$ip:$port';
      if (devices.any(
        (d) => d.ready && !d.relay && phoneRoutes[d.serial] == identity,
      )) {
        return;
      }
      final probe = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 2),
      );
      probe.destroy();
      await adb.run(['connect', address], timeout: const Duration(seconds: 4));
      final found = await adb.shell(
        address,
        'getprop ro.serialno',
        timeout: const Duration(seconds: 4),
      );
      if (found.trim() == identity) {
        phoneRoutes[address] = identity;
        await loadMetadata(address);
      }
    } catch (_) {
      // An isolated Wi-Fi, different LAN, or expired address keeps the relay in use.
    } finally {
      _localDiscoveryPending.remove(relaySerial);
    }
  }

  Future<void> refresh() async {
    if (scanning || disposed) return;
    scanning = true;
    emit();
    try {
      devices = await adb.devices();
      reconcileSelection();
      for (final d in devices.where((d) => d.ready)) {
        if (d.relay) {
          unawaited(discoverLocalRoute(d.serial));
        } else if (d.wireless) {
          unawaited(verifyLocalRoute(d.serial));
        }
        if (autoSetup || removedPhones.containsKey(phoneRoutes[d.serial])) {
          unawaited(setupPhone(d.serial));
        }
        if (!_metadataAt.containsKey(d.serial) ||
            DateTime.now().difference(_metadataAt[d.serial]!).inSeconds >= 30) {
          unawaited(loadMetadata(d.serial));
        }
      }
      devices = devices
          .where((d) => !removedPhones.containsKey(phoneRoutes[d.serial]))
          .map(
            (d) => _unresponsiveRoutes.contains(d.serial)
                ? Device(d.serial, 'offline', d.model)
                : d,
          )
          .toList();
      if (removedPhones.containsKey(phoneRoutes[selected])) selected = null;
      reconcileSelection();
      startupError = null;
      try {
        discovered = await adb.services();
        discoveryError = null;
      } catch (e) {
        discoveryError = '$e';
      }
    } catch (e) {
      startupError = '$e';
    } finally {
      scanning = false;
      emit();
    }
  }

  Future<void> loadMetadata(String serial) async {
    if (!_metadataPending.add(serial)) return;
    try {
      final text = await adb.shell(
        serial,
        'getprop ro.product.manufacturer; getprop ro.build.version.release; getprop ro.build.version.sdk; dumpsys battery; df -h /sdcard; echo BEAMADB_ID; getprop ro.serialno',
      );
      final lines = text.split('\n');
      _metadataAt[serial] = DateTime.now();
      metadata[serial] = {
        'brand': lines.firstOrNull ?? '',
        'android': lines.length > 1 ? lines[1].trim() : '',
        'sdk': lines.length > 2 ? lines[2].trim() : '',
        'battery': RegExp(r'level:\s*(\d+)').firstMatch(text)?.group(1) ?? '—',
        'details': text,
      };
      final identity = text.split('BEAMADB_ID').last.trim();
      final id =
          text.contains('BEAMADB_ID') &&
              identity.isNotEmpty &&
              identity != 'unknown'
          ? identity
          : serial;
      phoneRoutes[serial] = id;
      markInternetVerified(serial);
      if (removedPhones.containsKey(id)) {
        await savePhones();
        emit();
        return;
      }
      final previous = savedPhones[id] ?? {};
      savedPhones[id] = {
        ...previous,
        'model':
            devices.where((d) => d.serial == serial).firstOrNull?.label ??
            previous['model'] ??
            id,
        'battery': metadata[serial]!['battery']!,
        'lastSeen': DateTime.now().toIso8601String(),
      };
      await savePhones();
      reconcileSelection();
      emit();
    } catch (_) {
      /* The next explicit refresh can retry metadata. */
    } finally {
      _metadataPending.remove(serial);
    }
  }

  Future<T?> operation<T>(
    String title,
    Future<T> Function(Activity item) work, {
    String? target,
  }) async {
    final item = Activity(title, target ?? selected ?? 'Computer');
    activities.insert(0, item);
    if (activities.length > 200) {
      final index = activities.lastIndexWhere((a) => a.state != 'Running');
      if (index >= 0) activities.removeAt(index);
    }
    emit();
    try {
      final result = await work(item);
      item.state = 'Succeeded';
      return result;
    } catch (e) {
      item.state = e is BeamException && e.message.contains('cancelled')
          ? 'Cancelled'
          : 'Failed';
      item.detail = e is BeamException
          ? '${e.message}\n${e.details}'.trim()
          : '$e';
      return null;
    } finally {
      item.cancel = null;
      emit();
    }
  }

  Future<String?> command(
    String title,
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
    String? target,
  }) => operation(title, (item) async {
    final task = await adb.start(
      args,
      timeout: timeout,
      onOutput: (s) {
        item.detail = '${item.detail}$s';
        if (item.detail.length > 16000) {
          item.detail = item.detail.substring(item.detail.length - 16000);
        }
        emit();
      },
    );
    item.cancel = task.cancel;
    final output = await task.output;
    item.detail = output;
    return output;
  }, target: target);

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    emit();
    await preferences?.setString('theme', mode.name);
  }

  Future<void> setReducedMotion(bool value) async {
    reducedMotion = value;
    emit();
    await preferences?.setBool('reducedMotion', value);
  }

  List<Map<String, dynamic>> get workflows {
    try {
      return (jsonDecode(preferences?.getString('workflows') ?? '[]') as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveWorkflows(List<Map<String, dynamic>> value) async {
    await preferences?.setString('workflows', jsonEncode(value));
    emit();
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    await Future.wait(
      cleanups.toList().map((close) => close().catchError((Object _) {})),
    );
    await adb.close();
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
