// ==========================================================
// CropEye — HomePage (Universal Wheel + Cloud Backend Ready)
//  - Uses CloudService for YOLO, CNN, and Gemini
//  - Includes LLMPage navigation
// ==========================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

// ===== Cloud Backend Service =====
import 'cloud_service.dart';
import 'detect_camera_page.dart';
import 'llm_page.dart';

// ===== Imports for actual section pages =====
import 'service_page.dart';
import 'about_page.dart';
import 'portfolio_page.dart';
import 'contact_page.dart';
import 'blog_page.dart';
import 'settings_page.dart';
import 'app_drawer.dart';

// ===== Theme =====
const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);
const _pageBgBottom = Colors.white;

/// App sections in wheel order
const _sections = <String>[
  'HOME',
  'SERVICE',
  'ABOUT',
  'PORTFOLIO',
  'CONTACT',
  'BLOG',
  'SETTINGS',
];

/// Hero image per section
const _heroImageFor = <String, String>{
  'HOME': 'assets/homepage.jpg',
  'SERVICE': 'assets/service.jpg',
  'ABOUT': 'assets/about.jpg',
  'PORTFOLIO': 'assets/portfolio.jpg',
  'CONTACT': 'assets/contact.jpg',
  'BLOG': 'assets/blog.jpg',
  'SETTINGS': 'assets/settings.jpg'
};

// ==========================================================
// HOME PAGE (Main shell)
// ==========================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;
  double _wheelPage = 0;
  Timer? _debounce;
  File? _lastPhoto;

  late final AnimationController _enterCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  late final AnimationController _heroZoomCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat(reverse: true);

  late final PageController _wheelCtrl =
      PageController(viewportFraction: 0.28, initialPage: _index);

  final List<String> _steps = const [
    "🌱 Open your camera",
    "🍅 Focus the infected leaf",
    "🤖 View AI results",
  ];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _precacheAllHeroes();
    _wheelCtrl.addListener(() {
      setState(() => _wheelPage = _wheelCtrl.page ?? _wheelPage);
    });
    _cycleSteps();
  }

  Future<void> _precacheAllHeroes() async {
    for (final s in _sections) {
      final path = _heroImageFor[s];
      if (path != null && mounted) {
        await precacheImage(AssetImage(path), context);
      }
    }
  }

  void _cycleSteps() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      setState(() => _currentStep = (_currentStep + 1) % _steps.length);
      return true;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _wheelCtrl.dispose();
    _heroZoomCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ======================================================
  // Camera (HOME only)
  // ======================================================
  Future<void> _openCamera() async {
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission denied')),
      );
      return;
    }

    final cloud = context.read<CloudService>();

    final file = await Navigator.of(context).push<File?>(
      _animatedRoute<File?>(DetectCameraPage(cloud: cloud)),
    );

    if (!mounted) return;
    if (file != null) setState(() => _lastPhoto = file);
  }

  Route<T> _animatedRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, _) {
        final slide = Tween<Offset>(
          begin: const Offset(0.06, 0.06),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: page),
        );
      },
    );
  }

  // ======================================================
  // BUILD
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final activeSection = _sections[_index];
    final heroPath = _heroImageFor[activeSection];

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppSideDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.25,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Menu',
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageBgTop, _pageBgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _HeroPane(
                heroZoomCtrl: _heroZoomCtrl,
                imagePath: heroPath,
                section: activeSection,
              ),
              _WheelBar(
                controller: _wheelCtrl,
                page: _wheelPage,
                activeIndex: _index,
                onChanged: (i) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 200), () {
                    if (!mounted) return;
                    setState(() => _index = i);
                  });
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: FadeTransitionSection(
                    key: ValueKey(activeSection),
                    child: _buildSectionBody(activeSection),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBody(String section) {
    if (section == 'HOME') {
      return _HomeSection(
        key: const ValueKey('HOME'),
        enterCtrl: _enterCtrl,
        steps: _steps,
        stepIndex: _currentStep,
        onOpenCamera: _openCamera,
        lastPhoto: _lastPhoto,
      );
    }

    switch (section) {
      case 'SERVICE':
        return const ServiceSection(key: ValueKey('SERVICE'));
      case 'ABOUT':
        return const AboutSection(key: ValueKey('ABOUT'));
      case 'PORTFOLIO':
        return const PortfolioSection(key: ValueKey('PORTFOLIO'));
      case 'CONTACT':
        return const ContactPage(key: ValueKey('CONTACT'));
      case 'BLOG':
        return const BlogSection(key: ValueKey('BLOG'));
      case 'SETTINGS':
        return const SettingsPage(key: ValueKey('SETTINGS'));
      default:
        return _SimpleSection(key: ValueKey(section), title: section);
    }
  }
}

