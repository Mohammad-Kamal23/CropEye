import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);

/// ===================================================================
/// ServiceSection — optimized for universal wheel shell
/// ===================================================================
class ServiceSection extends StatefulWidget {
  const ServiceSection({super.key});

  @override
  State<ServiceSection> createState() => _ServiceSectionState();
}

class _ServiceSectionState extends State<ServiceSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  final List<Map<String, String>> _futureUpdates = const [
    {
      'title': '🔍 Auto Detection',
      'desc': 'Real-time detection of tomato leaf miners via camera feed.'
    },
    {
      'title': '🗺️ Disease Heatmap',
      'desc':
          'Track infection spread across greenhouses with visual data overlays.'
    },
    {
      'title': '🎙️ Voice Capture',
      'desc': 'Hands-free diagnosis and report creation using voice commands.'
    },
    {
      'title': '⚙️ Stay Tuned!',
      'desc':
          'More advanced AI-powered features are coming soon. Stay connected!'
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
              // ==== SECTION TITLE ====
              const Text(
                "Your Smart Agriculture Assistant",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _brandGreen,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),

              // ==== FEATURE CARDS ====
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _futureUpdates.length,
                itemBuilder: (context, i) {
                  final item = _futureUpdates[i];
                  return _ServiceCard(
                    title: item['title']!,
                    description: item['desc']!,
                    delayMs: 150 * i,
                  );
                },
              ),

              const SizedBox(height: 25),
              const Text(
                "Growing smarter every season 🌾",
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

/// ===================================================================
/// Reusable Service Card with tactile animation
/// ===================================================================
class _ServiceCard extends StatefulWidget {
  final String title;
  final String description;
  final int delayMs;

  const _ServiceCard({
    required this.title,
    required this.description,
    required this.delayMs,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 6,
          shadowColor: _brandGreen.withValues(alpha: 0.25),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
                  widget.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: _brandGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(delay: widget.delayMs.ms).fadeIn(duration: 450.ms).slideY(begin: 0.25, end: 0);
  }
}
