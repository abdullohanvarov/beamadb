import 'dart:async';
import 'dart:convert';
import 'dart:io';

const mirrorStatusPrefix = 'BEAMADB_MIRROR:';

class MirrorWindow {
  final String device;
  final Process process;
  String status = 'Starting';
  String detail = '';
  bool open = true;
  MirrorWindow(this.device, this.process);

  void command(String value) {
    if (!open) return;
    try {
      process.stdin.writeln(value);
    } catch (_) {}
  }

  void update(String line) {
    if (!line.startsWith(mirrorStatusPrefix)) return;
    try {
      final data = jsonDecode(line.substring(mirrorStatusPrefix.length));
      status = data['status'] as String;
      detail = data['detail'] as String? ?? '';
    } catch (_) {}
  }

  Future<void> stop() async {
    command('stop');
    try {
      await process.exitCode.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      process.kill();
    }
  }
}
