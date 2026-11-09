import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
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

Future<void> showResult(BuildContext context, AppStore store) async {
  if (!context.mounted || store.activities.isEmpty) return;
  final activity = store.activities.first;
  if (activity.state == 'Failed') {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activity.title),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(child: SelectableText(activity.detail)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${activity.title}: ${activity.state.toLowerCase()}'),
      ),
    );
  }
}
