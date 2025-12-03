// lib/pages/detect_camera_page.dart
// ==========================================================
// CropEye — Cloud Live Detection Page (IMAGE STREAM version)
// ==========================================================
// • YOLO + CNN live overlay with central guidance box
// • Uses Camera ImageStream (no polling takePicture loop)
// • Compatible with updated backend (FastAPI v9.x+)
// • Parses snake_case and camelCase keys for detection/stabilization
// • Handles no_leaf_detected flag to give user feedback
// • UI overlay encourages user to center the whole leaf
// • Auto-capture stability gate (3 stable frames)
// • Manual capture with feedback
// • Torch toggle
// • FPS + inference time
// • Robust bounding box handling for xyxy and xywh formats
// • Deep debug logs for stream + backend + parsing
// ==========================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../cloud_service.dart';
import '../llm_page.dart';

// ==========================================================
// Isolate compressor
// ==========================================================
Map<String, dynamic> _compressImageIsolate(Uint8List bytes) {
  try {
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return {
        'bytes': bytes,
        'width': 0,
        'height': 0,
      };
    }

    decoded = img.bakeOrientation(decoded);
    const int maxSide = 1280; // Better for YOLO
    img.Image working = decoded;

    if (decoded.width > decoded.height && decoded.width > maxSide) {
      working = img.copyResize(decoded, width: maxSide);
    } else if (decoded.height >= decoded.width && decoded.height > maxSide) {
      working = img.copyResize(decoded, height: maxSide);
    }

    final outBytes = img.encodeJpg(working, quality: 60);
    return {
      'bytes': outBytes,
      'width': working.width,
      'height': working.height,
    };
  } catch (_) {
    return {
      'bytes': bytes,
      'width': 0,
      'height': 0,
    };
  }
}

// ==========================================================
// CameraImage (YUV420) → JPEG bytes
// ==========================================================
Uint8List _cameraImageToJpegBytes(CameraImage image) {
  final int width = image.width;
  final int height = image.height;

  final Plane planeY = image.planes[0];
  final Plane planeU = image.planes[1];
  final Plane planeV = image.planes[2];

  final int strideY = planeY.bytesPerRow;
  final int strideU = planeU.bytesPerRow;
  final int strideV = planeV.bytesPerRow;
  final int pixelStrideU = planeU.bytesPerPixel ?? 1;
  final int pixelStrideV = planeV.bytesPerPixel ?? 1;

  final img.Image rgbImage = img.Image(width: width, height: height);

  final Uint8List bytesY = planeY.bytes;
  final Uint8List bytesU = planeU.bytes;
  final Uint8List bytesV = planeV.bytes;

  for (int y = 0; y < height; y++) {
    final int uvRow = (y ~/ 2);
    for (int x = 0; x < width; x++) {
      final int ypIndex = y * strideY + x;
      final int uvCol = (x ~/ 2);

      final int uvIndexU = uvRow * strideU + uvCol * pixelStrideU;
      final int uvIndexV = uvRow * strideV + uvCol * pixelStrideV;

      final int Y = bytesY[ypIndex];
      final int U = bytesU[uvIndexU];
      final int V = bytesV[uvIndexV];

      final double yVal = (Y - 16).toDouble();
      final double uVal = (U - 128).toDouble();
      final double vVal = (V - 128).toDouble();

      double r = 1.164 * yVal + 1.596 * vVal;
      double g = 1.164 * yVal - 0.392 * uVal - 0.813 * vVal;
      double b = 1.164 * yVal + 2.017 * uVal;

      final int ir = r.clamp(0, 255).toInt();
      final int ig = g.clamp(0, 255).toInt();
      final int ib = b.clamp(0, 255).toInt();

      rgbImage.setPixelRgb(x, y, ir, ig, ib);
    }
  }

  return Uint8List.fromList(img.encodeJpg(rgbImage, quality: 90));
}

// ==========================================================
// Live camera detection page
// ==========================================================
class DetectCameraPage extends StatefulWidget {
  final CloudService cloud;
  const DetectCameraPage({super.key, required this.cloud});

  @override
  State<DetectCameraPage> createState() => _DetectCameraPageState();
}

