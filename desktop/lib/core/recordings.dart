import 'dart:io';

/// Respect the user's localized Linux media folders, with standard fallbacks.
Future<String> recordingPath(
  String mode,
  String phone, {
  Directory? root,
  DateTime? now,
}) async {
  final audio = mode == 'audio' || mode == 'mic';
  String? directory = root?.path;
  if (directory == null && Platform.isLinux) {
    try {
      final result = await Process.run('xdg-user-dir', [
        audio ? 'MUSIC' : 'VIDEOS',
      ]);
      if (result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty) {
        directory = '${result.stdout}'.trim();
      }
    } on ProcessException {
      /* Use standard media folders. */
    }
  }
  directory ??=
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']}/${audio ? 'Music' : 'Videos'}';
  final folder = Directory('$directory/BeamADB');
  await folder.create(recursive: true);
  final safe = phone
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final label = safe.isEmpty
      ? 'Phone'
      : safe.substring(0, safe.length.clamp(0, 60));
  final timestamp = (now ?? DateTime.now()).toIso8601String().replaceAll(
    ':',
    '-',
  );
  final stem = '$label-$mode-$timestamp';
  var path = '${folder.path}/$stem.mkv';
  var count = 1;
  while (await File(path).exists()) {
    path = '${folder.path}/$stem-${count++}.mkv';
  }
  return path;
}
