#!/usr/bin/env bash
# 开发期预置 Kokoro 中英文 TTS 模型到 App 的 Application Support 目录。
# 用法: ./scripts/fetch-model.sh [--dest <目录>]  (默认使用 macOS App 沙盒外的用户级共享目录)
set -euo pipefail

MODEL_NAME="kokoro-multi-lang-v1_0"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MODEL_NAME}.tar.bz2"

# 默认放到用户级目录, macOS App 与 iOS 模拟器调试时通过 ModelManager 的开发重定向读取;
# 也可以用 --dest 指定自定义目录 (例如 App 的 Application Support)
DEST="${2:-$HOME/.local/share/wordsdancing/models}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.model-cache"
mkdir -p "$CACHE_DIR" "$DEST"

if [ ! -d "$CACHE_DIR/$MODEL_NAME" ]; then
  echo "==> 下载 $MODEL_URL (约 330MB, 已缓存则跳过)"
  if [ ! -f "$CACHE_DIR/$MODEL_NAME.tar.bz2" ]; then
    curl -SL --retry 3 -o "$CACHE_DIR/$MODEL_NAME.tar.bz2" "$MODEL_URL"
  fi
  echo "==> 解压中..."
  tar -xjf "$CACHE_DIR/$MODEL_NAME.tar.bz2" -C "$CACHE_DIR"
fi

echo "==> 复制到 $DEST/$MODEL_NAME"
rm -rf "$DEST/$MODEL_NAME"
cp -R "$CACHE_DIR/$MODEL_NAME" "$DEST/$MODEL_NAME"

echo "==> 完成. 模型文件:"
find "$DEST/$MODEL_NAME" -maxdepth 2 -type f | sort | head -20
echo "==> 所需关键文件校验:"
for f in model.onnx voices.bin tokens.txt lexicon-us-en.txt lexicon-zh.txt; do
  if [ -f "$DEST/$MODEL_NAME/$f" ]; then
    echo "  ✓ $f ($(du -h "$DEST/$MODEL_NAME/$f" | cut -f1))"
  else
    echo "  ✗ 缺少 $f" >&2; exit 1
  fi
done
[ -d "$DEST/$MODEL_NAME/espeak-ng-data" ] && echo "  ✓ espeak-ng-data/" || { echo "  ✗ 缺少 espeak-ng-data"; exit 1; }
