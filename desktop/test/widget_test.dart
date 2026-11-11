import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:beamadb_desktop/core/mirror_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/store.dart';
import 'package:beamadb_desktop/core/adb.dart';
import 'package:beamadb_desktop/core/theme.dart';
import 'package:beamadb_desktop/features/home.dart';
import 'package:beamadb_desktop/features/widgets.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });
  testWidgets('dashboard and Screen show the separate mirror state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final process = FakeMirrorProcess();
    final mirror = MirrorWindow('test', process);
    mirror.update(
      '$mirrorStatusPrefix${jsonEncode({'status': 'Live', 'detail': ''})}',
    );
    final store = AppStore(adb: FakeAdb())
      ..selected = 'test'
      ..devices = [const Device('test', 'device', 'Pixel')]
      ..mirrors['test'] = mirror;
    await tester.pumpWidget(
      MaterialApp(
        theme: beamTheme(Brightness.light),
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => Home(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Screen is being mirrored').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Show window'));
    await process.stdin.flush();
    expect(process.commands, contains('focus\n'));
    await tester.tap(find.text('Screen').first);
    await tester.pumpAndSettle();
    expect(find.text('Screen is being mirrored').hitTestable(), findsOneWidget);
    expect(find.text('Show mirror window').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Recent apps').hitTestable(), findsNothing);
    mirror.update(
      '$mirrorStatusPrefix${jsonEncode({'status': 'Disconnected', 'detail': 'Phone disconnected'})}',
    );
    store.emit();
    await tester.pumpAndSettle();
    expect(find.text('Phone disconnected').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    await process.stdin.close();
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

  testWidgets('mirror keeps readable dark controls under a light app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(adb: FakeAdb());
    await tester.pumpWidget(
      MaterialApp(
        theme: beamTheme(Brightness.light),
        home: Home(store: store, args: const ['--session', 'test', 'screen']),
      ),
    );
    await tester.pumpAndSettle();
    final controlsContext = tester.element(find.byType(WindowControls));
    expect(Theme.of(controlsContext).brightness, Brightness.dark);
    final volumeContext = tester.element(find.byTooltip('Volume Up'));
    final colors = Theme.of(volumeContext).colorScheme;
    expect(
      (colors.onSurface.computeLuminance() + .05) /
          (colors.surfaceContainerHighest.computeLuminance() + .05),
      greaterThan(4.5),
    );
    for (final label in ['Minimize', 'Maximize', 'Close']) {
      expect(
        find.descendant(
          of: find.byTooltip(label),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('detached mirror forwards edge drags to native window resizing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'isMaximized' ? false : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final store = AppStore(adb: FakeAdb());
    await tester.pumpWidget(
      MaterialApp(
        theme: beamTheme(Brightness.light),
        home: Home(store: store, args: const ['--session', 'test', 'screen']),
      ),
    );
    await tester.pumpAndSettle();
    for (final edge in [
      (const Offset(319, 260), const Offset(30, 0), 'right'),
      (const Offset(1, 260), const Offset(-30, 0), 'left'),
      (const Offset(319, 519), const Offset(30, 30), 'bottomRight'),
    ]) {
      await tester.dragFrom(edge.$1, edge.$2);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        calls.any(
          (call) =>
              call.method == 'startResizing' &&
              call.arguments['resizeEdge'] == edge.$3,
        ),
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'window controls are rendered and visible in main app and separate mirror window',
    (tester) async {
      tester.view.physicalSize = const Size(1240, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = AppStore(adb: FakeAdb())
        ..devices = [const Device('test', 'device', 'Pixel 8 Pro')]
        ..selected = 'test';

      // 1. Verify main app window has WindowControls
      await tester.pumpWidget(
        MaterialApp(
          theme: beamTheme(Brightness.dark),
          home: Home(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WindowControls), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      // 2. Verify separate mirror window mode has WindowControls
      await tester.pumpWidget(
        MaterialApp(
          theme: beamTheme(Brightness.dark),
          home: Home(store: store, args: const ['--session', 'test', 'screen']),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WindowControls), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('BeamADB · Pixel 8 Pro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}

class FakeAdb extends Adb {
  @override
  Future<String> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async => '';
}

class FakeMirrorProcess implements Process {
  final commands = <String>[];
  late final StreamController<List<int>> _controller =
      StreamController<List<int>>()
        ..stream.listen((bytes) => commands.add(utf8.decode(bytes)));
  late final IOSink _input = IOSink(_controller.sink);
  @override
  IOSink get stdin => _input;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode async => 0;
  @override
  int get pid => 123;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
