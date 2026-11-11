import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/adb.dart';
import '../core/store.dart';
import 'widgets.dart';

class FilesPage extends StatefulWidget {
  final AppStore store;
  const FilesPage({super.key, required this.store});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  String path = '/sdcard', query = '';
  List<RemoteFile> files = [];
  final Set<String> selected = {};
  final history = <String>[];
  bool loading = false, dropping = false, ascending = true;
  int generation = 0;
  String? error;
  final pathController = TextEditingController(text: '/sdcard');
  String? get device => widget.store.device?.serial;
  @override
  void initState() {
    super.initState();
    if (widget.store.ready) unawaited(load(path));
  }

  @override
  void dispose() {
    generation++;
    pathController.dispose();
    super.dispose();
  }

  Future<void> load(String destination, {bool remember = true}) async {
    if (device == null) return;
    final token = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.store.adb.listFiles(device!, destination);
      if (!mounted || token != generation) return;
      setState(() {
        if (remember && destination != path) history.add(path);
        path = destination;
        pathController.text = path;
        files = result;
        selected.clear();
      });
    } catch (e) {
      if (mounted && token == generation) setState(() => error = '$e');
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> upload(List<String> localPaths) async {
    final serial = device, destination = path;
    if (serial == null) return;
    for (final local in localPaths) {
      final name = p.basename(local);
      var target = p.posix.join(destination, name);
      bool exists = false;
      try {
        await widget.store.adb.shell(serial, 'test -e ${shellQuote(target)}');
        exists = true;
      } catch (_) {}
      if (exists && mounted) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$name already exists'),
            content: const Text(
              'Replacing a folder merges its contents and replaces matching files.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'skip'),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'keep'),
                child: const Text('Keep both'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (choice == null || choice == 'skip') continue;
        if (choice == 'keep') {
          target = p.posix.join(
            destination,
            '${p.basenameWithoutExtension(name)}-${DateTime.now().millisecondsSinceEpoch}${p.extension(name)}',
          );
        }
      }
      await widget.store.command(
        'Upload $name',
        ['-s', serial, 'push', local, target],
        timeout: const Duration(hours: 2),
        target: serial,
      );
      if (mounted && widget.store.activities.first.state == 'Failed') {
        await showResult(context, widget.store);
      }
    }
    if (mounted && device == serial && path == destination) {
      await load(path, remember: false);
    }
  }

  Future<void> download(RemoteFile file) async {
    final serial = device;
    if (serial == null) return;
    String? target;
    if (file.directory) {
      final folder = await getDirectoryPath(confirmButtonText: 'Download here');
      if (folder != null) target = p.join(folder, file.name);
    } else {
      target = (await getSaveLocation(suggestedName: file.name))?.path;
    }
    if (target == null) return;
    if (file.directory && await Directory(target).exists() && mounted) {
      if (!await confirmAction(
        context,
        'Merge into existing folder?',
        'Matching files in $target may be replaced.',
        label: 'Merge',
      )) {
        return;
      }
    }
    await widget.store.command(
      'Download ${file.name}',
      ['-s', serial, 'pull', file.path, target],
      timeout: const Duration(hours: 2),
      target: serial,
    );
    if (mounted) await showResult(context, widget.store);
  }

  Future<void> remove(List<RemoteFile> targets) async {
    final serial = device;
    if (serial == null || targets.isEmpty) return;
    if (!await confirmAction(
      context,
      'Permanently delete ${targets.length} item(s)?',
      targets.map((f) => f.path).join('\n'),
      label: 'Delete permanently',
    )) {
      return;
    }
    await widget.store.operation('Delete ${targets.length} item(s)', (_) async {
      for (final f in targets) {
        await widget.store.adb.delete(serial, f.path);
      }
    }, target: serial);
    if (mounted) {
      await showResult(context, widget.store);
      await load(path, remember: false);
    }
  }

  Future<void> rename(RemoteFile file) async {
    final serial = device;
    final name = await askText(
      context,
      'Rename ${file.name}',
      'New name',
      initial: file.name,
    );
    if (name == null || serial == null || name == file.name) return;
    await widget.store.operation('Rename ${file.name}', (_) async {
      if (name.isEmpty || name.contains('/') || name == '.' || name == '..') {
        throw const BeamException('Enter a single file or folder name.');
      }
      final target = p.posix.join(p.posix.dirname(file.path), name);
      await widget.store.adb.shell(
        serial,
        'test ! -e ${shellQuote(target)} && mv -- ${shellQuote(file.path)} ${shellQuote(target)}',
      );
    }, target: serial);
    if (mounted) {
      await showResult(context, widget.store);
      await load(path, remember: false);
    }
  }

  Future<void> createFolder() async {
    final serial = device, destination = path;
    final name = await askText(context, 'New folder', 'Folder name');
    if (name == null || serial == null) return;
    await widget.store.operation('Create folder', (_) async {
      if (name.isEmpty || name.contains('/') || name == '.' || name == '..') {
        throw const BeamException('Enter a single folder name.');
      }
      await widget.store.adb.shell(
        serial,
        'mkdir -- ${shellQuote(p.posix.join(destination, name))}',
      );
    }, target: serial);
    if (mounted) {
      await showResult(context, widget.store);
      await load(path, remember: false);
    }
  }

  Future<void> relocate(RemoteFile file, bool move) async {
    final serial = device;
    final destination = await askText(
      context,
      move ? 'Move ${file.name}' : 'Copy ${file.name}',
      'Full destination path on the phone',
      initial: file.path,
    );
    if (destination == null || serial == null) return;
    await widget.store.operation('${move ? 'Move' : 'Copy'} ${file.name}', (
      _,
    ) async {
      final target = safeRemotePath(destination, destructive: true);
      final source = safeRemotePath(file.path, destructive: move);
      if (target == source || target.startsWith('$source/')) {
        throw const BeamException(
          'Choose a different destination outside the source folder.',
        );
      }
      await widget.store.adb.shell(
        serial,
        'test ! -e ${shellQuote(target)} && ${move ? 'mv' : 'cp -R'} -- ${shellQuote(source)} ${shellQuote(target)}',
        timeout: const Duration(minutes: 5),
      );
    }, target: serial);
    if (mounted) {
      await showResult(context, widget.store);
      await load(path, remember: false);
    }
  }

  Future<void> preview(RemoteFile file) async {
    final serial = device;
    if (serial == null) return;
    final ext = p.extension(file.name).toLowerCase();
    final isImage = ['.png', '.jpg', '.jpeg', '.webp', '.gif'].contains(ext);
    final isText = [
      '.txt',
      '.log',
      '.json',
      '.xml',
      '.md',
      '.csv',
      '.yaml',
      '.yml',
    ].contains(ext);
    if ((!isImage && !isText) ||
        file.size > (isImage ? 20 * 1024 * 1024 : 1024 * 1024)) {
      setState(
        () => error =
            'Preview supports images up to 20 MB and text files up to 1 MB. Download this file to open it.',
      );
      return;
    }
    final temp = await Directory.systemTemp.createTemp('beamadb-preview-');
    final local = p.join(temp.path, 'preview$ext');
    try {
      final result = await widget.store.command('Preview ${file.name}', [
        '-s',
        serial,
        'pull',
        file.path,
        local,
      ], target: serial);
      if (result == null || !mounted) return;
      final text = isText ? await File(local).readAsString() : '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(file.name),
          content: SizedBox(
            width: 700,
            height: 480,
            child: isImage
                ? InteractiveViewer(
                    child: Image.file(
                      File(local),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('This image could not be decoded.'),
                    ),
                  )
                : SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = 'Preview failed: $e');
    } finally {
      await temp.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = files
        .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (!ascending) {
      filtered.sort(
        (a, b) => a.directory == b.directory
            ? b.name.compareTo(a.name)
            : a.directory
            ? -1
            : 1,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.store.ready)
          const Expanded(
            child: EmptyState(
              Icons.folder_outlined,
              'Your phone’s files, within reach',
              'Connect and authorize a phone to browse its accessible storage.',
            ),
          )
        else ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                onPressed: history.isEmpty
                    ? null
                    : () => load(history.removeLast(), remember: false),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                tooltip: 'Parent folder',
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                onPressed: path == '/'
                    ? null
                    : () => load(p.posix.dirname(path)),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: pathController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      prefixIcon:
                          const Icon(Icons.folder_open_outlined, size: 18),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: load,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh folder',
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                onPressed: () => load(path, remember: false),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: widget.store.ready ? createFolder : null,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('New folder', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: widget.store.ready
                    ? () async {
                        final chosen = await openFiles();
                        await upload(chosen.map((f) => f.path).toList());
                      }
                    : null,
                icon: const Icon(Icons.upload_rounded, size: 16),
                label: const Text('Upload', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 180,
                height: 32,
                child: TextField(
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Filter files…',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final name in [
                        'Storage',
                        'Download',
                        'DCIM',
                        'Pictures',
                        'Documents',
                        'Music',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            labelStyle: const TextStyle(fontSize: 11.5),
                            label: Text(name),
                            onPressed: () => load(
                              name == 'Storage'
                                  ? '/sdcard'
                                  : '/sdcard/$name',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: ascending ? 'Sort descending' : 'Sort ascending',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => ascending = !ascending),
                icon: Icon(
                  ascending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () async {
                  final folder = await getDirectoryPath();
                  if (folder != null) await upload([folder]);
                },
                icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
                label: const Text('Folder', style: TextStyle(fontSize: 12)),
              ),
              if (selected.isNotEmpty) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Delete selected (${selected.length})',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => remove(
                    files.where((f) => selected.contains(f.path)).toList(),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (error != null) Notice(error!, error: true),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => dropping = true),
              onDragExited: (_) => setState(() => dropping = false),
              onDragDone: (details) {
                setState(() => dropping = false);
                unawaited(upload(details.files.map((f) => f.path).toList()));
              },
              child: Panel(
                padding: EdgeInsets.zero,
                child: dropping
                    ? const EmptyState(
                        Icons.file_upload_outlined,
                        'Drop to upload',
                        'Files and folders keep their names and structure.',
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 44),
                                Expanded(
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => ascending = !ascending),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Name ${ascending ? '↑' : '↓'}',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 90,
                                  child: Text(
                                    'Size',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                                const SizedBox(width: 140),
                              ],
                            ),
                          ),
                          const Divider(),
                          Expanded(
                            child: filtered.isEmpty && !loading
                                ? EmptyState(
                                    Icons.folder_open_rounded,
                                    error == null
                                        ? 'Nothing here yet'
                                        : 'Folder unavailable',
                                    error == null
                                        ? 'Upload files or choose another folder.'
                                        : 'Correct the issue above and refresh.',
                                  )
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, i) {
                                      final f = filtered[i];
                                      return ListTile(
                                        leading: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Checkbox(
                                              value: selected.contains(f.path),
                                              onChanged: (v) => setState(() {
                                                if (v!) {
                                                  selected.add(f.path);
                                                } else {
                                                  selected.remove(f.path);
                                                }
                                              }),
                                            ),
                                            Icon(
                                              f.directory
                                                  ? Icons.folder_rounded
                                                  : f.link
                                                  ? Icons.link
                                                  : Icons.description_outlined,
                                              color: f.directory
                                                  ? const Color(0xffd3a04b)
                                                  : Colors.blueGrey,
                                            ),
                                          ],
                                        ),
                                        title: Text(
                                          f.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: f.link
                                            ? const Text('Symbolic link')
                                            : null,
                                        onTap: f.directory
                                            ? () => load(f.path)
                                            : () => download(f),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 90,
                                              child: Text(
                                                f.directory
                                                    ? '—'
                                                    : formatBytes(f.size),
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Download',
                                              onPressed: () => download(f),
                                              icon: const Icon(
                                                Icons.download_outlined,
                                                size: 19,
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              onSelected: (v) {
                                                if (v == 'rename') rename(f);
                                                if (v == 'copy') {
                                                  relocate(f, false);
                                                }
                                                if (v == 'move') {
                                                  relocate(f, true);
                                                }
                                                if (v == 'preview') preview(f);
                                                if (v == 'delete') remove([f]);
                                              },
                                              itemBuilder: (_) => [
                                                if (!f.directory)
                                                  const PopupMenuItem(
                                                    value: 'preview',
                                                    child: Text('Preview'),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'copy',
                                                  child: Text('Copy to…'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'move',
                                                  child: Text('Move to…'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'rename',
                                                  child: Text('Rename'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text(
                                                    'Delete permanently',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${filtered.length} items · ${selected.length} selected · Transfers appear in Activity',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
