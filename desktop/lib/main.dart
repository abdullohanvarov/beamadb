import 'dart:async';
import 'dart:io';
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
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1240, 820),
      minimumSize: Size(900, 620),
      center: true,
      title: 'BeamADB',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final store = AppStore();
  runApp(BeamApp(store: store, mediaError: mediaError, args: args));
  unawaited(store.initialize());
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
