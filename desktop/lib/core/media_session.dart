import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'adb.dart';

/// Scrcpy raw H.264/PCM transport. libmpv decodes on native threads and the
/// media_kit texture bridge renders without copying frames through Dart.
class MediaSession extends ChangeNotifier {
  final Adb adb;
  final String device, mode;
  Player? player;
  VideoController? video;
  Process? _serverProcess;
  Socket? _source, _control, _consumer;
  StreamIterator<List<int>>? _sourceReader;
  List<int> _pendingBytes = [];
  String? _remoteServer;
  ServerSocket? _relay;
  int? _forwardPort;
  int cameraRotation = 0;
  bool cameraAudio = false;
  bool cameraAudioMuted = false;
  Player? audioPlayer;
  Socket? _audioSource;
  ServerSocket? _audioRelay;
  Socket? _audioConsumer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String status = 'Stopped', detail = '';
  bool _closing = false, _disposed = false;
  bool muted = false, recording = false;
  String? recordingPath;
  MediaSession(this.adb, this.device, this.mode);
  bool get audioOnly => mode == 'audio' || mode == 'mic';
  bool get active => player != null;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({
    int maxSize = 1920,
    int fps = 60,
    String camera = 'back',
    int bitrate = 8000000,
    bool stayAwake = true,
    int cameraRotation = 0,
    bool cameraAudio = true,
  }) async {
    if (active || _closing) return;
    this.cameraRotation = cameraRotation;
    this.cameraAudio = cameraAudio;
    cameraAudioMuted = false;
    status = 'Starting';
    detail = '';
    emit();
    try {
      if (adb.server.isEmpty || adb.serverVersion.isEmpty) {
        throw const BeamException(
          'Bundled scrcpy tools are missing. Reinstall BeamADB or check the tool folder.',
        );
      }
      if (!File(adb.server).existsSync()) {
        throw const BeamException('The Android capture server is missing.');
      }
      if (mode == 'camera') {
        final sdk =
            int.tryParse(
              (await adb.shell(device, 'getprop ro.build.version.sdk')).trim(),
            ) ??
            0;
        if (sdk < 31) {
          throw const BeamException(
            'Camera streaming requires Android 12 or newer.',
          );
        }
      }
      final id = Random.secure()
          .nextInt(0x7fffffff)
          .toRadixString(16)
          .padLeft(8, '0');
      _remoteServer = '/data/local/tmp/beamadb-$id.jar';
      await adb.run(['-s', device, 'push', adb.server, _remoteServer!]);
      final portText = await adb.run([
        '-s',
        device,
        'forward',
        'tcp:0',
        'localabstract:scrcpy_$id',
      ]);
      _forwardPort = int.parse(portText.trim());
      final hasAudio = audioOnly || (mode == 'camera' && cameraAudio);
      final args = [
        'CLASSPATH=$_remoteServer',
        'app_process',
        '/',
        'com.genymobile.scrcpy.Server',
        adb.serverVersion,
        'scid=$id',
        'tunnel_forward=true',
        'raw_stream=true',
        'send_dummy_byte=true',
        'cleanup=true',
        'video=${!audioOnly}',
        'audio=$hasAudio',
        'control=${!audioOnly && mode == 'screen'}',
        'max_size=$maxSize',
        'max_fps=$fps',
        'video_codec=h264',
        'video_bit_rate=$bitrate',
        'stay_awake=$stayAwake',
        if (hasAudio) ...[
          'audio_codec=raw',
          'audio_source=${mode == 'camera' ? 'mic' : (mode == 'mic' ? 'mic' : 'output')}',
        ],
        if (mode == 'camera') ...[
          'video_source=camera',
          if (camera.startsWith('id:'))
            'camera_id=${camera.substring(3)}'
          else
            'camera_facing=$camera',
        ],
      ];
      _serverProcess = await adb.spawn([
        '-s',
        device,
        'shell',
        '${args.first} ${args.skip(1).map(shellQuote).join(' ')}',
      ]);
      void log(String chunk) {
        detail = '$detail$chunk';
        if (detail.length > 8000) {
          detail = detail.substring(detail.length - 8000);
        }
      }

      _subscriptions.add(
        _serverProcess!.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(log),
      );
      _subscriptions.add(
        _serverProcess!.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(log),
      );
      unawaited(
        _serverProcess!.exitCode.then((code) {
          if (!_closing && player != null) {
            status = 'Disconnected';
            detail +=
                '\nCapture stopped (exit $code). Reconnect the device and retry.';
            emit();
          }
        }),
      );
      // ADB accepts the local TCP socket even before Android is listening.
      // Wait for scrcpy's dummy byte, not merely for a successful TCP connect.
      for (var attempt = 0; attempt < 30; attempt++) {
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            _forwardPort!,
            timeout: const Duration(milliseconds: 500),
          );
          _source = socket;
          final reader = StreamIterator<List<int>>(socket);
          _sourceReader = reader;
          final ready = await reader.moveNext().timeout(
            const Duration(seconds: 1),
          );
          if (!ready || reader.current.isEmpty || reader.current.first != 0) {
            throw const BeamException('Capture handshake is not ready.');
          }
          _pendingBytes = reader.current.skip(1).toList();
          break;
        } catch (_) {
          _source?.destroy();
          _source = null;
          await _sourceReader?.cancel();
          _sourceReader = null;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      if (_source == null) {
        throw BeamException('The phone capture service did not start.', detail);
      }
      if (mode == 'camera' && cameraAudio) {
        for (var attempt = 0; attempt < 15; attempt++) {
          try {
            _audioSource = await Socket.connect(
              InternetAddress.loopbackIPv4,
              _forwardPort!,
              timeout: const Duration(milliseconds: 500),
            );
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
        }
        if (_audioSource != null) {
          _audioRelay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
          _subscriptions.add(
            _audioRelay!.listen((consumer) {
              if (_audioConsumer != null) {
                consumer.destroy();
                return;
              }
              _audioConsumer = consumer;
              unawaited(consumer.done.catchError((Object _) {}));
              unawaited(
                consumer.addStream(_audioSource!).catchError((Object e) {
                  if (!_closing) {
                    detail += '\nCamera audio stream error: $e';
                  }
                }),
              );
            }),
          );
          audioPlayer = Player(
            configuration: const PlayerConfiguration(
              bufferSize: 256 * 1024,
              logLevel: MPVLogLevel.warn,
            ),
          );
          final nativeAudio = audioPlayer!.platform as NativePlayer;
          await nativeAudio.setProperty('demuxer', 'rawaudio');
          await nativeAudio.setProperty('demuxer-rawaudio-rate', '48000');
          await nativeAudio.setProperty('demuxer-rawaudio-channels', 'stereo');
          await nativeAudio.setProperty('demuxer-rawaudio-format', 's16le');
          await nativeAudio.setProperty('cache', 'no');
          await nativeAudio.setProperty('untimed', 'yes');
          unawaited(
            audioPlayer!
                .open(Media('tcp://127.0.0.1:${_audioRelay!.port}'))
                .catchError((Object e) {
                  detail += '\nCamera audio playback error: $e';
                }),
          );
        }
      }
      if (!audioOnly && mode == 'screen') {
        _control = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _forwardPort!,
          timeout: const Duration(seconds: 3),
        );
        _subscriptions.add(
          _control!.listen(
            (_) {},
            onError: (Object e) {
              detail += '\nControl connection: $e';
            },
          ),
        );
      }
      _relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _subscriptions.add(
        _relay!.listen((consumer) {
          if (_consumer != null) {
            consumer.destroy();
            return;
          }
          _consumer = consumer;
          unawaited(consumer.done.catchError((Object _) {}));
          unawaited(
            consumer
                .addStream(_mediaBytes())
                .then((_) {
                  if (!_closing) {
                    status = 'Disconnected';
                    emit();
                  }
                  consumer.destroy();
                })
                .catchError((Object e) {
                  if (!_closing) {
                    status = 'Failed';
                    detail += '\nStream interrupted: $e';
                    emit();
                  }
                }),
          );
        }),
      );
      player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 512 * 1024,
          logLevel: MPVLogLevel.warn,
        ),
      );
      _subscriptions.add(
        player!.stream.log.listen((entry) {
          log('[${entry.prefix}] ${entry.text}\n');
        }),
      );
      if (!audioOnly) {
        video = VideoController(player!);
        _subscriptions.add(player!.stream.width.listen((_) => emit()));
        _subscriptions.add(player!.stream.height.listen((_) => emit()));
      }
      final native = player!.platform as NativePlayer;
      await native.setProperty('demuxer', audioOnly ? 'rawaudio' : 'lavf');
      // media_kit opens a one-item playlist. Only our generated loopback TCP
      // URL is ever loaded into this private player; external playlists are not accepted.
      await native.setProperty('load-unsafe-playlists', 'yes');
      await native.setProperty('cache', 'no');
      await native.setProperty('demuxer-readahead-secs', '0');
      if (audioOnly) {
        await native.setProperty('demuxer-rawaudio-rate', '48000');
        await native.setProperty('demuxer-rawaudio-channels', 'stereo');
        await native.setProperty('demuxer-rawaudio-format', 's16le');
      } else {
        await native.setProperty('demuxer-lavf-format', 'h264');
        await native.setProperty('demuxer-lavf-probesize', '32');
        await native.setProperty('demuxer-lavf-analyzeduration', '0.1');
        await native.setProperty('untimed', 'yes');
        await native.setProperty('vd-lavc-threads', '1');
        if (cameraRotation != 0) {
          await native.setProperty('video-rotate', '$cameraRotation');
        }
      }
      _subscriptions.add(
        player!.stream.error.listen((error) {
          if (!_closing) {
            status = 'Failed';
            detail += '\n$error';
            emit();
          }
        }),
      );
      emit();
      await player!
          .open(Media('tcp://127.0.0.1:${_relay!.port}'))
          .timeout(const Duration(seconds: 15));
      if (!audioOnly) {
        if ((player!.state.width ?? 0) <= 1) {
          await player!.stream.width
              .firstWhere((width) => width != null && width > 1)
              .timeout(const Duration(seconds: 15));
        }
        await video!.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 15),
        );
      }
      if (audioOnly && player!.state.audioParams.sampleRate == null) {
        await player!.stream.audioParams
            .firstWhere((params) => (params.sampleRate ?? 0) > 0)
            .timeout(const Duration(seconds: 15));
      }
      if (status == 'Starting') status = 'Live';
      emit();
    } catch (e) {
      final logs = detail;
      await stop();
      status = 'Failed';
      detail =
          '${e is TimeoutException ? 'No media arrived. Check the device and capture permissions.' : e}\n$logs';
      emit();
      throw BeamException('Could not start $mode streaming.', detail);
    }
  }

  Stream<List<int>> _mediaBytes() async* {
    if (_pendingBytes.isNotEmpty) yield _pendingBytes;
    _pendingBytes = [];
    final reader = _sourceReader!;
    while (!_closing && await reader.moveNext()) {
      yield reader.current;
    }
  }

  void key(int code) {
    for (final action in [0, 1]) {
      final data = ByteData(14)
        ..setUint8(0, 0)
        ..setUint8(1, action)
        ..setUint32(2, code);
      _control?.add(data.buffer.asUint8List());
    }
  }

  void text(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > 300) return;
    final data = ByteData(5)
      ..setUint8(0, 1)
      ..setUint32(1, bytes.length);
    _control?.add([...data.buffer.asUint8List(), ...bytes]);
  }

  void displayPower(bool on) {
    _control?.add([10, on ? 1 : 0]);
  }

  Future<void> paste(String text) async {
    final bytes = utf8.encode(text);
    if (_control == null) {
      throw const BeamException('Start screen control first.');
    }
    if (bytes.length > 256 * 1024) {
      throw const BeamException(
        'Clipboard text is too large. Use file transfer for large content.',
      );
    }
    final header = ByteData(14)
      ..setUint8(0, 9)
      ..setUint64(1, 0)
      ..setUint8(9, 1)
      ..setUint32(10, bytes.length);
    _control!.add([...header.buffer.asUint8List(), ...bytes]);
    await _control!.flush();
  }

  void scroll(double x, double y, int width, int height, double dx, double dy) {
    final data = ByteData(21)
      ..setUint8(0, 3)
      ..setUint32(1, (x * width).round().clamp(0, width - 1))
      ..setUint32(5, (y * height).round().clamp(0, height - 1))
      ..setUint16(9, width)
      ..setUint16(11, height)
      ..setInt16(13, (-dx / 60 * 2048).round().clamp(-32768, 32767))
      ..setInt16(15, (-dy / 60 * 2048).round().clamp(-32768, 32767));
    _control?.add(data.buffer.asUint8List());
  }

  void touch(int action, double x, double y, int width, int height) {
    if (width <= 0 || height <= 0) return;
    final data = ByteData(32)
      ..setUint8(0, 2)
      ..setUint8(1, action)
      ..setUint64(2, 0)
      ..setUint32(10, (x * width).round().clamp(0, width - 1))
      ..setUint32(14, (y * height).round().clamp(0, height - 1))
      ..setUint16(18, width)
      ..setUint16(20, height)
      ..setUint16(22, action == 1 ? 0 : 65535)
      ..setUint32(24, 1)
      ..setUint32(28, action == 1 ? 0 : 1);
    _control?.add(data.buffer.asUint8List());
  }

  Future<void> rotateCamera([int? newRotation]) async {
    cameraRotation = newRotation ?? ((cameraRotation + 90) % 360);
    if (player != null) {
      try {
        final native = player!.platform as NativePlayer;
        await native.setProperty('video-rotate', '$cameraRotation');
      } catch (_) {}
    }
    emit();
  }

  Future<void> setCameraAudioMuted(bool value) async {
    cameraAudioMuted = value;
    await audioPlayer?.setVolume(value ? 0 : 100);
    emit();
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    await player?.setVolume(value ? 0 : 100);
    emit();
  }

  Future<void> record(String? path) async {
    if (player == null) throw const BeamException('Start a stream first.');
    await (player!.platform as NativePlayer).setProperty(
      'stream-record',
      path ?? '',
    );
    recording = path != null;
    recordingPath = path;
    emit();
  }

  Future<void> stop() async {
    if (_closing) return;
    _closing = true;
    if (recording) {
      try {
        await record(null);
      } catch (_) {}
    }
    _source?.destroy();
    _source = null;
    await _sourceReader?.cancel();
    _sourceReader = null;
    _control?.destroy();
    _control = null;
    _consumer?.destroy();
    _consumer = null;
    await _relay?.close();
    _relay = null;
    _audioConsumer?.destroy();
    _audioConsumer = null;
    await _audioRelay?.close();
    _audioRelay = null;
    _audioSource?.destroy();
    _audioSource = null;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await audioPlayer?.dispose();
    audioPlayer = null;
    await player?.dispose();
    player = null;
    video = null;
    _serverProcess?.kill();
    _serverProcess = null;
    if (_forwardPort != null) {
      try {
        await adb.run([
          '-s',
          device,
          'forward',
          '--remove',
          'tcp:$_forwardPort',
        ]);
      } catch (_) {}
      _forwardPort = null;
    }
    if (_remoteServer != null && !adb.closed) {
      try {
        await adb.shell(device, 'rm -f ${shellQuote(_remoteServer!)}');
      } catch (_) {}
      _remoteServer = null;
    }
    status = 'Stopped';
    _closing = false;
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
