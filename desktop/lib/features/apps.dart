import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../core/adb.dart';
import '../core/store.dart';
import 'widgets.dart';

class AppsPage extends StatefulWidget {
  final AppStore store;
  const AppsPage({super.key, required this.store});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  List<String> packages = [];
  String query = '';
  bool system = false, loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.store.ready) unawaited(load());
  }

  Future<void> load() async {
    final serial = widget.store.selected;
    if (serial == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final text = await widget.store.adb.shell(
        serial,
        'pm list packages ${system ? '-s' : '-3'}',
      );
      if (mounted) {
        setState(
          () => packages =
              text
                  .split('\n')
                  .where((l) => l.startsWith('package:'))
                  .map((l) => l.substring(8).trim())
                  .toList()
                ..sort(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> install(List<String> paths) async {
    final serial = widget.store.selected;
    if (serial == null || paths.isEmpty) return;
    if (paths.any((p) => !p.toLowerCase().endsWith('.apk'))) {
      setState(
        () => error =
            'Choose APK files. App bundles must first be converted into APKs.',
      );
      return;
    }
    await widget.store.command(
      paths.length == 1 ? 'Install APK' : 'Install split APK set',
      [
        '-s',
        serial,
        paths.length == 1 ? 'install' : 'install-multiple',
        '-r',
        ...paths,
      ],
      timeout: const Duration(minutes: 5),
      target: serial,
    );
    if (mounted) {
      await showResult(context, widget.store);
      await load();
    }
  }

  Future<void> action(String package, String action) async {
    final serial = widget.store.selected;
    if (serial == null) return;
    if (action == 'export') {
      final folder = await getDirectoryPath(
        confirmButtonText: 'Export APKs here',
      );
      if (folder == null) return;
      await widget.store.operation('Export APKs: $package', (item) async {
        final output = await widget.store.adb.shell(
          serial,
          'pm path ${shellQuote(package)}',
        );
        final paths = output
            .split('\n')
            .where((line) => line.startsWith('package:'))
            .map((line) => line.substring(8).trim())
            .toList();
        if (paths.isEmpty) {
          throw const BeamException('No accessible APK paths were found.');
        }
        final dir = Directory(
          p.join(folder, '$package-${DateTime.now().millisecondsSinceEpoch}'),
        );
        await dir.create();
        for (final remote in paths) {
          await widget.store.adb.run([
            '-s',
            serial,
            'pull',
            remote,
            p.join(dir.path, p.posix.basename(remote)),
          ]);
        }
        item.detail =
            'Exported ${paths.length} APK file(s) to ${dir.path}. Split APKs must be installed together.';
      }, target: serial);
      if (mounted) await showResult(context, widget.store);
      return;
    }
    if (action == 'details') {
      final result = await widget.store.command('Inspect $package', [
        '-s',
        serial,
        'shell',
        'dumpsys package ${shellQuote(package)}',
      ]);
      if (mounted && result != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(package),
            content: SizedBox(
              width: 700,
              height: 500,
              child: SingleChildScrollView(
                child: SelectableText(
                  result,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (action == 'clear' || action == 'uninstall') {
      if (!await confirmAction(
        context,
        action == 'clear' ? 'Clear all app data?' : 'Uninstall app?',
        '$package\n\nThis removes app data and cannot be undone.',
        label: action == 'clear' ? 'Clear data' : 'Uninstall',
      )) {
        return;
      }
    }
    final command = switch (action) {
      'launch' => [
        '-s',
        serial,
        'shell',
        'monkey -p ${shellQuote(package)} -c android.intent.category.LAUNCHER 1',
      ],
      'stop' => ['-s', serial, 'shell', 'am force-stop ${shellQuote(package)}'],
      'clear' => ['-s', serial, 'shell', 'pm clear ${shellQuote(package)}'],
      'uninstall' => ['-s', serial, 'uninstall', package],
      _ => <String>[],
    };
    if (command.isEmpty) return;
    await widget.store.operation('$action $package', (item) async {
      final output = await widget.store.adb.run(command);
      if (RegExp(r'Failure|Error:|No activities found').hasMatch(output)) {
        throw BeamException('Android rejected this operation.', output);
      }
      item.detail = output;
    }, target: serial);
    if (mounted) {
      await showResult(context, widget.store);
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = packages
        .where((p) => p.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Apps',
          'Install something new. Take care of what’s already there.',
          actions: [
            FilledButton.icon(
              onPressed: !widget.store.ready
                  ? null
                  : () async {
                      final files = await openFiles(
                        acceptedTypeGroups: [
                          const XTypeGroup(label: 'APK', extensions: ['apk']),
                        ],
                      );
                      if (files.length > 1 &&
                          context.mounted &&
                          !await confirmAction(
                            context,
                            'Install split APK set?',
                            'Selected files must be splits of the same app. Install unrelated APKs one at a time.',
                          )) {
                        return;
                      }
                      await install(files.map((f) => f.path).toList());
                    },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Install APK'),
            ),
          ],
        ),
        if (!widget.store.ready)
          const Expanded(
            child: EmptyState(
              Icons.apps_rounded,
              'Your apps, organized',
              'Connect a phone to install APKs and manage applications.',
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: 'Search package name…',
                      hintStyle: const TextStyle(fontSize: 12.5),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilterChip(
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
                label: const Text('System apps'),
                selected: system,
                onSelected: (v) {
                  setState(() => system = v);
                  load();
                },
              ),
              IconButton(
                tooltip: 'Refresh apps',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (error != null) Notice(error!, error: true),
          if (system)
            const Notice(
              'System apps are shown for inspection. Removal is disabled in this view.',
            ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: DropTarget(
              onDragDone: (d) => install(d.files.map((f) => f.path).toList()),
              child: Panel(
                padding: EdgeInsets.zero,
                child: filtered.isEmpty && !loading
                    ? const EmptyState(
                        Icons.apps,
                        'No matching apps',
                        'Drop an APK here to install it, or adjust your search.',
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, i) => const Divider(),
                        itemBuilder: (context, i) {
                          final package = filtered[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 6,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.android_rounded,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              package.split('.').last,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              package,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => action(package, 'launch'),
                                  child: const Text('Open'),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) => action(package, v),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'export',
                                      child: Text('Export APK files'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'details',
                                      child: Text('Package details'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'stop',
                                      child: Text('Force stop'),
                                    ),
                                    if (!system) ...[
                                      const PopupMenuItem(
                                        value: 'clear',
                                        child: Text('Clear app data'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'uninstall',
                                        child: Text('Uninstall'),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
