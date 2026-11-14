import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../core/mirror_window.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../core/adb.dart';
import '../core/friendly_error.dart';
import '../core/media_session.dart';
import '../core/store.dart';
import '../core/recordings.dart';
import '../core/theme.dart';
import 'widgets.dart';

class MediaPage extends StatefulWidget {
  final AppStore store;
  final String mode;
  final String? runtimeError;
  final bool autoStart;
  final bool emulatorMode;
  final List<String> launchArgs;
  const MediaPage({
    super.key,
    required this.store,
    required this.mode,
    this.runtimeError,
    this.autoStart = false,
    this.emulatorMode = false,
    this.launchArgs = const [],
  });
  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  MediaSession? session;
  int quality = 1920, fps = 60, bitrate = 8000000;
  bool stayAwake = true, phoneScreenOff = false;
  String camera = 'back', source = 'audio';
  int cameraRotation = 0;
  bool cameraAudio = true;
  bool fullscreen = false;
  bool isPinned = false;
  bool starting = false;
  bool autoStarted = false;
  Timer? recoveryTimer;
  bool recovering = false;
  bool hadLiveStream = false;
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
    final options = widget.launchArgs
        .where((a) => a.startsWith('--mirror-options='))
        .firstOrNull;
    if (options != null) {
      try {
        final data = jsonDecode(
          utf8.decode(
            base64Url.decode(options.substring('--mirror-options='.length)),
          ),
        );
        quality = data['quality'] as int;
        fps = data['fps'] as int;
        bitrate = data['bitrate'] as int;
        stayAwake = data['stayAwake'] as bool;
      } catch (_) {}
    }
    recoveryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => recoverMirror(),
    );
    session = widget.store.sessions['${widget.store.selected}:${widget.mode}'];
    session?.addListener(updated);
    _autoStart();
  }

  @override
  void didUpdateWidget(covariant MediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _autoStart();
  }

  void _autoStart() {
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

  Future<void> recoverMirror() async {
    if (!mounted ||
        !widget.emulatorMode ||
        recovering ||
        starting ||
        !hadLiveStream ||
        !widget.store.ready) {
      return;
    }
    final routeChanged =
        session != null && session!.device != widget.store.selected;
    if (!routeChanged &&
        session?.status != 'Disconnected' &&
        session?.status != 'Failed') {
      return;
    }
    recovering = true;
    try {
      await session?.stop();
      if (mounted && hadLiveStream) await start(quiet: true);
    } finally {
      recovering = false;
    }
  }

  Future<void> start({bool quiet = false}) async {
    if (widget.mode == 'screen' && !widget.emulatorMode) {
      await widget.store.openMirror(
        quality: quality,
        fps: fps,
        bitrate: bitrate,
        stayAwake: stayAwake,
      );
      if (mounted) await showResult(context, widget.store);
      return;
    }
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
        maxSize: device.relay ? quality.clamp(0, 1280) : quality,
        camera: camera,
        fps: device.relay ? fps.clamp(0, 30) : fps,
        bitrate: device.relay ? bitrate.clamp(0, 2000000) : bitrate,
        stayAwake: stayAwake,
        cameraRotation: cameraRotation,
        cameraAudio: cameraAudio,
      ),
    );
    starting = false;
    if (mounted) {
      setState(() {});
      focus.requestFocus();
      if (!quiet) await showResult(context, widget.store);
    }
  }

  void updated() {
    if (session?.status == 'Live') hadLiveStream = true;
    if (session?.status == 'Stopped' && !recovering && !starting) {
      hadLiveStream = false;
    }
    if (widget.emulatorMode && session != null) {
      stdout.writeln(
        '$mirrorStatusPrefix${jsonEncode({'status': session!.status, 'detail': session!.detail})}',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> stopStream() async {
    hadLiveStream = false;
    await session?.stop();
  }

  bool switchingCamera = false;
  Future<void> switchCamera() async {
    if (switchingCamera) return;
    switchingCamera = true;
    final next = camera == 'front' ? 'back' : 'front';
    setState(() => camera = next);
    if (session?.active == true) {
      final wasLive = session?.status == 'Live';
      await stopStream();
      if (wasLive && mounted) {
        await start(quiet: true);
      }
    }
    switchingCamera = false;
    if (mounted) setState(() {});
  }

  Future<void> detached() async {
    final device = widget.store.device;
    if (device == null) return;
    await stopStream();
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
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Saved to $path')));
        }
      });
    } else {
      await widget.store.operation('Start recording', (_) async {
        final phone = widget.store.phones
            .where(
              (p) =>
                  p.connections.any((d) => d.serial == widget.store.selected),
            )
            .firstOrNull;
        final path = await recordingPath(
          widget.mode,
          phone?.name ?? widget.store.device?.label ?? 'Phone',
        );
        await session!.record(path);
      });
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
    recoveryTimer?.cancel();
    session?.removeListener(updated);
    focus.dispose();
    super.dispose();
  }

  Widget emulatorLayout(BuildContext context, bool active) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xff0b0e14),
      body: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xff121620),
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.smartphone_rounded,
                            size: 16,
                            color: beamBlue,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'BeamADB · ${widget.store.device?.label ?? 'Phone Mirror'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                WindowControls(
                  buttonWidth: 32,
                  buttonHeight: 26,
                  onClose: () async {
                    await stopStream();
                    await windowManager.destroy();
                    exit(0);
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: active
                      ? videoView()
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.smartphone_rounded,
                                  size: 56,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: .5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  session?.status == 'Failed' ||
                                          session?.status == 'Disconnected'
                                      ? 'Mirror disconnected'
                                      : (starting
                                            ? 'Connecting to phone…'
                                            : 'Screen mirror is ready'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (session?.detail.isNotEmpty == true) ...[
                                  const SizedBox(height: 8),
                                  Builder(
                                    builder: (context) {
                                      final friendly = FriendlyError.parse(
                                        session!.detail,
                                      );
                                      return Column(
                                        children: [
                                          Text(
                                            friendly.description,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: colors.error,
                                            ),
                                          ),
                                          if (friendly.suggestion != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              friendly.suggestion!,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: starting ? null : start,
                                  icon: Icon(
                                    starting
                                        ? Icons.timelapse
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    starting ? 'Starting…' : 'Start Mirror',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Container(
                  width: 46,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: .85,
                    ),
                    border: Border(
                      left: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .3),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          IconButton(
                            tooltip: phoneScreenOff
                                ? 'Turn screen on'
                                : 'Turn screen off (Power)',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              phoneScreenOff
                                  ? Icons.power_settings_new_rounded
                                  : Icons.power_rounded,
                              color: phoneScreenOff
                                  ? Colors.grey
                                  : Colors.amber,
                            ),
                            onPressed: () {
                              phoneScreenOff = !phoneScreenOff;
                              session?.displayPower(!phoneScreenOff);
                              setState(() {});
                            },
                          ),
                          IconButton(
                            tooltip: 'Volume Up',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.volume_up_rounded),
                            onPressed: () => session?.key(24),
                          ),
                          IconButton(
                            tooltip: 'Volume Down',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.volume_down_rounded),
                            onPressed: () => session?.key(25),
                          ),
                          IconButton(
                            tooltip: 'Rotate screen',
                            iconSize: 19,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.screen_rotation_rounded),
                            onPressed: () async {
                              final serial = widget.store.selected;
                              if (serial != null) {
                                await widget.store.operation('Rotate screen', (
                                  _,
                                ) async {
                                  await widget.store.adb.shell(
                                    serial,
                                    'settings put system user_rotation \$(( ( \$(settings get system user_rotation 2>/dev/null || echo 0) + 1 ) % 4 ))',
                                  );
                                });
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Take screenshot',
                            iconSize: 19,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.photo_camera_rounded),
                            onPressed: screenshot,
                          ),
                          IconButton(
                            tooltip: session?.recording == true
                                ? 'Stop recording'
                                : 'Record screen',
                            iconSize: 19,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              session?.recording == true
                                  ? Icons.stop_circle_rounded
                                  : Icons.fiber_manual_record_rounded,
                              color: session?.recording == true
                                  ? Colors.red
                                  : null,
                            ),
                            onPressed: record,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: colors.outlineVariant.withValues(
                                alpha: .4,
                              ),
                            ),
                          ),
                          AndroidNavControls(
                            isVertical: true,
                            iconSize: 20,
                            buttonColor: const Color(0xffeceef4),
                            onBack: () => session?.key(4),
                            onHome: () => session?.key(3),
                            onRecents: () => session?.key(187),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: colors.outlineVariant.withValues(
                                alpha: .4,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Paste clipboard',
                            iconSize: 19,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null &&
                                  data!.text!.isNotEmpty) {
                                await widget.store.operation(
                                  'Paste clipboard',
                                  (_) => session!.paste(data.text!),
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Send text to phone',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.keyboard_rounded),
                            onPressed: () async {
                              final text = await askText(
                                context,
                                'Send text to phone',
                                'Text',
                              );
                              if (text != null && text.isNotEmpty) {
                                session?.text(text);
                              }
                            },
                          ),
                          IconButton(
                            tooltip: isPinned
                                ? 'Unpin window'
                                : 'Always on top',
                            iconSize: 19,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              color: isPinned ? beamBlue : null,
                            ),
                            onPressed: () async {
                              setState(() => isPinned = !isPinned);
                              await windowManager.setAlwaysOnTop(isPinned);
                            },
                          ),
                          IconButton(
                            tooltip: fullscreen
                                ? 'Exit fullscreen'
                                : 'Fullscreen',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                            ),
                            onPressed: () async {
                              fullscreen = !fullscreen;
                              await windowManager.setFullScreen(fullscreen);
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mirror = widget.mode == 'screen' && !widget.emulatorMode
        ? widget.store.mirrors[widget.store.selected]
        : null;
    final active = (session?.active ?? false) || (mirror?.open ?? false);
    if (widget.emulatorMode && widget.mode == 'screen') {
      return Theme(
        data: beamTheme(Brightness.dark),
        child: VirtualWindowFrame(
          child: Builder(builder: (context) => emulatorLayout(context, active)),
        ),
      );
    }
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
            if (active && widget.mode == 'camera') ...[
              IconButton(
                tooltip: camera == 'front'
                    ? 'Switch to Back camera'
                    : 'Switch to Front camera',
                icon: Icon(
                  camera == 'front'
                      ? Icons.camera_rear_rounded
                      : Icons.camera_front_rounded,
                ),
                onPressed: switchCamera,
              ),
              IconButton(
                tooltip: 'Rotate camera 90°',
                icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
                onPressed: () {
                  final next =
                      ((session?.cameraRotation ?? cameraRotation) + 90) % 360;
                  session?.rotateCamera(next);
                  setState(() => cameraRotation = next);
                },
              ),
              if (session?.cameraAudio == true)
                IconButton(
                  tooltip: session!.cameraAudioMuted
                      ? 'Unmute camera voice'
                      : 'Mute camera voice',
                  icon: Icon(
                    session!.cameraAudioMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                  ),
                  color: session!.cameraAudioMuted
                      ? Colors.redAccent
                      : beamBlue,
                  onPressed: () {
                    session!.setCameraAudioMuted(!session!.cameraAudioMuted);
                    setState(() {});
                  },
                ),
            ],
            if (active && widget.mode != 'audio' && mirror == null)
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
            if (active && mirror == null)
              OutlinedButton.icon(
                onPressed: detached,
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Separate window'),
              ),
            FilledButton.icon(
              onPressed: starting
                  ? null
                  : active
                  ? () => mirror != null ? mirror.stop() : stopStream()
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
                ? 'The stream disconnected. Tap Start to reconnect.'
                : FriendlyError.parse(session!.detail, 'Stream Interrupted').summary,
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
              if (widget.mode == 'camera') ...[
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
                DropdownButton<int>(
                  value: cameraRotation,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0° (Normal)')),
                    DropdownMenuItem(value: 90, child: Text('90° (Clockwise)')),
                    DropdownMenuItem(
                      value: 180,
                      child: Text('180° (Inverted)'),
                    ),
                    DropdownMenuItem(
                      value: 270,
                      child: Text('270° (Counter-clockwise)'),
                    ),
                  ],
                  onChanged: (v) => setState(() => cameraRotation = v!),
                ),
                FilterChip(
                  selected: cameraAudio,
                  showCheckmark: false,
                  avatar: Icon(
                    cameraAudio ? Icons.mic_rounded : Icons.mic_off_rounded,
                    size: 16,
                    color: cameraAudio ? beamBlue : Colors.grey,
                  ),
                  label: Text(
                    cameraAudio ? 'Camera audio: ON' : 'Camera audio: OFF',
                  ),
                  onSelected: (val) => setState(() => cameraAudio = val),
                ),
              ],
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
        const SizedBox(height: 8),
        Expanded(
          child: Panel(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: mirror != null
                  ? EmptyState(
                      Icons.screen_share_rounded,
                      mirror.open
                          ? (mirror.status == 'Live'
                                ? 'Screen is being mirrored'
                                : 'Screen mirror · ${mirror.status}')
                          : 'Screen mirror · ${mirror.status}',
                      mirror.detail.isNotEmpty
                          ? FriendlyError.parse(mirror.detail, 'Screen Mirror').description
                          : mirror.open
                          ? 'Your phone screen is open in a separate window.'
                          : 'Start Screen to open a new mirror window.',
                      action: mirror.open
                          ? OutlinedButton.icon(
                              onPressed: () => mirror.command('focus'),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Show mirror window'),
                            )
                          : null,
                    )
                  : active
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
                        if (widget.mode == 'camera' && active)
                          Positioned(
                            right: 16,
                            top: 16,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              child: IconButton(
                                tooltip: camera == 'front'
                                    ? 'Switch to Back camera'
                                    : 'Switch to Front camera',
                                icon: Icon(
                                  camera == 'front'
                                      ? Icons.camera_rear_rounded
                                      : Icons.camera_front_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: switchCamera,
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
        if (active && mirror == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.mode == 'screen') ...[
                  AndroidNavControls(
                    onBack: () => session!.key(4),
                    onHome: () => session!.key(3),
                    onRecents: () => session!.key(187),
                  ),
                  const SizedBox(width: 4),
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
                      color: phoneScreenOff ? Colors.grey : null,
                    ),
                  ),
                ],
                if (widget.mode == 'camera') ...[
                  FilledButton.tonalIcon(
                    onPressed: switchCamera,
                    icon: Icon(
                      camera == 'front'
                          ? Icons.camera_rear_rounded
                          : Icons.camera_front_rounded,
                      size: 18,
                    ),
                    label: Text(
                      camera == 'front'
                          ? 'Switch to Back'
                          : 'Switch to Front',
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await session?.rotateCamera();
                      setState(() {});
                    },
                    icon: const Icon(Icons.rotate_right_rounded, size: 18),
                    label: Text('Rotate (${session?.cameraRotation ?? 0}°)'),
                  ),
                  if (session?.cameraAudio == true)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: (session?.cameraAudioMuted ?? false)
                            ? Colors.red
                            : beamBlue,
                      ),
                      onPressed: () async {
                        final newMuted = !(session?.cameraAudioMuted ?? false);
                        await session?.setCameraAudioMuted(newMuted);
                        setState(() {});
                      },
                      icon: Icon(
                        (session?.cameraAudioMuted ?? false)
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        size: 18,
                      ),
                      label: Text(
                        (session?.cameraAudioMuted ?? false)
                            ? 'Turn on voice'
                            : 'Turn off voice',
                      ),
                    ),
                ],
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
    final rawW = session!.player!.state.width ?? 1080;
    final rawH = session!.player!.state.height ?? 1920;
    final isRotated = (session?.cameraRotation ?? 0) % 180 != 0;
    final width = isRotated ? rawH : rawW;
    final height = isRotated ? rawW : rawH;
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
