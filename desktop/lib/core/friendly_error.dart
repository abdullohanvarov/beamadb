import 'adb.dart';

/// Interprets raw terminal, ADB, scrcpy, and system error responses into
/// elegant, user-friendly messages with actionable suggestions.
class FriendlyError {
  final String title;
  final String description;
  final String? suggestion;
  final String raw;

  const FriendlyError({
    required this.title,
    required this.description,
    this.suggestion,
    this.raw = '',
  });

  String get summary =>
      suggestion != null ? '$description $suggestion' : description;

  @override
  String toString() => summary;

  static FriendlyError parse(dynamic error, [String? fallbackTitle]) {
    final rawText = error is BeamException
        ? (error.details.isNotEmpty
            ? '${error.message}\n${error.details}'
            : error.message).trim()
        : (error?.toString() ?? '').trim();
    final lower = rawText.toLowerCase();

    // 1. Device unauthorized / lock screen
    if (lower.contains('unauthorized') || lower.contains('not authorized')) {
      return FriendlyError(
        title: 'Phone Authorization Required',
        description:
            'USB debugging has not been authorized on your phone.',
        suggestion:
            'Unlock your phone and tap "Allow" or "Always allow" on the USB debugging prompt.',
        raw: rawText,
      );
    }

    // 2. Device offline / not found / multiple
    if (lower.contains('device offline') || lower.contains("device 'offline'")) {
      return FriendlyError(
        title: 'Device is Offline',
        description:
            'Your phone is connected, but Android reports that it is currently offline.',
        suggestion:
            'Unplug and reconnect the USB cable, or toggle Wireless Debugging off and on in Developer Options.',
        raw: rawText,
      );
    }
    if (lower.contains('no devices/emulators found') ||
        lower.contains('device not found') ||
        lower.contains("device '(null)' not found") ||
        (lower.contains('not found') && lower.contains('device'))) {
      return FriendlyError(
        title: 'Device Not Found',
        description: 'No accessible Android device was detected by ADB.',
        suggestion:
            'Check your USB connection, make sure your phone screen is unlocked, and verify USB debugging is on.',
        raw: rawText,
      );
    }
    if (lower.contains('more than one device/emulator')) {
      return FriendlyError(
        title: 'Multiple Devices Connected',
        description:
            'More than one phone is connected to your computer.',
        suggestion:
            'Select the specific phone you want to use from the top device dropdown.',
        raw: rawText,
      );
    }

    // 3. Network & Wireless Pairing
    if (lower.contains('connection refused') ||
        lower.contains('actively refused')) {
      return FriendlyError(
        title: 'Connection Refused by Phone',
        description:
            'The phone rejected the wireless connection attempt.',
        suggestion:
            'Ensure Wireless Debugging is enabled on your phone and that the port number is correct.',
        raw: rawText,
      );
    }
    if (lower.contains('connection timed out') ||
        lower.contains('timed out') ||
        lower.contains('etimedout') ||
        lower.contains('no route to host')) {
      return FriendlyError(
        title: 'Connection Timed Out',
        description: 'Could not reach your phone over the local network.',
        suggestion:
            'Verify that your computer and phone are connected to the exact same Wi-Fi network.',
        raw: rawText,
      );
    }
    if (lower.contains('unable to start pairing client') ||
        lower.contains('wrong password') ||
        lower.contains('bad pairing code')) {
      return FriendlyError(
        title: 'Invalid or Expired Pairing Code',
        description: 'The 6-digit pairing code was not accepted.',
        suggestion:
            'Open "Pair device with pairing code" on your phone and enter the fresh 6-digit code and port shown.',
        raw: rawText,
      );
    }
    if (lower.contains('already connected to')) {
      return FriendlyError(
        title: 'Already Connected',
        description: 'This wireless connection is already active.',
        raw: rawText,
      );
    }

    // 4. App Installation (APK)
    if (lower.contains('install_failed_user_restricted') ||
        lower.contains('install canceled by user')) {
      return FriendlyError(
        title: 'Installation Blocked by Phone',
        description:
            'Your phone blocked installing the app via USB.',
        suggestion:
            'In your phone\'s Developer Options, turn on "Install via USB" and allow the installation prompt.',
        raw: rawText,
      );
    }
    if (lower.contains('install_failed_insufficient_storage') ||
        lower.contains('no space left')) {
      return FriendlyError(
        title: 'Storage is Full',
        description:
            'The phone does not have enough free storage space to complete this action.',
        suggestion:
            'Free up some space on your phone and try again.',
        raw: rawText,
      );
    }
    if (lower.contains('install_failed_version_downgrade')) {
      return FriendlyError(
        title: 'Newer Version Already Installed',
        description:
            'A newer version of this app is already installed on your phone.',
        suggestion:
            'Uninstall the existing app from your phone first if you want to install an older version.',
        raw: rawText,
      );
    }
    if (lower.contains('install_failed_update_incompatible') ||
        lower.contains('signatures do not match')) {
      return FriendlyError(
        title: 'Incompatible App Signature',
        description:
            'The APK signature does not match the version currently on your phone.',
        suggestion:
            'Uninstall the previous version from your phone before installing this package.',
        raw: rawText,
      );
    }
    if (lower.contains('install_failed_invalid_apk') ||
        lower.contains('install_parse_failed')) {
      return FriendlyError(
        title: 'Invalid APK File',
        description:
            'The selected APK file is corrupted or incompatible with this phone.',
        suggestion: 'Download a fresh copy of the APK package.',
        raw: rawText,
      );
    }
    if (lower.contains('install_failed_test_only')) {
      return FriendlyError(
        title: 'Test-Only Package',
        description:
            'This APK has the test-only flag set and cannot be installed normally.',
        raw: rawText,
      );
    }

    // 5. Filesystem & Permissions
    if (lower.contains('permission denied')) {
      return FriendlyError(
        title: 'Access Restricted by Android',
        description:
            'Android denied access to this file or folder location.',
        suggestion:
            'System directories are protected. Try accessing user folders like Downloads, Documents, or DCIM.',
        raw: rawText,
      );
    }
    if (lower.contains('read-only file system')) {
      return FriendlyError(
        title: 'Read-Only Location',
        description:
            'The target location is on a read-only partition.',
        suggestion: 'Choose a writable location such as internal user storage.',
        raw: rawText,
      );
    }
    if (lower.contains('no such file or directory')) {
      return FriendlyError(
        title: 'File or Folder Not Found',
        description: 'The specified item could not be found on the device.',
        raw: rawText,
      );
    }
    if (lower.contains('file exists')) {
      return FriendlyError(
        title: 'Item Already Exists',
        description:
            'An item with this name already exists in this directory.',
        raw: rawText,
      );
    }

    // 6. Camera, Screen Mirroring & Scrcpy
    if (lower.contains('screen is off') ||
        lower.contains('screen_off') ||
        lower.contains('device is locked')) {
      return FriendlyError(
        title: 'Phone Screen is Locked',
        description: 'Screen mirroring cannot start while the phone screen is locked.',
        suggestion: 'Unlock your phone screen and try again.',
        raw: rawText,
      );
    }
    if (lower.contains('could not start camera') ||
        lower.contains('cameraaccess') ||
        lower.contains('cameradevice') ||
        lower.contains('camera_facing')) {
      return FriendlyError(
        title: 'Camera In Use or Unavailable',
        description: 'The phone camera could not be opened.',
        suggestion:
            'Ensure no other app is currently using the camera on your phone, then try again.',
        raw: rawText,
      );
    }
    if (lower.contains('audio capture not supported')) {
      return FriendlyError(
        title: 'Audio Capture Unsupported',
        description:
            'Internal audio capture is not supported on this device’s Android version.',
        suggestion: 'Android 11 or higher is required for phone audio playback streaming.',
        raw: rawText,
      );
    }
    if (lower.contains('mediacodec') ||
        lower.contains('video_bit_rate') ||
        lower.contains('video encoder')) {
      return FriendlyError(
        title: 'Hardware Video Encoder Issue',
        description: 'The phone encountered an issue while encoding the video stream.',
        suggestion: 'Try lowering the resolution (e.g. to 1280px) in mirror settings.',
        raw: rawText,
      );
    }
    if (lower.contains('no media arrived') || lower.contains('first frame')) {
      return FriendlyError(
        title: 'Video Stream Timed Out',
        description: 'The video stream started but did not deliver frames in time.',
        suggestion: 'Make sure your phone screen is on and unlocked.',
        raw: rawText,
      );
    }
    if (lower.contains('bundled scrcpy tools are missing')) {
      return FriendlyError(
        title: 'Mirroring Tools Missing',
        description: 'The bundled screen mirroring tools were not found on this computer.',
        suggestion: 'Reinstall BeamADB or verify the application directory.',
        raw: rawText,
      );
    }

    // 7. Relay & BeamADB Link
    if (lower.contains('configure the relay in connect device')) {
      return FriendlyError(
        title: 'Relay Configuration Required',
        description: 'The internet relay is not configured on this computer yet.',
        suggestion: 'Go to Connect device → Remote to set up your VPS relay first.',
        raw: rawText,
      );
    }
    if (lower.contains('phone did not confirm configuration')) {
      return FriendlyError(
        title: 'Link Setup Confirmation Timed Out',
        description: 'The companion app on the phone did not confirm configuration.',
        suggestion: 'Unlock your phone, open BeamADB Link, and tap Retry.',
        raw: rawText,
      );
    }
    if (lower.contains('phone setup failed') ||
        lower.contains('automatic setup failed')) {
      return FriendlyError(
        title: 'Link Setup Interrupted',
        description: 'Permanent Link setup could not be completed.',
        suggestion:
            'Unlock your phone, allow "Install via USB" in Developer Options, and try again.',
        raw: rawText,
      );
    }

    // 8. General cleanup fallback
    String cleaned = rawText
        .replaceAll(RegExp(r'adb: error: ', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[server\] ERROR: ', caseSensitive: false), '')
        .replaceAll(RegExp(r'Failure\s*\[', caseSensitive: false), '')
        .replaceAll(RegExp(r'\]\s*$'), '')
        .replaceAll(
          RegExp(r'java\.lang\.[a-zA-Z]+Exception: ', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'^Exception: ', caseSensitive: false), '')
        .trim();

    if (cleaned.contains('\n')) {
      cleaned = cleaned.split('\n').first.trim();
    }
    if (cleaned.length > 120) {
      cleaned = '${cleaned.substring(0, 117)}...';
    }
    if (cleaned.isEmpty) {
      cleaned = 'The requested operation could not be completed.';
    }

    return FriendlyError(
      title: fallbackTitle ?? 'Operation Unsuccessful',
      description: cleaned,
      suggestion: null,
      raw: rawText,
    );
  }
}

