// settings_functions.dart
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_provider.dart';

class SettingsFunctions {
  // =========================
  // Save banner
  // =========================
  static Future<void> saveSettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("settings_saved", true);
    _showSnack(context, "✅ Settings saved successfully!");
  }

  // =========================
  // Biometrics
  // =========================
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool?> toggleBiometric(bool enable) async {
    try {
      if (enable) {
        final canCheck = await _auth.canCheckBiometrics;
        final available = await _auth.getAvailableBiometrics();
        if (!canCheck || available.isEmpty) {
          log("No biometrics available");
          return false;
        }
        final ok = await _auth.authenticate(
          localizedReason: "Enable biometric login for CropEye",
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        if (ok) {
          final p = await SharedPreferences.getInstance();
          await p.setBool('biometricEnabled', true);
          return true;
        }
        return false;
      } else {
        final p = await SharedPreferences.getInstance();
        await p.remove('biometricEnabled');
        return false;
      }
    } catch (e) {
      log("Biometric error: $e");
      return null;
    }
  }

  // =========================
  // Profile helpers
  // =========================
  static Future<Map<String, String?>> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    return {
      'name': p.getString('profile_name') ?? 'User',
      'email': p.getString('profile_email') ?? 'example@email.com',
      'avatar': p.getString('profile_avatar_path'),
    };
  }

  static Future<void> _pickAndSaveAvatar(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final p = await SharedPreferences.getInstance();
      await p.setString('profile_avatar_path', picked.path);
      _showSnack(context, "📷 Profile photo updated");
    } catch (e) {
      _showSnack(context, "Failed to pick image: $e");
    }
  }

  static Future<void> openProfileEditor(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString('profile_name') ?? "User";
    final email = p.getString('profile_email') ?? "example@email.com";
    final avatarPath = p.getString('profile_avatar_path');

    final nameCtrl = TextEditingController(text: name);
    final emailCtrl = TextEditingController(text: email);

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("Edit Profile"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar + change button
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF1B5E20).withOpacity(0.12),
                backgroundImage: (avatarPath != null && File(avatarPath).existsSync())
                    ? FileImage(File(avatarPath))
                    : null,
                child: (avatarPath == null || !File(avatarPath).existsSync())
                    ? const Icon(Icons.person, size: 38, color: Color(0xFF1B5E20))
                    : null,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await _pickAndSaveAvatar(ctx);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text("Change photo"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Name"),
              ),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
              onPressed: () async {
                await p.setString('profile_name', nameCtrl.text.trim());
                await p.setString('profile_email', emailCtrl.text.trim());
                Navigator.pop(ctx);
                _showSnack(context, "Profile updated");
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // =========================
  // Password
  // =========================
  static Future<void> openPasswordReset(BuildContext context) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Change Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(obscureText: true, controller: passCtrl, decoration: const InputDecoration(labelText: "New Password")),
            TextField(obscureText: true, controller: confirmCtrl, decoration: const InputDecoration(labelText: "Confirm Password")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
            onPressed: () async {
              if (passCtrl.text.trim() == confirmCtrl.text.trim() && passCtrl.text.isNotEmpty) {
                final p = await SharedPreferences.getInstance();
                await p.setString("local_password", passCtrl.text.trim());
                Navigator.pop(ctx);
                _showSnack(context, "Password updated locally.");
              } else {
                _showSnack(context, "Passwords do not match!");
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // =========================
  // Toggles
  // =========================
  static Future<void> toggleAutoSync(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool("auto_sync", value);
    log("Auto sync → $value");
  }

  static Future<void> toggleNotifications(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool("notifications_enabled", value);
    log("Notifications → $value");
  }

  static Future<void> showFeatureAlert(BuildContext context) async {
    _showSnack(context, "🔔 Feature alerts are now active!");
  }

  static Future<void> resetAll(BuildContext context, SettingsProvider settings) async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    await settings.resetToDefault();
    _showSnack(context, "All settings reset");
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }
}
