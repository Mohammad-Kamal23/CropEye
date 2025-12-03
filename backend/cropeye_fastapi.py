"""
CropEye Backend — FastAPI (Rebuilt v9.2 - Indexed DB Ready + Full-Frame CNN)
============================================================================

Updates in this version (header block only):
- KEEPS: YOLO resize at 640 and CNN resize at 224 (no change to model contracts).
- FIX: CNN now uses the full frame (resized to 224x224) instead of center-cropping.
- PREP: Added config + helpers for the indexed database (leaf_index.pkl).
- SAFETY: Model loading remains GPU-first with safe CPU fallback and detailed error logs.
"""

import os
import sys  
# --- 🔴 CLOUD RUN CUDA PATH FIX (DO NOT TOUCH GPU FLAGS) 🔴 ---
# FORCE FIX: Overwrite Cloud Run's "polluted" path with the clean system path.
# This makes the app ignore broken CV2 drivers and use the real NVIDIA drivers.
clean_path = "/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
os.environ["LD_LIBRARY_PATH"] = clean_path

import time
import asyncio
import threading
import base64
from datetime import datetime, timezone
from typing import Optional, Tuple, Dict, Any, List

import cv2
import numpy as np
import onnxruntime as ort
import pickle
import ctypes
import glob

from fastapi import FastAPI, UploadFile, File, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

import google.generativeai as genai

# ---------------------------------------------------------------------------
# Basic process/thread settings
# ---------------------------------------------------------------------------

CPU_COUNT = os.cpu_count() or 4
os.environ.setdefault("OMP_NUM_THREADS", str(CPU_COUNT))
os.environ.setdefault("OPENBLAS_NUM_THREADS", os.environ["OMP_NUM_THREADS"])
os.environ.setdefault("MKL_NUM_THREADS", os.environ["OMP_NUM_THREADS"])
os.environ.setdefault("UV_THREADPOOL_SIZE", "64")
os.environ["ORT_TENSORRT_UNAVAILABLE"] = "1"

IDLE_TIMEOUT_SEC = int(os.getenv("IDLE_TIMEOUT_SEC", "900"))
ALLOW_IDLE_EXIT = os.getenv("ALLOW_IDLE_EXIT", "1") == "1"

YOLO_MODEL_PATH = os.getenv("YOLO_MODEL_PATH", os.path.join("models", "best_yolo_s.onnx"))
CNN_MODEL_PATH = os.getenv("CNN_MODEL_PATH", os.path.join("models", "shufflenetv2_full_precision.onnx"))

# ---------------------------------------------------------------------------
# BLOCK 1: INDEXED DATABASE CONFIGURATION
# ---------------------------------------------------------------------------
# We use the exact path you provided for local testing.
# If running on Cloud Run, ensure the file is uploaded to "INDEXED-DATABASE/leaf_index.pkl"
if os.name == 'nt':  # Windows
    INDEX_DB_PATH = r"C:\Users\homeb\Desktop\BACKEND\INDEXED-DATABASE\leaf_index.pkl"
else:  # Linux / Cloud Run
    INDEX_DB_PATH = os.path.join("INDEXED-DATABASE", "leaf_index.pkl")

# Minimum similarity score (0.0 to 1.0) to accept a database match
INDEX_DB_MIN_SIM = 0.65

# --- CRITICAL CONFIGURATION ---
# YOLO must be 640. CNN must be 224. Do not change these unless models are re-exported.
IMG_SIZE = int(os.getenv("YOLO_IMG", "640"))
CONF_THRESH = float(os.getenv("YOLO_CONF", "0.25"))
IOU_THRESH = float(os.getenv("YOLO_IOU", "0.65"))

CNN_INPUT_SIZE = int(os.getenv("CNN_INPUT_SIZE", "224"))
CNN_CLASSES = ["healthy", "mild", "moderate", "severe"]

SMOOTH_ALPHA = float(os.getenv("SMOOTH_ALPHA", "0.40"))
CNN_SMOOTH_ALPHA = float(os.getenv("CNN_SMOOTH_ALPHA", "0.75"))

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

