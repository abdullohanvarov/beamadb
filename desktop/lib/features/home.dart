import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
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

  @override
  void didUpdateWidget(covariant Home oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (detached &&
        widget.args.length >= 3 &&
        (oldWidget.args.length < 2 || oldWidget.args[1] != widget.args[1])) {
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
    if (detached) {
      return Scaffold(
        body: Column(
          children: [
            if (page != 1)
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
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
                              Icon(
                                page == 3
                                    ? Icons.videocam_rounded
                                    : Icons.volume_up_rounded,
                                size: 16,
                                color: beamBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'BeamADB · ${page == 3 ? 'Camera' : 'Audio'} Stream',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
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
                        await windowManager.destroy();
                        exit(0);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            Expanded(
              child: MediaPage(
                key: ValueKey('detached-$page-${widget.args[1]}'),
                store: store,
                mode: page == 3 ? 'camera' : (page == 4 ? 'audio' : 'screen'),
                runtimeError: widget.mediaError,
                autoStart: true,
                emulatorMode: page == 1,
                launchArgs: widget.args,
              ),
            ),
          ],
        ),
      );
    }
    final failure = store.activities
        .where((a) => a.state == 'Failed' && !dismissedFailures.contains(a))
        .firstOrNull;
    return Scaffold(
      body: Row(
        children: [
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
                          DragToMoveArea(
                            child: Padding(
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
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .4),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DragToMoveArea(
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.smartphone_rounded,
                                  color: store.ready
                                      ? beamBlue
                                      : colors.onSurfaceVariant,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                if (store.devices.isEmpty)
                                  Text(
                                    'No device connected',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  )
                                else
                                  Flexible(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value:
                                            store.devices.any(
                                              (d) => d.serial == store.selected,
                                            )
                                            ? store.selected
                                            : null,
                                        isExpanded: true,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.onSurface,
                                        ),
                                        hint: const Text(
                                          'Select a device',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                        items: store.devices
                                            .map(
                                              (d) => DropdownMenuItem(
                                                value: d.serial,
                                                child: Text(
                                                  '${d.label} · ${d.ready ? (d.wireless ? 'Wi-Fi' : 'USB') : d.state}',
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                const SizedBox(width: 8),
                                if (store.scanning)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Refresh devices',
                                  iconSize: 18,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: store.scanning
                                      ? null
                                      : store.refresh,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                                const SizedBox(width: 6),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  onPressed: pair,
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text(
                                    'Connect device',
                                    style: TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      WindowControls(
                        onClose: () async {
                          await widget.store.shutdown();
                          await windowManager.destroy();
                          exit(0);
                        },
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                if (store.startupError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
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
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
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
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
          'Your devices',
          '${store.phones.where((p) => p.online).length} online · ${store.phones.length} saved · Select a phone to start',
        ),
        if (store.phones.isNotEmpty) ...[
          Text('Your phones', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: store.phones
                    .map(
                      (phone) =>
                          SizedBox(width: width, child: phoneCard(phone)),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
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
        for (final mirror in store.mirrors.values.where((m) => m.open)) ...[
          const SizedBox(height: 18),
          Panel(
            child: ListTile(
              leading: Icon(
                Icons.screen_share_rounded,
                color: mirror.status == 'Live' ? Colors.green : Colors.orange,
              ),
              title: Text(
                mirror.status == 'Live'
                    ? 'Screen is being mirrored'
                    : 'Screen mirror · ${mirror.status}',
              ),
              subtitle: Text(
                '${store.devices.where((d) => d.serial == mirror.device).firstOrNull?.label ?? mirror.device} · Separate window${mirror.detail.isEmpty ? '' : '\n${mirror.detail}'}',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => mirror.command('focus'),
                    child: const Text('Show window'),
                  ),
                  TextButton(onPressed: mirror.stop, child: const Text('Stop')),
                ],
              ),
            ),
          ),
        ],
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

  Widget phoneCard(PhoneSummary phone) {
    final selected = phone.connections.any((d) => d.serial == store.selected);
    final colors = Theme.of(context).colorScheme;
    final statuses = phone.connections
        .map((d) => store.linkSetup[d.serial])
        .whereType<String>()
        .toSet();
    final preferred = phone.preferred;
    final internet = preferred?.relay == true;
    return Card(
      color: selected
          ? colors.primaryContainer.withValues(alpha: .3)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? beamBlue
              : colors.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: phone.preferred == null
            ? null
            : () => store.select(phone.preferred!.serial),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.smartphone_rounded,
                    color: phone.online ? beamBlue : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      phone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove phone',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Remove ${phone.name}?'),
                          content: const Text(
                            'Remove this phone and uninstall BeamADB Link using ADB. Automatic setup will not reinstall it. If it is offline, or uninstall disconnects its relay, connect through USB/local ADB to finish or verify removal.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove and uninstall'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await store.removePhone(phone);
                        if (mounted) await showResult(context, store);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Rename phone',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final name = await askText(
                        context,
                        'Rename phone',
                        'Choose a name you recognize',
                        initial: phone.name,
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await store.renamePhone(phone.id, name);
                      }
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    avatar: Icon(
                      Icons.circle,
                      size: 9,
                      color: phone.online
                          ? Colors.green
                          : colors.onSurfaceVariant,
                    ),
                    label: Text(phone.online ? 'Online' : 'Offline'),
                  ),
                  if (phone.battery != null && phone.battery != '—')
                    Chip(
                      avatar: const Icon(Icons.battery_std_rounded, size: 16),
                      label: Text(
                        '${phone.battery}%${phone.online ? '' : ' last seen'}',
                      ),
                    ),
                  if (!internet && preferred?.ready == true)
                    Chip(
                      label: Text(
                        preferred!.wireless ? 'Local network' : 'USB',
                      ),
                    ),
                  if (internet)
                    const Chip(
                      avatar: Icon(Icons.public, size: 16),
                      label: Text('Internet'),
                    ),
                ],
              ),
              if (statuses.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    statuses.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (phone.connections.any((d) => d.state == 'unauthorized'))
                const Text('Unlock phone and approve debugging'),
              if (!phone.online && phone.lastSeen != null)
                Text(
                  'Last seen ${DateTime.tryParse(phone.lastSeen!)?.toLocal().toString().split('.').first ?? phone.lastSeen}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
      ),
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
            SwitchListTile(
              title: const Text('Device connection notifications'),
              subtitle: const Text(
                'The VPS reports when a phone connects or stops responding. Alerts also work while the desktop window is closed; disconnect detection takes about 35 seconds.',
              ),
              value: store.connectionNotifications,
              onChanged: store.setConnectionNotifications,
            ),
            ...store.removedPhones.entries.map(
              (entry) => ListTile(
                leading: const Icon(Icons.phonelink_erase_outlined),
                title: const Text('Removed device'),
                subtitle: Text(entry.value),
              ),
            ),
            SwitchListTile(
              title: const Text('Set up connected phones automatically'),
              subtitle: const Text(
                'Install BeamADB Link and securely configure internet access on authorized ADB phones. Android approvals may still be needed.',
              ),
              value: store.autoSetup,
              onChanged: store.setAutoSetup,
            ),
            const ListTile(
              leading: Icon(Icons.video_library_outlined),
              title: Text('Recordings saved automatically'),
              subtitle: Text(
                'Videos/BeamADB for screen and camera · Music/BeamADB for audio. Files include the phone name, capture type and date.',
              ),
            ),
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
