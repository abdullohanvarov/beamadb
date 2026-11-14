import 'dart:async';
import 'dart:io';
import 'remote_link.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import '../core/adb.dart';
import '../core/friendly_error.dart';
import '../core/store.dart';
import 'widgets.dart';

class PairingDialog extends StatefulWidget {
  final AppStore store;
  const PairingDialog({super.key, required this.store});
  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final address = TextEditingController(),
      code = TextEditingController(),
      connection = TextEditingController();
  int method = 0, generation = 0;
  bool busy = false;
  String? error;
  String status = 'Scan from Wireless debugging → Pair device with QR code.';
  String service = '', secret = '';
  DateTime expires = DateTime.now();
  Timer? timer;
  @override
  void initState() {
    super.initState();
    regenerate();
  }

  void regenerate() {
    generation++;
    final random = Random.secure();
    service = 'ADB-WIFI-${random.nextInt(0x7fffffff).toRadixString(16)}';
    secret = (100000 + random.nextInt(900000)).toString();
    expires = DateTime.now().add(const Duration(minutes: 2));
    error = null;
    status = 'Scan from Wireless debugging → Pair device with QR code.';
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => scan());
    if (mounted) setState(() {});
  }

  Future<void> scan() async {
    if (method != 0 || busy) return;
    if (DateTime.now().isAfter(expires)) {
      timer?.cancel();
      if (mounted) {
        setState(() => status = 'This QR code expired. Generate a new one.');
      }
      return;
    }
    final token = generation;
    try {
      final services = await widget.store.adb.services();
      final match = services
          .where(
            (s) =>
                s.pairing &&
                (s.name == service || s.name.startsWith('$service.')),
          )
          .firstOrNull;
      if (match != null && mounted && token == generation) {
        await doPair(match.address, secret, token: token);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = FriendlyError.parse(e, 'Pairing Failed').summary,
        );
      }
    }
  }

  Future<void> doPair(String target, String pairingCode, {int? token}) async {
    setState(() {
      busy = true;
      error = null;
      status = 'Pairing securely…';
    });
    try {
      await widget.store.adb.pair(target, pairingCode);
      if (!mounted || (token != null && token != generation)) return;
      setState(() => status = 'Paired. Finding the connection port…');
      if (connection.text.trim().isNotEmpty) {
        await widget.store.adb.connect(connection.text.trim());
      } else {
        final host = target.substring(0, target.lastIndexOf(':'));
        String? connect;
        for (var i = 0; i < 8; i++) {
          final services = await widget.store.adb.services();
          connect = services
              .where((s) => !s.pairing && s.host == host)
              .firstOrNull
              ?.address;
          if (connect != null) break;
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted || (token != null && token != generation)) return;
        }
        if (connect == null) {
          setState(
            () => status =
                'Paired successfully. Use Direct connection with the address shown on the main Wireless debugging screen.',
          );
          return;
        }
        await widget.store.adb.connect(connect);
      }
      timer?.cancel();
      await widget.store.refresh();
      if (mounted) setState(() => status = 'Connected. Your phone is ready.');
    } catch (e) {
      if (mounted) {
        setState(
          () => error = FriendlyError.parse(e, 'Pairing Failed').summary,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    address.dispose();
    code.dispose();
    connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect your phone'),
    content: SizedBox(
      width: 660,
      height: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('QR code')),
              const ButtonSegment(value: 1, label: Text('Pairing code')),
              const ButtonSegment(value: 2, label: Text('Direct')),
              const ButtonSegment(value: 3, label: Text('USB')),
              if (Platform.isLinux)
                const ButtonSegment(value: 4, label: Text('Remote')),
            ],
            selected: {method},
            onSelectionChanged: busy
                ? null
                : (v) => setState(() {
                    method = v.first;
                    error = null;
                  }),
          ),
          const SizedBox(height: 20),
          if (error != null)
            Notice(
              FriendlyError.parse(error, 'Connection Error').summary,
              error: true,
            ),
          Expanded(
            child: SingleChildScrollView(
              child: method == 0
                  ? Column(
                      children: [
                        const Text(
                          'Use the same Wi-Fi network. On Android 11+, enable Developer options and Wireless debugging.',
                        ),
                        const SizedBox(height: 18),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(20),
                          child: CustomPaint(
                            size: const Size(210, 210),
                            painter: QrPainter(
                              'WIFI:T:ADB;S:$service;P:$secret;;',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(status, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: busy ? null : regenerate,
                          child: const Text('Generate new QR code'),
                        ),
                      ],
                    )
                  : method == 4
                  ? RemoteLink(store: widget.store)
                  : method == 3
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '1. Enable USB debugging in Developer options.\n\n2. Connect a data-capable USB cable.\n\n3. Unlock the phone and approve this computer.',
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: widget.store.refresh,
                          child: const Text('Check USB devices'),
                        ),
                        const SizedBox(height: 20),
                        for (final d in widget.store.devices.where(
                          (d) => !d.wireless,
                        ))
                          ListTile(
                            title: Text(d.label),
                            subtitle: Text(d.state),
                            trailing: TextButton(
                              onPressed: !d.ready || busy
                                  ? null
                                  : () async {
                                      setState(() => busy = true);
                                      await widget.store.operation(
                                        'Switch to wireless',
                                        (_) async {
                                          final routes = await widget.store.adb
                                              .shell(d.serial, 'ip -4 route');
                                          final ip = RegExp(
                                            r'\bsrc\s+(\d+\.\d+\.\d+\.\d+)',
                                          ).firstMatch(routes)?.group(1);
                                          if (ip == null) {
                                            throw const BeamException(
                                              'Connect the phone to Wi-Fi first.',
                                            );
                                          }
                                          await widget.store.adb.run([
                                            '-s',
                                            d.serial,
                                            'tcpip',
                                            '5555',
                                          ]);
                                          await Future<void>.delayed(
                                            const Duration(seconds: 2),
                                          );
                                          await widget.store.adb.connect(
                                            '$ip:5555',
                                          );
                                        },
                                        target: d.serial,
                                      );
                                      await widget.store.refresh();
                                      if (mounted) {
                                        setState(() => busy = false);
                                        if (context.mounted) {
                                          await showResult(
                                            context,
                                            widget.store,
                                          );
                                        }
                                      }
                                    },
                              child: const Text('Switch to wireless'),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          method == 1
                              ? 'On the phone: Wireless debugging → Pair device with pairing code.'
                              : 'Use the IP address and connection port from the main Wireless debugging screen.',
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: address,
                          decoration: InputDecoration(
                            labelText: method == 1
                                ? 'Pairing address (IP:port)'
                                : 'Connection address (IP:port)',
                            hintText: '192.168.1.12:37123',
                          ),
                        ),
                        if (method == 1) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: code,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: 'Six-digit code',
                            ),
                          ),
                          TextField(
                            controller: connection,
                            decoration: const InputDecoration(
                              labelText: 'Connection address (optional)',
                              helperText:
                                  'This uses a different port from pairing.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (method == 1) {
                                    await doPair(
                                      address.text.trim(),
                                      code.text.trim(),
                                    );
                                  } else {
                                    setState(() {
                                      busy = true;
                                      error = null;
                                    });
                                    try {
                                      await widget.store.adb.connect(
                                        address.text.trim(),
                                      );
                                      await widget.store.refresh();
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => error = FriendlyError.parse(
                                            e,
                                            'Connection Failed',
                                          ).summary,
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  }
                                },
                          child: Text(
                            method == 1 ? 'Pair and connect' : 'Connect',
                          ),
                        ),
                        if (method == 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(status),
                          ),
                        const SizedBox(height: 16),
                        for (final s in widget.store.discovered.where(
                          (s) => s.pairing == (method == 1),
                        ))
                          ListTile(
                            dense: true,
                            title: Text(s.address),
                            subtitle: Text(s.name),
                            trailing: const Icon(Icons.north_west),
                            onTap: () => address.text = s.address,
                          ),
                      ],
                    ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class QrPainter extends CustomPainter {
  final String value;
  QrPainter(this.value);
  @override
  void paint(Canvas canvas, Size size) {
    final image = QrImage(
      QrCode.fromData(data: value, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    final cell = size.width / image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < image.moduleCount; y++) {
      for (var x = 0; x < image.moduleCount; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + .1, cell + .1),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter oldDelegate) => value != oldDelegate.value;
}
