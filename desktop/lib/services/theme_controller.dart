import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Light / dark / follow-the-system appearance, persisted across launches.
///
/// [AppColors] tokens are plain getters, so a palette switch can't be picked
/// up by inherited-widget dependencies alone. After flipping
/// [AppColors.isDark] we mark every element dirty (the same mechanism hot
/// reload uses); widget state and navigation are preserved.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark => AppColors.isDark;

  /// Reads the saved choice and applies it. Call before `runApp` so the first
  /// frame already uses the right palette.
  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_prefsKey),
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      _mode = ThemeMode.system;
    }
    AppColors.isDark = _resolveDark();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Not persisting is harmless; the choice still applies this session.
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == ThemeMode.system) _apply();
  }

  bool _resolveDark() => switch (_mode) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  void _apply() {
    final dark = _resolveDark();
    final changed = dark != AppColors.isDark;
    AppColors.isDark = dark;
    notifyListeners();
    if (changed) WidgetsBinding.instance.reassembleApplication();
  }
}
