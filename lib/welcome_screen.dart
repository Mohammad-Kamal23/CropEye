// welcome_screen.dart — v11 (static photo, tagline restored & lowered)
import 'dart:ui';
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'register_page.dart';
import 'admin_login_page.dart';
import 'admin_register_page.dart';
import 'welcome_design.dart';

const _brandGreenDark = Color(0xFF1B5E20);
const _brandGreen     = Color(0xFF2E7D32);

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Static background used by WelcomeDesign; pre-cache to avoid pop-in.
  final ImageProvider _bg = const AssetImage('assets/welcome_screen.jpg');

  // ---- Tweak these to nudge layout (0.0–1.0 from top) ----
  // Where the tagline starts as a fraction of screen height.
  static const double kTaglineTopFrac = 0.58; // move lower/higher: 0.60 -> lower, 0.54 -> higher
  // Extra bottom padding to float content above the nav bar a bit.
  static const double kBottomPad      = 34.0;
  // Button width limits so it matches the mock on phones & tablets.
  static const double kBtnMinW = 320.0;
  static const double kBtnMaxW = 420.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(_bg, context);
    });
  }

  void _showRoleSelection(BuildContext context, bool isSignIn) {
    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: Colors.white.withOpacity(.92),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            "Continue as",
            style: TextStyle(fontWeight: FontWeight.bold, color: _brandGreenDark),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleBtn(
                context,
                "User",
                isSignIn ? const LoginPage() : const RegisterPage(),
                Icons.person_outline,
              ),
              const SizedBox(height: 10),
              _roleBtn(
                context,
                "Admin",
                isSignIn ? const AdminLoginPage() : const AdminRegisterPage(),
                Icons.security_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBtn(BuildContext context, String role, Widget page, IconData icon) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandGreen,
        minimumSize: const Size(220, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        elevation: 3,
      ),
      icon: Icon(icon, color: Colors.white),
      label: Text(role, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      onPressed: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq   = MediaQuery.of(context);
    final size = mq.size;
    final safe = mq.padding;

    // Where we begin the overlaid content (tagline + buttons + footer)
    final double contentTop = (size.height * kTaglineTopFrac).clamp(120.0, size.height * 0.82);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // === STATIC BACKGROUND (full photo via your painter) ===
            const WelcomeDesign(),

            // === TAGLINE + BUTTONS + SOCIAL (lowered to match reference) ===
            Positioned.fill(
              top: contentTop,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 0, 20, safe.bottom + kBottomPad),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: kBtnMinW, maxWidth: kBtnMaxW),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tagline (RESTORED)
                        const Text(
                          'AI-driven farming, reimagined.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 18),

                        // Buttons
                        _mainBtn(context, "SIGN IN", isSignIn: true),
                        const SizedBox(height: 14),
                        _mainBtn(context, "SIGN UP", isSignIn: false, outline: true),

                        const SizedBox(height: 28),

                        // Social
                        const Text('Follow us on social media!',
                            style: TextStyle(fontSize: 16, color: Colors.white70)),
                        const SizedBox(height: 10),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.facebook, color: Colors.white, size: 32),
                            SizedBox(width: 18),
                            Icon(Icons.g_translate, color: Colors.white, size: 32),
                            SizedBox(width: 18),
                            Icon(Icons.apple, color: Colors.white, size: 32),
                          ],
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          "© 2025 Cropeye — University of Jordan AI Team",
                          style: TextStyle(fontSize: 12.5, color: Colors.white70, letterSpacing: 0.3),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainBtn(BuildContext context, String text,
      {required bool isSignIn, bool outline = false}) {
    return GestureDetector(
      onTap: () => _showRoleSelection(context, isSignIn),
      child: Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: outline
              ? null
              : const LinearGradient(
                  // warmer, softer green for the sunset photo
                  colors: [Color(0xFF3B7D42), _brandGreenDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: outline ? Colors.transparent : null,
          border: Border.all(
            color: Colors.white.withOpacity(outline ? 0.95 : 0.70),
            width: outline ? 1.6 : 0.8,
          ),
          boxShadow: outline
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(.28),
                    blurRadius: 12,
                    offset: const Offset(0, 7),
                  )
                ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}
