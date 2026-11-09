import 'dart:io';
import 'dart:async';
import 'package:beamadb_desktop/core/adb.dart';
import 'package:beamadb_desktop/core/media_session.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:beamadb_desktop/core/store.dart';
import 'package:beamadb_desktop/core/theme.dart';
import 'package:beamadb_desktop/features/home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('native desktop navigation and screenshot', (tester) async {
    MediaKit.ensureInitialized();
    final store = AppStore();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: beamTheme(Brightness.light),
        home: RepaintBoundary(
          key: boundary,
          child: Home(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/beamadb-desktop-overview.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    for (final name in [
      'Screen',
      'Files',
      'Camera',
      'Audio',
      'Apps',
      'Developer Tools',
      'Activity',
      'Settings',
    ]) {
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$name must render without layout exceptions',
      );
    }
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets('native H264 texture decoding', (tester) async {
    final sample = File('/tmp/beamadb-sample.h264');
    expect(
      await sample.exists(),
      true,
      reason:
          'Generate /tmp/beamadb-sample.h264 before running native media tests.',
    );
    final player = Player();
    final controller = VideoController(player);
    await tester.pumpWidget(
      MaterialApp(
        home: Video(controller: controller, controls: NoVideoControls),
      ),
    );
    await (player.platform as NativePlayer).setProperty('demuxer', 'lavf');
    await (player.platform as NativePlayer).setProperty(
      'demuxer-lavf-format',
      'h264',
    );
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    final dimensions = player.stream.width.firstWhere(
      (w) => w != null && w > 1,
    );
    await player.open(Media(sample.path));
    // Render while the native player is decoding.
    for (var i = 0; i < 40 && player.state.width == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await controller.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 10),
    );
    expect(
      await dimensions.timeout(const Duration(seconds: 10)),
      640,
      reason: errors.join('\n'),
    );
    expect(player.state.width, 640);
    expect(player.state.height, 360);
    await subscription.cancel();
    await player.dispose();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('scrcpy transport handshake, embedded stream and cleanup', (
    tester,
  ) async {
    final adb = CaptureFixtureAdb();
    await adb.prepare();
    final session = MediaSession(adb, 'fixture', 'screen');
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: session,
          builder: (_, _) => session.video == null
              ? const SizedBox()
              : Video(controller: session.video!, controls: NoVideoControls),
        ),
      ),
    );
    Object? error;
    var complete = false;
    unawaited(
      session
          .start()
          .catchError((Object e) {
            error = e;
          })
          .whenComplete(() => complete = true),
    );
    for (var i = 0; i < 200 && !complete; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (error != null || session.status != 'Live') {
      debugPrint(session.detail);
    }
    expect(error, isNull, reason: session.detail);
    expect(session.status, 'Live', reason: session.detail);
    expect(session.player!.state.width, 640);
    session.key(3);
    session.touch(0, .5, .5, 640, 360);
    await tester.pump(const Duration(milliseconds: 100));
    expect(adb.controls.length, greaterThanOrEqualTo(60));
    await session.record('/tmp/beamadb-native-recording.mkv');
    await tester.pump(const Duration(seconds: 2));
    await session.record(null);
    expect(
      await File('/tmp/beamadb-native-recording.mkv').length(),
      greaterThan(0),
    );
    await session.stop();
    expect(adb.removedForward, true);
    expect(session.player, isNull);
    await adb.finish();
    session.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native PCM audio stream and cleanup', (tester) async {
    final adb = CaptureFixtureAdb(audio: true);
    await adb.prepare();
    final session = MediaSession(adb, 'fixture', 'audio');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.start();
    for (
      var i = 0;
      i < 50 && session.player!.state.audioParams.sampleRate == null;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      session.player!.state.audioParams.sampleRate,
      48000,
      reason: session.detail,
    );
    await session.setMuted(true);
    await tester.pump(const Duration(milliseconds: 150));
    expect(session.player!.state.volume, 0);
    await session.stop();
    await adb.finish();
    session.dispose();
  });
}

class CaptureFixtureAdb extends Adb {
  final bool audio;
  CaptureFixtureAdb({this.audio = false});
  late ServerSocket listener;
  final sockets = <Socket>[];
  final controls = <int>[];
  bool removedForward = false;
  Timer? timer;
  Future<void> prepare() async {
    server = '/tmp/beamadb-sample.h264';
    serverVersion = '5.0.1';
    listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = await File(server).readAsBytes();
    listener.listen((socket) {
      sockets.add(socket);
      unawaited(socket.done.catchError((Object _) {}));
      if (sockets.length == 1) {
        socket.add([0]);
        if (audio) {
          timer = Timer.periodic(
            const Duration(milliseconds: 100),
            (_) => socket.add(List<int>.filled(19200, 0)),
          );
        }
      } else {
        socket.listen(controls.addAll, onError: (Object _) {});
        var offset = 0;
        timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
          if (offset >= bytes.length) offset = 0;
          final end = (offset + 4096).clamp(0, bytes.length);
          sockets.first.add(bytes.sublist(offset, end));
          offset = end;
        });
      }
    });
  }

  @override
  Future<String> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (args.contains('tcp:0')) return '${listener.port}';
    if (args.contains('--remove')) removedForward = true;
    return '';
  }

  @override
  Future<Process> spawn(List<String> args) =>
      Process.start('/bin/sleep', ['60']);
  Future<void> finish() async {
    timer?.cancel();
    for (final s in sockets) {
      s.destroy();
    }
    await listener.close();
  }
}
