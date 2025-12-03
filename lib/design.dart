// design.dart — Cropeye Auth Final (Realistic Tomato Edition)
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

const _green = Color(0xFF2E7D32);
//const _darkGreen = Color(0xFF1B5E20);
const _orange = Color(0xFFFF7043);
const _yellow = Color(0xFFFFE082);
const _tomatoRed = Color(0xFFE53935);

class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> fields;
  final String buttonText;
  final VoidCallback onSubmit;
  final String? footerText;
  final String? footerActionText;
  final VoidCallback? onFooterAction;
  final Widget? topIcon;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.fields,
    required this.buttonText,
    required this.onSubmit,
    this.footerText,
    this.footerActionText,
    this.onFooterAction,
    this.topIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_green, _yellow, _orange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ===== HEADER =====
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_green, _yellow, _orange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(80),
                    bottomRight: Radius.circular(80),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 30, bottom: 25),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const TomatoBadge(size: 90),
                      const SizedBox(height: 15),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            subtitle!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ===== FORM BODY =====
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 25),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(60),
                      topRight: Radius.circular(60),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 15,
                        offset: Offset(0, -3),
                      )
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        ...fields,
                        const SizedBox(height: 22),
                        MainButton(text: buttonText, onPressed: onSubmit),
                        const SizedBox(height: 25),
                        if (footerText != null && footerActionText != null)
                          Column(
                            children: [
                              const Divider(
                                  height: 35,
                                  thickness: 0.8,
                                  indent: 40,
                                  endIndent: 40),
                              RichText(
                                text: TextSpan(
                                  text: footerText!,
                                  style: const TextStyle(
                                      color: Colors.black87, fontSize: 15),
                                  children: [
                                    const WidgetSpan(
                                        child: SizedBox(width: 4)),
                                    WidgetSpan(
                                      child: GestureDetector(
                                        onTap: onFooterAction,
                                        child: Text(
                                          footerActionText!,
                                          style: const TextStyle(
                                            color: _tomatoRed,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🍅 Realistic Tomato Badge
class TomatoBadge extends StatelessWidget {
  final double size;
  const TomatoBadge({super.key, this.size = 90});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      child: CustomPaint(
        size: Size.square(size),
        painter: _RealTomatoPainter(),
      ),
    );
  }
}

class _RealTomatoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2.2;

    // === Base Shadow ===
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, r * 0.15), width: r * 1.8, height: r * 1.6),
      shadow,
    );

    // === Tomato Body (organic shape) ===
    final tomatoPath = Path()
      ..moveTo(c.dx, c.dy - r)
      ..cubicTo(c.dx + r * 1.0, c.dy - r * 0.8, c.dx + r * 1.05, c.dy + r * 0.9, c.dx, c.dy + r)
      ..cubicTo(c.dx - r * 1.05, c.dy + r * 0.9, c.dx - r * 1.0, c.dy - r * 0.8, c.dx, c.dy - r)
      ..close();

    final tomatoPaint = Paint()
      ..shader = ui.Gradient.radial(
        c,
        r * 1.2,
        [
          const Color(0xFF9B0000),
          const Color(0xFFC62828),
          const Color(0xFFD32F2F),
          const Color(0xFFFF7043),
        ],
        [0.05, 0.4, 0.75, 1.0],
      );
    canvas.drawPath(tomatoPath, tomatoPaint);

    // === Gloss Highlight (subtle arc) ===
    final gloss = Paint()
      ..shader = ui.Gradient.linear(
        c.translate(-r * 0.4, -r * 0.35),
        c,
        [Colors.white.withOpacity(0.5), Colors.transparent],
      )
      ..blendMode = BlendMode.lighten;
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(-r * 0.25, -r * 0.25),
        width: r * 0.9,
        height: r * 0.6,
      ),
      gloss,
    );

    // === Leaf Crown (multi-leaf) ===
    final leafPaint = Paint()
      ..shader = ui.Gradient.linear(
        c.translate(0, -r),
        c,
        [const Color(0xFF1B5E20), const Color(0xFF66BB6A)],
      )
      ..style = PaintingStyle.fill;

    for (var i = -2; i <= 2; i++) {
      final angle = i * 0.3;
      final leaf = Path()
        ..moveTo(c.dx, c.dy - r * 0.8)
        ..quadraticBezierTo(
          c.dx + r * 0.25 * angle,
          c.dy - r * 1.2,
          c.dx + r * 0.4 * angle,
          c.dy - r * 0.75,
        )
        ..close();
      canvas.drawPath(leaf, leafPaint);
    }

    // === Stem ===
    final stem = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(c.dx, c.dy - r * 0.9),
      Offset(c.dx, c.dy - r * 1.25),
      stem,
    );

    // === Rim Light ===
    final rimLight = Paint()
      ..shader = ui.Gradient.linear(
        c.translate(-r, 0),
        c.translate(r, 0),
        [Colors.white.withOpacity(0.15), Colors.transparent],
      )
      ..blendMode = BlendMode.screen;
    canvas.drawPath(tomatoPath, rimLight);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// 🌿 TextField
class AuthTextField extends StatelessWidget {
  final IconData icon;
  final String hint;
  final bool obscure;
  final TextEditingController? controller;

  const AuthTextField({
    super.key,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _green),
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(35),
            borderSide: BorderSide(color: Colors.black26),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(35),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// 🌅 Main Button
class MainButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const MainButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(35),
          gradient: const LinearGradient(
            colors: [_green, _yellow, _orange, _tomatoRed],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