class _DetectCameraPageState extends State<DetectCameraPage> {
  // Local confidence threshold for "stable" leaf
  static const double _confThreshold = 0.50;

  // Central guidance overlay size
  double _overlayRatio = 0.85;

  CameraController? _camera;
  bool _busy = false;
  bool _navigating = false;

  bool _autoDetectEnabled = true;
  bool _torchOn = false;

  List<CloudDetection> _detections = const [];
  List<CloudDetection> _stabilizedDetections = const [];

  DateTime? _armedAt;
  bool _capturePending = false;
  int _stableFrames = 0;

  double? _lastInferenceMs;
  String? _lastLabel; // raw CNN
  double? _lastConf; // raw CNN

  // FastAPI v9.x final + index outputs
  String? _finalLabel;
  double? _finalConf;
  String? _finalSource; // "live_only" | "index"
  String? _indexLabel;
  double? _indexConf;

  List<double>? _mergedBox;
  List<double>? _mergedBoxNorm;

  double? _fps;
  DateTime? _lastFrameTime;

  Size _sourceSize = const Size(640, 640);

  Duration _serverSuggestedDelay = const Duration(milliseconds: 2500);
  bool _serverAutoCapture = false;

  double _detectConf;
  double _detectIou;

  bool? _noLeafDetected;

  File? _lastFrameFile;

  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  int _frameId = 0;

  _DetectCameraPageState()
      : _detectConf = 0.30,
        _detectIou = 0.60;

  @override
  void initState() {
    super.initState();
    _detectConf = widget.cloud.defaultConf;
    _detectIou = widget.cloud.defaultIou;
    _initCamera();
  }

  @override
  void dispose() {
    try {
      _camera?.dispose();
    } catch (_) {}
    _camera = null;
    super.dispose();
  }

  // ----------------------------------------------------------
  // Camera Init (ImageStream)
  // ----------------------------------------------------------
  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      _camera = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _camera!.initialize();
      await _camera!.setFlashMode(FlashMode.off);

      debugPrint(
          "📷 Camera initialized: ${_camera!.description.name} (${_camera!.value.previewSize})");

      await _camera!.startImageStream(_onStreamImage);

      if (!mounted) return;

