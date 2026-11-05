import 'package:flutter/foundation.dart';

import 'package:church_service_timer/domain/domain.dart';

/// The theme and appearance the app renders, including unsaved previews
/// from the Appearance page. Saved values come from [AppState].
class AppearancePreview {
  final themeSelection = ValueNotifier<String>('midnight_lime');
  final appearanceSelection = ValueNotifier<AppearancePreferences>(
    const AppearancePreferences(),
  );
  AppearancePreferences? _appearance;
  String? _theme;

  /// Shows [value] until it is saved or cleared; null returns to [saved].
  void previewAppearance(
    AppearancePreferences? value,
    AppearancePreferences saved,
  ) {
    _appearance = value;
    appearanceSelection.value = value ?? saved;
  }

  void previewTheme(String? id, String saved) {
    _theme = id;
    themeSelection.value = id ?? saved;
  }

  /// Applies saved preferences unless a preview is active.
  void sync(AppState state) {
    themeSelection.value = _theme ?? state.themeId;
    appearanceSelection.value = _appearance ?? state.appearance;
  }

  void dispose() {
    themeSelection.dispose();
    appearanceSelection.dispose();
  }
}
