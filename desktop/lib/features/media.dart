import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../core/adb.dart';
import '../core/media_session.dart';
import '../core/store.dart';
import 'widgets.dart';

class MediaPage extends StatefulWidget {
  final AppStore store;
  final String mode;
  final String? runtimeError;
  final bool autoStart;
  const MediaPage({
    super.key,
    required this.store,
    required this.mode,
    this.runtimeError,
    this.autoStart = false,
  });
  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  MediaSession? session;
  int quality = 1920, fps = 60, bitrate = 8000000;
  bool stayAwake = true, phoneScreenOff = false;
  String camera = 'back', source = 'audio';
  bool fullscreen = false;
  bool starting = false;
  bool autoStarted = false;
  final focus = FocusNode();
  final List<Process> children = [];
  String get title => switch (widget.mode) {
    'camera' => 'Camera',
    'audio' => 'Audio',
    _ => 'Screen',
  };
  @override
  void initState() {
    super.initState();
    session = widget.store.sessions['${widget.store.selected}:${widget.mode}'];
    session?.addListener(updated);
  }

  @override
  void didUpdateWidget(covariant MediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoStart &&
        !autoStarted &&
        widget.store.ready &&
        widget.runtimeError == null) {
      autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(start());
      });
    }
  }

  Future<void> start() async {
    final device = widget.store.device;
    if (device == null || !device.ready) return;
    if (starting || (session?.active ?? false)) return;
    starting = true;
    if (session != null) widget.store.cleanups.remove(session!.stop);
    session?.removeListener(updated);
    session?.dispose();
    session = MediaSession(
      widget.store.adb,
      device.serial,
      widget.mode == 'audio' ? source : widget.mode,
    )..addListener(updated);
    widget.store.sessions['${device.serial}:${widget.mode}'] = session!;
    widget.store.cleanups.add(session!.stop);
    session!.addListener(widget.store.emit);
    setState(() {});
    await widget.store.operation(
      'Start ${title.toLowerCase()}',
      (_) => session!.start(
        maxSize: quality,
        camera: camera,
        fps: fps,
        bitrate: bitrate,
        stayAwake: stayAwake,
      ),
    );
    starting = false;
    if (mounted) {
      setState(() {});
      focus.requestFocus();
      await showResult(context, widget.store);
    }
  }

  void updated() {
    if (mounted) setState(() {});
  }

  Future<void> detached() async {
    final device = widget.store.device;
    if (device == null) return;
    await session?.stop();
    await widget.store.operation('Open separate window', (_) async {
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['--session', device.serial, widget.mode],
        mode: ProcessStartMode.detached,
        environment: {
          'BEAMADB_HOME':
              Platform.environment['BEAMADB_HOME'] ??
              Directory.current.parent.path,
        },
      );
      children.add(process);
    });
  }

  Future<void> record() async {
    if (session == null) return;
    if (session!.recording) {
      final path = session!.recordingPath;
      await widget.store.operation('Save recording', (_) async {
        await session!.record(null);
        if (path == null ||
            !await File(path).exists() ||
            await File(path).length() == 0) {
          throw const BeamException('No recording data was saved.');
        }
      });
    } else {
      final location = await getSaveLocation(
        suggestedName: 'BeamADB-${DateTime.now().millisecondsSinceEpoch}.mkv',
      );
      if (location == null) return;
      await widget.store.operation(
        'Start recording',
        (_) => session!.record(location.path),
      );
    }
    if (mounted) await showResult(context, widget.store);
  }

  Future<void> screenshot() async {
    final location = await getSaveLocation(
      suggestedName: 'BeamADB-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (location == null) return;
    await widget.store.operation('Save screenshot', (_) async {
      final data = await session?.player?.screenshot();
      if (data == null) {
        throw const BeamException('No video frame is available yet.');
      }
      await File(location.path).writeAsBytes(data);
    });
    if (mounted) await showResult(context, widget.store);
  }

  @override
  void dispose() {
    session?.removeListener(updated);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = session?.active ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title,
          switch (widget.mode) {
            'camera' => 'A fresh perspective, right on your desktop.',
            'audio' => 'Your phone’s sound. Your computer’s speakers.',
            _ => 'A bigger canvas for everything on your phone.',
          },
          actions: [
            if (active && widget.mode != 'audio')
              IconButton(
                tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: () async {
                  fullscreen = !fullscreen;
                  await windowManager.setFullScreen(fullscreen);
                  if (mounted) setState(() {});
                },
                icon: Icon(
                  fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            if (active)
              OutlinedButton.icon(
                onPressed: detached,
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Separate window'),
              ),
            FilledButton.icon(
              onPressed: starting
                  ? null
                  : active
                  ? () => session?.stop()
                  : !widget.store.ready || widget.runtimeError != null
                  ? null
                  : start,
              icon: Icon(
                active ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                starting
                    ? 'Starting…'
                    : active
                    ? 'Stop'
                    : 'Start $title',
              ),
            ),
          ],
        ),
        if (widget.runtimeError != null)
          Notice(widget.runtimeError!, error: true),
        if (session?.status == 'Failed' || session?.status == 'Disconnected')
          Notice(
            session!.detail.isEmpty
                ? 'The stream disconnected. Stop and start to reconnect.'
                : session!.detail,
            error: true,
          ),
        if (!active)
          Wrap(
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.mode != 'audio')
                DropdownButton<int>(
                  value: quality,
                  items: const [
                    DropdownMenuItem(
                      value: 1280,
                      child: Text('Balanced · 720p'),
                    ),
                    DropdownMenuItem(
                      value: 1920,
                      child: Text('High quality · 1080p'),
                    ),
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Native resolution'),
                    ),
                  ],
                  onChanged: (v) => setState(() => quality = v!),
                ),
              if (widget.mode == 'camera')
                DropdownButton<String>(
                  value: camera,
                  items: ['back', 'front', 'external']
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text('$c camera'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => camera = v!),
                ),
              if (widget.mode == 'audio')
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'audio',
                      label: Text('Phone playback'),
                      icon: Icon(Icons.volume_up_outlined),
                    ),
                    ButtonSegment(
                      value: 'mic',
                      label: Text('Microphone'),
                      icon: Icon(Icons.mic_none),
                    ),
                  ],
                  selected: {source},
                  onSelectionChanged: (v) => setState(() => source = v.first),
                ),
            ],
          ),
        const SizedBox(height: 14),
        Expanded(
          child: Panel(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: active
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: widget.mode == 'audio'
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        size: 90,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        session!.status,
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        source == 'mic'
                                            ? 'Microphone monitoring is active'
                                            : 'Phone audio playback',
                                      ),
                                      const SizedBox(height: 16),
                                      IconButton(
                                        onPressed: () =>
                                            session!.setMuted(!session!.muted),
                                        icon: Icon(
                                          session!.muted
                                              ? Icons.volume_off
                                              : Icons.volume_up,
                                          size: 32,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : videoView(),
                        ),
                        Positioned(
                          left: 16,
                          top: 16,
                          child: Chip(
                            avatar: Icon(
                              session!.status == 'Live'
                                  ? Icons.circle
                                  : Icons.timelapse,
                              size: 10,
                              color: session!.status == 'Live'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            label: Text(
                              session!.recording
                                  ? '${session!.status} · Recording'
                                  : session!.status,
                            ),
                          ),
                        ),
                      ],
                    )
                  : EmptyState(
                      widget.mode == 'camera'
                          ? Icons.videocam_outlined
                          : widget.mode == 'audio'
                          ? Icons.headphones_rounded
                          : Icons.screen_share_outlined,
                      widget.store.ready
                          ? '$title is ready when you are'
                          : 'Connect a phone to get started',
                      widget.mode == 'audio'
                          ? 'Playback capture depends on Android and app support. Microphone monitoring is always started explicitly.'
                          : 'Your live view appears here. Open it in a separate window whenever you need more room.',
                    ),
            ),
          ),
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.mode == 'screen') ...[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => session!.key(4),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: 'Home',
                    onPressed: () => session!.key(3),
                    icon: const Icon(Icons.circle_outlined),
                  ),
                  IconButton(
                    tooltip: 'Recent apps',
                    onPressed: () => session!.key(187),
                    icon: const Icon(Icons.crop_square),
                  ),
                ],
                if (widget.mode == 'screen')
                  IconButton(
                    tooltip: phoneScreenOff
                        ? 'Turn phone screen on'
                        : 'Turn phone screen off',
                    onPressed: () {
                      phoneScreenOff = !phoneScreenOff;
                      session!.displayPower(!phoneScreenOff);
                      setState(() {});
                    },
                    icon: Icon(
                      phoneScreenOff ? Icons.smartphone : Icons.phonelink_lock,
                    ),
                  ),
                if (widget.mode != 'audio')
                  OutlinedButton.icon(
                    onPressed: screenshot,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Screenshot'),
                  ),
                OutlinedButton.icon(
                  onPressed: record,
                  icon: Icon(
                    session!.recording
                        ? Icons.stop_circle_outlined
                        : Icons.fiber_manual_record,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: Text(session!.recording ? 'Save recording' : 'Record'),
                ),
                if (widget.mode == 'screen')
                  TextButton(
                    onPressed: () async {
                      final text = await askText(
                        context,
                        'Send text to phone',
                        'Text',
                      );
                      if (text != null) session!.text(text);
                    },
                    child: const Text('Send text'),
                  ),
                if (widget.mode == 'screen')
                  TextButton(
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        'Paste clipboard?',
                        'Send the current computer clipboard text to this phone?',
                      );
                      if (ok) {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (data?.text != null) {
                          await widget.store.operation(
                            'Paste clipboard',
                            (_) => session!.paste(data!.text!),
                          );
                        }
                      }
                    },
                    child: const Text('Paste clipboard'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget videoView() {
    final controller = session?.video;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final width = session!.player!.state.width ?? 1080;
    final height = session!.player!.state.height ?? 1920;
    return ColoredBox(
      color: const Color(0xff0d1016),
      child: Center(
        child: AspectRatio(
          aspectRatio: width / height,
          child: Focus(
            focusNode: focus,
            onKeyEvent: (node, event) {
              if (widget.mode != 'screen' || event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              final codes = {
                LogicalKeyboardKey.enter: 66,
                LogicalKeyboardKey.backspace: 67,
                LogicalKeyboardKey.escape: 4,
                LogicalKeyboardKey.arrowLeft: 21,
                LogicalKeyboardKey.arrowRight: 22,
                LogicalKeyboardKey.arrowUp: 19,
                LogicalKeyboardKey.arrowDown: 20,
              };
              final code = codes[event.logicalKey];
              if (code != null) {
                session!.key(code);
                return KeyEventResult.handled;
              }
              if (event.character != null &&
                  !HardwareKeyboard.instance.isControlPressed &&
                  !HardwareKeyboard.instance.isAltPressed) {
                session!.text(event.character!);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: LayoutBuilder(
              builder: (context, constraints) => Listener(
                onPointerDown: (e) {
                  focus.requestFocus();
                  if (widget.mode == 'screen') {
                    session!.touch(
                      0,
                      e.localPosition.dx / constraints.maxWidth,
                      e.localPosition.dy / constraints.maxHeight,
                      width,
                      height,
                    );
                  }
                },
                onPointerMove: (e) {
                  if (widget.mode == 'screen') {
                    session!.touch(
                      2,
                      e.localPosition.dx / constraints.maxWidth,
                      e.localPosition.dy / constraints.maxHeight,
                      width,
                      height,
                    );
                  }
                },
                onPointerUp: (e) {
                  if (widget.mode == 'screen') {
                    session!.touch(
                      1,
                      e.localPosition.dx / constraints.maxWidth,
                      e.localPosition.dy / constraints.maxHeight,
                      width,
                      height,
                    );
                  }
                },
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && widget.mode == 'screen') {
                    session!.scroll(
                      event.localPosition.dx / constraints.maxWidth,
                      event.localPosition.dy / constraints.maxHeight,
                      width,
                      height,
                      event.scrollDelta.dx,
                      event.scrollDelta.dy,
                    );
                  }
                },
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
