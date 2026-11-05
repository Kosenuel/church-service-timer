import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// A focusable explanation for a disabled action. The real control stays
/// disabled; tapping or activating this wrapper never executes its action.
class UnavailableAction extends StatelessWidget {
  final String? reason;
  final Widget child;
  const UnavailableAction({
    super.key,
    required this.reason,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    if (reason == null) return child;
    void explain() => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(reason!), duration: const Duration(seconds: 4)),
    );
    return Semantics(
      button: true,
      label: reason,
      onTap: explain,
      child: Tooltip(
        message: reason!,
        child: InkWell(
          onTap: explain,
          borderRadius: BorderRadius.circular(14),
          child: ExcludeFocus(child: AbsorbPointer(child: child)),
        ),
      ),
    );
  }
}

/// Longer selections share one phone sheet / wide-window dialog treatment.
/// The supplied content is a non-scrolling column; this surface owns scrolling.
Future<T?> showAppSelection<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  Widget content(BuildContext ctx, ScrollController? scroll) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, appLayout(ctx).gap, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'Close $title',
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const AppDivider(indent: 0, endIndent: 0),
      Flexible(
        child: SingleChildScrollView(
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(appLayout(ctx).panelPadding),
          child: builder(ctx),
        ),
      ),
    ],
  );
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<T>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: MediaQuery.sizeOf(ctx).height * .85,
          ),
          child: content(ctx, null),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        minChildSize: .35,
        maxChildSize: .94,
        builder: (ctx, scroll) => content(ctx, scroll),
      ),
    ),
  );
}

class DurationField extends StatelessWidget {
  final String value;
  final VoidCallback? onTap;
  const DurationField({super.key, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Edit duration, $value, minutes and seconds',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Duration · min:sec',
          enabled: onTap != null,
          prefixIcon: const Icon(Icons.timer_outlined),
          suffixIcon: const Icon(Icons.edit_outlined),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}
