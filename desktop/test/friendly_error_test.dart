import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/friendly_error.dart';
import 'package:beamadb_desktop/core/adb.dart';
import 'package:beamadb_desktop/core/media_session.dart';

void main() {
  group('FriendlyError', () {
    test('translates unauthorized error to clear guidance', () {
      final err = FriendlyError.parse('error: device unauthorized. Please approve USB debugging.');
      expect(err.title, 'Phone Authorization Required');
      expect(err.suggestion, contains('Unlock your phone'));
    });

    test('translates INSTALL_FAILED_USER_RESTRICTED to Developer Options tip', () {
      final err = FriendlyError.parse('Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]');
      expect(err.title, 'Installation Blocked by Phone');
      expect(err.suggestion, contains('Install via USB'));
    });

    test('translates offline and connection refused errors', () {
      final offline = FriendlyError.parse('error: device offline');
      expect(offline.title, 'Device is Offline');

      final refused = FriendlyError.parse('cannot connect to 192.168.1.50:5555: Connection refused');
      expect(refused.title, 'Connection Refused by Phone');
      expect(refused.suggestion, contains('Wireless Debugging'));
    });

    test('translates scrcpy and camera errors', () {
      final camera = FriendlyError.parse('[server] ERROR: Could not start camera: camera_facing=back failed');
      expect(camera.title, 'Camera In Use or Unavailable');
      expect(camera.suggestion, contains('camera'));

      final screenOff = FriendlyError.parse('device is locked or SCREEN_OFF');
      expect(screenOff.title, 'Phone Screen is Locked');
    });

    test('cleans raw terminal noise gracefully for unrecognized errors', () {
      final err = FriendlyError.parse('adb: error: unexpected failure in custom command\nadditional stack trace');
      expect(err.description, 'unexpected failure in custom command');
      expect(err.raw, contains('additional stack trace'));
    });

    test('integrates with BeamException and explainError', () {
      final ex = explainError('INSTALL_FAILED_INSUFFICIENT_STORAGE', 1);
      expect(ex.message, contains('free storage space'));
    });
  });

  group('Camera facing in MediaSession', () {
    test('tracks and updates camera facing', () async {
      final adb = Adb();
      final session = MediaSession(adb, 'test_device', 'camera');
      expect(session.cameraFacing, 'back');
      await session.setCameraFacing('front');
      expect(session.cameraFacing, 'front');
      await session.setCameraFacing('back');
      expect(session.cameraFacing, 'back');
    });
  });
}

