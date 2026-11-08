import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/main.dart';

/// Small building blocks shared by the home pages.
extension HomeWidgets on HomeState {
  Widget panel({required Widget child, EdgeInsets? padding}) => Material(
    color: appColors(context).surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: appColors(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: padding ?? EdgeInsets.all(appLayout(context).panelPadding),
      child: child,
    ),
  );
  Widget label(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: appColors(context).muted,
      letterSpacing: 1.6,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
  Widget button(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
    String? disabledReason,
  }) => UnavailableAction(
    reason: controlsLocked || action == null
        ? disabledReason ?? unavailableReason(text)
        : null,
    child: primary
        ? FilledButton.icon(
            onPressed: controlsLocked ? null : action,
            icon: Icon(icon, size: 20),
            label: Text(text),
          )
        : OutlinedButton.icon(
            onPressed: controlsLocked ? null : action,
            icon: Icon(icon, size: 20),
            label: Text(text),
          ),
  );

  /// A compact button with the icon above a short label, for a row of
  /// three even actions.
  Widget stackedButton(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 76)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
    );
    return UnavailableAction(
      reason: controlsLocked || action == null ? unavailableReason(text) : null,
      child: primary
          ? FilledButton(
              style: style,
              onPressed: controlsLocked ? null : action,
              child: child,
            )
          : OutlinedButton(
              style: style,
              onPressed: controlsLocked ? null : action,
              child: child,
            ),
    );
  }
}
