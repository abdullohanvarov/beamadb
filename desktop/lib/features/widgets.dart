import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../core/friendly_error.dart';
import '../core/store.dart';

class PageHeading extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> actions;
  const PageHeading(
    this.title,
    this.subtitle, {
    super.key,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.4,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState(
    this.icon,
    this.title,
    this.description, {
    super.key,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final bool error;
  final Widget? action;
  const Notice(this.text, {super.key, this.error = false, this.action});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: (error ? Colors.red : Colors.blue).withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          size: 20,
          color: error ? Colors.red : Colors.blue,
        ),
        const SizedBox(width: 12),
        Expanded(child: SelectableText(text)),
        ?action,
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String description, {
  String label = 'Continue',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 430, child: Text(description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> askText(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  // Dialog exit animations may still reference its text controller.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class FriendlyErrorDialog extends StatefulWidget {
  final String title;
  final String detail;

  const FriendlyErrorDialog({
    super.key,
    required this.title,
    required this.detail,
  });

  @override
  State<FriendlyErrorDialog> createState() => _FriendlyErrorDialogState();
}

class _FriendlyErrorDialogState extends State<FriendlyErrorDialog> {
  bool showTechnical = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final friendly = FriendlyError.parse(widget.detail, widget.title);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: colors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friendly.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friendly.description,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              if (friendly.suggestion != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          friendly.suggestion!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (friendly.raw.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => showTechnical = !showTechnical),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          showTechnical
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          showTechnical
                              ? 'Hide technical details'
                              : 'Show technical details',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showTechnical) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        friendly.raw,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

Future<void> showResult(BuildContext context, AppStore store) async {
  if (!context.mounted || store.activities.isEmpty) return;
  final activity = store.activities.first;
  if (activity.state == 'Failed') {
    await showDialog<void>(
      context: context,
      builder: (context) => FriendlyErrorDialog(
        title: activity.title,
        detail: activity.detail,
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${activity.title}: ${activity.state.toLowerCase()}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class WindowControls extends StatefulWidget {
  final VoidCallback? onClose;
  final bool showMaximize;
  final double buttonWidth;
  final double buttonHeight;

  const WindowControls({
    super.key,
    this.onClose,
    this.showMaximize = true,
    this.buttonWidth = 38,
    this.buttonHeight = 28,
  });

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _check();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _check();

  @override
  void onWindowUnmaximize() => _check();

  Future<void> _check() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted && max != isMaximized) {
        setState(() => isMaximized = max);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xff1f2433)
            : colors.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.8),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _WindowBtn(
            icon: Icons.remove_rounded,
            iconSize: 18,
            tooltip: 'Minimize',
            width: widget.buttonWidth,
            height: widget.buttonHeight,
            onTap: () => windowManager.minimize(),
          ),
          if (widget.showMaximize) ...[
            const SizedBox(width: 1),
            _WindowBtn(
              icon: isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              iconSize: isMaximized ? 13 : 15,
              tooltip: isMaximized ? 'Restore' : 'Maximize',
              width: widget.buttonWidth,
              height: widget.buttonHeight,
              onTap: () async {
                try {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                    setState(() => isMaximized = false);
                  } else {
                    await windowManager.maximize();
                    setState(() => isMaximized = true);
                  }
                } catch (_) {}
              },
            ),
          ],
          const SizedBox(width: 1),
          _WindowBtn(
            icon: Icons.close_rounded,
            iconSize: 17,
            tooltip: 'Close',
            isClose: true,
            width: widget.buttonWidth,
            height: widget.buttonHeight,
            onTap: widget.onClose ?? () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WindowBtn extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final bool isClose;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const _WindowBtn({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    this.isClose = false,
    required this.width,
    required this.height,
    this.onTap,
  });

  @override
  State<_WindowBtn> createState() => _WindowBtnState();
}

class _WindowBtnState extends State<_WindowBtn> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final normalColor = isDark
        ? const Color(0xffffffff)
        : const Color(0xff111318);

    Color bg = Colors.transparent;
    Color iconCol = normalColor;

    if (hovering) {
      if (widget.isClose) {
        bg = const Color(0xffe81123);
        iconCol = Colors.white;
      } else {
        bg = isDark
            ? Colors.white.withValues(alpha: 0.22)
            : colors.onSurface.withValues(alpha: 0.12);
        iconCol = isDark ? Colors.white : Colors.black;
      }
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: TextButton(
          onPressed: widget.onTap,
          onHover: (value) => setState(() => hovering = value),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            foregroundColor: iconCol,
            backgroundColor: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: CustomPaint(
            size: Size.square(widget.iconSize),
            painter: _WindowGlyph(widget.tooltip, iconCol),
          ),
        ),
      ),
    );
  }
}

// Draw essential window controls independently of icon font loading.
class _WindowGlyph extends CustomPainter {
  final String action;
  final Color color;
  const _WindowGlyph(this.action, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final box = rect.deflate(3);
    switch (action) {
      case 'Minimize':
        canvas.drawLine(
          Offset(box.left, size.height / 2),
          Offset(box.right, size.height / 2),
          paint,
        );
      case 'Close':
        canvas.drawLine(box.topLeft, box.bottomRight, paint);
        canvas.drawLine(box.topRight, box.bottomLeft, paint);
      case 'Restore':
        canvas.drawRect(
          Rect.fromLTWH(4, 2, size.width - 6, size.height - 6),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(2, 4, size.width - 6, size.height - 6),
          paint,
        );
      default:
        canvas.drawRect(box, paint);
    }
  }

  @override
  bool shouldRepaint(_WindowGlyph oldDelegate) =>
      action != oldDelegate.action || color != oldDelegate.color;
}

class AndroidNavControls extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onRecents;
  final bool isVertical;
  final Color? buttonColor;
  final double iconSize;

  const AndroidNavControls({
    super.key,
    required this.onBack,
    required this.onHome,
    required this.onRecents,
    this.isVertical = false,
    this.buttonColor,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor =
        buttonColor ??
        (isDark ? const Color(0xffeceef4) : const Color(0xff22262e));

    Widget buildNavBtn({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      double? sizeOverride,
    }) {
      return _NavIconBtn(
        icon: icon,
        iconSize: sizeOverride ?? iconSize,
        tooltip: tooltip,
        color: effectiveColor,
        onTap: onTap,
      );
    }

    final children = [
      buildNavBtn(
        icon: Icons.arrow_back_ios_new_rounded,
        sizeOverride: iconSize - 2,
        tooltip: 'Back',
        onTap: onBack,
      ),
      buildNavBtn(icon: Icons.circle_outlined, tooltip: 'Home', onTap: onHome),
      buildNavBtn(
        icon: Icons.crop_square_rounded,
        tooltip: 'Recent apps',
        onTap: onRecents,
      ),
    ];

    if (isVertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _NavIconBtn extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _NavIconBtn({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NavIconBtn> createState() => _NavIconBtnState();
}

class _NavIconBtnState extends State<_NavIconBtn> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 38,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovering
                  ? colors.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: hovering ? colors.primary : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
