// ==========================================================
// LLMPage v8.2 — Updated for FastAPI backend
// ==========================================================
// • Displays last captured image from DetectCameraPage
// • On entry: sends that image to /detect_base64 to get CNN + Gemini advice
// • Displays auto diagnosis + confidence + recommendation
// • Shows only real camera image (no enhanced/LLM image)
// • Correct chat bubbles + Arabic support
// • Text bar always above Android/iPhone system buttons (SafeArea)
// • Swipe-to-reply, delete, copy
// • Persistent chat history
// • Gemini safe-clean
// • User questions are sent to Gemini with latest diagnosis context
// ==========================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud_service.dart';

// ==========================================================
// Helpers
// ==========================================================
bool isArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

String cleanLLMText(String text) {
  var t = text.trim();
  if (t.startsWith("<html") || t.contains("<!DOCTYPE")) {
    return "⚠️ الخادم غير مستقر مؤقتًا. حاول مرة أخرى.";
  }
  // Remove bold markers and convert list markers to bullet points
  t = t.replaceAll("**", "");
  t = t.replaceAllMapped(RegExp(r'^[\*\-]\s+', multiLine: true), (m) => "• ");
  t = t.replaceAll("\n* ", "\n• ");
  t = t.replaceAll("\n- ", "\n• ");
  // Convert numbered lists to bullet points while preserving numbers
  t = t.replaceAllMapped(RegExp(r'^\s*(\d+)[\)\.]\s+', multiLine: true), (m) => "${m[1]}) ");
  t = t.replaceAll(RegExp(r'\n{3,}'), "\n\n");
  return t;
}

// ==========================================================
// Chat Message Model
// ==========================================================
class ChatMessage {
  final bool fromUser;
  final String text;
  final String? imageB64;
  final String? replyTo;
  final DateTime timestamp;
  ChatMessage({
    required this.fromUser,
    required this.text,
    this.imageB64,
    this.replyTo,
    required this.timestamp,
  });
  Map<String, dynamic> toJson() => {
        "fromUser": fromUser,
        "text": text,
        "imageB64": imageB64,
        "replyTo": replyTo,
        "timestamp": timestamp.toIso8601String(),
      };
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        fromUser: j["fromUser"],
        text: j["text"] ?? "",
        imageB64: j["imageB64"],
        replyTo: j["replyTo"],
        timestamp: DateTime.parse(j["timestamp"]),
      );
}

// ==========================================================
// Storage
// ==========================================================
class ChatStorage {
  static const key = "cropeye_chat_history";
  static Future<void> save(List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final list = msgs.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(key, list);
  }
  static Future<List<ChatMessage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key);
    if (list == null) return [];
    return list.map((s) => ChatMessage.fromJson(jsonDecode(s))).toList();
  }
}

// ==========================================================
// Main Chat Page
// ==========================================================
class LLMPage extends StatefulWidget {
  const LLMPage({super.key});
  @override
  State<LLMPage> createState() => _LLMPageState();
}

