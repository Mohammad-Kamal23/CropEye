// app_drawer.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _brandGreen = Color(0xFF1B5E20);

class AppSideDrawer extends StatefulWidget {
  const AppSideDrawer({super.key});

  @override
  State<AppSideDrawer> createState() => _AppSideDrawerState();
}

class _AppSideDrawerState extends State<AppSideDrawer> {
  String _name = 'User';
  String _email = 'example@email.com';
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('profile_name') ?? 'User';
      _email = prefs.getString('profile_email') ?? 'example@email.com';
      _avatarPath = prefs.getString('profile_avatar_path');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),

            // Avatar
            CircleAvatar(
              radius: 48,
              backgroundColor: _brandGreen.withOpacity(0.15),
              backgroundImage:
                  _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
              child: _avatarPath == null
                  ? Icon(Icons.person, size: 48, color: _brandGreen.withOpacity(0.8))
                  : null,
            ),

            const SizedBox(height: 14),

            // Name
            Text(
              _name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : _brandGreen,
              ),
            ),

            const SizedBox(height: 4),

            // Email
            Text(
              _email,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14.5,
              ),
            ),

            const SizedBox(height: 24),

            Divider(
              color: isDark ? Colors.white24 : Colors.black12,
              thickness: 1,
              indent: 32,
              endIndent: 32,
            ),

            const SizedBox(height: 14),
            Icon(Icons.eco_outlined,
                size: 32, color: isDark ? Colors.white54 : _brandGreen),
            const SizedBox(height: 6),
            Text(
              "CropEye App",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Version 1.0.0 (Beta)",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                "© 2025 University of Jordan AI Team",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
