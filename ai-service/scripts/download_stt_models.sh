#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${ROOT_DIR}/models/sherpa"
ARCHIVE="/tmp/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2"
VAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

mkdir -p "${MODEL_DIR}"
curl -L --fail --retry 3 "${URL}" -o "${ARCHIVE}"
tar -xjf "${ARCHIVE}" -C "${MODEL_DIR}"
curl -L --fail --retry 3 "${VAD_URL}" -o "${MODEL_DIR}/silero_vad.onnx"
rm -f "${ARCHIVE}"

echo "Sherpa Zipformer model installed in ${MODEL_DIR}"
