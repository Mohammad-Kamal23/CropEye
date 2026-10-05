// ==========================================================
// CropEye Cloud Service — v10.7 (PATCHED)
// Bulletproof YOLO + CNN parsing for Flutter LIVE detection
// ==========================================================
//
// KEY POINTS:
// ✔ RAW-only pipeline
// ✔ Perfect YOLO parsing (label, confidence, xyxy, xywh, normalized)
// ✔ Keeps every feature you had (LLM, debug, fullDiagnosis, index DB)
// ✔ Error path for /detect now returns {success:false, error, statusCode}
//   instead of fake detections.
// ==========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// ==========================================================
// Detection Object (YOLO) — 100% FIXED
// ==========================================================
class CloudDetection {
  final String label;
  final double confidence;
  final List<double> box; // always xyxy format

  CloudDetection({
    required this.label,
    required this.confidence,
    required this.box,
  });

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static List<double> _list(dynamic v) {
    if (v is List) return v.map((e) => _d(e)).toList();
    if (v is String && v.startsWith('[')) {
      try {
        final arr = jsonDecode(v);
        if (arr is List) return arr.map((e) => _d(e)).toList();
      } catch (_) {}
    }
    return [];
  }

  factory CloudDetection.fromJson(Map<String, dynamic> j) {
    final String label = j['label']?.toString() ?? 'unknown';
    final double conf = _d(j['confidence']);

    List<double> box = _list(j['box']);

    // If backend returns xywh
    if (box.isEmpty &&
        j.containsKey('x') &&
        j.containsKey('y') &&
        j.containsKey('w') &&
        j.containsKey('h')) {
      final double x = _d(j['x']);
      final double y = _d(j['y']);
      final double w = _d(j['w']);
      final double h = _d(j['h']);
      box = [x, y, x + w, y + h];
    }

    return CloudDetection(label: label, confidence: conf, box: box);
  }
}

// ==========================================================
// CLOUD SERVICE — FULL FILE WITH FIXED YOLO + ERROR LOGIC
// ==========================================================
class CloudService with ChangeNotifier {
  final String apiBaseUrl;

  double defaultConf;
  double defaultIou;

  bool isReady = false;

  // CNN + INDEX state
  String? lastCnnLabel;
  double? lastCnnConf;
  String? lastGeminiAdvice;

  String? lastIndexLabel;
  double? lastIndexConf;
  String? lastFinalSource; // "live_only" or "index"

  bool? lastNoLeafDetected;

  int? sourceW;
  int? sourceH;

  // LLM supports last camera capture
  String? lastCapturePath;

  final List<String> _memory = [];

  /// Backend address, chosen at build time (no code change needed):
  ///   flutter run --dart-define=CROPEYE_API_URL=http://10.0.2.2:8000       (Android emulator)
  ///   flutter run --dart-define=CROPEYE_API_URL=http://192.168.1.5:8000    (phone on the same Wi-Fi as your PC)
  /// Without it the app talks to a backend on this machine (desktop, web, iOS simulator).
  static const String defaultApiUrl =
      String.fromEnvironment('CROPEYE_API_URL', defaultValue: 'http://127.0.0.1:8000');

  CloudService({
    this.apiBaseUrl = defaultApiUrl,
    this.defaultConf = 0.30,
    this.defaultIou = 0.60,
  });

  void setLastCapturePath(String path) {
    lastCapturePath = path;
    notifyListeners();
  }

