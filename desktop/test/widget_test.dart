import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/store.dart';
import 'package:beamadb_desktop/core/adb.dart';
import 'package:beamadb_desktop/core/theme.dart';
import 'package:beamadb_desktop/features/home.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });
  testWidgets(
    'desktop exposes everyday actions and developer tools without a device',
    (tester) async {
      tester.view.physicalSize = const Size(1240, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: beamTheme(Brightness.light),
          home: Home(store: store),
        ),
      );
      expect(find.text('Mirror your screen'), findsOneWidget);
      expect(find.text('Explore your files'), findsOneWidget);
      expect(find.text('Open your camera'), findsOneWidget);
      expect(find.text('Developer Tools'), findsOneWidget);
      await tester.tap(find.text('Files').first);
      await tester.pump();
      expect(find.text('Your phone’s files, within reach'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets('connected workspace fits the minimum Linux window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(adb: FakeAdb())
      ..devices = [
        const Device(
          'test',
          'device',
          'A very long device model name for layout testing',
        ),
      ]
      ..selected = 'test';
    await tester.pumpWidget(
      MaterialApp(
        theme: beamTheme(Brightness.dark),
        home: Home(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final name in [
      'Screen',
      'Files',
      'Camera',
      'Audio',
      'Apps',
      'Developer Tools',
    ]) {
      await tester.ensureVisible(find.text(name).first);
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
    }
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

class FakeAdb extends Adb {
  @override
  Future<String> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async => '';
}