// ==========================================================
// FadeTransition wrapper
// ==========================================================
class FadeTransitionSection extends StatefulWidget {
  final Widget child;
  const FadeTransitionSection({super.key, required this.child});
  @override
  State<FadeTransitionSection> createState() => _FadeTransitionSectionState();
}

class _FadeTransitionSectionState extends State<FadeTransitionSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..forward();

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _fadeCtrl, child: widget.child);
}

// ==========================================================
// HERO pane
// ==========================================================
class _HeroPane extends StatelessWidget {
  final AnimationController heroZoomCtrl;
  final String? imagePath;
  final String section;
  const _HeroPane({
    required this.heroZoomCtrl,
    required this.imagePath,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    const height = 260.0;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(56),
        bottomRight: Radius.circular(56),
      ),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath != null)
              AnimatedBuilder(
                animation: heroZoomCtrl,
                builder: (context, child) {
                  final scale = 1 + 0.04 * heroZoomCtrl.value;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Image.asset(imagePath!, key: ValueKey(imagePath), fit: BoxFit.cover),
              ),
            if (imagePath == null)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x6628A745),
                    Color(0x44F6E27A),
                    Color(0x66E95454),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  section,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// WheelBar
// ==========================================================
class _WheelBar extends StatelessWidget {
  final PageController controller;
  final double page;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const _WheelBar({
    required this.controller,
    required this.page,
    required this.activeIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.22),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: PageView.builder(
              controller: controller,
              itemCount: _sections.length,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              onPageChanged: onChanged,
              itemBuilder: (context, i) {
                final dist = (page - i).abs().clamp(0.0, 1.0);
                final scale = 1.0 - (dist * 0.25);
                final opacity = 1.0 - (dist * 0.45);
                final isActive = i == activeIndex;

                return Center(
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: isActive ? const Color(0x6628A745) : Colors.white.withOpacity(0.08),
                        ),
                        child: Text(
                          _sections[i],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// HOME body
// ==========================================================
class _HomeSection extends StatelessWidget {
  final AnimationController enterCtrl;
  final List<String> steps;
  final int stepIndex;
  final VoidCallback onOpenCamera;
  final File? lastPhoto;

  const _HomeSection({
    super.key,
    required this.enterCtrl,
    required this.steps,
    required this.stepIndex,
    required this.onOpenCamera,
    required this.lastPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: _brandGreen,
                child: Icon(Icons.psychology, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 650),
                  child: Text(
                    steps[stepIndex],
                    key: ValueKey(stepIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FadeTransition(
            opacity: enterCtrl,
            child: Column(
              children: const [
                Text(
                  "SERVICE",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _brandGreen,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Your Smart Agriculture Assistant",
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionCircle(
                icon: Icons.camera_alt,
                label: "Camera",
                onTap: onOpenCamera,
              ).animate().fadeIn(duration: 380.ms).scale(begin: const Offset(.9, .9)),
              _ActionCircle(
                icon: Icons.smart_toy,
                label: "LLM",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LLMPage()),
                ),
              ).animate(delay: 80.ms).fadeIn(duration: 380.ms).scale(begin: const Offset(.9, .9)),
            ],
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              "“The discovery of agriculture was the first big step toward a civilized life.”\n– Arthur Keith",
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 15, color: Colors.black87),
            ),
          ),
          if (lastPhoto != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(lastPhoto!, fit: BoxFit.cover),
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================================
// SimpleSection + ActionCircle
// ==========================================================
class _SimpleSection extends StatelessWidget {
  final String title;
  const _SimpleSection({super.key, required this.title});
  @override
  Widget build(BuildContext context) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _brandGreen,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Page content will be wired next. The wheel remains visible and active.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      );
}

class _ActionCircle extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCircle({required this.icon, required this.label, required this.onTap});
  @override
  State<_ActionCircle> createState() => _ActionCircleState();
}

class _ActionCircleState extends State<_ActionCircle> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF2E7D32),
                    Color(0xFFF6E27A),
                    Color(0xFFE95454),
                    Color(0xFF2E7D32),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 16, offset: const Offset(0, 7)),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.88)),
                child: CircleAvatar(
                  radius: _pressed ? 37 : 41,
                  backgroundColor: Colors.white,
                  child: Icon(widget.icon, color: _brandGreen, size: _pressed ? 34 : 40),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
}