      setState(() {});
    } catch (e, st) {
      debugPrint("❌ Camera init failed: $e\n$st");
    }
  }

  // ----------------------------------------------------------
  // Torch Toggle
  // ----------------------------------------------------------
  Future<void> _toggleTorch() async {
    if (_camera == null) return;
    try {
      _torchOn = !_torchOn;
      await _camera!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  // ----------------------------------------------------------
  // EXIF-bake + optional downscale (for manual capture only)
  // ----------------------------------------------------------
  Future<File> _compressFrame(File orig) async {
    try {
      final Uint8List bytes = await orig.readAsBytes();
      final Map<String, dynamic> data =
          await compute(_compressImageIsolate, bytes);
      final List<int> outBytes = List<int>.from(data['bytes'] as List);
      final int width = data['width'] as int? ?? 0;
      final int height = data['height'] as int? ?? 0;
      if (width > 0 && height > 0) {
        _sourceSize = Size(width.toDouble(), height.toDouble());
      }
      final dir = await getTemporaryDirectory();
      final outPath =
          "${dir.path}/upl_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final outFile = File(outPath);
      await outFile.writeAsBytes(outBytes, flush: true);
      return outFile;
    } catch (_) {
      return orig;
    }
  }

  // ----------------------------------------------------------
  // Capture feedback
  // ----------------------------------------------------------
  Future<void> _captureFeedback() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  // ----------------------------------------------------------
  // STREAM HANDLER — LIVE YOLO + CNN (v10.7 — FIXED + DEEP DEBUG)
  // ----------------------------------------------------------
  void _onStreamImage(CameraImage image) async {
    if (!_autoDetectEnabled) return;
    if (_camera == null || _busy || _navigating) return;

    // Throttle frames (avoid DDOSing backend)
    final nowGlobal = DateTime.now();
    if (nowGlobal.difference(_lastSent).inMilliseconds < 220) return;
    _lastSent = nowGlobal;

    _busy = true;
    final int myFrame = ++_frameId;
    final DateTime start = DateTime.now();

    try {
      // =======================================================
      // DEBUG 1 — METADATA
      // =======================================================
      debugPrint(
        "----------------------------------------------\n"
        "🎥 FRAME $myFrame RECEIVED\n"
        "format=${image.format.group}, planes=${image.planes.length}, "
        "res=${image.width}x${image.height}, time=${DateTime.now()}\n"
        "----------------------------------------------",
      );

      // =======================================================
      // Convert YUV → JPEG
      // =======================================================
      final Uint8List jpegBytes = _cameraImageToJpegBytes(image);
      debugPrint("🟩 [$myFrame] JPEG created: ${jpegBytes.length} bytes");

      if (jpegBytes.length < 600) {
        debugPrint("❌ [$myFrame] JPEG too small — SKIPPING (corrupt)");
        return;
      }

      // =======================================================
      // Isolate compression
      // =======================================================
      final Map<String, dynamic> data =
          await compute(_compressImageIsolate, jpegBytes);
      final List<int> outBytes = List<int>.from(data['bytes'] as List);

      debugPrint("🟦 [$myFrame] Compressed bytes = ${outBytes.length}");

      if (outBytes.length < 600) {
        debugPrint("❌ [$myFrame] Compressed result too small — SKIP");
        return;
      }

      final int width = (data['width'] as num?)?.toInt() ?? 0;
      final int height = (data['height'] as num?)?.toInt() ?? 0;

      debugPrint("📐 [$myFrame] Final dim = ${width}x${height}");

      if (width == 0 || height == 0) {
        debugPrint("❌ [$myFrame] Invalid image dim — skip");
        return;
      }

      _sourceSize = Size(width.toDouble(), height.toDouble());

      // =======================================================
      // Atomic file write
      // =======================================================
      final dir = await getTemporaryDirectory();
      final String tmpPath =
          "${dir.path}/stream_tmp_${DateTime.now().microsecondsSinceEpoch}.jpg";
      final File tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(outBytes, flush: true);

      final int fileSize = await tmpFile.length();
      if (fileSize < 600) {
        debugPrint("❌ [$myFrame] FILE WRITE FAILED — size=$fileSize — SKIP");
        return;
      }

      final String finalPath =
          "${dir.path}/stream_${DateTime.now().microsecondsSinceEpoch}.jpg";
      final File finalFile = await tmpFile.rename(finalPath);

      _lastFrameFile = finalFile;

      debugPrint("💾 [$myFrame] Saved frame: $finalPath ($fileSize bytes)");

      // =======================================================
      // CALL BACKEND
      // =======================================================
      debugPrint(
        "🌍 [$myFrame] Sending to backend… "
        "(conf=${_detectConf.toStringAsFixed(2)}, iou=${_detectIou.toStringAsFixed(2)})",
      );

      final result = await widget.cloud.detect(
        finalFile,
        conf: _detectConf,
        iou: _detectIou,
      );

      final int totalMs = DateTime.now().difference(start).inMilliseconds;
      debugPrint(
        "🟨 [$myFrame] BACKEND RESPONSE in ${totalMs}ms\n"
        "Keys: ${result.keys.toList()}",
      );

      if (result.isEmpty) {
        debugPrint("🚨 [$myFrame] BACKEND EMPTY — maybe server error?");
        return;
      }
      if (result["success"] == false && result["error"] != null) {
        debugPrint("🚨 [$myFrame] BACKEND ERROR: ${result["error"]}");
      }

      if (!mounted) return;

      // ======================================================
      // PARSING — YOLO detections
      // ======================================================
      final rawDet = result["detections"];
      final List<CloudDetection> detections;
      if (rawDet is List) {
        detections = rawDet.map<CloudDetection>((e) {
          if (e is CloudDetection) return e;
          if (e is Map<String, dynamic>) return CloudDetection.fromJson(e);
          if (e is Map) {
            return CloudDetection.fromJson(Map<String, dynamic>.from(e));
          }
          throw Exception("Unexpected detection type ${e.runtimeType}");
        }).toList(growable: false);
      } else {
        detections = const <CloudDetection>[];
      }

      final rawStab =
          result["stabilizedDetections"] ?? result["stabilized_detections"];
      final List<CloudDetection> stabilized;
      if (rawStab is List) {
        stabilized = rawStab.map<CloudDetection>((e) {
          if (e is CloudDetection) return e;
          if (e is Map<String, dynamic>) return CloudDetection.fromJson(e);
          if (e is Map) {
            return CloudDetection.fromJson(Map<String, dynamic>.from(e));
          }
          throw Exception(
            "Unexpected stabilizedDetection type ${e.runtimeType}",
          );
        }).toList(growable: false);
      } else {
        stabilized = detections;
      }

      // CNN (live) — support raw + legacy keys
      final String cnnLabel = (result["cnnLabel"] ??
              result["cnn_label_raw"] ??
              result["cnn_label"] ??
              "Unknown")
          .toString();

      final num cnnConfNum = (result["cnnConf"] ??
          result["cnn_conf_raw"] ??
          result["cnn_confidence"] ??
          0.0) as num;
      final double cnnConf = cnnConfNum.toDouble().clamp(0.0, 1.0);

      // Final fused outputs (live + index)
      final String? finalLabel =
          (result["finalLabel"] ?? result["final_label"])?.toString();
      final num finalConfNum =
          (result["finalConf"] ?? result["final_confidence"] ?? 0.0) as num;
      final String? finalSource =
          (result["finalSource"] ?? result["final_source"])?.toString();

      final String? indexLabel =
          (result["indexLabel"] ?? result["index_label"])?.toString();
      final num indexConfNum =
          (result["indexConf"] ?? result["index_confidence"] ?? 0.0) as num;

      // Timing
      final num tms =
          (result["totalMs"] ?? result["total_time_ms"] ?? 0.0) as num;
      final double inferenceMs = tms.toDouble();

      // Source dims from backend
      final num swServer =
          (result["sourceW"] ?? result["source_w"] ?? 0) as num;
      final num shServer =
          (result["sourceH"] ?? result["source_h"] ?? 0) as num;

      if (swServer > 0 && shServer > 0) {
        _sourceSize = Size(swServer.toDouble(), shServer.toDouble());
      }

      // Auto-capture hints
      final bool autoFromServer = (result["autoCaptureSuggested"] ??
              result["auto_capture_suggested"] ??
              false) ==
          true;

      final int delayServer = ((result["suggestedDelayMs"] ??
              result["suggested_delay_ms"] ??
              2500) as num)
          .toInt();

      _serverSuggestedDelay = Duration(milliseconds: delayServer);
      _serverAutoCapture = autoFromServer;

      // Leaf detection flag
      final bool noLeaf =
          (result["noLeafDetected"] ?? result["no_leaf_detected"] ?? false) ==
              true;

      // Merged boxes
      List<double>? mergedBox;
      final mb = result["mergedBox"] ?? result["merged_box"];
      if (mb is List) {
        mergedBox = mb.map<double>((e) => (e as num).toDouble()).toList();
      }

      List<double>? mergedBoxNorm;
      final mbn = result["mergedBoxNorm"] ?? result["merged_box_norm"];
      if (mbn is List) {
        mergedBoxNorm = mbn.map<double>((e) => (e as num).toDouble()).toList();
      }

      debugPrint(
        "✅ [$myFrame] Parsed: det=${detections.length}, stab=${stabilized.length}, "
        "cnn='$cnnLabel'@${(cnnConf * 100).toStringAsFixed(1)}%, "
        "final='${finalLabel ?? cnnLabel}'@${(finalConfNum.toDouble().clamp(0.0, 1.0) * 100).toStringAsFixed(1)}% "
        "source=${finalSource ?? 'live_only'}, noLeaf=$noLeaf, autoCap=$_serverAutoCapture",
      );

      setState(() {
        _detections = List.from(detections);
        _stabilizedDetections = List.from(stabilized);

        _lastLabel = cnnLabel;
        _lastConf = cnnConf;
        _lastInferenceMs = inferenceMs;

        _finalLabel = finalLabel ?? cnnLabel;
        _finalConf = finalConfNum.toDouble().clamp(0.0, 1.0);
        _finalSource = finalSource;

        _indexLabel = indexLabel;
        _indexConf = indexConfNum.toDouble().clamp(0.0, 1.0);

        _noLeafDetected = noLeaf;

        _mergedBox = mergedBox;
        _mergedBoxNorm = mergedBoxNorm;
      });

      // FPS update (per processed frame)
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final dt = now.difference(_lastFrameTime!).inMilliseconds;
        if (dt > 0) {
          final f = 1000 / dt;
          _fps = (_fps == null) ? f : (0.6 * _fps! + 0.4 * f);
        }
      }
      _lastFrameTime = now;

      // ============================
      // Auto-capture logic (RAW ONLY)
      // ============================
      final bool hasConfident =
          _stabilizedDetections.any((d) => d.confidence >= _confThreshold);

      if (hasConfident) {
        _stableFrames++;
      } else {
        _stableFrames = 0;
      }

      debugPrint(
        "🎯 [$myFrame] hasConfident=$hasConfident "
        "stableFrames=$_stableFrames "
        "autoCapture=$_serverAutoCapture "
        "armedAt=$_armedAt capturePending=$_capturePending",
      );

      if (!_capturePending &&
          !_navigating &&
          _serverAutoCapture &&
          _stableFrames >= 3 &&
          _lastFrameFile != null) {
        _armedAt ??= DateTime.now();
        if (DateTime.now().difference(_armedAt!) >= _serverSuggestedDelay) {
          _capturePending = true;
          await _captureFeedback();
          await _saveAndProceed(_lastFrameFile!);
          return;
        }
      }

      if (!hasConfident) {
        _armedAt = null;
      }
    } catch (e, st) {
      debugPrint("🔥 STREAM ERROR (frame $myFrame): $e\n$st");
    } finally {
      _busy = false;
      _capturePending = false;

      // Overall FPS based on full pipeline time
      final int ms = DateTime.now().difference(start).inMilliseconds;
      if (ms > 0) {
        final f = 1000 / ms;
        _fps = (_fps == null) ? f : (0.7 * _fps! + 0.3 * f);
      }
    }
  }

  // ----------------------------------------------------------
  // Manual Capture (RAW only)
  // ----------------------------------------------------------
  Future<void> _manualCapture() async {
    if (_camera == null || _busy || _navigating) return;
    _busy = true;
    try {
      try {
        await _camera!.stopImageStream();
      } catch (_) {}

      final XFile frame = await _camera!.takePicture();
      File file = File(frame.path);
      file = await _compressFrame(file);
      await _captureFeedback();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 Manual capture sent...'),
          backgroundColor: Colors.orange,
        ),
      );
      await _saveAndProceed(file);
    } catch (e, st) {
      debugPrint('⚠️ Manual capture error: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveAndProceed(File file) async {
    if (_navigating) return;
    _navigating = true;

    final label = _finalLabel ?? widget.cloud.lastCnnLabel ?? "Unknown";
    final dir = await getApplicationDocumentsDirectory();
    final outPath =
        "${dir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg";
    await file.copy(outPath);

    widget.cloud.lastCapturePath = outPath;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📸 Captured ($label)'),
        backgroundColor: Colors.green[800],
      ),
    );

    await Future.delayed(const Duration(milliseconds: 200));
    try {
      await _camera?.dispose();
    } catch (_) {}
    _camera = null;

    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LLMPage()),
    );
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_camera == null || !_camera!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final Size preview = _camera!.value.previewSize ?? const Size(640, 480);

    final bool hasConfident =
        _stabilizedDetections.any((d) => d.confidence >= _confThreshold);

    final bool noLeaf = _noLeafDetected == true;

    final String statusText = !_autoDetectEnabled
        ? "Paused"
        : noLeaf
            ? "No leaf"
            : hasConfident
                ? "Stable"
                : "Scanning…";

    final Color statusColor = !_autoDetectEnabled
        ? Colors.grey
        : noLeaf
            ? Colors.redAccent
            : hasConfident
                ? Colors.greenAccent
                : Colors.orangeAccent;

    final String hudLabel = _finalLabel ?? _lastLabel ?? "?";
    final double hudConf = _finalConf ?? _lastConf ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Live Detection',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _autoDetectEnabled ? Icons.pause_circle_filled : Icons.play_arrow,
              color: Colors.white,
            ),
            tooltip:
                _autoDetectEnabled ? 'Pause auto-detect' : 'Resume auto-detect',
            onPressed: () {
              setState(() {
                _autoDetectEnabled = !_autoDetectEnabled;
                _armedAt = null;
                _stableFrames = 0;
              });
            },
          ),
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? Colors.amberAccent : Colors.white,
            ),
            tooltip: 'Toggle torch',
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final Size viewSize =
              Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_camera!),

              // Detection overlay
              CustomPaint(
                painter: _DetectionPainter(
                  detections: _stabilizedDetections.isNotEmpty
                      ? _stabilizedDetections
                      : _detections,
                  viewSize: viewSize,
                  originalSize: _sourceSize,
                  sensorPreviewSize: preview,
                ),
              ),

              // Guidance box
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: viewSize.width * _overlayRatio,
                      height: viewSize.height * _overlayRatio,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.5),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: (!hasConfident)
                          ? const Center(
                              child: Text(
                                'Place full leaf inside the box',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              // Countdown
              if (_armedAt != null)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: _CountdownBanner(
                    armedAt: _armedAt!,
                    delay: _serverSuggestedDelay,
                  ),
                ),

              // Telemetry
              if (_lastInferenceMs != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '⚡ ${_lastInferenceMs!.toStringAsFixed(0)} ms',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (_fps != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '🎯 ${_fps!.toStringAsFixed(1)} fps',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          '$hudLabel ${(100 * hudConf).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Status badge
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        !_autoDetectEnabled
                            ? Icons.pause_circle_filled
                            : noLeaf
                                ? Icons.search_off
                                : hasConfident
                                    ? Icons.check_circle
                                    : Icons.radar,
                        color: statusColor,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Controls + sliders
              Positioned(
                left: 12,
                right: 92,
                bottom: 0,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Guide size',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Expanded(
                            child: Slider(
                              value: _overlayRatio,
                              min: 0.65,
                              max: 0.95,
                              divisions: 6,
                              label: _overlayRatio.toStringAsFixed(2),
                              activeColor: Colors.blueAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (val) {
                                setState(() => _overlayRatio = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _chip(
                              'conf 0.45',
                              () => setState(() => _detectConf = 0.45),
                              active: (_detectConf - 0.45).abs() < 1e-6,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              'conf 0.55',
                              () => setState(() => _detectConf = 0.55),
                              active: (_detectConf - 0.55).abs() < 1e-6,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              'conf 0.65',
                              () => setState(() => _detectConf = 0.65),
                              active: (_detectConf - 0.65).abs() < 1e-6,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              'conf 0.75',
                              () => setState(() => _detectConf = 0.75),
                              active: (_detectConf - 0.75).abs() < 1e-6,
                            ),
                            const SizedBox(width: 16),
                            _chip(
                              'IoU 0.40',
                              () => setState(() => _detectIou = 0.40),
                              active: (_detectIou - 0.40).abs() < 1e-6,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              'IoU 0.50',
                              () => setState(() => _detectIou = 0.50),
                              active: (_detectIou - 0.50).abs() < 1e-6,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              'IoU 0.60',
                              () => setState(() => _detectIou = 0.60),
                              active: (_detectIou - 0.60).abs() < 1e-6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_busy)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8.0, right: 4.0),
        child: FloatingActionButton(
          backgroundColor: Colors.deepOrangeAccent,
          onPressed: _manualCapture,
          tooltip: "Manual Capture (final analysis)",
          child: const Icon(Icons.camera_alt_rounded),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Chips for threshold
  // ----------------------------------------------------------
  Widget _chip(String label, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.greenAccent.withOpacity(0.25)
              : const Color(0x22000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? Colors.greenAccent : Colors.white24,
            width: active ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.greenAccent : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// Countdown Banner
// ==========================================================
class _CountdownBanner extends StatelessWidget {
  final DateTime armedAt;
  final Duration delay;

  const _CountdownBanner({
    required this.armedAt,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final remain = delay - DateTime.now().difference(armedAt);
    final int sec =
        remain.isNegative ? 0 : (remain.inMilliseconds / 1000).ceil();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Capturing in $sec s…',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// 🛑 DEBUGGER PAINTER: FULL DIAGNOSTIC MODE (ROTATION FIXED)
// Replace your existing _DetectionPainter with this entire class.
// Watch your "Debug Console" in VS Code while the app runs.
// ==========================================================

class _DetectionPainter extends CustomPainter {
  final List<CloudDetection> detections;
  final Size viewSize; // Phone Screen Size (e.g., 1080 x 2400)
  final Size originalSize; // Camera Image Size  (e.g., 720 x 480)
  final Size sensorPreviewSize;

  _DetectionPainter({
    required this.detections,
    required this.viewSize,
    required this.originalSize,
    required this.sensorPreviewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 🔍 DIAGNOSTIC 1: IS DATA COMING IN?
    print("\n--- 🎨 PAINTER FRAME START ---");
    print("🔹 Detections Count: ${detections.length}");
    print("🔹 View Size (Screen): $viewSize");
    print("🔹 Original Size (Image): $originalSize");

    if (detections.isEmpty) {
      print("⚠️ PAINTER: No detections to draw. Skipping frame.");
      return;
    }

    // 🔍 DIAGNOSTIC 2: IS SCALE CALCULATED CORRECTLY?
    if (originalSize.width == 0 || originalSize.height == 0) {
      print("❌ PAINTER ERROR: Original Image Size is 0! Cannot scale.");
      return;
    }

    // ROTATION LOGIC: Android Image (Landscape) -> Phone Screen (Portrait)
    // We scale Image HEIGHT to Screen WIDTH
    double scaleX = viewSize.width / originalSize.height;
    double scaleY = viewSize.height / originalSize.width;
    double scale = math.max(scaleX, scaleY);

    double dx = (viewSize.width - (originalSize.height * scale)) / 2.0;
    double dy = (viewSize.height - (originalSize.width * scale)) / 2.0;

    print("🔹 Scale Factor: $scale");
    print("🔹 Offsets: dx=$dx, dy=$dy");

    final Paint boxPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint textBg = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];

      // 🔍 DIAGNOSTIC 3: RAW DATA FROM BACKEND
      print("🔸 [$i] Raw Box from Server: ${d.box} (Label: ${d.label})");

      if (d.box.length < 4) {
        print("❌ [$i] INVALID BOX: Has fewer than 4 coordinates.");
        continue;
      }

      double imgX1 = d.box[0].toDouble();
      double imgY1 = d.box[1].toDouble();
      double imgX2 = d.box[2].toDouble();
      double imgY2 = d.box[3].toDouble();

      // 🔍 DIAGNOSTIC 4: COORDINATE TRANSFORMATION (90° Rotation)
      // We swap X/Y because the image is rotated 90 degrees relative to the screen
      double screenX1 = (imgY1 * scale) + dx;
      double screenY1 = (imgX1 * scale) + dy;
      double screenX2 = (imgY2 * scale) + dx;
      double screenY2 = (imgX2 * scale) + dy;

      double left = math.min(screenX1, screenX2);
      double right = math.max(screenX1, screenX2);
      double top = math.min(screenY1, screenY2);
      double bottom = math.max(screenY1, screenY2);

      Rect rect = Rect.fromLTRB(left, top, right, bottom);

      print("🔸 [$i] Transformed Box (Before Clamp): $rect");

      // Clamp to screen to prevent "infinity" drawing errors
      rect = Rect.fromLTRB(
        rect.left.clamp(0.0, viewSize.width),
        rect.top.clamp(0.0, viewSize.height),
        rect.right.clamp(0.0, viewSize.width),
        rect.bottom.clamp(0.0, viewSize.height),
      );

      print("✅ [$i] FINAL DRAWING RECT: $rect");

      if (rect.width <= 0 || rect.height <= 0) {
        print(
            "⚠️ [$i] WARNING: Box has 0 width/height after clamping! It will be invisible.");
      }

      // DRAW
      canvas.drawRect(rect, boxPaint);

      // DRAW TEXT
      final String labelText =
          '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top - 22, tp.width + 10, 22),
        textBg,
      );
      tp.paint(canvas, Offset(rect.left + 5, rect.top - 20));
    }
    print("--- 🎨 PAINTER FRAME END ---\n");
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter old) =>
      true; // Force repaint for debugging
}
