# ==========================================================
# CropEye Backend — The "Golden Compat" Build
# Base: CUDA 11.8 + CuDNN 8 (Perfect match for ONNX 1.16)
# ==========================================================

FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Force Clean Path (System libs first)
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"

# 2. System Deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    git wget curl unzip \
    libgl1 libglib2.0-0 tzdata \
    libopenblas-dev liblapack-dev libgomp1 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 3. Python Setup
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip setuptools wheel && \
    python3 -m pip install --no-cache-dir -r /app/requirements.txt

# 4. Install Torch & ONNX (CUDA 11.8 compatible versions)
# We install Torch for CUDA 11.8 specifically to match the container
RUN python3 -m pip install --no-cache-dir \
    torch==2.1.0 torchvision==0.16.0 \
    --index-url https://download.pytorch.org/whl/cu118

# Install the stable ONNX Runtime that matches CUDA 11
RUN python3 -m pip install --no-cache-dir onnxruntime-gpu==1.16.3

# 5. Cleanup Conflicting OpenCV Libs (The ChatGPT Fix)
RUN rm -rf /usr/local/lib/python3.10/dist-packages/cv2/qt/plugins/platforms || true && \
    rm -rf /usr/local/lib/python3.10/dist-packages/cv2/../../lib64 || true

# 6. Config
ENV ORT_TENSORRT_UNAVAILABLE=1
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1 OMP_NUM_THREADS=1
ENV NVIDIA_VISIBLE_DEVICES=all NVIDIA_DRIVER_CAPABILITIES=compute,utility

COPY . /app
EXPOSE 8080
CMD ["python3", "-m", "uvicorn", "cropeye_fastapi:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]