import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _brandGreen = Color(0xFF1B5E20);
//const _pageBgTop = Color(0xFFE3F4E1);

/// ===============================================================
/// BlogSection — Offline Local Version (saves posts on device)
/// ===============================================================
class BlogSection extends StatefulWidget {
  const BlogSection({super.key});

  @override
  State<BlogSection> createState() => _BlogSectionState();
}

class _BlogSectionState extends State<BlogSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  final TextEditingController _postController = TextEditingController();
  List<Map<String, String>> _posts = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('local_posts') ?? [];
    setState(() {
      _posts = stored
          .map((s) => Map<String, String>.from(jsonDecode(s)))
          .toList()
          .reversed
          .toList();
    });
  }

  Future<void> _savePosts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _posts.map((p) => jsonEncode(p)).toList();
    await prefs.setStringList('local_posts', encoded);
  }

  void _addPost() {
    final text = _postController.text.trim();
    if (text.isEmpty) return;

    final post = {
      'author': '🧑‍💻 You',
      'content': text,
      'date': DateTime.now().toLocal().toString().substring(0, 16),
    };

    setState(() {
      _posts.insert(0, post);
    });

    _savePosts();
    _postController.clear();
    FocusScope.of(context).unfocus();
  }

  void _deletePost(int index) {
    setState(() {
      _posts.removeAt(index);
    });
    _savePosts();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _postController.dispose();
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
              // ==== SECTION HEADER ====
              const Text(
                "Community Blog 🌿",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _brandGreen,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 22),

              // ==== POST INPUT FIELD ====
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: _brandGreen,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _postController,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: "Write something inspiring 🌱✨",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: _brandGreen),
                      onPressed: _addPost,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ==== POSTS LIST ====
              if (_posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    "No posts yet — start the conversation 🌿",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ListView.builder(
                  primary: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _posts.length,
                  itemBuilder: (context, i) {
                    final post = _posts[i];
                    return Dismissible(
                      key: ValueKey(post['date']),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _deletePost(i),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: Colors.red.withOpacity(0.7),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: _PostCard(
                        author: post['author']!,
                        content: post['content']!,
                        date: post['date']!,
                        delayMs: i * 120,
                      ),
                    );
                  },
                ),

              const SizedBox(height: 30),

              // ==== FOOTER ====
              const Divider(color: _brandGreen, thickness: 1.2),
              const SizedBox(height: 10),
              const Text(
                "🌾 Join the conversation. Grow with us.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// POST CARD — for displaying user posts elegantly
/// ===============================================================
class _PostCard extends StatelessWidget {
  final String author;
  final String content;
  final String date;
  final int delayMs;

  const _PostCard({
    required this.author,
    required this.content,
    required this.date,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 5,
      shadowColor: _brandGreen.withOpacity(0.25),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          border: Border.all(
            color: _brandGreen.withOpacity(0.25),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _brandGreen,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              content,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              date,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
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
