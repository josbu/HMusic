import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences Key for ThemeMode
const _themeModePrefKey = 'app_theme_mode';

/// Provide an instance of SharedPreferences.
/// Typically overridden in `main.dart` after initialization.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main.dart');
});

/// Manage the App's ThemeMode
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return _loadThemeMode();
  }

  /// Load ThemeMode from SharedPreferences
  ThemeMode _loadThemeMode() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final index = prefs.getInt(_themeModePrefKey);
      if (index != null && index >= 0 && index < ThemeMode.values.length) {
        return ThemeMode.values[index];
      }
    } catch (e) {
      debugPrint('Error loading theme mode: $e');
    }
    // Default to system
    return ThemeMode.system;
  }

  /// Update ThemeMode and save to SharedPreferences
  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;

    state = mode;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setInt(_themeModePrefKey, mode.index);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});
