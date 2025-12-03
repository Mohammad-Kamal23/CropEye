import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global theme and app settings manager.
/// Handles dark/light mode, system sync, and persistence across sessions.
class SettingsProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _followSystemTheme = true;

  bool get isDarkMode => _isDarkMode;
  bool get followSystemTheme => _followSystemTheme;

  SettingsProvider() {
    _loadSettings();
  }

  /// Loads saved preferences from local storage.
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('darkMode') ?? false;
      _followSystemTheme = prefs.getBool('followSystemTheme') ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint("⚠️ Settings load failed: $e");
    }
  }

  /// Toggles manual dark mode, disables system-follow temporarily.
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    _followSystemTheme = false; // manual override
    await _savePrefs();
    notifyListeners();
  }

  /// Enables or disables following system-wide brightness.
  Future<void> toggleFollowSystem(bool value) async {
    _followSystemTheme = value;
    await _savePrefs();
    notifyListeners();
  }

  /// Automatically updates theme based on device brightness.
  /// Triggered from MyApp when brightness changes.
  void updateSystemBrightness(Brightness brightness) {
    if (_followSystemTheme) {
      final newMode = brightness == Brightness.dark;
      if (_isDarkMode != newMode) {
        _isDarkMode = newMode;
        notifyListeners();
      }
    }
  }

  /// Explicitly save all settings to shared preferences.
  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('darkMode', _isDarkMode);
      await prefs.setBool('followSystemTheme', _followSystemTheme);
    } catch (e) {
      debugPrint("⚠️ Failed to save settings: $e");
    }
  }

  /// Resets all settings to default state.
  Future<void> resetToDefault() async {
    _isDarkMode = false;
    _followSystemTheme = true;
    await _savePrefs();
    notifyListeners();
  }

  /// Allows external files (like settings_functions.dart) to directly update settings.
  Future<void> setTheme({bool? darkMode, bool? followSystem}) async {
    if (darkMode != null) _isDarkMode = darkMode;
    if (followSystem != null) _followSystemTheme = followSystem;
    await _savePrefs();
    notifyListeners();
  }
}
