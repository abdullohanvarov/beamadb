import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'adb.dart';
import 'media_session.dart';

class Activity {
  final String title;
  final String device;
  final DateTime time = DateTime.now();
  String state = 'Running', detail = '';
  Future<void> Function()? cancel;
  Activity(this.title, this.device);
}

class AppStore extends ChangeNotifier {
  final Adb adb;
  AppStore({Adb? adb}) : adb = adb ?? Adb();
  List<Device> devices = [];
  List<Service> discovered = [];
  String? selected;
  String? startupError;
  String? discoveryError;
  bool initialized = false, scanning = false, disposed = false;
  final List<Activity> activities = [];
  final Map<String, MediaSession> sessions = {};
  final Set<Future<void> Function()> cleanups = {};
  final Map<String, Map<String, String>> metadata = {};
  final Map<String, DateTime> _metadataAt = {};
  final Set<String> _metadataPending = {};
  ThemeMode themeMode = ThemeMode.system;
  bool reducedMotion = false;
  bool get ready => device?.ready ?? false;
  Device? get device => devices.where((d) => d.serial == selected).firstOrNull;
  SharedPreferences? preferences;
  Timer? _timer;

  Future<void> initialize() async {
    try {
      preferences = await SharedPreferences.getInstance();
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == preferences?.getString('theme'),
        orElse: () => ThemeMode.system,
      );
      reducedMotion = preferences?.getBool('reducedMotion') ?? false;
      await adb.initialize(customPath: preferences?.getString('adbPath'));
      initialized = true;
      startupError = null;
      await refresh();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    } catch (e) {
      startupError = '$e';
    }
    emit();
  }

  void emit() {
    if (!disposed) notifyListeners();
  }

  void select(String serial) {
    selected = serial;
    emit();
    unawaited(loadMetadata(serial));
  }

  Future<void> refresh() async {
    if (scanning || disposed) return;
    scanning = true;
    emit();
    try {
      devices = await adb.devices();
      selected ??=
          devices.where((d) => d.ready).firstOrNull?.serial ??
          devices.firstOrNull?.serial;
      if (selected != null &&
          (!_metadataAt.containsKey(selected) ||
              DateTime.now().difference(_metadataAt[selected]!).inSeconds >=
                  30) &&
          ready) {
        unawaited(loadMetadata(selected!));
      }
      startupError = null;
      try {
        discovered = await adb.services();
        discoveryError = null;
      } catch (e) {
        discoveryError = '$e';
      }
    } catch (e) {
      startupError = '$e';
    } finally {
      scanning = false;
      emit();
    }
  }

  Future<void> loadMetadata(String serial) async {
    if (!_metadataPending.add(serial)) return;
    try {
      final text = await adb.shell(
        serial,
        'getprop ro.product.manufacturer; getprop ro.build.version.release; getprop ro.build.version.sdk; dumpsys battery; df -h /sdcard',
      );
      final lines = text.split('\n');
      _metadataAt[serial] = DateTime.now();
      metadata[serial] = {
        'brand': lines.firstOrNull ?? '',
        'android': lines.length > 1 ? lines[1].trim() : '',
        'sdk': lines.length > 2 ? lines[2].trim() : '',
        'battery': RegExp(r'level:\s*(\d+)').firstMatch(text)?.group(1) ?? '—',
        'details': text,
      };
      emit();
    } catch (_) {
      /* The next explicit refresh can retry metadata. */
    } finally {
      _metadataPending.remove(serial);
    }
  }

  Future<T?> operation<T>(
    String title,
    Future<T> Function(Activity item) work, {
    String? target,
  }) async {
    final item = Activity(title, target ?? selected ?? 'Computer');
    activities.insert(0, item);
    if (activities.length > 200) {
      final index = activities.lastIndexWhere((a) => a.state != 'Running');
      if (index >= 0) activities.removeAt(index);
    }
    emit();
    try {
      final result = await work(item);
      item.state = 'Succeeded';
      return result;
    } catch (e) {
      item.state = e is BeamException && e.message.contains('cancelled')
          ? 'Cancelled'
          : 'Failed';
      item.detail = e is BeamException
          ? '${e.message}\n${e.details}'.trim()
          : '$e';
      return null;
    } finally {
      item.cancel = null;
      emit();
    }
  }

  Future<String?> command(
    String title,
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
    String? target,
  }) => operation(title, (item) async {
    final task = await adb.start(
      args,
      timeout: timeout,
      onOutput: (s) {
        item.detail = '${item.detail}$s';
        if (item.detail.length > 16000) {
          item.detail = item.detail.substring(item.detail.length - 16000);
        }
        emit();
      },
    );
    item.cancel = task.cancel;
    final output = await task.output;
    item.detail = output;
    return output;
  }, target: target);

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    emit();
    await preferences?.setString('theme', mode.name);
  }

  Future<void> setReducedMotion(bool value) async {
    reducedMotion = value;
    emit();
    await preferences?.setBool('reducedMotion', value);
  }

  List<Map<String, dynamic>> get workflows {
    try {
      return (jsonDecode(preferences?.getString('workflows') ?? '[]') as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveWorkflows(List<Map<String, dynamic>> value) async {
    await preferences?.setString('workflows', jsonEncode(value));
    emit();
  }

  Future<void> shutdown() async {
    _timer?.cancel();
    await Future.wait(
      cleanups.toList().map((close) => close().catchError((Object _) {})),
    );
    await adb.close();
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
