# Model files

The trained weights are not stored in this repository (they are large binary files). Put them here:

| File | What it is | Setting |
|---|---|---|
| `best_yolo_s.onnx` | YOLOv8s leaf / pest detector, 640 x 640 input | `YOLO_MODEL_PATH` |
| `shufflenetv2_full_precision.onnx` | ShuffleNetV2 severity classifier (healthy / mild / moderate / severe), 224 x 224 input | `CNN_MODEL_PATH` |

Any path works if you set the variable (see `../.env.example`). Without the files the server still starts and
reports which model is missing on `/healthz`.