LOG_DIR = "logs"
os.makedirs(LOG_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        with open(os.path.join(LOG_DIR, "server.log"), "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        # Never crash because of logging
        pass


def dlog(msg: str) -> None:
    if os.getenv("DEBUG_MODE", "0") == "1":
        log(msg)

# ---------------------------------------------------------------------------
# Indexed database helpers (loaded once on startup)
# ---------------------------------------------------------------------------

indexed_vectors: Optional[np.ndarray] = None
indexed_labels: Optional[np.ndarray] = None
indexed_meta: Dict[str, Any] = {}
_index_loaded_ok: bool = False

def load_indexed_database() -> None:
    """
    Load leaf_index.pkl from INDEX_DB_PATH, if available.
    Expected (but not strictly enforced) structure:
      {
        "vectors": np.ndarray [N, D],
        "labels":  np.ndarray [N] or list of str,
        ... (any extra metadata)
      }
    If the format is incompatible, index-based refinement is simply disabled.
    """
    global indexed_vectors, indexed_labels, indexed_meta, _index_loaded_ok

    _index_loaded_ok = False
    indexed_vectors = None
    indexed_labels = None
    indexed_meta = {}

    if not os.path.exists(INDEX_DB_PATH):
        log(f"ℹ️ Indexed DB not found at {INDEX_DB_PATH} — skipping.")
        return

    try:
        with open(INDEX_DB_PATH, "rb") as f:
            obj = pickle.load(f)
    except Exception as e:
        log(f"⚠️ Failed to load indexed DB ({INDEX_DB_PATH}): {e}")
        return

    if isinstance(obj, dict) and "vectors" in obj and "labels" in obj:
        vectors = np.asarray(obj["vectors"], dtype=np.float32)
        labels = np.asarray(obj["labels"])
        if vectors.ndim != 2 or vectors.shape[0] == 0:
            log(f"⚠️ Indexed DB has invalid vector shape: {vectors.shape}")
            return
        if labels.shape[0] != vectors.shape[0]:
            log(
                f"⚠️ Indexed DB labels length mismatch: "
                f"len(labels)={labels.shape[0]} vs vectors={vectors.shape[0]}"
            )
            return

        # L2-normalize vectors for cosine similarity
        norms = np.linalg.norm(vectors, axis=1, keepdims=True) + 1e-9
        vectors = vectors / norms

        indexed_vectors = vectors
        indexed_labels = labels
        indexed_meta = {k: v for k, v in obj.items() if k not in ("vectors", "labels")}
        _index_loaded_ok = True

        log(
            f"✅ Indexed DB loaded: {vectors.shape[0]} entries, "
            f"dim={vectors.shape[1]}, path={INDEX_DB_PATH}"
        )
    else:
        log(
            "⚠️ Indexed DB format unsupported. "
            "Expected dict with 'vectors' and 'labels' keys; index disabled."
        )

# ---------------------------------------------------------------------------
# FastAPI app + CORS
# ---------------------------------------------------------------------------

app = FastAPI(title="CropEye FastAPI Backend", version="9.2")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# ONNX runtime helpers (Enhanced Debug Version)
# ---------------------------------------------------------------------------

# GLOBAL VARIABLE TO STORE GPU ERRORS
load_errors: Dict[str, str] = {}

def make_session_options() -> ort.SessionOptions:
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    so.execution_mode = ort.ExecutionMode.ORT_PARALLEL
    so.intra_op_num_threads = CPU_COUNT
    so.inter_op_num_threads = max(1, CPU_COUNT // 2)
    try:
        # Allow ORT to run in FP16 when possible (safe on L4)
        so.add_session_config_entry("session.inference_mode", "ORT_ENABLE_FP16")
    except Exception:
        pass
    return so


def load_onnx_model(path: str, label: str):
    """
    Robust loader:
      1) Try strict GPU (CUDAExecutionProvider).
      2) If that fails, log the exact error and fall back to CPU.
      3) Record errors in load_errors for /gpu_failure_reason debugging.
    """
    global load_errors

    if not os.path.exists(path):
        msg = f"{label} model is missing at {path}"
        log(msg)
        load_errors[label] = msg
        return None, None, None

    so = make_session_options()

    # --- ATTEMPT 1: STRICT GPU LOAD ---
    try:
        sess = ort.InferenceSession(path, sess_options=so, providers=["CUDAExecutionProvider"])
        log(f"✅ {label} successfully loaded on GPU")
        return sess, sess.get_inputs()[0].name, sess.get_outputs()[0].name
    except Exception as e:
        full_error = str(e)
        log(f"⚠️ {label} GPU Init Failed. Error: {full_error}")
        load_errors[label] = full_error

    # --- ATTEMPT 2: CPU FALLBACK ---
    try:
        log(f"{label} falling back to CPU...")
        sess = ort.InferenceSession(path, sess_options=so, providers=["CPUExecutionProvider"])
        log(f"✅ {label} successfully loaded on CPU")
        return sess, sess.get_inputs()[0].name, sess.get_outputs()[0].name
    except Exception as e:
        err = f"{label} CPU Fallback also failed: {e}"
        log(f"❌ {err}")
        load_errors[label] = err
        return None, None, None

# ---------------------------------------------------------------------------
# Global model state
# ---------------------------------------------------------------------------

yolo_sess: Optional[ort.InferenceSession] = None
yolo_in: Optional[str] = None
yolo_out: Optional[str] = None

cnn_sess: Optional[ort.InferenceSession] = None
cnn_in: Optional[str] = None
cnn_out: Optional[str] = None

gemini_model = None

# Smoothing state
_smooth_lock = threading.Lock()
_last_boxes: List[Dict[str, Any]] = []
_last_cnn_probs: np.ndarray = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float32)

# Warmup state
_warmup_complete = False
_warmup_lock = threading.Lock()

# Idle reaper state
_last_req_ts = time.time()

def _update_last_request() -> None:
    global _last_req_ts
    _last_req_ts = time.time()


def _idle_reaper() -> None:
    while True:
        time.sleep(60)
        if not ALLOW_IDLE_EXIT:
            continue
        idle_for = time.time() - _last_req_ts
        if idle_for >= IDLE_TIMEOUT_SEC:
            log(f"💤 Idle for {idle_for:.0f}s ≥ {IDLE_TIMEOUT_SEC}s — exiting.")
            os._exit(0)

# ---------------------------------------------------------------------------
# Utility + preprocessing helpers
# ---------------------------------------------------------------------------

def _clip01(x: float) -> float:
    return float(max(0.0, min(1.0, float(x))))


def softmax(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float32)
    x -= np.max(x)
    e = np.exp(x)
    return e / (np.sum(e) + 1e-9)


def detect_lang_from_text(text: str, default: str = "ar") -> str:
    if not text:
        return default
    has_ar = any(
        "\u0600" <= ch <= "\u06FF" or "\u0750" <= ch <= "\u077F" or "\u08A0" <= ch <= "\u08FF"
        for ch in text
    )
    has_lat = any("a" <= ch <= "z" for ch in text.lower())
    if has_ar and not has_lat:
        return "ar"
    if has_lat and not has_ar:
        return "en"
    if has_ar and has_lat:
        return "ar"
    return default


def preprocess_image_bytes(
    img_bytes: bytes,
) -> Tuple[np.ndarray, np.ndarray, Tuple[int, int, float, int, int, float]]:
    """
    Prepares image for YOLO.
    RETURNS:
      - img_rgb: Original image (RGB), used for CNN full-frame classification.
      - tensor:  Resized image (640x640) specifically for YOLO.
      - meta:    Metadata for bounding box rescaling.
    """
    img_array = np.frombuffer(img_bytes, dtype=np.uint8)
    img_bgr = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise ValueError("Invalid image data")
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    orig_h, orig_w = img_rgb.shape[:2]

    # Brightness check/adjustment (on the original RGB)
    gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
    brightness = float(gray.mean())

    if brightness < 80:
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        img_rgb = cv2.cvtColor(clahe.apply(gray), cv2.COLOR_GRAY2RGB)
    elif brightness > 200:
        img_rgb = np.clip(img_rgb * 0.85, 0, 255).astype(np.uint8)

    # --- YOLO RESIZING (Target: IMG_SIZE / 640) ---
    scale = IMG_SIZE / max(orig_h, orig_w)
    nh, nw = int(orig_h * scale), int(orig_w * scale)
    resized = cv2.resize(img_rgb, (nw, nh), interpolation=cv2.INTER_AREA)

    canvas = np.full((IMG_SIZE, IMG_SIZE, 3), 114, dtype=np.uint8)
    top = (IMG_SIZE - nh) // 2
    left = (IMG_SIZE - nw) // 2
    canvas[top : top + nh, left : left + nw] = resized

    tensor = np.transpose(canvas.astype(np.float32) / 255.0, (2, 0, 1))[None, ...]

    # Adjust confidence threshold based on brightness
    conf_thresh = CONF_THRESH if brightness >= 90 else min(CONF_THRESH, 0.15)

    return img_rgb, tensor, (left, top, scale, orig_w, orig_h, conf_thresh)


def nms(boxes: np.ndarray, scores: np.ndarray, iou_threshold: float = 0.65) -> List[int]:
    if len(boxes) == 0:
        return []
    boxes = boxes.astype(np.float32)
    scores = scores.astype(np.float32)

    x1, y1, x2, y2 = boxes.T
    areas = (x2 - x1) * (y2 - y1)
    order = scores.argsort()[::-1]

    keep: List[int] = []
    while order.size > 0:
        i = int(order[0])
        keep.append(i)
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        w = np.maximum(0.0, xx2 - xx1)
        h = np.maximum(0.0, yy2 - yy1)
        inter = w * h
        iou = inter / (areas[i] + areas[order[1:]] - inter + 1e-6)
        order = order[np.where(iou <= iou_threshold)[0] + 1]
    return keep


def is_leaf_like(img_rgb: np.ndarray, box: List[int]) -> bool:
    """
    Filters out objects that are clearly NOT leaves (like hands/faces)
    based on Hue (Skin is usually Red/Orange, Leaves are Green/Yellow).
    Preserves dark/shadowed leaves.
    """
    x1, y1, x2, y2 = box
    h_img, w_img = img_rgb.shape[:2]
    
    # 1. GEOMETRY CHECKS (Sanity)
    # Block tiny noise dots
    area = (x2 - x1) * (y2 - y1)
    if area < 0.01 * (w_img * h_img): 
        return False

    # Block long thin lines or flat bars
    width = x2 - x1
    height = max(1, (y2 - y1))
    aspect = width / height
    if aspect < 0.2 or aspect > 5.0:
        return False

    # 2. SMART COLOR FILTER
    try:
        roi = img_rgb[y1:y2, x1:x2]
        if roi.size == 0: return False
        
        # Convert RGB to HSV
        # Hue Range in OpenCV is 0-180
        # 0-20:   Red/Orange (Skin)
        # 20-30:  Yellow (Dried Leaves/Skin)
        # 30-90:  Green (Healthy/Mild Leaves)
        # 90-130: Blue/Cyan (Sky/Clothes)
        # 130-180: Purple/Pink/Red
        
        hsv = cv2.cvtColor(roi, cv2.COLOR_RGB2HSV)
        h, s, v = cv2.split(hsv)

        # LOGIC: We count "Plant-Like" pixels.
        # A pixel is "Plant-Like" if:
        # 1. It is Greenish (Hue 25 to 100)
        # 2. OR It is VERY Dark (Value < 60) -> Shadowed Leaf
        # 3. OR It is Unsaturated (Saturation < 30) -> Grey/Dead Leaf
        
        # Mask for Green range (25 to 110)
        green_mask = (h > 25) & (h < 110)
        
        # Mask for Shadows/Grey (Allow detection in the dark)
        shadow_mask = (v < 60) | (s < 30)
        
        # Combine: It's valid if it's Green OR Shadow
        valid_pixels = green_mask | shadow_mask
        
        ratio = np.sum(valid_pixels) / roi.size
        
        # If less than 15% of the box is Plant-like or Shadow-like,
        # it's probably a bright hand/face/wall.
        if ratio < 0.15:
            return False
            
    except Exception:
        pass # If math fails, trust YOLO

    return True


def center_crop_for_cnn(img_rgb: np.ndarray, ratio: float = 0.85) -> np.ndarray:
    """
    Kept for potential future use, but NOT used for the main CNN path anymore.
    CropEye CNN now uses the FULL frame resized to 224x224.
    """
    h, w = img_rgb.shape[:2]
    ratio = max(0.0, min(1.0, float(ratio)))
    if ratio <= 0.0 or ratio > 1.0:
        return img_rgb
    new_w = int(w * ratio)
    new_h = int(h * ratio)
    left = max(0, (w - new_w) // 2)
    top = max(0, (h - new_h) // 2)
    return img_rgb[top : top + new_h, left : left + new_w]


def smooth_boxes(current_boxes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    global _last_boxes
    with _smooth_lock:
        if not _last_boxes:
            _last_boxes = [dict(b) for b in current_boxes]
            return current_boxes
        out: List[Dict[str, Any]] = []
        n = min(len(current_boxes), len(_last_boxes))
        for i in range(n):
            prev = _last_boxes[i]["box"]
            curr = current_boxes[i]["box"]
            smoothed = [
                int(SMOOTH_ALPHA * prev[j] + (1.0 - SMOOTH_ALPHA) * curr[j])
                for j in range(4)
            ]
            item = dict(current_boxes[i])
            item["box"] = smoothed
            item["confidence"] = float(
                0.5 * _last_boxes[i]["confidence"] + 0.5 * item["confidence"]
            )
            out.append(item)
        if len(current_boxes) > n:
            out.extend(current_boxes[n:])
        _last_boxes = [dict(b) for b in out]
        return out


def smooth_classification(current_probs: Optional[np.ndarray]) -> np.ndarray:
    global _last_cnn_probs
    if current_probs is None:
        return _last_cnn_probs
    with _smooth_lock:
        smoothed = CNN_SMOOTH_ALPHA * _last_cnn_probs + (1.0 - CNN_SMOOTH_ALPHA) * current_probs
        smoothed = smoothed / (np.sum(smoothed) + 1e-9)
        _last_cnn_probs = smoothed
        return smoothed

# ---------------------------------------------------------------------------
# Classification helpers (full-frame CNN + index refinement hooks)
# ---------------------------------------------------------------------------

def _probs_to_embedding(probs: np.ndarray) -> np.ndarray:
    """
    Convert CNN probability vector into a normalized embedding.
    This assumes the index was built on the same representation.
    """
    v = np.asarray(probs, dtype=np.float32).reshape(-1)
    n = float(np.linalg.norm(v)) + 1e-9
    return v / n


def query_index_from_probs(
    probs: Optional[np.ndarray],
) -> Tuple[Optional[str], float]:
    """
    Use the indexed database to refine the label from CNN probabilities.
    Returns:
      (best_label_from_index or None, index_confidence in [0, 1])
    If the index is not available or incompatible, returns (None, 0.0).
    """
    if not _index_loaded_ok:
        return None, 0.0
    if probs is None:
        return None, 0.0
    if indexed_vectors is None or indexed_labels is None:
        return None, 0.0

    try:
        q = _probs_to_embedding(probs)
        if indexed_vectors.shape[1] != q.shape[0]:
            # Shape mismatch between query and stored vectors
            dlog(
                f"INDEX SHAPE MISMATCH: query_dim={q.shape[0]} "
                f"vs index_dim={indexed_vectors.shape[1]}"
            )
            return None, 0.0

        # Cosine similarity
        sims = indexed_vectors @ q
        best_idx = int(np.argmax(sims))
        best_sim = float(sims[best_idx])

        # Map cosine similarity [-1, 1] → [0, 1]
        conf = (best_sim + 1.0) / 2.0
        if conf < INDEX_DB_MIN_SIM:
            return None, conf

        best_label = str(indexed_labels[best_idx])
        return best_label, conf
    except Exception as e:
        dlog(f"query_index_from_probs error: {e}")
        return None, 0.0


def choose_best_label(
    live_label: str,
    live_conf: float,
    index_label: Optional[str],
    index_conf: float,
) -> Tuple[str, float, str]:
    """
    Decide which label to keep:
      - If index is unavailable or weaker → keep live_label.
      - If index has higher confidence → use index_label.
    Returns:
      (final_label, final_confidence, source_flag: 'live' | 'index' | 'live_only')
    """
    live_conf = float(_clip01(live_conf))
    index_conf = float(_clip01(index_conf))

    if not index_label or index_conf <= live_conf:
        # Keep original CNN result
        return live_label, live_conf, "live_only"

    # Index is more confident → use it
    return index_label, index_conf, "index"
    

def classify_roi(img_rgb: np.ndarray) -> Tuple[Optional[np.ndarray], str, float]:
    """
    Center-Focus Classification:
    1. Crop Center 85% (matches Flutter UI).
    2. Resize to 224x224.
    3. Infer.
    """
    if cnn_sess is None:
        return None, "unknown", 0.0
    
    try:
        # 1. Focus on Center (Ignore background noise)
        h, w = img_rgb.shape[:2]
        ratio = 0.85
        ch, cw = int(h * ratio), int(w * ratio)
        y, x = (h - ch) // 2, (w - cw) // 2
        focused = img_rgb[y:y+ch, x:x+cw]

        # 2. Resize
        roi = cv2.resize(focused, (CNN_INPUT_SIZE, CNN_INPUT_SIZE), interpolation=cv2.INTER_AREA)
        
        # 3. Preprocess
        roi = roi.astype(np.float32) / 255.0
        roi = roi.transpose(2, 0, 1)[None, ...]
        
        # 4. Run
        raw = cnn_sess.run([cnn_out], {cnn_in: roi})[0][0]
        
        # 5. Softmax
        exps = np.exp(raw - np.max(raw))
        probs = exps / np.sum(exps)
        idx = int(np.argmax(probs))
        return probs, CNN_CLASSES[idx], float(probs[idx])
    except Exception as e:
        log(f"⚠️ CNN Error: {e}")
        return None, "error", 0.0

# ---------------------------------------------------------------------------
# Gemini helpers (Upgraded v9.2 — cleaner prompts, stronger fallback, safer text)
# ---------------------------------------------------------------------------

def generate_gemini_recommendation(label: str, conf: float, lang_hint: str = "auto") -> str:
    """
    Generates short actionable advice for LLM result page.
    Uses cached Gemini with fallback when API fails.
    """
    if gemini_model is None:
        return "Gemini disabled."

    lang = (lang_hint or "auto").lower()
    if lang not in ("en", "ar"):
        lang = "ar"

    p = _clip01(conf)

    if lang == "en":
        base_prompt = f"""
You are CropEye, an agronomy AI advisor specialized in tomato leafminer (Tuta absoluta).
The current classification is: {label.upper()} (confidence {p:.2f}).

Provide a short, practical recommendation in English.
No markdown. No special symbols. Use simple numbered lines.
""".strip()

    else:
        base_prompt = f"""
أنت CropEye، مساعد ذكاء اصطناعي متخصص في إدارة آفة Tuta absoluta في الطماطم.
التصنيف الحالي: {label} بنسبة ثقة {p:.2f}.

قدّم توصية قصيرة وعملية باللغة العربية الفصحى.
بدون تنسيق، بدون رموز خاصة. استخدم أرقامًا بسيطة في بداية السطور.
""".strip()

    try:
        resp = gemini_model.generate_content(base_prompt)
        out = (getattr(resp, "text", "") or "").strip()
        return out if out else "Gemini returned no content."
    except Exception as e:
        log(f"⚠️ Gemini error: {e}")
        return "Gemini unavailable."


# Local cache (per confidence bucket)
_gem_cache: Dict[Tuple[str, int, str], Dict[str, Any]] = {}
_gem_cache_lock = threading.Lock()
_gem_cache_ttl = int(os.getenv("GEMINI_CACHE_TTL_SEC", "30"))


# ---------------------------------------------------------------------------
# Postprocessing + enhancement (Upgraded v9.2 for stability)
# ---------------------------------------------------------------------------

def postprocess(
    outputs: List[np.ndarray],
    img_rgb: np.ndarray,
    meta: Tuple[int, int, float, int, int, float],
    iou_for_nms: float,
) -> List[Dict[str, Any]]:

    left, top, scale, orig_w, orig_h, conf_thresh = meta
    preds = outputs[0]

    # Normalize shapes
    if preds.ndim == 3:
        preds = np.squeeze(preds, axis=0)
        if preds.shape[0] < preds.shape[1]:
            preds = preds.T
    elif preds.ndim == 1:
        preds = preds.reshape(-1, 6)

    if preds.ndim != 2 or preds.shape[1] < 5:
        dlog(f"⚠️ Unexpected YOLO head shape: {preds.shape}")
        return []

    preds = preds.astype(np.float32, copy=False)
    xywh = preds[:, :4]
    tail = preds[:, 4:]

    # Confidence extraction upgrade
    if tail.shape[1] == 1:
        conf = np.clip(tail[:, 0], 0.0, 1.0)
    else:
        # YOLOv8 logic (objectness × best_class)
        obj = np.clip(tail[:, 0], 0.0, 1.0)
        cls_conf = np.max(tail[:, 1:], axis=1) if tail.shape[1] > 1 else 1.0
        conf = np.clip(obj * cls_conf, 0.0, 1.0)

    mask = conf >= float(conf_thresh)
    if not np.any(mask):
        return []

    xywh = xywh[mask]
    conf = conf[mask]

    # Convert xywh → xyxy
    x, y, w_box, h_box = xywh.T
    xyxy = np.stack([x - w_box / 2, y - h_box / 2, x + w_box / 2, y + h_box / 2], axis=1)

    # Rescale if normalized
    mx = float(np.max(xyxy)) if xyxy.size else 0.0
    if mx <= 1.1:
        xyxy *= IMG_SIZE

    # Reverse letterboxing
    s = max(scale, 1e-6)
    xyxy[:, [0, 2]] = (xyxy[:, [0, 2]] - left) / s
    xyxy[:, [1, 3]] = (xyxy[:, [1, 3]] - top) / s

    # Clamp
    xyxy[:, [0, 2]] = np.clip(xyxy[:, [0, 2]], 0, orig_w - 1)
    xyxy[:, [1, 3]] = np.clip(xyxy[:, [1, 3]], 0, orig_h - 1)

    # Filter invalid
    valid = (xyxy[:, 2] > xyxy[:, 0]) & (xyxy[:, 3] > xyxy[:, 1])
    if not np.any(valid):
        return []

    xyxy = xyxy[valid]
    conf = conf[valid]

    # NMS
    keep = nms(xyxy, conf, iou_threshold=float(iou_for_nms))
    if len(keep) == 0:
        return []

    xyxy = xyxy[keep]
    conf = conf[keep]

    boxes: List[Dict[str, Any]] = []
    for (bx1, by1, bx2, by2), c in zip(xyxy, conf):
        bx1i, by1i, bx2i, by2i = [int(round(v)) for v in (bx1, by1, bx2, by2)]
        if bx2i <= bx1i or by2i <= by1i:
            continue
        item = {
            "label": "leaf",
            "confidence": float(_clip01(c)),
            "box": [bx1i, by1i, bx2i, by2i],
            "box_norm": [
                round(bx1i / orig_w, 4),
                round(by1i / orig_h, 4),
                round(bx2i / orig_w, 4),
                round(by2i / orig_h, 4),
            ],
        }
        if is_leaf_like(img_rgb, item["box"]):
            boxes.append(item)

    dlog(
        f"🌿 YOLO kept {len(boxes)} leaf-like boxes "
        f"(raw={len(xyxy)}) — sample={boxes[0]['box'] if boxes else 'None'}"
    )
    return boxes


def enhance_for_ocr(
    img_rgb: np.ndarray,
    detections: List[Dict[str, Any]],
    k: int = 3,
) -> np.ndarray:
    """
    Lightweight enhancement: used only for preview and OCR-like clarity.
    GPU mode disabled unless DEBUG_MODE=1.
    """
    if not detections:
        return img_rgb

    try:
        dev = ort.get_device().upper()
    except Exception:
        dev = "CPU"

    if dev == "GPU" and os.getenv("DEBUG_MODE", "0") != "1":
        return img_rgb

    h, w = img_rgb.shape[:2]
    out = img_rgb.copy()

    dets = sorted(detections, key=lambda d: d["confidence"], reverse=True)[: max(1, k)]

    for d in dets:
        x1, y1, x2, y2 = d["box"]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w - 1, x2), min(h - 1, y2)
        roi = out[y1:y2, x1:x2]
        if roi.size == 0:
            continue

        gray = cv2.cvtColor(roi, cv2.COLOR_RGB2GRAY)
        clahe = cv2.createCLAHE(clipLimit=1.2, tileGridSize=(8, 8))
        enh = clahe.apply(gray)
        enh = np.clip((enh.astype(np.float32) / 255.0) ** 0.97 * 255.0, 0, 255).astype(np.uint8)
        out[y1:y2, x1:x2] = cv2.cvtColor(enh, cv2.COLOR_GRAY2RGB)

    return out


# ---------------------------------------------------------------------------
# Core inference pipeline (Upgraded v9.2 — now READY for index comparison)
# ---------------------------------------------------------------------------

def run_inference_pipeline(
    img_rgb: np.ndarray,
    yolo_tensor: np.ndarray,
    meta: Tuple[int, int, float, int, int, float],
    mode: str,
    lang_hint: str,
) -> Dict[str, Any]:

    t0 = time.time()

    conf_now, iou_now = meta[-1], IOU_THRESH

    # ------------------------------
    # 1. YOLO
    # ------------------------------
    t_yolo0 = time.time()
    yolo_outs = yolo_sess.run([yolo_out], {yolo_in: yolo_tensor})
    t_yolo1 = time.time()

    detections = postprocess(yolo_outs, img_rgb, meta, iou_now)
    stabilized = smooth_boxes(detections) if detections else []

    h, w = img_rgb.shape[:2]
    if detections:
        xs1 = [d["box"][0] for d in detections]
        ys1 = [d["box"][1] for d in detections]
        xs2 = [d["box"][2] for d in detections]
        ys2 = [d["box"][3] for d in detections]
        merged_box = [int(min(xs1)), int(min(ys1)), int(max(xs2)), int(max(ys2))]
        merged_box_norm = [
            merged_box[0] / w,
            merged_box[1] / h,
            merged_box[2] / w,
            merged_box[3] / h,
        ]
    else:
        merged_box = None
        merged_box_norm = None

    enhanced_full = enhance_for_ocr(img_rgb, detections, k=3)

    # ------------------------------
    # 2. CNN FULL-FRAME CLASSIFICATION
    # ------------------------------
    t_cnn0 = time.time()
    raw_probs, raw_label, raw_conf = classify_roi(img_rgb)
    t_cnn1 = time.time()

    # Live smoothing (camera only)
    if mode in ["multipart", "raw"]:
        smoothed_probs = smooth_classification(raw_probs)
    else:
        smoothed_probs = raw_probs

    if smoothed_probs is not None:
        idx = int(np.argmax(smoothed_probs))
        cnn_label = CNN_CLASSES[idx]
        cnn_conf = float(_clip01(smoothed_probs[idx]))
    else:
        cnn_label, cnn_conf = raw_label, raw_conf

    # ------------------------------
    # 3. SECOND-PASS INDEXED DB CHECK
    # ------------------------------
    index_label, index_conf = query_index_from_probs(smoothed_probs)

    final_label, final_conf, source = choose_best_label(
        cnn_label, cnn_conf,
        index_label, index_conf
    )

    # ------------------------------
    # 4. GEMINI ADVICE
    # ------------------------------
    t_gem0 = time.time()
    lang_key = (lang_hint or "auto").lower()
    gemini_text = "Gemini not configured."

    if gemini_model is not None:
        bucket = int(final_conf * 20)
        key = (final_label, bucket, lang_key)
        now_ts = time.time()

        with _gem_cache_lock:
            cached = _gem_cache.get(key)
            if cached and (now_ts - cached["ts"] <= _gem_cache_ttl):
                gemini_text = cached["text"]
            else:
                gemini_text = generate_gemini_recommendation(final_label, final_conf, lang_key)
                _gem_cache[key] = {"text": gemini_text, "ts": now_ts}

    t_gem1 = time.time()

    # ------------------------------
    # 5. ENCODE PREVIEW
    # ------------------------------
    _, buf_enh = cv2.imencode(
        ".jpg",
        cv2.cvtColor(enhanced_full, cv2.COLOR_RGB2BGR),
        [int(cv2.IMWRITE_JPEG_QUALITY), 70],
    )
    b64_enh = base64.b64encode(buf_enh).decode("utf-8")

    mean_conf = float(np.mean([d["confidence"] for d in detections])) if detections else 0.0
    auto_capture_suggested = bool(mean_conf >= 0.60)

    total_ms = int((time.time() - t0) * 1000)

    # ------------------------------
    # 6. FINAL RESPONSE
    # ------------------------------

    result: Dict[str, Any] = {
        "success": True,
        "intake_mode": mode,
        "source_w": int(w),
        "source_h": int(h),

        "detections": detections,
        "stabilized_detections": stabilized,
        "merged_box": merged_box,
        "merged_box_norm": merged_box_norm,

        # CNN + Index output
        "cnn_label_raw": raw_label,
        "cnn_conf_raw": raw_conf,
        "cnn_label_smoothed": cnn_label,
        "cnn_conf_smoothed": cnn_conf,

        "index_label": index_label,
        "index_confidence": index_conf,

        "final_label": final_label,
        "final_confidence": final_conf,
        "final_source": source,   # "live_only" or "index"

        "gemini_advice": gemini_text,

        "no_leaf_detected": not bool(detections),
        "enhanced_b64": b64_enh,

        "auto_capture_suggested": auto_capture_suggested,
        "suggested_delay_ms": 3000,

        "total_time_ms": total_ms,
        "timing": {
            "yolo_ms": int((t_yolo1 - t_yolo0) * 1000),
            "cnn_ms": int((t_cnn1 - t_cnn0) * 1000),
            "gemini_ms": int((t_gem1 - t_gem0) * 1000),
        },
    }

    log(
        f"✅ Inference ({mode}) {total_ms} ms | "
        f"raw={raw_label}@{raw_conf:.2f} | "
        f"final={final_label}@{final_conf:.2f} ({source}) | "
        f"det={len(detections)}"
    )

    return result

# ---------------------------------------------------------------------------
# BLOCK 2: DATABASE LOADERS (Fixed for List-of-Dicts format)
# ---------------------------------------------------------------------------

indexed_vectors: Optional[np.ndarray] = None
indexed_labels: Optional[np.ndarray] = None
_index_loaded_ok: bool = False

def load_indexed_database() -> None:
    global indexed_vectors, indexed_labels, _index_loaded_ok
    
    _index_loaded_ok = False
    if not os.path.exists(INDEX_DB_PATH):
        log(f"ℹ️ Database not found at {INDEX_DB_PATH} — refinement disabled.")
        return

    try:
        with open(INDEX_DB_PATH, "rb") as f:
            data = pickle.load(f)
            
        # SCENARIO A: User's Format (List of Dictionaries)
        if isinstance(data, list) and len(data) > 0 and "vector" in data[0]:
            log(f"📂 Detected List-based database with {len(data)} entries.")
            try:
                # Extract columns
                vec_list = [item["vector"] for item in data]
                lbl_list = [item["label"] for item in data]
                
                # Stack into NumPy arrays
                vectors = np.array(vec_list, dtype=np.float32)
                labels = np.array(lbl_list)
            except Exception as e:
                log(f"❌ Error parsing list structure: {e}")
                return

        # SCENARIO B: Alternative Format (Dictionary of Arrays)
        elif isinstance(data, dict) and "vectors" in data and "labels" in data:
            vectors = np.asarray(data["vectors"], dtype=np.float32)
            labels = np.asarray(data["labels"])
            
        else:
            log("⚠️ Database file format not recognized (must be list of dicts or dict of arrays).")
            return

        # Normalize vectors for Cosine Similarity
        # (Divides every vector by its length so dot product = cosine similarity)
        norms = np.linalg.norm(vectors, axis=1, keepdims=True) + 1e-9
        indexed_vectors = vectors / norms
        indexed_labels = labels
        _index_loaded_ok = True
        
        log(f"✅ Database loaded successfully: {len(labels)} entries.")

    except Exception as e:
        log(f"❌ Failed to load database file: {e}")

def query_index_from_probs(probs: Optional[np.ndarray]) -> Tuple[Optional[str], float]:
    """
    Compares the live CNN output (probs) against the loaded database.
    Returns: (Best Label, Confidence Score)
    """
    if not _index_loaded_ok or probs is None or indexed_vectors is None:
        return None, 0.0

    try:
        # 1. Convert probabilities to a vector (Basic Embedding)
        # Ideally, use the dense layer output, but probs work for basic refinement.
        q = np.asarray(probs, dtype=np.float32).reshape(-1)
        
        # 2. Normalize the query vector
        q_norm = np.linalg.norm(q) + 1e-9
        q = q / q_norm

        # 3. Check shapes
        if indexed_vectors.shape[1] != q.shape[0]:
            dlog(f"Shape mismatch: DB={indexed_vectors.shape[1]} vs Query={q.shape[0]}")
            return None, 0.0

        # 4. Fast Cosine Similarity (Matrix Multiplication)
        sims = indexed_vectors @ q
        
        # 5. Find the best match
        best_idx = int(np.argmax(sims))
        best_sim = float(sims[best_idx])

        # 6. Convert similarity (-1 to 1) to confidence (0 to 1)
        conf = (best_sim + 1.0) / 2.0
        
        if conf < INDEX_DB_MIN_SIM:
            return None, conf

        return str(indexed_labels[best_idx]), conf

    except Exception as e:
        log(f"⚠️ Vector query error: {e}")
        return None, 0.0

# ---------------------------------------------------------------------------
# BLOCK 3: STARTUP EVENT
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup():
    global yolo_sess, yolo_in, yolo_out, cnn_sess, cnn_in, cnn_out, gemini_model
    
    log("🔄 Starting CropEye Backend...")
    
    # 1. Load Models
    yolo_sess, yolo_in, yolo_out = load_onnx_model(YOLO_MODEL_PATH, "YOLO")
    cnn_sess, cnn_in, cnn_out = load_onnx_model(CNN_MODEL_PATH, "CNN")
    
    # 2. Load Database (The Critical Fix)
    load_indexed_database()
    
    # 3. Initialize Gemini
    if GEMINI_API_KEY:
        try:
            genai.configure(api_key=GEMINI_API_KEY)
            gemini_model = genai.GenerativeModel("models/gemini-2.5-flash")
            log("✅ Gemini Ready")
        except: 
            log("⚠️ Gemini Failed")

    # 4. Start Idle Timer
    if ALLOW_IDLE_EXIT:
        threading.Thread(target=_idle_reaper, daemon=True).start()

# ---------------------------------------------------------------------------
# Warmup helpers
# ---------------------------------------------------------------------------

async def run_warmup_once() -> Dict[str, Any]:
    """
    Runs a single warmup pass for YOLO (IMG_SIZE) and CNN (CNN_INPUT_SIZE).
    Ensures shapes match the models to avoid crashes.
    """
    global _warmup_complete

    if _warmup_complete:
        return {"ok": True, "msg": "already warm"}

    with _warmup_lock:
        if _warmup_complete:
            return {"ok": True, "msg": "already warm (locked)"}

        if yolo_sess is None and cnn_sess is None:
            log("⚠️ Warmup skipped: both YOLO and CNN sessions are None.")
            return {"ok": False, "error": "models_not_loaded"}

        try:
            t0 = time.time()
            log("🔥 Warmup: starting…")

            # YOLO warmup (IMG_SIZE, e.g. 640)
            if yolo_sess is not None:
                dummy = np.zeros((1, 3, IMG_SIZE, IMG_SIZE), dtype=np.float32)
                _ = yolo_sess.run([yolo_out], {yolo_in: dummy})

            # CNN warmup (CNN_INPUT_SIZE, e.g. 224)
            if cnn_sess is not None:
                dummy_cnn = np.zeros(
                    (1, 3, CNN_INPUT_SIZE, CNN_INPUT_SIZE), dtype=np.float32
                )
                _ = cnn_sess.run([cnn_out], {cnn_in: dummy_cnn})

            _warmup_complete = True
            dt = int((time.time() - t0) * 1000)
            log(f"🔥 Warmup completed in {dt} ms")
            return {"ok": True, "time_ms": dt}
        except Exception as e:
            log(f"❌ Warmup failed: {e}")
            return {"ok": False, "error": str(e)}


# ---------------------------------------------------------------------------
# DEBUG ENDPOINTS (place these BEFORE /ping)
# ---------------------------------------------------------------------------

@app.get("/debug_ort")
def debug_ort():
    import onnxruntime as ort
    try:
        return {
            "available_providers": ort.get_available_providers(),
            "default_device": ort.get_device(),
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/torchinfo")
def torchinfo():
    import torch
    return {
        "torch_version": torch.__version__,
        "cuda_available": torch.cuda.is_available(),
        "cuda_device_count": torch.cuda.device_count(),
        "device_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    }


@app.get("/sysinfo")
def sysinfo():
    import subprocess, os
    return {
        "env": {
            "LD_LIBRARY_PATH": os.environ.get("LD_LIBRARY_PATH"),
            "NVIDIA_VISIBLE_DEVICES": os.environ.get("NVIDIA_VISIBLE_DEVICES"),
            "NVIDIA_DRIVER_CAPABILITIES": os.environ.get("NVIDIA_DRIVER_CAPABILITIES"),
        },
        "cuda_usr_local": subprocess.getoutput("ls -l /usr/local/cuda/lib64"),
        "cuda_usr_lib": subprocess.getoutput("ls -l /usr/lib/x86_64-linux-gnu | grep cuda"),
    }


# ---------------------------------------------------------------------------
# EXTRA GPU/ORT DEBUG ENDPOINTS
# ---------------------------------------------------------------------------

@app.get("/providers")
def providers():
    return {
        "yolo_providers": yolo_sess.get_providers() if yolo_sess else None,
        "cnn_providers": cnn_sess.get_providers() if cnn_sess else None,
    }


@app.get("/provider_details")
def provider_details():
    try:
        return {
            "available_providers": ort.get_available_providers(),
            "default_device": ort.get_device(),
            "yolo_session_providers": yolo_sess.get_providers() if yolo_sess else None,
            "cnn_session_providers": cnn_sess.get_providers() if cnn_sess else None,
            "yolo_provider_options": yolo_sess.get_provider_options() if yolo_sess else None,
            "cnn_provider_options": cnn_sess.get_provider_options() if cnn_sess else None,
            "using_cuda": "CUDAExecutionProvider" in (yolo_sess.get_providers() if yolo_sess else []),
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/session_info")
def session_info():
    try:
        return {
            "yolo_inputs": [i.name for i in yolo_sess.get_inputs()] if yolo_sess else None,
            "yolo_outputs": [o.name for o in yolo_sess.get_outputs()] if yolo_sess else None,
            "cnn_inputs": [i.name for i in cnn_sess.get_inputs()] if cnn_sess else None,
            "cnn_outputs": [o.name for o in cnn_sess.get_outputs()] if cnn_sess else None,
            "yolo_provider_options": yolo_sess.get_provider_options() if yolo_sess else None,
            "cnn_provider_options": cnn_sess.get_provider_options() if cnn_sess else None,
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/cuda_test")
def cuda_test():
    """
    Uses IMG_SIZE for YOLO warm test to avoid shape mismatch.
    """
    try:
        import numpy as np

        dummy = np.random.rand(1, 3, IMG_SIZE, IMG_SIZE).astype("float32")
        out = yolo_sess.run([yolo_out], {yolo_in: dummy})
        return {
            "success": True,
            "provider": yolo_sess.get_providers() if yolo_sess else None,
            "output_shape": out[0].shape,
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "provider": yolo_sess.get_providers() if yolo_sess else None,
        }


@app.get("/gpu_dmesg")
def gpu_dmesg():
    import subprocess
    try:
        return {"dmesg": subprocess.getoutput("dmesg | grep -i nvrm | tail -n 50")}
    except Exception as e:
        return {"error": str(e)}


@app.get("/libcheck")
def libcheck():
    import subprocess
    try:
        return {
            "usr_lib_cuda": subprocess.getoutput(
                "ls -l /usr/lib/x86_64-linux-gnu | grep cuda"
            ),
            "local_cuda_lib64": subprocess.getoutput("ls -l /usr/local/cuda/lib64"),
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/meminfo")
def meminfo():
    import subprocess
    try:
        return {"nvidia_smi": subprocess.getoutput("nvidia-smi")}
    except Exception as e:
        return {"error": str(e)}


@app.get("/debug/deep_scan")
def deep_scan():
    """
    Physical scan of the container to find where CUDA libraries are located
    and whether they can be loaded via ctypes.
    """
    import subprocess

    # 1. Environment
    env_vars = {
        "LD_LIBRARY_PATH": os.environ.get("LD_LIBRARY_PATH", ""),
        "CUDA_VISIBLE_DEVICES": os.environ.get("NVIDIA_VISIBLE_DEVICES", "Not Set"),
        "PATH": os.environ.get("PATH", ""),
    }

    # 2. Hunt for key CUDA libraries on disk
    search_paths = [
        "/usr/lib",
        "/usr/local/lib",
        "/usr/local/cuda/lib64",
        "/usr/local/nvidia/lib",
        "/usr/local/nvidia/lib64",
    ]

    found_libs: List[str] = []
    for base in search_paths:
        if os.path.exists(base):
            for root, dirs, files in os.walk(base):
                for f in files:
                    if "libcudnn" in f or "libcublas" in f:
                        found_libs.append(os.path.join(root, f))
                # shallow walk for speed
                if root.count(os.sep) - base.count(os.sep) > 2:
                    del dirs[:]

    # 3. CTypes load test
    load_test: Dict[str, str] = {}
    target_libs = ["libcudnn.so.8", "libcublas.so.11", "libcudart.so.11"]

    if "12" in str(os.environ.get("LD_LIBRARY_PATH", "")):
        target_libs.extend(["libcublas.so.12", "libcudart.so.12"])

    for lib in target_libs:
        try:
            ctypes.cdll.LoadLibrary(lib)
            load_test[lib] = "OK"
        except Exception as e:
            load_test[lib] = f"FAILED: {e}"

    return {
        "environment": env_vars,
        "found_libraries_on_disk": found_libs[:50],
        "ctypes_load_test": load_test,
        "onnx_load_errors": load_errors,
    }


@app.get("/gpu_failure_reason")
def gpu_failure_reason():
    import onnxruntime
    return {
        "ort_detected_providers": onnxruntime.get_available_providers(),
        "exact_load_errors": load_errors,
        "environment": {
            "LD_LIBRARY_PATH": os.environ.get("LD_LIBRARY_PATH"),
            "CUDA_VISIBLE_DEVICES": os.environ.get("NVIDIA_VISIBLE_DEVICES"),
        },
    }

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/ping")
async def ping() -> Dict[str, Any]:
    _update_last_request()
    return {
        "status": "ok",
        "time": datetime.now(timezone.utc).isoformat(),
        "uptime_sec": int(time.time() - _last_req_ts),
    }


@app.get("/gpuinfo")
async def gpuinfo() -> Dict[str, Any]:
    try:
        dev = ort.get_device()
    except Exception as e:
        dev = f"error: {e}"
    providers: List[str] = []
    try:
        if yolo_sess is not None:
            providers = yolo_sess.get_providers()
    except Exception:
        pass
    return {
        "ort_device": dev,
        "providers": providers,
        "cpu_count": CPU_COUNT,
    }


@app.post("/warmup")
@app.get("/warmup")
async def warmup() -> Dict[str, Any]:
    _update_last_request()
    return await run_warmup_once()


@app.get("/healthz")
async def healthz() -> Dict[str, Any]:
    _update_last_request()
    return {
        "yolo_loaded": yolo_sess is not None,
        "cnn_loaded": cnn_sess is not None,
        "warmup_completed": _warmup_complete,
    }


@app.get("/debug")
async def debug_info() -> Dict[str, Any]:
    _update_last_request()
    try:
        recent = ""
        log_path = os.path.join(LOG_DIR, "server.log")
        if os.path.exists(log_path):
            with open(log_path, encoding="utf-8") as f:
                recent = f.read()[-1800:]
        return {
            "yolo_loaded": yolo_sess is not None,
            "cnn_loaded": cnn_sess is not None,
            "gemini_ready": gemini_model is not None,
            "warmup_completed": _warmup_complete,
            "cpu_count": CPU_COUNT,
            "recent_log": recent,
        }
    except Exception as e:
        return {"error": str(e)}


@app.post("/chat")
async def chat(request: Request) -> JSONResponse:
    _update_last_request()
    try:
        if gemini_model is None:
            raise HTTPException(status_code=500, detail="Gemini not configured")

        data = await request.json()
        user_msg: str = (data.get("message") or "").trim()
    except AttributeError:
        data = await request.json()
        user_msg = (data.get("message") or "").strip()

    context: str = (data.get("context") or "").strip()
    lang_override: str = (data.get("lang") or "").lower()

    if not user_msg:
        raise HTTPException(status_code=400, detail="Empty message")

    lang = lang_override if lang_override in ("en", "ar") else detect_lang_from_text(user_msg, default="ar")

    if lang == "ar":
        prompt = f"""
أنت CropEye، مساعد ذكاء اصطناعي زراعي متخصص في الطماطم ودودة Tuta absoluta، ويمكنك أيضًا الإجابة عن أسئلة عامة إذا طلب المستخدم ذلك.

سياق الحوار السابق (إن وجد):
{context}

رسالة المستخدم:
"{user_msg}"

التعليمات المهمة:
1) أجب بالعربية الفصحى البسيطة فقط.
2) لا تخلط العربية والإنجليزية في نفس الجملة إلا للأسماء أو المصطلحات الضرورية.
3) لا تستخدم أي تنسيق ماركداون ولا علامات مثل * أو - أو • أو #.
4) اجعل الإجابة منظمة وواضحة، ويمكنك استخدام أسطر مرقمة بالشكل 1) 2) 3).
5) إذا كان السؤال عامًا (ليس عن الزراعة فقط)، تعامل معه بشكل طبيعي كمحادثة عادية ولكن حافظ على نفس الأسلوب المنظم.
"""
    else:
        prompt = f"""
You are CropEye, an AI assistant. Your main focus is tomatoes and Tuta absoluta management, but you can also chat normally and answer general questions if the user wants.

Previous context (if any):
{context}

User message:
"{user_msg}"

Important instructions:
1) Answer ONLY in clear English.
2) Do NOT mix Arabic and English in the same sentence.
3) Do NOT use markdown formatting and do NOT use symbols like *, -, •, or #.
4) Keep the answer organized and readable. You may use simple numbered lines like 1) 2) 3).
5) If the question is general and not about farming, respond like a normal helpful assistant but still follow the same clean style.
"""
    try:
        resp = gemini_model.generate_content(prompt.strip())
        reply = (getattr(resp, "text", "") or "").strip()
        log(f"💬 LLM chat | lang={lang} | msg='{user_msg[:70]}…'")
        return JSONResponse({"reply": reply, "lang": lang})
    except Exception as e:
        log(f"❌ /chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/detect")
async def detect(request: Request):
    """
    Main inference endpoint used by the Flutter live camera.
    CRASH-PROOF VERSION: Handles bad frames without killing the connection.
    """
    _update_last_request()
    try:
        # 1. Safe Data Reading
        body = await request.body()
        if not body:
            return JSONResponse({"success": False, "error": "Empty Body"}, status_code=400)
        
        ct = request.headers.get("content-type", "")
        img_bytes = None

        # Handle all 3 input types safely
        if "multipart" in ct:
            form = await request.form()
            if "image" in form:
                img_bytes = await form["image"].read()
        elif "json" in ct:
            data = await request.json()
            b64 = data.get("image_b64", "")
            if "," in b64: b64 = b64.split(",")[1]
            img_bytes = base64.b64decode(b64)
        else:
            img_bytes = body # Raw bytes

        if not img_bytes:
             return JSONResponse({"success": False, "error": "No Image"}, status_code=400)

        # 2. Preprocess (Decodes image + resizes for YOLO)
        img_rgb, tensor, meta = preprocess_image_bytes(img_bytes)
        
        # 3. Warmup if needed (prevents first-request lag)
        if not _warmup_complete: 
            await run_warmup_once()
        
        # 4. Run Pipeline (YOLO + Center-Focus CNN)
        loop = asyncio.get_running_loop()
        # Detect language from query param
        lang = (request.query_params.get("lang") or "auto").lower()
        
        # Execute in thread pool to keep server responsive
        res = await loop.run_in_executor(
            None, 
            lambda: run_inference_pipeline(img_rgb, tensor, meta, mode="live", lang_hint=lang)
        )
        return res

    except ValueError as ve:
        # ⚠️ THE FIX: We return a JSON error, we DO NOT crash the socket.
        # This stops "BufferQueue Abandoned" errors on the phone.
        return JSONResponse({"success": False, "error": f"Bad Image: {ve}"}, status_code=400)
        
    except Exception as e:
        log(f"🔥 Detect Error: {e}")
        return JSONResponse({"success": False, "error": "Server Error"}, status_code=500)

@app.post("/detect_base64")
async def detect_base64(request: Request) -> JSONResponse:
    """
    LLMPage endpoint. 
    Triggered when "Auto-Capture" is successful.
    Performs: Final Classification & Database Index Check (Future).
    """
    _update_last_request()

    if yolo_sess is None:
        raise HTTPException(status_code=500, detail="YOLO not loaded")

    if not _warmup_complete:
        warm_status = await run_warmup_once()
        if not warm_status.get("ok", False):
            raise HTTPException(status_code=500, detail="Model warmup failed")

    data = await request.json()
    img_b64 = (data.get("image_b64") or "").strip()
    if not img_b64:
        raise HTTPException(status_code=400, detail="No image_b64 provided")
    if "," in img_b64 and "base64" in img_b64.split(",", 1)[0]:
        img_b64 = img_b64.split(",", 1)[1]
    try:
        img_bytes = base64.b64decode(img_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image")

    try:
        img_rgb, yolo_tensor, meta = preprocess_image_bytes(img_bytes)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    lang_hint = (request.query_params.get("lang") or "auto").lower()
    loop = asyncio.get_running_loop()
    
    # Note: In the future, if you add vector search, insert logic here 
    # to load leaf_index.pkl and compare vectors before returning result.
    
    result = await loop.run_in_executor(
        None,
        lambda: run_inference_pipeline(img_rgb, yolo_tensor, meta, "json_b64", lang_hint),
    )
    return JSONResponse(result)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


@app.get("/")
async def index() -> Dict[str, Any]:
    return {"message": "CropEye FastAPI backend is running."}

# ============================================================================
# 🔥 BONUS DEBUG ROUTES (SAFE — DO NOT MODIFY ANY EXISTING ROUTES)
# ============================================================================

import psutil, subprocess, threading


@app.get("/debug/env_full")
async def debug_env_full():
    """Show ALL environment variables"""
    return dict(os.environ)


@app.get("/debug/onnx_providers")
async def debug_onnx_providers():
    """Check ONNX provider availability and active sessions."""
    return {
        "available": ort.get_available_providers(),
        "runtime_device": ort.get_device(),
        "yolo": yolo_sess.get_providers() if yolo_sess else None,
        "cnn": cnn_sess.get_providers() if cnn_sess else None,
        "errors": load_errors,
    }


@app.get("/debug/model_io")
async def debug_model_io():
    """Inspect YOLO/CNN input-output tensor signatures."""
    return {
        "yolo_inputs": [i.__dict__ for i in yolo_sess.get_inputs()] if yolo_sess else None,
        "yolo_outputs": [o.__dict__ for o in yolo_sess.get_outputs()] if yolo_sess else None,
        "cnn_inputs": [i.__dict__ for i in cnn_sess.get_inputs()] if cnn_sess else None,
        "cnn_outputs": [o.__dict__ for o in cnn_sess.get_outputs()] if cnn_sess else None,
    }


@app.get("/debug/sysinfo_full")
async def debug_sysinfo_full():
    """Full system scan (RAM, CPU, disk, load, threads)."""
    return {
        "cpu_count": psutil.cpu_count(),
        "cpu_percent": psutil.cpu_percent(interval=0.5),
        "ram_percent": psutil.virtual_memory().percent,
        "ram_used_MB": round(psutil.virtual_memory().used / 1048576, 2),
        "ram_total_MB": round(psutil.virtual_memory().total / 1048576, 2),
        "disk_usage_GB": {
            "used": round(psutil.disk_usage('/').used / 1e9, 2),
            "total": round(psutil.disk_usage('/').total / 1e9, 2)
        },
        "threads": len(threading.enumerate()),
        "python_version": sys.version,
        "working_dir": os.getcwd(),
    }


@app.get("/debug/files")
async def debug_files():
    """List important directories in container."""
    listing = {}
    for d in ["/", "/app", "/app/models", "/usr/local/cuda/lib64",
              "/usr/local/nvidia/lib64", "/usr/lib/x86_64-linux-gnu"]:
        try:
            listing[d] = os.listdir(d)
        except:
            listing[d] = "NOT ACCESSIBLE"
    return listing


@app.get("/debug/dependencies")
async def debug_dependencies():
    """Dump pip list to verify dependency versions."""
    try:
        output = subprocess.getoutput("pip list")
        return {"pip_list": output}
    except Exception as e:
        return {"error": str(e)}


@app.get("/debug/ctypes_libs")
async def debug_ctypes_libs():
    """Try loading CUDA/CUDNN libraries manually."""
    test_libs = [
        "libcudart.so", "libcudart.so.11", "libcudnn.so.8",
        "libcublas.so.11", "libcublasLt.so.11"
    ]
    results = {}
    for lib in test_libs:
        try:
            ctypes.cdll.LoadLibrary(lib)
            results[lib] = "OK"
        except Exception as e:
            results[lib] = f"FAILED: {e}"
    return results


@app.get("/debug/nvidia")
async def debug_nvidia():
    """Check GPU presence (Cloud Run sometimes disables GPU without warning)."""
    try:
        return {
            "nvidia_smi": subprocess.getoutput("nvidia-smi"),
            "driver": subprocess.getoutput("cat /proc/driver/nvidia/version"),
            "gpus": subprocess.getoutput("nvidia-smi -L")
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/debug/dmesg_gpu")
async def debug_dmesg_gpu():
    """Check Cloud Run kernel NVIDIA logs (GPU crashes)."""
    return {
        "nvrm_logs": subprocess.getoutput("dmesg | grep -i nvrm | tail -n 40")
    }


@app.get("/debug/timing")
async def debug_timing():
    """Quick check YOLO + CNN timing WITHOUT image."""
    try:
        dummy_yolo = np.zeros((1, 3, IMG_SIZE, IMG_SIZE), dtype=np.float32)
        dummy_cnn = np.zeros((1, 3, CNN_INPUT_SIZE, CNN_INPUT_SIZE), dtype=np.float32)

        t0 = time.time()
        y_out = yolo_sess.run([yolo_out], {yolo_in: dummy_yolo})
        t1 = time.time()
        c_out = cnn_sess.run([cnn_out], {cnn_in: dummy_cnn})
        t2 = time.time()

        return {
            "yolo_ms": int((t1 - t0) * 1000),
            "cnn_ms": int((t2 - t1) * 1000),
            "providers": yolo_sess.get_providers(),
        }
    except Exception as e:
        return {"error": str(e)}


@app.get("/debug/full_diagnosis")
async def debug_full_diagnosis():
    """
    🔥 MASTER DEBUG — RUNS EVERYTHING
    """
    return {
        "ENV": await debug_env_full(),
        "ONNX": await debug_onnx_providers(),
        "MODEL_IO": await debug_model_io(),
        "SYSTEM": await debug_sysinfo_full(),
        "FILES": await debug_files(),
        "CTYPES": await debug_ctypes_libs(),
        "NVIDIA": await debug_nvidia(),
        "DMESG": await debug_dmesg_gpu(),
    }
