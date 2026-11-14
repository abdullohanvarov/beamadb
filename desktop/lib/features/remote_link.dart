import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../core/store.dart';

class RemoteLink extends StatefulWidget {
  final AppStore store;
  const RemoteLink({super.key, required this.store});
  @override
  State<RemoteLink> createState() => _RemoteLinkState();
}

class _RemoteLinkState extends State<RemoteLink> {
  bool busy = false;
  String presence = '';
  bool cellular = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    readPresence();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => readPresence());
  }

  Future<void> readPresence() async {
    final root =
        Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    try {
      final config = jsonDecode(
        await File('$root/beamadb-link/desktop.json').readAsString(),
      );
      final enabled = config['cellularMode'] == true;
      if (mounted && cellular != enabled) setState(() => cellular = enabled);
      final files = <File>[File('$root/beamadb-link/status')];
      final phones = Directory('$root/beamadb-link/phones');
      if (await phones.exists()) {
        await for (final entry in phones.list()) {
          if (entry is Directory) files.add(File('${entry.path}/status'));
        }
      }
      var online = 0;
      for (final status in files) {
        if (await status.exists() &&
            DateTime.now().difference(await status.lastModified()).inSeconds <=
                40 &&
            await status.readAsString() == 'Phone online') {
          online++;
        }
      }
      final value = '$online phone(s) reachable through the relay';
      if (mounted && presence != value) setState(() => presence = value);
    } catch (_) {
      if (mounted && presence.isNotEmpty) setState(() => presence = '');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String message = '';
  Future<void> configure() async {
    setState(() => busy = true);
    try {
      final desktop = await openFile(confirmButtonText: 'Choose desktop.json');
      if (desktop == null) return;
      final phone = await openFile(confirmButtonText: 'Choose phone.json');
      if (phone == null) return;
      final script = File(
        '${File(Platform.resolvedExecutable).parent.path}/remote/install-agent.sh',
      );
      if (!await script.exists()) {
        throw Exception(
          'Install the BeamADB release bundle containing the remote agent.',
        );
      }
      final result = await Process.run('bash', [
        script.path,
        desktop.path,
        phone.path,
      ]);
      if (result.exitCode != 0) {
        throw Exception('Agent setup failed: ${result.stderr}');
      }
      if (mounted) {
        setState(
          () => message =
              'Ubuntu agent enabled. Send the invitation to your paired phone.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    final serial = widget.store.selected;
    if (serial == null) return;
    setState(() => busy = true);
    try {
      await widget.store.setupPhone(serial, retry: true);
      if (mounted) {
        setState(
          () => message =
              widget.store.linkSetup[serial] ??
              'Connect this phone directly over USB or local ADB to configure it.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setCellular() async {
    final enable = !cellular;
    if (enable) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep ADB available on cellular?'),
          content: const Text(
            'After connecting on trusted Wi-Fi, BeamADB starts an ADB TCP listener on the phone. It requires an authorized ADB key, but other devices on the local network can reach port 45885. Internet traffic stays inside the encrypted relay. After a phone reboot, trusted Wi-Fi is needed again. Network changes may interrupt running commands.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable cellular mode'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final script =
          '${File(Platform.resolvedExecutable).parent.path}/remote/cellular.py';
      final result = await Process.run('python3', [
        script,
        enable ? 'enable' : 'disable',
      ]);
      if (mounted) {
        setState(() => message = '${result.stdout}${result.stderr}'.trim());
      }
      await readPresence();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Connect a phone using USB or authorized local ADB. BeamADB installs and configures its companion automatically. Android may ask you to approve installation or debugging.',
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : configure,
        child: const Text('Configure Ubuntu agent'),
      ),
      TextButton(
        onPressed: busy || !widget.store.ready ? null : send,
        child: const Text('Set up selected phone'),
      ),
      const SizedBox(height: 16),
      Text('Cellular handover: ${cellular ? "enabled" : "disabled"}'),
      const Text(
        'Connect on trusted Wi-Fi after each phone reboot. Then the relay can reconnect over mobile data.',
      ),
      TextButton(
        onPressed: busy ? null : setCellular,
        child: Text(
          cellular ? 'Disable cellular mode' : 'Enable cellular mode',
        ),
      ),
      TextButton(
        onPressed: busy || !widget.store.ready
            ? null
            : () async {
                await widget.store.adb.run([
                  '-s',
                  widget.store.selected!,
                  'shell',
                  'am',
                  'start',
                  '-n',
                  'dev.beamadb.link/.Setup',
                ]);
              },
        child: const Text('Open companion settings on phone'),
      ),
      if (presence.isNotEmpty) Text(presence),
      if (message.isNotEmpty) Text(message),
    ],
  );
}
