import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/store.dart';
import '../core/theme.dart';
import 'widgets.dart';
import 'pairing.dart';
import 'files.dart';
import 'media.dart';
import 'apps.dart';
import 'developer.dart';

class Home extends StatefulWidget {
  final AppStore store;
  final String? mediaError;
  final List<String> args;
  const Home({
    super.key,
    required this.store,
    this.mediaError,
    this.args = const [],
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int page = 0;
  final Set<Activity> dismissedFailures = {};
  static const labels = [
    'Overview',
    'Screen',
    'Files',
    'Camera',
    'Audio',
    'Apps',
    'Developer Tools',
    'Activity',
    'Settings',
  ];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.screen_share_outlined,
    Icons.folder_outlined,
    Icons.videocam_outlined,
    Icons.graphic_eq_rounded,
    Icons.apps_rounded,
    Icons.terminal_rounded,
    Icons.history_rounded,
    Icons.tune_rounded,
  ];
  AppStore get store => widget.store;
  bool get detached => widget.args.contains('--session');
  @override
  void initState() {
    super.initState();
    if (detached && widget.args.length >= 3) {
      store.selected = widget.args[1];
      page = switch (widget.args[2]) {
        'camera' => 3,
        'audio' || 'mic' => 4,
        _ => 1,
      };
    }
  }

  void navigate(int value) => setState(() => page = value);
  Future<void> pair() => showDialog<void>(
    context: context,
    builder: (_) => PairingDialog(store: store),
  );
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failure = store.activities
        .where((a) => a.state == 'Failed' && !dismissedFailures.contains(a))
        .firstOrNull;
    return Scaffold(
      body: Row(
        children: [
          if (!detached)
            Container(
              width: 214,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                30,
                                20,
                                30,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: beamBlue,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Icon(
                                      Icons.bolt_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Flexible(
                                    child: FittedBox(
                                      child: Text(
                                        'BeamADB',
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -.6,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(24, 0, 0, 12),
                              child: Text(
                                'YOUR WORKSPACE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            for (var i = 0; i < labels.length; i++) ...[
                              if (i == 6)
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 15,
                                  ),
                                  child: Divider(),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 3,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    minLeadingWidth: 22,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    selected: page == i,
                                    selectedColor: beamBlue,
                                    selectedTileColor: beamBlue.withValues(
                                      alpha: .09,
                                    ),
                                    leading: Icon(icons[i], size: 21),
                                    title: Text(
                                      labels[i],
                                      style: TextStyle(
                                        fontWeight: page == i
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    onTap: () => navigate(i),
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 14,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Private. Local. Yours.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'DESKTOP PREVIEW · 2.0',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .4),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.smartphone_rounded,
                        color: store.ready ? beamBlue : colors.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      if (store.devices.isEmpty)
                        Text(
                          'No device connected',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        )
                      else
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value:
                                  store.devices.any(
                                    (d) => d.serial == store.selected,
                                  )
                                  ? store.selected
                                  : null,
                              isExpanded: true,
                              hint: const Text('Select a device'),
                              items: store.devices
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d.serial,
                                      child: Text(
                                        '${d.label} · ${d.ready ? (d.wireless ? 'Wi-Fi' : 'USB') : d.state}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) store.select(v);
                              },
                            ),
                          ),
                        ),
                      if (store.devices.isEmpty) const Spacer(),
                      if (store.scanning)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      IconButton(
                        tooltip: 'Refresh devices',
                        onPressed: store.scanning ? null : store.refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: pair,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Connect device'),
                      ),
                    ],
                  ),
                ),
                if (store.startupError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                    child: Notice(
                      store.startupError!,
                      error: true,
                      action: TextButton(
                        onPressed: store.initialize,
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                    child: Notice(
                      '${failure.title} failed. ${failure.detail.split('\n').first}',
                      error: true,
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => navigate(7),
                            child: const Text('Details'),
                          ),
                          IconButton(
                            tooltip: 'Dismiss failure',
                            onPressed: () =>
                                setState(() => dismissedFailures.add(failure)),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: IndexedStack(
                      index: page,
                      children: [
                        overview(),
                        MediaPage(
                          key: ValueKey('screen-${store.selected}'),
                          store: store,
                          mode: 'screen',
                          runtimeError: widget.mediaError,
                          autoStart: detached && page == 1,
                        ),
                        FilesPage(
                          key: ValueKey('files-${store.selected}'),
                          store: store,
                        ),
                        MediaPage(
                          key: ValueKey('camera-${store.selected}'),
                          store: store,
                          mode: 'camera',
                          runtimeError: widget.mediaError,
                          autoStart: detached && page == 3,
                        ),
                        MediaPage(
                          key: ValueKey('audio-${store.selected}'),
                          store: store,
                          mode: 'audio',
                          runtimeError: widget.mediaError,
                          autoStart: detached && page == 4,
                        ),
                        AppsPage(
                          key: ValueKey('apps-${store.selected}'),
                          store: store,
                        ),
                        DeveloperPage(
                          key: ValueKey('dev-${store.selected}'),
                          store: store,
                        ),
                        activity(),
                        settings(),
                      ],
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

  Widget overview() {
    final device = store.device;
    final meta = store.metadata[store.selected] ?? {};
    return ListView(
      children: [
        PageHeading(
          'Your phone. More possibilities.',
          'A little distance. The same connection.',
        ),
        Panel(
          child: Row(
            children: [
              Container(
                width: 94,
                height: 118,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xffe8eeff), Color(0xffd7e5ff)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.phone_android_rounded,
                  size: 60,
                  color: beamBlue,
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device?.label ?? 'Bring your phone closer.',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      device == null
                          ? 'Connect over USB or pair wirelessly to get started.'
                          : device.ready
                          ? '${device.wireless ? 'Wireless' : 'USB'} connection · Ready to explore'
                          : 'Device ${device.state}. Unlock it and approve debugging.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (meta['android'] != null)
                          Chip(label: Text('Android ${meta['android']}')),
                        if (meta['battery'] != null)
                          Chip(
                            avatar: const Icon(
                              Icons.battery_std_rounded,
                              size: 16,
                            ),
                            label: Text('${meta['battery']}%'),
                          ),
                        if (device == null)
                          FilledButton(
                            onPressed: pair,
                            child: const Text('Connect your first device'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (store.sessions.values.any((s) => s.active)) ...[
          const SizedBox(height: 18),
          Panel(
            child: Column(
              children: store.sessions.values
                  .where((s) => s.active)
                  .map(
                    (s) => ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text('${s.mode} · ${s.device}'),
                      subtitle: Text(s.status),
                      trailing: TextButton(
                        onPressed: s.stop,
                        child: const Text('Stop'),
                      ),
                      onTap: () {
                        store.select(s.device);
                        navigate(
                          s.mode == 'screen'
                              ? 1
                              : s.mode == 'camera'
                              ? 3
                              : 4,
                        );
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 30),
        const Text(
          'Make yourself at home',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: constraints.maxWidth > 900 ? 4 : 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 180,
            children: [
              actionCard(
                'Mirror your screen',
                'A bigger view. Full control.',
                Icons.screen_share_outlined,
                1,
                const Color(0xff356af0),
              ),
              actionCard(
                'Explore your files',
                'Move what matters.',
                Icons.folder_outlined,
                2,
                const Color(0xffb68022),
              ),
              actionCard(
                'Open your camera',
                'A fresh perspective.',
                Icons.videocam_outlined,
                3,
                const Color(0xff8b5bd7),
              ),
              actionCard(
                'Listen to your phone',
                'Your audio, on your desk.',
                Icons.graphic_eq_rounded,
                4,
                const Color(0xff29977e),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Panel(
          child: Row(
            children: [
              const Icon(Icons.code_rounded, color: beamBlue),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Built for your next big idea, too.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Logs, shell, app testing and diagnostics. All in one workspace.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => navigate(6),
                child: const Text('Developer tools →'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget actionCard(
    String title,
    String subtitle,
    IconData icon,
    int destination,
    Color color,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => navigate(destination),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget activity() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        'Activity',
        'Transfers, operations and the details that matter.',
      ),
      Expanded(
        child: store.activities.isEmpty
            ? const EmptyState(
                Icons.check_circle_outline_rounded,
                'All quiet here',
                'Your transfers and operations will appear here, along with any steps that need attention.',
              )
            : ListView.separated(
                itemCount: store.activities.length,
                separatorBuilder: (_, i) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = store.activities[i];
                  return Panel(
                    padding: const EdgeInsets.all(8),
                    child: ExpansionTile(
                      leading: Icon(
                        a.state == 'Succeeded'
                            ? Icons.check_circle_outline
                            : a.state == 'Running'
                            ? Icons.timelapse
                            : Icons.error_outline,
                        color: a.state == 'Failed'
                            ? Colors.red
                            : a.state == 'Succeeded'
                            ? Colors.teal
                            : beamBlue,
                      ),
                      title: Text(a.title),
                      subtitle: Text(
                        '${a.device} · ${a.state} · ${a.time.toLocal().toString().substring(11, 19)}',
                      ),
                      trailing: a.cancel == null
                          ? null
                          : TextButton(
                              onPressed: a.cancel,
                              child: const Text('Cancel'),
                            ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            a.detail.isEmpty
                                ? 'No additional details.'
                                : a.detail,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
  Widget settings() => ListView(
    children: [
      const PageHeading('Settings', 'A workspace that feels like yours.'),
      Panel(
        child: Column(
          children: [
            ListTile(
              title: const Text('Appearance'),
              subtitle: const Text('Follow your system or choose a theme.'),
              trailing: DropdownButton<ThemeMode>(
                value: store.themeMode,
                items: ThemeMode.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (m) {
                  if (m != null) store.setTheme(m);
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              subtitle: const Text(
                'Prefer quiet transitions and fewer animations.',
              ),
              value: store.reducedMotion,
              onChanged: store.setReducedMotion,
            ),
            const Divider(),
            ListTile(
              title: const Text('ADB executable'),
              subtitle: Text(store.adb.executable),
              trailing: TextButton(
                onPressed: () async {
                  final path = await askText(
                    context,
                    'Custom ADB path',
                    'Leave empty to use the bundled version',
                    initial: store.preferences?.getString('adbPath') ?? '',
                  );
                  if (path == null) return;
                  await store.preferences?.setString('adbPath', path);
                  await store.initialize();
                },
                child: const Text('Change'),
              ),
            ),
            ListTile(
              title: const Text('Capture engine'),
              subtitle: Text(
                'scrcpy ${store.adb.serverVersion.isEmpty ? 'unavailable' : store.adb.serverVersion} · native media textures',
              ),
            ),
            ListTile(
              title: const Text('Platform'),
              subtitle: Text(
                '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}',
              ),
            ),
            ListTile(
              title: const Text('Diagnostics'),
              subtitle: const Text(
                'Copy tool versions and connection states. No pairing codes.',
              ),
              trailing: TextButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text:
                        'BeamADB 2.0 preview\n${Platform.operatingSystem}\nADB: ${store.adb.executable}\nscrcpy: ${store.adb.serverVersion}\nDevices: ${store.devices.map((d) => d.state).join(', ')}',
                  ),
                ),
                child: const Text('Copy'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Notice(
        'Desktop preview: Linux builds are validated here. Windows runners are included; Windows runtime validation requires a Windows machine.',
      ),
    ],
  );
}