class _LLMPageState extends State<LLMPage> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  List<ChatMessage> _msgs = [];
  bool _loading = false;
  bool _aiTyping = false;
  String? replyTarget;
  bool _lastUserArabic = true;
  late AnimationController _dots;
  @override
  void initState() {
    super.initState();
    initializeDateFormatting("ar", null);
    initializeDateFormatting("en", null);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    _initChat();
  }
  @override
  void dispose() {
    _dots.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }
  // ----------------------------------------------------------
  // Initialize Chat + Auto Insert Camera Diagnosis
  // ----------------------------------------------------------
  Future<void> _initChat() async {
    _msgs = await ChatStorage.load();
    final cloud = context.read<CloudService>();
    // AUTO-ADD CAMERA IMAGE + RUN /detect_base64 ON ENTRY
    if (cloud.lastCapturePath != null) {
      final file = File(cloud.lastCapturePath!);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        // 1) Insert image bubble (user)
        setState(() {
          _msgs.add(ChatMessage(fromUser: true, text: "", imageB64: b64, timestamp: DateTime.now()));
          _loading = true;
          _aiTyping = true;
        });
        await ChatStorage.save(_msgs);
        _scrollToEnd();
        // 2) Send to backend for CNN + Gemini advice
        try {
          final serverText = await cloud.sendImageForDetection(b64);
          // Force update of cloud.latest values before reading them
          cleanLLMText(serverText);
          final label = cloud.lastCnnLabel ?? "—";
          final confStr = cloud.lastCnnConf != null
              ? "${(cloud.lastCnnConf! * 100).toStringAsFixed(1)}%"
              : "—";
          final advice = cloud.lastGeminiAdvice ??
              "لم يتمكن المساعد من توليد توصية مفصلة. حاول مرة أخرى أو أرسل صورة أوضح.";
          // If no leaf was detected, show a friendly message
          final bool noLeaf = cloud.lastNoLeafDetected == true ||
              label.trim().toLowerCase() == "unknown";
          String diag;
          if (noLeaf) {
            diag = cleanLLMText(
                "🚫 No leaf detected in the image. Please capture a clear leaf image and try again.");
          } else {
            diag = cleanLLMText("""
📸 **تم التقاط صورة جديدة وتحليلها**

🔍 **النتيجة:** $label  
📈 **الثقة:** $confStr  

💡 **التوصية:**  
$advice
""");
          }
          setState(() {
            _msgs.add(ChatMessage(
                fromUser: false,
                text: diag,
                imageB64: null,
                timestamp: DateTime.now()));
            _loading = false;
            _aiTyping = false;
          });
          await ChatStorage.save(_msgs);
          _scrollToEnd();
        } catch (e) {
          setState(() {
            _msgs.add(ChatMessage(fromUser: false, text: "⚠️ فشل تحليل الصورة: $e", timestamp: DateTime.now()));
            _loading = false;
            _aiTyping = false;
          });
          await ChatStorage.save(_msgs);
        }
        // Consume the capture path so it won't auto-run again
        cloud.lastCapturePath = null;
      }
    }
    // If chat still empty → show welcome summary based on latest diagnosis
    if (_msgs.isEmpty) {
      final label = cloud.lastCnnLabel ?? "—";
      final conf = cloud.lastCnnConf != null
          ? "${(cloud.lastCnnConf! * 100).toStringAsFixed(1)}%"
          : "—";
      final advice = cloud.lastGeminiAdvice ??
          "لم يتم تحليل أي صورة بعد. قم بالتقاط صورة أولاً.";
      final txt = cleanLLMText("""
👋 أهلاً بك في CropEye Assistant

🔍 التشخيص الأخير: $label  
📈 الثقة: $conf  

💡 التوصية:  
$advice
""");
      _msgs.add(ChatMessage(fromUser: false, text: txt, timestamp: DateTime.now()));
      await ChatStorage.save(_msgs);
    }
    if (mounted) {
      setState(() {});
      _scrollToEnd();
    }
  }
  // ----------------------------------------------------------
  // Clear Chat
  // ----------------------------------------------------------
  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("مسح المحادثة"),
        content: const Text("هل تريد مسح جميع الرسائل؟"),
        actions: [
          TextButton(child: const Text("إلغاء"), onPressed: () => Navigator.pop(ctx, false)),
          TextButton(child: const Text("مسح", style: TextStyle(color: Colors.red)), onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _msgs.clear();
      replyTarget = null;
    });
    ChatStorage.save([]);
  }
  // ----------------------------------------------------------
  // Send Text (with diagnosis context)
  // ----------------------------------------------------------
  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _lastUserArabic = isArabic(text);
    final user = ChatMessage(
      fromUser: true,
      text: text,
      replyTo: replyTarget,
      timestamp: DateTime.now(),
    );
    setState(() {
      _msgs.add(user);
      replyTarget = null;
      _controller.clear();
      _loading = true;
      _aiTyping = true;
    });
    ChatStorage.save(_msgs);
    _scrollToEnd();
    final cloud = context.read<CloudService>();
    // Build diagnosis context so Gemini "sees" the last image result
    String contextHint = "";
    if (cloud.lastCnnLabel != null || cloud.lastGeminiAdvice != null) {
      final label = cloud.lastCnnLabel ?? "غير معروف";
      final conf = cloud.lastCnnConf != null
          ? "${(cloud.lastCnnConf! * 100).toStringAsFixed(1)}%"
          : "غير متوفر";
      final advice = cloud.lastGeminiAdvice ?? "";
      contextHint = """
[Context: Latest tomato leaf analysis]
- Diagnosis: $label
- Confidence: $conf
- Recommendation: $advice

Use this context when answering the user's question. If the user asks what to do, explain clearly based on this diagnosis.
""";
    }
    final prompt = contextHint.isEmpty ? text : "$contextHint\n\nUser question:\n$text";
    try {
      final raw = await cloud.chatWithGemini(prompt);
      final reply = cleanLLMText(raw);
      final ai = ChatMessage(fromUser: false, text: reply, timestamp: DateTime.now());
      setState(() {
        _msgs.add(ai);
        _loading = false;
        _aiTyping = false;
      });
      ChatStorage.save(_msgs);
      _scrollToEnd();
    } catch (e) {
      setState(() {
        _msgs.add(ChatMessage(fromUser: false, text: "⚠️ خطأ: $e", timestamp: DateTime.now()));
        _loading = false;
        _aiTyping = false;
      });
      ChatStorage.save(_msgs);
    }
  }
  // ----------------------------------------------------------
  // Scroll Bottom
  // ----------------------------------------------------------
  void _scrollToEnd() async {
    await Future.delayed(const Duration(milliseconds: 180));
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  // ----------------------------------------------------------
  // Timestamp
  // ----------------------------------------------------------
  String fmt(DateTime t, String text) {
    return DateFormat("hh:mm a", isArabic(text) ? "ar" : "en").format(t);
  }
  // ----------------------------------------------------------
  // UI Build
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FFF0),
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text("CropEye Assistant", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _msgs.isEmpty || _loading ? null : _clearChat),
          IconButton(icon: const Icon(Icons.image), onPressed: _loading ? null : _pickImage),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: _msgs.length + (_aiTyping ? 1 : 0),
                itemBuilder: (c, i) {
                  if (_aiTyping && i == _msgs.length) {
                    return _typingBubble();
                  }
                  return _chatBubble(_msgs[i]);
                },
              ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }
  // ----------------------------------------------------------
  // Chat Bubble
  // ----------------------------------------------------------
  Widget _chatBubble(ChatMessage m) {
    final isUser = m.fromUser;
    final rtl = isArabic(m.text.isEmpty && m.imageB64 != null ? "صورة" : m.text);
    final txt = m.text;
    return Slidable(
      key: UniqueKey(),
      endActionPane: isUser
          ? ActionPane(motion: const DrawerMotion(), children: [SlidableAction(icon: Icons.reply, backgroundColor: Colors.green.shade200, onPressed: (_) => _setReplyTo(m))])
          : null,
      startActionPane: !isUser
          ? ActionPane(motion: const DrawerMotion(), children: [SlidableAction(icon: Icons.reply, backgroundColor: Colors.green.shade200, onPressed: (_) => _setReplyTo(m))])
          : null,
      child: GestureDetector(
        onLongPress: () => _showMessageMenu(m),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              CircleAvatar(radius: 18, backgroundColor: Colors.green[700], child: const Icon(Icons.eco, color: Colors.white)),
            if (!isUser) const SizedBox(width: 6),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isUser ? Colors.green[700] : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: isUser ? null : Border.all(color: Colors.green.withOpacity(0.25)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(1, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (m.replyTo != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          "↩ ${m.replyTo}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isUser ? Colors.white70 : Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (m.imageB64 != null && m.imageB64!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            base64Decode(m.imageB64!),
                            height: 240,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    if (txt.isNotEmpty)
                      Directionality(
                        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                        child: Text(
                          txt,
                          style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.5),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
                      child: Text(
                        fmt(m.timestamp, txt),
                        style: TextStyle(fontSize: 11, color: isUser ? Colors.white70 : Colors.black45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isUser) const SizedBox(width: 6),
            if (isUser)
              const CircleAvatar(radius: 18, backgroundColor: Colors.green, child: Icon(Icons.person, color: Colors.white)),
          ],
        ),
      ),
    );
  }
  // ----------------------------------------------------------
  // Typing Bubble
  // ----------------------------------------------------------
  Widget _typingBubble() {
    return Row(
      children: [
        CircleAvatar(radius: 18, backgroundColor: Colors.green[700], child: const Icon(Icons.eco, color: Colors.white)),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _dots,
          builder: (_, __) {
            final dots = "." * (1 + (_dots.value * 3).floor());
            final label = _lastUserArabic ? "يكتب" : "typing";
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.25)),
              ),
              child: Text(
                "$label$dots",
                style: const TextStyle(fontSize: 14),
              ),
            );
          },
        ),
      ],
    );
  }
  // ----------------------------------------------------------
  // Reply function
  // ----------------------------------------------------------
  void _setReplyTo(ChatMessage m) {
    setState(() {
      replyTarget = m.text.isEmpty ? "Image" : m.text;
    });
  }
  // ----------------------------------------------------------
  // Menu for message
  // ----------------------------------------------------------
  void _showMessageMenu(ChatMessage m) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("Copy"),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.text));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text("Delete"),
              onTap: () {
                setState(() => _msgs.remove(m));
                ChatStorage.save(_msgs);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
  // ----------------------------------------------------------
  // Input bar FIXED ABOVE SYSTEM BUTTONS
  // ----------------------------------------------------------
  Widget _inputBar() {
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
        child: Column(
          children: [
            if (replyTarget != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        replyTarget!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.green),
                      ),
                    ),
                    GestureDetector(onTap: () => setState(() => replyTarget = null), child: const Icon(Icons.close, size: 18)),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: "اكتب سؤالك…",
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _loading
                    ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(icon: const Icon(Icons.send_rounded, color: Colors.green, size: 28), onPressed: _sendText),
              ],
            ),
          ],
        ),
      ),
    );
  }
  // ----------------------------------------------------------
  // Pick image from gallery
  // ----------------------------------------------------------
  Future<void> _pickImage() async {
    if (_loading) return;
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final b64 = base64Encode(bytes);
    final user = ChatMessage(fromUser: true, text: "", imageB64: b64, timestamp: DateTime.now());
    setState(() {
      _msgs.add(user);
      _loading = true;
      _aiTyping = true;
    });
    ChatStorage.save(_msgs);
    _scrollToEnd();
    final cloud = context.read<CloudService>();
    try {
      final serverTxt = await cloud.sendImageForDetection(b64);
      // Force update of cloud.latest values before reading them
      cleanLLMText(serverTxt);
      final label = cloud.lastCnnLabel ?? "Unknown";
      final confStr = cloud.lastCnnConf != null
          ? "${(cloud.lastCnnConf! * 100).toStringAsFixed(1)}%"
          : "—";
      final advice = cloud.lastGeminiAdvice ?? "—";
      // If no leaf is detected, inform the user instead of showing generic diagnosis
      final bool noLeaf = cloud.lastNoLeafDetected == true ||
          label.trim().toLowerCase() == "unknown";
      String diagText;
      if (noLeaf) {
        diagText = cleanLLMText(
            "🚫 No leaf detected in the image. Please select or capture a clear leaf image and try again.");
      } else {
        diagText = cleanLLMText("""
📸 تم تحليل الصورة

📌 التشخيص: $label  
📈 الثقة: $confStr  

💡 التوصية:
$advice
""");
      }
      final ai = ChatMessage(
        fromUser: false,
        text: diagText,
        imageB64: null,
        timestamp: DateTime.now(),
      );
      setState(() {
        _msgs.add(ai);
        _loading = false;
        _aiTyping = false;
      });
      ChatStorage.save(_msgs);
      _scrollToEnd();
    } catch (e) {
      setState(() {
        _msgs.add(ChatMessage(fromUser: false, text: "⚠️ فشل تحليل الصورة: $e", timestamp: DateTime.now()));
        _loading = false;
        _aiTyping = false;
      });
      ChatStorage.save(_msgs);
    }
  }
}