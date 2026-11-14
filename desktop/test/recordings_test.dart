import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/recordings.dart';

void main() {
  test(
    'recordings create a folder and safe, readable, non-overwriting names',
    () async {
      final root = await Directory.systemTemp.createTemp('beamadb-recordings-');
      try {
        final date = DateTime(2026, 11, 14, 15, 30);
        final first = await recordingPath(
          'screen',
          '../My Phone / 1',
          root: root,
          now: date,
        );
        expect(
          first.startsWith(
            '${root.path}/BeamADB/My-Phone-1-screen-2026-11-14T15-30',
          ),
          isTrue,
        );
        expect(await Directory('${root.path}/BeamADB').exists(), isTrue);
        await File(first).writeAsString('existing recording');
        final second = await recordingPath(
          'screen',
          '../My Phone / 1',
          root: root,
          now: date,
        );
        expect(second, isNot(first));
        expect(await File(first).readAsString(), 'existing recording');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
