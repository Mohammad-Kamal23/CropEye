import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);

/// ===============================================================
/// PortfolioSection — Team Showcase + Project Story
/// ===============================================================
class PortfolioSection extends StatefulWidget {
  const PortfolioSection({super.key});

  @override
  State<PortfolioSection> createState() => _PortfolioSectionState();
}

class _PortfolioSectionState extends State<PortfolioSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  final List<Map<String, String>> _teamMembers = const [
    {
      'name': 'Mohammad Kamal Abdelaziz',
      'role': 'AI & Data Science Engineer',
      'email': 'moh203.kamal@gmail.com',
      'desc':
          'Specializes in AI model design, mobile deployment, and Green AI optimization.'
    },
    {
      'name': 'Adam Freihat',
      'role': 'Data Science Researcher',
      'email': '—',
      'desc':
          'Focuses on dataset engineering and real-time data pipelines for precision agriculture.'
    },
    {
      'name': 'Mohammad Nasrallah',
      'role': 'AI Model Developer',
      'email': '—',
      'desc':
          'Works on model refinement, augmentation strategy, and YOLO segmentation.'
    },
    {
      'name': 'Mohammad Abu Foul',
      'role': 'Software Engineer',
      'email': '—',
      'desc':
          'Develops backend logic, integrates the pipeline with user-facing mobile systems.'
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
                "Meet the Minds Behind CropEye",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _brandGreen,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 22),

              // ==== TEAM MEMBERS ====
              ListView.builder(
                primary: false,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _teamMembers.length,
                itemBuilder: (context, i) {
                  final member = _teamMembers[i];
                  return _TeamCard(
                    name: member['name']!,
                    role: member['role']!,
                    email: member['email']!,
                    desc: member['desc']!,
                    delayMs: 180 * i,
                  );
                },
              ),

              const SizedBox(height: 30),

              // ==== CROPEYE STORY ====
              const Text(
                "Our Journey",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _brandGreen,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "CropEye was founded with the goal of uniting AI and agriculture — empowering farmers to fight crop diseases efficiently. Our journey began at the University of Jordan, where passion for sustainability and innovation came together.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 26),

              // ==== TAGLINE ====
              const Text(
                "Innovation through collaboration 🌾",
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

/// ===============================================================
/// TEAM CARD — clean design with soft gradient + unified animation
/// ===============================================================
class _TeamCard extends StatelessWidget {
  final String name;
  final String role;
  final String email;
  final String desc;
  final int delayMs;

  const _TeamCard({
    required this.name,
    required this.role,
    required this.email,
    required this.desc,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: _brandGreen.withValues(alpha: 0.25),
      child: Container(
        padding: const EdgeInsets.all(18),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _brandGreen.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.person, color: _brandGreen, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      color: _brandGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  if (email != '—') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.email,
                            size: 16, color: _brandGreen),
                        const SizedBox(width: 6),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ]
                ],
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
