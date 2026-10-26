import 'package:flutter/material.dart';
import 'app_theme.dart';

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
  const AppMenuAction(
    this.value,
    this.label, {
    this.destructive = false,
    this.checked,
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
          child: Text(
            actions[i].label,
            style: actions[i].destructive
                ? TextStyle(color: appColors(context).error)
                : null,
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