  // ==========================================================
  // HTML cleaner (Cloud Run 502/503 HTML → safe JSON)
  // ==========================================================
  String _cleanHTML(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('<html') ||
        lower.contains('<!doctype') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable') ||
        lower.contains('internal server error')) {
      return '{"error":"server_unavailable"}';
    }
    return body;
  }

  // ==========================================================
  // Warm initialization
  // ==========================================================
  Future<void> initialize({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final r = await http
            .get(Uri.parse('$apiBaseUrl/ping'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          isReady = true;
          notifyListeners();
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    isReady = false;
    notifyListeners();
  }

  // ==========================================================
  // JPEG compression (same as your original)
  // ==========================================================
  Future<File> _compress(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;

      final jpg = img.encodeJpg(decoded, quality: 85);

      final p = file.path;
      final dot = p.lastIndexOf('.');
      final newPath =
          (dot == -1) ? '${p}_c.jpg' : '${p.substring(0, dot)}_c.jpg';

      final out = File(newPath);
      await out.writeAsBytes(jpg, flush: true);
      return out;
    } catch (_) {
      return file;
    }
  }

  double? _toDoubleOrNull(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ==========================================================
  // /detect — FULL LIVE YOLO + CNN + INDEX
  // ==========================================================
  Future<Map<String, dynamic>> detect(
    File imgFile, {
    double? conf,
    double? iou,
  }) async {
    final c = conf ?? defaultConf;
    final n = iou ?? defaultIou;

    // Pass conf and iou as query parameters
    final uri = Uri.parse('$apiBaseUrl/detect?conf=$c&iou=$n');

    // Extra safety: compress once (same behavior for manual + stream)
    final compressed = await _compress(imgFile);

    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', compressed.path));

    try {
      final stream = await req.send().timeout(const Duration(seconds: 90));
      final res = await http.Response.fromStream(stream);
      final cleaned = _cleanHTML(res.body);

      // ====================================================
      // ERROR PATH — DO NOT FAKE DETECTIONS
      // ====================================================
      if (res.statusCode != 200) {
        dynamic decodedErr;
        try {
          decodedErr = jsonDecode(cleaned);
        } catch (_) {
          decodedErr = cleaned;
        }

        debugPrint("❌ DETECT ERROR ${res.statusCode}");
        debugPrint("❌ MSG: $decodedErr");

        // Return error payload to Flutter so stream code can see it
        if (decodedErr is Map<String, dynamic>) {
          return {
            "success": decodedErr["success"] ?? false,
            "error": decodedErr["error"] ?? "unknown_error",
            "statusCode": res.statusCode,
            "raw": decodedErr,
          };
        } else {
          return {
            "success": false,
            "error": "http_${res.statusCode}",
            "statusCode": res.statusCode,
            "raw": decodedErr,
          };
        }
      }

      // ====================================================
      // SUCCESS PATH — NORMAL PARSING
      // ====================================================
      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['error'] == 'server_unavailable') {
        return {
          "success": false,
          "error": "server_unavailable",
          "statusCode": 503,
        };
      }

      final Map<String, dynamic> m =
          Map<String, dynamic>.from(decoded as Map);

      // Parse source dims
      sourceW = m['source_w'] is num ? (m['source_w'] as num).toInt() : null;
      sourceH = m['source_h'] is num ? (m['source_h'] as num).toInt() : null;

      // ======================================================
      // YOLO PARSING — FIXED
      // ======================================================
      final dynamic detRawDynamic = m['detections'];
      final dynamic stabRawDynamic =
          m['stabilized_detections'] ?? m['stabilizedDetections'];

      final List<CloudDetection> detections = [];
      final List<CloudDetection> stabilized = [];

      if (detRawDynamic is List) {
        for (final e in detRawDynamic) {
          if (e is Map) {
            detections.add(
              CloudDetection.fromJson(Map<String, dynamic>.from(e)),
            );
          }
        }
      }

      if (stabRawDynamic is List) {
        for (final e in stabRawDynamic) {
          if (e is Map) {
            stabilized.add(
              CloudDetection.fromJson(Map<String, dynamic>.from(e)),
            );
          }
        }
      } else {
        stabilized.addAll(detections);
      }

      // ======================================================
      // CNN + INDEX FINAL LABEL MAPPING — FIXED
      // ======================================================
      final dynamic finalLabelRaw =
          m['final_label'] ?? m['cnn_label_smoothed'] ?? m['cnn_label_raw'];

      final dynamic finalConfRaw =
          m['final_confidence'] ?? m['cnn_conf_smoothed'] ?? m['cnn_conf_raw'];

      lastCnnLabel = finalLabelRaw?.toString();
      lastCnnConf = _toDoubleOrNull(finalConfRaw);

      lastIndexLabel = m['index_label']?.toString();
      lastIndexConf = _toDoubleOrNull(m['index_confidence']);
      lastFinalSource = m['final_source']?.toString();

      final bool noLeaf = (m['no_leaf_detected'] ?? false) == true;
      lastNoLeafDetected = noLeaf;

      notifyListeners();

      // FULL return map preserved plus "success" flag
      return {
        "success": true,
        "detections": detections,
        "stabilizedDetections": stabilized,
        "sourceW": sourceW,
        "sourceH": sourceH,

        "cnnLabel": lastCnnLabel,
        "cnnConf": lastCnnConf,
        "finalLabel": lastCnnLabel,
        "finalConf": lastCnnConf,

        "indexLabel": lastIndexLabel,
        "indexConf": lastIndexConf,
        "finalSource": lastFinalSource,

        "mergedBox": (m['merged_box'] is List) ? m['merged_box'] : null,
        "mergedBoxNorm":
            (m['merged_box_norm'] is List) ? m['merged_box_norm'] : null,

        "autoCaptureSuggested": m['auto_capture_suggested'] ?? false,
        "suggestedDelayMs": m['suggested_delay_ms'] ?? 2500,
        "totalMs": m['total_time_ms'] ?? 0.0,

        "noLeafDetected": noLeaf,
      };
    } catch (e, st) {
      debugPrint("❌ detect exception: $e\n$st");
      return {
        "success": false,
        "error": "exception",
        "exception": e.toString(),
      };
    }
  }

  // ==========================================================
  // /detect_base64 — LLM Page uses this
  // ==========================================================
  Future<String> sendImageForDetection(String b64) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/detect_base64');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_b64': b64}),
          )
          .timeout(const Duration(seconds: 60));

      final cleaned = _cleanHTML(res.body);
      if (res.statusCode != 200) {
        dynamic decodedErr;
        try {
          decodedErr = jsonDecode(cleaned);
        } catch (_) {
          decodedErr = cleaned;
        }
        return '⚠️ Detection failed (${res.statusCode}): $decodedErr';
      }

      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['error'] == 'server_unavailable') {
        return '⚠️ Server temporarily unavailable.';
      }

      final Map<String, dynamic> m =
          Map<String, dynamic>.from(decoded as Map);

      final dynamic finalLabelRaw =
          m['final_label'] ?? m['cnn_label_smoothed'] ?? m['cnn_label_raw'];

      final dynamic finalConfRaw =
          m['final_confidence'] ?? m['cnn_conf_smoothed'] ?? m['cnn_conf_raw'];

      lastCnnLabel = finalLabelRaw?.toString() ?? 'Unknown';
      lastCnnConf = _toDoubleOrNull(finalConfRaw);

      lastIndexLabel = m['index_label']?.toString();
      lastIndexConf = _toDoubleOrNull(m['index_confidence']);
      lastFinalSource = m['final_source']?.toString();

      lastGeminiAdvice = m['gemini_advice']?.toString() ?? '—';

      final bool noLeaf = (m['no_leaf_detected'] ?? false) == true;
      lastNoLeafDetected = noLeaf;

      notifyListeners();

      final confPercent = ((lastCnnConf ?? 0.0) * 100).toStringAsFixed(1);

      String sourceTag = '';
      if (lastFinalSource == 'index') {
        sourceTag = ' (refined using database matches)';
      }

      return '''
📸 Image Analyzed

Diagnosis: $lastCnnLabel$sourceTag
Confidence: $confPercent%

Recommendation:
$lastGeminiAdvice
''';
    } catch (e) {
      return '❌ Error: $e';
    }
  }

  // ==========================================================
  // /chat — Gemini with memory
  // ==========================================================
  bool _isArabic(String s) => RegExp(r'[\u0621-\u064A]').hasMatch(s);

  Future<String> chatWithGemini(String message) async {
    final msg = message.trim();
    if (msg.isEmpty) return 'Please type something.';
    final lang = _isArabic(msg) ? 'ar' : 'en';

    _memory.add('User: $msg');
    while (_memory.length > 12) _memory.removeAt(0);

    final body = jsonEncode({
      'message': msg,
      'context': _memory.join('\n'),
      'lang': lang,
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/chat');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 45));

      final cleaned = _cleanHTML(res.body);
      if (res.statusCode >= 500) {
        return '⚠️ Gemini temporarily unavailable.';
      }

      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['error'] == 'server_unavailable') {
        return '⚠️ Please try again in a moment.';
      }

      final reply = decoded['reply']?.toString() ?? '—';

      _memory.add('AI: $reply');
      while (_memory.length > 12) _memory.removeAt(0);

      lastGeminiAdvice = reply;
      notifyListeners();
      return reply;
    } catch (e) {
      return '❌ Chat error: $e';
    }
  }

  // ==========================================================
  // /debug
  // ==========================================================
  Future<Map<String, dynamic>> debug() async {
    try {
      final r = await http
          .get(Uri.parse('$apiBaseUrl/debug'))
          .timeout(const Duration(seconds: 10));

      final cleaned = _cleanHTML(r.body);
      if (r.statusCode != 200) return {};

      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['error'] == 'server_unavailable') {
        return {};
      }

      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return {};
    }
  }

  // ==========================================================
  // /debug/full_diagnosis
  // ==========================================================
  Future<Map<String, dynamic>> fullDiagnosis() async {
    try {
      final r = await http
          .get(Uri.parse('$apiBaseUrl/debug/full_diagnosis'))
          .timeout(const Duration(seconds: 20));

      final cleaned = _cleanHTML(r.body);
      if (r.statusCode != 200) return {};

      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['error'] == 'server_unavailable') {
        return {};
      }

      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return {};
    }
  }

  // ==========================================================
  // GETTERS
  // ==========================================================
  bool get isConnected => isReady;
  bool get hasDiagnosis => lastCnnLabel != null;
}
