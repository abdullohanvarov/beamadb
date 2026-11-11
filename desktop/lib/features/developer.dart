import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/adb.dart';
import '../core/store.dart';
import 'widgets.dart';

class DeveloperPage extends StatefulWidget {
  final AppStore store;
  const DeveloperPage({super.key, required this.store});
  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  int tab = 0;
  static const tabs = [
    'Logs',
    'Shell',
    'Diagnostics',
    'Networking',
    'App testing',
    'Workflows',
  ];
  final command = TextEditingController(),
      filter = TextEditingController(),
      package = TextEditingController(),
      portLocal = TextEditingController(text: '8080'),
      portRemote = TextEditingController(text: '8080');
  final List<String> logs = [], shellHistory = [];
  String output = '', rules = '', severity = 'V';
  bool paused = false, reverse = true;
  List<String> pausedLines = [];
  Process? logProcess;
  CommandTask? shellTask;
  StreamSubscription<String>? logSubscription, logErrors;
  Timer? repaint;
  int dropped = 0;
  bool dirty = false;
  String? get serial => widget.store.selected;
  @override
  void initState() {
    super.initState();
    repaint = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (dirty && mounted && !paused) {
        dirty = false;
        setState(() {});
      }
    });
  }

  Future<void> startLogs() async {
    if (serial == null || logProcess != null) return;
    await widget.store.operation('Start live logs', (_) async {
      final proc = await widget.store.adb.spawn([
        '-s',
        serial!,
        'logcat',
        '-v',
        'threadtime',
        '*:$severity',
      ]);
      logProcess = proc;
      void add(String line) {
        logs.add(line);
        if (logs.length > 5000) {
          logs.removeAt(0);
          dropped++;
        }
        dirty = true;
      }

      logSubscription = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(add);
      logErrors = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(add);
      unawaited(
        proc.exitCode.then((code) {
          if (identical(logProcess, proc)) {
            logProcess = null;
            add('Log stream ended (exit $code).');
            if (mounted) setState(() {});
          }
        }),
      );
    });
    if (mounted) setState(() {});
  }

  Future<void> stopLogs() async {
    final proc = logProcess;
    logProcess = null;
    proc?.kill();
    await logSubscription?.cancel();
    await logErrors?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> runShell([String? text]) async {
    final input = (text ?? command.text).trim();
    if (serial == null || input.isEmpty || shellTask != null) return;
    shellHistory.add(input);
    command.clear();
    setState(() => output += '\n\$ $input\n');
    await widget.store.operation('Shell command', (item) async {
      shellTask = await widget.store.adb.start(
        ['-s', serial!, 'shell', input],
        timeout: const Duration(minutes: 5),
        onOutput: (chunk) {
          if (mounted) {
            setState(() {
              output += chunk.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
              if (output.length > 100000) {
                output = output.substring(output.length - 100000);
              }
            });
          }
        },
      );
      item.cancel = shellTask!.cancel;
      try {
        item.detail = await shellTask!.output;
      } finally {
        shellTask = null;
        if (mounted) setState(() {});
      }
    });
    if (mounted) await showResult(context, widget.store);
  }

  Future<void> diagnostic(String title, String cmd) async {
    final result = await widget.store.command(title, [
      '-s',
      serial!,
      'shell',
      cmd,
    ], timeout: const Duration(minutes: 2));
    if (mounted) {
      setState(() => output = result ?? widget.store.activities.first.detail);
    }
  }

  Future<void> exportText(String text, String name) async {
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return;
    await widget.store.operation(
      'Export $name',
      (_) => File(location.path).writeAsString(text),
    );
    if (mounted) await showResult(context, widget.store);
  }

  Future<void> loadRules() async {
    final result = await widget.store.command(
      'Inspect port rules',
      reverse ? ['-s', serial!, 'reverse', '--list'] : ['forward', '--list'],
    );
    if (mounted) {
      setState(() => rules = result ?? widget.store.activities.first.detail);
    }
  }

  Future<void> portRule(bool remove) async {
    final local = int.tryParse(portLocal.text),
        remote = int.tryParse(portRemote.text);
    await widget.store.operation(
      remove ? 'Remove port rule' : 'Create port rule',
      (item) async {
        if (local == null ||
            remote == null ||
            local < 1 ||
            remote < 1 ||
            local > 65535 ||
            remote > 65535) {
          throw const BeamException('Ports must be between 1 and 65535.');
        }
        item.detail = await widget.store.adb.run([
          '-s',
          serial!,
          reverse ? 'reverse' : 'forward',
          if (remove) '--remove' else '--no-rebind',
          'tcp:$local',
          if (!remove) 'tcp:$remote',
        ]);
      },
    );
    if (mounted) {
      await showResult(context, widget.store);
      await loadRules();
    }
  }

  @override
  void dispose() {
    repaint?.cancel();
    logProcess?.kill();
    unawaited(logSubscription?.cancel());
    unawaited(logErrors?.cancel());
    unawaited(shellTask?.cancel());
    for (final c in [command, filter, package, portLocal, portRemote]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'Developer Tools',
          'Less friction between an idea and a working app.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: List.generate(
              tabs.length,
              (i) => ButtonSegment(value: i, label: Text(tabs[i])),
            ),
            selected: {tab},
            onSelectionChanged: (s) => setState(() => tab = s.first),
          ),
        ),
        const SizedBox(height: 10),
        if (!widget.store.ready)
          const Expanded(
            child: EmptyState(
              Icons.terminal_rounded,
              'Your engineering workspace',
              'Connect an authorized phone to inspect logs, run commands and test applications.',
            ),
          )
        else
          Expanded(
            child: switch (tab) {
              0 => logView(),
              1 => shellView(),
              2 => diagnostics(),
              3 => networking(),
              4 => testing(),
              _ => workflows(),
            },
          ),
      ],
    );
  }

  Widget console(String text) => Panel(
    padding: const EdgeInsets.all(16),
    child: SizedBox.expand(
      child: SingleChildScrollView(
        child: SelectableText(
          text.isEmpty ? 'Output will appear here.' : text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ),
    ),
  );
  Widget logView() {
    final visible = (paused ? pausedLines : logs)
        .where((l) => l.toLowerCase().contains(filter.text.toLowerCase()))
        .toList();
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: logProcess == null ? startLogs : stopLogs,
              icon: Icon(logProcess == null ? Icons.play_arrow : Icons.stop),
              label: Text(logProcess == null ? 'Start logs' : 'Stop'),
            ),
            DropdownButton<String>(
              value: severity,
              items: ['V', 'D', 'I', 'W', 'E', 'F']
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                        {
                          'V': 'Verbose',
                          'D': 'Debug',
                          'I': 'Info',
                          'W': 'Warning',
                          'E': 'Error',
                          'F': 'Fatal',
                        }[v]!,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: logProcess != null
                  ? null
                  : (v) => setState(() => severity = v!),
            ),
            SizedBox(
              width: 230,
              child: TextField(
                controller: filter,
                decoration: const InputDecoration(
                  hintText: 'Filter text, tag or PID',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                if (!paused) pausedLines = List.of(logs);
                paused = !paused;
              }),
              child: Text(paused ? 'Resume display' : 'Pause display'),
            ),
            IconButton(
              tooltip: 'Clear display',
              onPressed: () => setState(() => logs.clear()),
              icon: const Icon(Icons.clear_all),
            ),
            TextButton(
              onPressed: () =>
                  exportText(visible.join('\n'), 'beamadb-logcat.txt'),
              child: const Text('Export'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Panel(
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) => SelectableText(
                visible[i],
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.5,
                  color: RegExp(r'\s[EF]\s').hasMatch(visible[i])
                      ? Colors.red
                      : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${logs.length} buffered lines · $dropped older lines discarded${paused ? ' · Display paused; collection continues' : ''}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget shellView() => Column(
    children: [
      const Notice(
        'Commands run on the selected Android device. Review destructive commands before executing them.',
      ),
      Expanded(child: console(output)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: command,
              decoration: const InputDecoration(
                prefixText: '\$ ',
                hintText: 'Enter an Android shell command',
              ),
              onSubmitted: (_) => runShell(),
            ),
          ),
          const SizedBox(width: 12),
          if (shellTask != null)
            OutlinedButton(
              onPressed: shellTask!.cancel,
              child: const Text('Cancel'),
            )
          else
            FilledButton(onPressed: runShell, child: const Text('Run')),
          PopupMenuButton<String>(
            tooltip: 'Command history',
            onSelected: (v) => command.text = v,
            itemBuilder: (_) => shellHistory.reversed
                .take(30)
                .map((s) => PopupMenuItem(value: s, child: Text(s)))
                .toList(),
          ),
        ],
      ),
    ],
  );
  Widget diagnostics() => Column(
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => diagnostic('Device information', 'getprop'),
            child: const Text('Device information'),
          ),
          OutlinedButton(
            onPressed: () => diagnostic('Battery report', 'dumpsys battery'),
            child: const Text('Battery'),
          ),
          OutlinedButton(
            onPressed: () => diagnostic('Memory report', 'dumpsys meminfo'),
            child: const Text('Memory'),
          ),
          OutlinedButton(
            onPressed: () => diagnostic('Storage report', 'df -h'),
            child: const Text('Storage'),
          ),
          OutlinedButton(
            onPressed: () async {
              final folder = await getDirectoryPath(
                confirmButtonText: 'Save report here',
              );
              if (folder == null) return;
              await widget.store.command('Capture bug report', [
                '-s',
                serial!,
                'bugreport',
                p.join(
                  folder,
                  'beamadb-bugreport-${DateTime.now().millisecondsSinceEpoch}.zip',
                ),
              ], timeout: const Duration(minutes: 10));
              if (mounted) await showResult(context, widget.store);
            },
            child: const Text('Bug report'),
          ),
          OutlinedButton(
            onPressed: () async {
              final location = await getSaveLocation(
                suggestedName: 'beamadb.perfetto-trace',
              );
              if (location == null) return;
              final remote =
                  '/data/misc/perfetto-traces/beamadb-${DateTime.now().millisecondsSinceEpoch}.trace';
              await widget.store.operation(
                'Capture 10-second performance trace',
                (item) async {
                  try {
                    final task = await widget.store.adb.start([
                      '-s',
                      serial!,
                      'shell',
                      'perfetto -o ${shellQuote(remote)} -t 10s sched freq idle am wm gfx view binder_driver',
                    ], timeout: const Duration(seconds: 40));
                    item.cancel = task.cancel;
                    await task.output;
                    await widget.store.adb.run([
                      '-s',
                      serial!,
                      'pull',
                      remote,
                      location.path,
                    ]);
                  } finally {
                    try {
                      await widget.store.adb.shell(
                        serial!,
                        'rm -f ${shellQuote(remote)}',
                      );
                    } catch (_) {}
                  }
                },
              );
              if (mounted) await showResult(context, widget.store);
            },
            child: const Text('Performance trace'),
          ),
          TextButton(
            onPressed: () => exportText(output, 'beamadb-diagnostics.txt'),
            child: const Text('Export output'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Notice(
        'Diagnostic output can contain personal information. Review it before sharing.',
      ),
      Expanded(child: console(output)),
    ],
  );
  Widget networking() => ListView(
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connect your development services',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Phone → computer (reverse)'),
              subtitle: Text(
                reverse
                    ? 'A port on your phone reaches a service on this computer.'
                    : 'A port on this computer reaches a service on the phone.',
              ),
              value: reverse,
              onChanged: (v) => setState(() => reverse = v),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: portLocal,
                    decoration: InputDecoration(
                      labelText: reverse ? 'Phone port' : 'Computer port',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: portRemote,
                    decoration: InputDecoration(
                      labelText: reverse
                          ? 'Computer service port'
                          : 'Phone service port',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => portRule(false),
                  child: const Text('Create rule'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (await confirmAction(
                      context,
                      'Remove this port rule?',
                      'Remove the rule for the entered source port on this device?',
                    )) {
                      await portRule(true);
                    }
                  },
                  child: const Text('Remove rule'),
                ),
                TextButton(
                  onPressed: loadRules,
                  child: const Text('Inspect rules'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Panel(
        child: SelectableText(
          rules.isEmpty
              ? 'Inspect rules to see existing mappings. Rules remain until removed or ADB stops.'
              : rules,
        ),
      ),
    ],
  );
  Widget testing() => Column(
    children: [
      TextField(
        controller: package,
        decoration: const InputDecoration(
          labelText: 'Package name',
          hintText: 'com.example.app',
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => diagnostic(
              'App memory',
              'dumpsys meminfo ${shellQuote(package.text.trim())}',
            ),
            child: const Text('App memory'),
          ),
          OutlinedButton(
            onPressed: () => diagnostic(
              'Rendering statistics',
              'dumpsys gfxinfo ${shellQuote(package.text.trim())}',
            ),
            child: const Text('Rendering statistics'),
          ),
          OutlinedButton(
            onPressed: () async {
              final link = await askText(context, 'Launch deep link', 'URI');
              if (link == null) return;
              await diagnostic(
                'Launch deep link',
                'am start -W -a android.intent.action.VIEW -d ${shellQuote(link)} ${package.text.isEmpty ? '' : shellQuote(package.text.trim())}',
              );
            },
            child: const Text('Deep link'),
          ),
          OutlinedButton(
            onPressed: () async {
              final permission = await askText(
                context,
                'Grant runtime permission',
                'Permission, e.g. android.permission.CAMERA',
              );
              if (permission == null || package.text.trim().isEmpty) return;
              await diagnostic(
                'Grant permission',
                'pm grant ${shellQuote(package.text.trim())} ${shellQuote(permission)}',
              );
            },
            child: const Text('Grant permission'),
          ),
          OutlinedButton(
            onPressed: () async {
              final permission = await askText(
                context,
                'Revoke runtime permission',
                'Permission',
              );
              if (permission == null || package.text.trim().isEmpty) return;
              await diagnostic(
                'Revoke permission',
                'pm revoke ${shellQuote(package.text.trim())} ${shellQuote(permission)}',
              );
            },
            child: const Text('Revoke permission'),
          ),
          FilledButton(
            onPressed: () async {
              final runner = await askText(
                context,
                'Run instrumentation tests',
                'Test package / runner',
                initial:
                    '${package.text}.test/androidx.test.runner.AndroidJUnitRunner',
              );
              if (runner == null) return;
              final result = await widget.store
                  .command('Instrumentation tests', [
                    '-s',
                    serial!,
                    'shell',
                    'am instrument -w -r ${shellQuote(runner)}',
                  ], timeout: const Duration(minutes: 20));
              if (mounted) {
                setState(
                  () => output = result ?? widget.store.activities.first.detail,
                );
              }
            },
            child: const Text('Run tests'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(child: console(output)),
    ],
  );
  Widget workflows() {
    final workflows = widget.store.workflows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Notice(
          'Saved workflows run reviewed shell commands in order on the selected phone. Execution stops on the first error. Review commands before each run.',
        ),
        FilledButton.icon(
          onPressed: () async {
            final name = await askText(context, 'New workflow', 'Name');
            if (name == null || name.trim().isEmpty || !mounted) return;
            final steps = await showDialog<String>(
              context: context,
              builder: (_) => const WorkflowEditor(),
            );
            if (steps == null) return;
            await widget.store.saveWorkflows([
              ...workflows,
              {
                'name': name,
                'steps': steps
                    .split('\n')
                    .where((s) => s.trim().isNotEmpty)
                    .toList(),
              },
            ]);
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.add),
          label: const Text('New workflow'),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: workflows.isEmpty
              ? const EmptyState(
                  Icons.account_tree_outlined,
                  'Make repeatable work effortless',
                  'Save a sequence of Android shell commands, review it, then run it on the selected device.',
                )
              : ListView.builder(
                  itemCount: workflows.length,
                  itemBuilder: (context, i) {
                    final workflow = workflows[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workflow['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              (workflow['steps'] as List).join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: () async {
                                    final target = serial!;
                                    if (!await confirmAction(
                                      context,
                                      'Run ${workflow['name']}?',
                                      'Device: $target\n\n${(workflow['steps'] as List).join('\n')}\n\nCommands can modify or delete device data.',
                                      label: 'Run reviewed steps',
                                    )) {
                                      return;
                                    }
                                    await widget.store.operation(
                                      'Workflow: ${workflow['name']}',
                                      (item) async {
                                        for (final step
                                            in workflow['steps'] as List) {
                                          final task = await widget.store.adb
                                              .start(
                                                [
                                                  '-s',
                                                  target,
                                                  'shell',
                                                  step as String,
                                                ],
                                                timeout: const Duration(
                                                  minutes: 5,
                                                ),
                                              );
                                          item.cancel = task.cancel;
                                          item.detail +=
                                              '\n\$ $step\n${await task.output}\n';
                                          widget.store.emit();
                                        }
                                      },
                                      target: target,
                                    );
                                    if (context.mounted) {
                                      await showResult(context, widget.store);
                                    }
                                  },
                                  child: const Text('Review and run'),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Delete workflow',
                                  onPressed: () async {
                                    workflows.removeAt(i);
                                    await widget.store.saveWorkflows(workflows);
                                    if (mounted) setState(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class WorkflowEditor extends StatefulWidget {
  const WorkflowEditor({super.key});
  @override
  State<WorkflowEditor> createState() => _WorkflowEditorState();
}

class _WorkflowEditorState extends State<WorkflowEditor> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Workflow steps'),
    content: SizedBox(
      width: 600,
      child: TextField(
        controller: controller,
        minLines: 8,
        maxLines: 15,
        decoration: const InputDecoration(
          hintText:
              'One Android shell command per line\ngetprop ro.build.version.release\ndumpsys battery',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save workflow'),
      ),
    ],
  );
}
