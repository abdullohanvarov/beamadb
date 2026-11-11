import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'features/home.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? mediaError;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    mediaError = 'Native media runtime is unavailable: $e';
  }
  await windowManager.ensureInitialized();
  final isSession = args.contains('--session');
  final isScreen = isSession && args.length >= 3 && args[2] == 'screen';
  final windowSize = isScreen
      ? const Size(460, 890)
      : isSession
      ? const Size(600, 750)
      : const Size(1240, 820);
  final minSize = isScreen
      ? const Size(320, 520)
      : isSession
      ? const Size(400, 400)
      : const Size(900, 620);
  final windowTitle = isScreen
      ? 'BeamADB · Phone Mirror'
      : isSession
      ? 'BeamADB · Stream'
      : 'BeamADB';

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: windowSize,
      minimumSize: minSize,
      center: true,
      title: windowTitle,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final store = AppStore();
  runApp(BeamApp(store: store, mediaError: mediaError, args: args));
  unawaited(store.initialize());
  if (isScreen) {
    stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((
      command,
    ) async {
      if (command == 'stop') await windowManager.close();
      if (command == 'focus') {
        await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }
}

class BeamApp extends StatefulWidget {
  final AppStore store;
  final String? mediaError;
  final List<String> args;
  const BeamApp({
    super.key,
    required this.store,
    this.mediaError,
    this.args = const [],
  });
  @override
  State<BeamApp> createState() => _BeamAppState();
}

class _BeamAppState extends State<BeamApp> with WindowListener {
  bool closing = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
  }

  @override
  void onWindowClose() async {
    if (closing) return;
    closing = true;
    await widget.store.shutdown();
    await windowManager.destroy();
    exit(0);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => MaterialApp(
      title: 'BeamADB',
      debugShowCheckedModeBanner: false,
      theme: beamTheme(Brightness.light),
      darkTheme: beamTheme(Brightness.dark),
      themeMode: widget.store.themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              widget.store.reducedMotion ||
              MediaQuery.of(context).disableAnimations,
        ),
        child: child!,
      ),
      home: Home(
        store: widget.store,
        mediaError: widget.mediaError,
        args: widget.args,
      ),
    ),
  );
}
