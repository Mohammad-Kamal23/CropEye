import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'settings_provider.dart';
import 'settings_functions.dart'; // unified logic controller

const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);
const _pageBgBottom = Colors.white;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..forward();

  bool _notifications = true;
  bool _autoSync = true;
  bool _biometricLogin = false;

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = settings.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      // ✅ One-tap SAVE always available
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'settings_save_fab',
        backgroundColor: _brandGreen,
        icon: const Icon(Icons.save, color: Colors.white),
        label: const Text(
          "Save",
          style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold
          ),
        ),
        onPressed: () => SettingsFunctions.saveSettings(context),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark ? [Colors.black87, Colors.black] : [_pageBgTop, _pageBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96), // bottom padding so FAB doesn’t cover last tiles
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 🔹 Small, unobtrusive page label (no big block)
                      const SizedBox(height: 8),
                      Text(
                        "Settings",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : _brandGreen,
                          letterSpacing: 0.5,
                        ),
                      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.2, end: 0),

                      const SizedBox(height: 12),
                      FadeTransition(
                        opacity: _fadeCtrl,
                        child: Text(
                          "Personalize your CropEye experience",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ==== SETTINGS SECTIONS ====
                      _sectionHeader("Account", isDark),
                      _tile(
                        icon: Icons.person_outline,
                        title: "Profile Information",
                        subtitle: "Edit your profile details",
                        isDark: isDark,
                        onTap: () => SettingsFunctions.openProfileEditor(context),
                      ),
                      _tile(
                        icon: Icons.lock_outline,
                        title: "Change Password",
                        subtitle: "Update your password securely",
                        isDark: isDark,
                        onTap: () => SettingsFunctions.openPasswordReset(context),
                      ),

                      _sectionHeader("Privacy & Security", isDark),
                      _switch(
                        icon: Icons.fingerprint,
                        title: "Biometric Login",
                        value: _biometricLogin,
                        isDark: isDark,
                        onChanged: (v) async {
                          final ok = await SettingsFunctions.toggleBiometric(v);
                          if (ok != null) setState(() => _biometricLogin = ok);
                        },
                      ),
                      _switch(
                        icon: Icons.sync_lock_outlined,
                        title: "Auto Data Sync",
                        value: _autoSync,
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _autoSync = v);
                          SettingsFunctions.toggleAutoSync(v);
                        },
                      ),

                      _sectionHeader("App Preferences", isDark),
                      _switch(
                        icon: Icons.phone_android,
                        title: "Follow System Theme",
                        value: settings.followSystemTheme,
                        isDark: isDark,
                        onChanged: (v) => settings.toggleFollowSystem(v),
                      ),
                      _switch(
                        icon: Icons.dark_mode_outlined,
                        title: "Dark Mode",
                        value: isDark,
                        isDark: isDark,
                        onChanged: (_) => settings.toggleDarkMode(),
                      ),

                      _sectionHeader("Notifications", isDark),
                      _switch(
                        icon: Icons.notifications_active_outlined,
                        title: "App Notifications",
                        value: _notifications,
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _notifications = v);
                          SettingsFunctions.toggleNotifications(v);
                        },
                      ),
                      _tile(
                        icon: Icons.tips_and_updates_outlined,
                        title: "Feature Alerts",
                        subtitle: "Stay updated on CropEye news",
                        isDark: isDark,
                        onTap: () => SettingsFunctions.showFeatureAlert(context),
                      ),

                      _sectionHeader("About CropEye", isDark),
                      _tile(
                        icon: Icons.info_outline,
                        title: "Version",
                        subtitle: "1.0.0 (Beta)",
                        isDark: isDark,
                      ),
                      _tile(
                        icon: Icons.group_outlined,
                        title: "Developed By",
                        subtitle: "Mohammad Kamal Abdelaziz & UJ AI Team",
                        isDark: isDark,
                      ),
                      _tile(
                        icon: Icons.eco_outlined,
                        title: "Future Work",
                        subtitle: "Upcoming AI integrations and live detection!",
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==== UI Helpers ====
  Widget _sectionHeader(String title, bool isDark) => Padding(
        padding: const EdgeInsets.only(top: 18.0, bottom: 8.0),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.lightGreenAccent : _brandGreen,
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.15, end: 0);

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    required bool isDark,
  }) =>
      _glassTile(
        ListTile(
          leading: Icon(icon, color: isDark ? Colors.white : _brandGreen),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                )
              : null,
          onTap: onTap,
        ),
        isDark,
      );

  Widget _switch({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) =>
      _glassTile(
        SwitchListTile(
          secondary: Icon(icon, color: isDark ? Colors.white : _brandGreen),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          value: value,
          activeColor: _brandGreen,
          onChanged: onChanged,
        ),
        isDark,
      );

  Widget _glassTile(Widget child, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.grey[900] : Colors.white)?.withOpacity(0.8),
                border: Border.all(
                  color: isDark ? Colors.white30 : _brandGreen.withOpacity(0.25),
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.2, end: 0);
}
