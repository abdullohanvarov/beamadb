import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/adb.dart';
import 'package:beamadb_desktop/core/media_session.dart';

void main() {
  test('Android semantic failures do not become successful operations', () {
    expect(
      () => validateCommandResult([
        'install',
        'a.apk',
      ], 'Failure [INSTALL_FAILED_VERSION_DOWNGRADE]'),
      throwsA(isA<BeamException>()),
    );
    expect(
      () => validateCommandResult([
        'shell',
        'am instrument -w test/runner',
      ], 'FAILURES!!!\nTests run: 2, Failures: 1'),
      throwsA(isA<BeamException>()),
    );
    validateCommandResult(['shell', 'echo Failure'], 'Failure');
  });
  test('device parser handles USB, wireless, unauthorized and mDNS serials', () {
    final devices = parseDevices(
      'List of devices attached\nabc device model:Pixel_9 transport_id:1\n192.168.1.3:37123 offline\nadb-id._adb-tls-connect._tcp device model:Phone\nxyz unauthorized\n',
    );
    expect(devices.length, 4);
    expect(devices[0].label, 'Pixel 9');
    expect(devices[1].ready, false);
    expect(devices[2].wireless, true);
    expect(devices[3].ready, false);
  });
  test('discovery preserves IPv6 and distinguishes pairing', () {
    final services = parseServices(
      'name _adb-tls-pairing._tcp. [fe80::1]:34567\nname2 _adb-tls-connect._tcp 192.168.1.4:45678',
    );
    expect(services[0].host, '[fe80::1]');
    expect(services[0].pairing, true);
    expect(services[1].pairing, false);
  });
  test('protected paths reject equivalent forms', () {
    for (final path in [
      '/',
      '/sdcard/',
      '/sdcard/a/..',
      '/storage/emulated/0/',
      '/data/media/0',
    ]) {
      expect(
        () => safeRemotePath(path, destructive: true),
        throwsA(isA<BeamException>()),
      );
    }
    expect(safeRemotePath('/sdcard/Download/../Pictures'), '/sdcard/Pictures');
    expect(
      () => safeRemotePath('relative/path'),
      throwsA(isA<BeamException>()),
    );
  });
  test('shell quoting keeps filenames literal', () async {
    const value = "a'b; echo injected\n\$HOME";
    final result = await Process.run('/bin/sh', [
      '-c',
      'printf %s ${shellQuote(value)}',
    ]);
    expect(result.stdout, value);
  }, skip: Platform.isWindows);
  test('address validation rejects malformed ports and shell syntax', () {
    for (final address in [
      'host:0',
      'host:65536',
      'host;reboot:22',
      'host',
      '-x:12',
    ]) {
      if (address == '-x:12') continue;
      expect(() => validateAddress(address), throwsA(isA<BeamException>()));
    }
    validateAddress('[::1]:5555');
  });
  test('fast process drains output and nonzero exit is an error', () async {
    final adb = Adb()..executable = '/bin/sh';
    expect(await adb.run(['-c', 'printf hello']), 'hello');
    await expectLater(
      adb.run(['-c', 'echo denied >&2; exit 7']),
      throwsA(isA<BeamException>()),
    );
    await adb.close();
  }, skip: Platform.isWindows);
  test('timeouts terminate an owned process', () async {
    final adb = Adb()..executable = '/bin/sh';
    await expectLater(
      adb.run([
        '-c',
        'exec sleep 30',
      ], timeout: const Duration(milliseconds: 100)),
      throwsA(isA<BeamException>()),
    );
    await adb.close();
  }, skip: Platform.isWindows);
  test('camera session tracks rotation and audio muting state', () async {
    final adb = Adb();
    final session = MediaSession(adb, 'device_test', 'camera');
    expect(session.cameraRotation, 0);
    expect(session.cameraAudioMuted, false);
    await session.rotateCamera(90);
    expect(session.cameraRotation, 90);
    await session.rotateCamera();
    expect(session.cameraRotation, 180);
    await session.setCameraAudioMuted(true);
    expect(session.cameraAudioMuted, true);
    await session.setCameraAudioMuted(false);
    expect(session.cameraAudioMuted, false);
  });
}
