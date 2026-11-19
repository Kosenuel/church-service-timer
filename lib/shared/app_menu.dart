import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Shared separators for dialog choices and other short option lists.
class AppMenuList extends StatelessWidget {
  final List<Widget> children;
  const AppMenuList({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const AppDivider(indent: 0, endIndent: 0),
        children[i],
      ],
    ],
  );
}

class AppMenuAction<T> {
  final T value;
  final String label;
  final bool destructive;
  final bool? checked;

  /// The keyboard key that does the same, shown quietly at the right.
  final String? keys;
  const AppMenuAction(
    this.value,
    this.label, {
    this.destructive = false,
    this.checked,
    this.keys,
  });
}

/// Popup items do not inherit ListTile density, so apply it explicitly.
List<PopupMenuEntry<T>> appMenuEntries<T>(
  BuildContext context,
  List<AppMenuAction<T>> actions,
) {
  final layout = appLayout(context);
  return [
    for (var i = 0; i < actions.length; i++) ...[
      if (i > 0) _AppMenuSeparator<T>(essential: actions[i].destructive),
      if (actions[i].checked != null)
        CheckedPopupMenuItem<T>(
          value: actions[i].value,
          checked: actions[i].checked!,
          height: layout.controlHeight,
          padding: layout.tileInsets,
          child: Text(actions[i].label),
        )
      else
        PopupMenuItem<T>(
          value: actions[i].value,
          height: layout.controlHeight,
          padding: layout.tileInsets,
          child: actions[i].keys == null
              ? Text(
                  actions[i].label,
                  style: actions[i].destructive
                      ? TextStyle(color: appColors(context).error)
                      : null,
                )
              : Row(
                  children: [
                    Expanded(child: Text(actions[i].label)),
                    const SizedBox(width: 24),
                    ExcludeSemantics(
                      child: Text(
                        actions[i].keys!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: appColors(context).muted,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
    ],
  ];
}

class _AppMenuSeparator<T> extends PopupMenuEntry<T> {
  final bool essential;
  const _AppMenuSeparator({this.essential = false});
  @override
  double get height => 8;
  @override
  bool represents(T? value) => false;
  @override
  State<_AppMenuSeparator<T>> createState() => _AppMenuSeparatorState<T>();
}

class _AppMenuSeparatorState<T> extends State<_AppMenuSeparator<T>> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Center(child: AppDivider(essential: widget.essential)),
  );
}
