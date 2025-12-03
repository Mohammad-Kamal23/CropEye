import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);

/// ================================================================
/// AboutSection — Unified version for the universal navigation shell
/// ================================================================
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  final List<Map<String, String>> _storySections = const [
    {
      'title': '🌿 Our Vision',
      'text':
          'At CropEye, we believe that technology and nature can work hand in hand. Our goal is to empower farmers and agricultural specialists with AI-driven tools that protect crops and preserve ecosystems.'
    },
    {
      'title': '🤖 What We Do',
      'text':
          'We combine deep learning models, computer vision, and on-device intelligence to detect diseases in tomato plants early and accurately — reducing pesticide use and increasing yield sustainability.'
    },
    {
      'title': '🌎 Our Mission',
      'text':
          'Our mission is to bridge the gap between data science and farming, making smart agriculture accessible for everyone through clean design, open collaboration, and reliable results.'
    },
    {
      'title': '👨‍💻 The CropEye Team',
      'text':
          'We are a group of passionate Data Science majors from the University of Jordan — united by a shared love for innovation and environmental care.'
    },
  ];

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: FadeTransition(
        opacity: _fadeCtrl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16),
          child: Column(
            children: [
              // ==== PAGE HEADER ====
              const Text(
                "AI for Sustainable Agriculture",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _brandGreen,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 22),

              // ==== STORY SECTIONS ====
              ListView.builder(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _storySections.length,
                itemBuilder: (context, i) {
                  final item = _storySections[i];
                  return _StoryCard(
                    title: item['title']!,
                    text: item['text']!,
                    delayMs: i * 180,
                  );
                },
              ),

              const SizedBox(height: 30),

              // ==== TAGLINE ====
              const Text(
                "Empowering Farmers Through AI 🌾",
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ================================================================
/// StoryCard — reusable with consistent animation & design language
/// ================================================================
class _StoryCard extends StatelessWidget {
  final String title;
  final String text;
  final int delayMs;

  const _StoryCard({
    required this.title,
    required this.text,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 5,
      shadowColor: _brandGreen.withValues(alpha: 0.25),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              _pageBgTop.withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: _brandGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.justify,
              style: const TextStyle(
                fontSize: 15.5,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: delayMs.ms)
        .fadeIn(duration: 450.ms)
        .slideY(begin: 0.25, end: 0);
  }
}
