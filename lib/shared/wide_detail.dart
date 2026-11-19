import 'package:flutter/material.dart';

/// A settings detail page that lays out its own panes in a wide window.
/// The detail page gives it the whole body instead of one scrolling
/// column; each pane scrolls on its own.
class FillsWideWindow extends StatelessWidget {
  final Widget child;
  const FillsWideWindow({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}
