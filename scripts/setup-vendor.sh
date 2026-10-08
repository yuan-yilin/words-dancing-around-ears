#!/usr/bin/env bash
# 从 vendor-downloads/ 手动下载的官方 release 包, 搭建 Packages/Core/Vendor 本地二进制依赖。
# 前置: 手动下载 4 个 zip 放入 vendor-downloads/ (地址见 README.md 或 PLAN.md)。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DL="$ROOT/vendor-downloads"
VENDOR="$ROOT/Packages/Core/Vendor"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

declare -a MAP=(
  "sherpa-onnx-v1.13.8-macos-static:SherpaOnnxMacOS"
  "sherpa-onnx-v1.13.8-ios-static:SherpaOnnxIOS"
  "onnxruntime-macos-static-xcframework-1.28.2:OnnxruntimeMacOS"
  "onnxruntime-ios-static-xcframework-1.28.2:OnnxruntimeIOS"
)

# 官方 Package.swift 中的 checksum, 用于校验手动下载的文件
declare -A CHECKSUMS=(
  ["sherpa-onnx-v1.13.8-macos-static"]="93f7a064abe99e0d6185a88c5b36ce18c4bff35cd0d5e4e81f81151de8e3e7e5"
  ["sherpa-onnx-v1.13.8-ios-static"]="6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de"
  ["onnxruntime-macos-static-xcframework-1.28.2"]="cb0b0bec912c77229517c463e28a3fac9674c521f9599919efff1ef2b42f3da0"
  ["onnxruntime-ios-static-xcframework-1.28.2"]="2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599"
)

for entry in "${MAP[@]}"; do
  src="${entry%%:*}"; dst="${entry##*:}"
  zip="$DL/${src}.xcframework.zip"
  if [ ! -f "$zip" ]; then
    echo "✗ 缺少 $zip" >&2; exit 1
  fi
  echo "==> 校验 ${src}.zip"
  actual=$(shasum -a 256 "$zip" | cut -d' ' -f1)
  expected="${CHECKSUMS[$src]}"
  if [ "$actual" != "$expected" ]; then
    echo "✗ checksum 不匹配: $zip" >&2
    echo "  期望: $expected" >&2
    echo "  实际: $actual" >&2
    exit 1
  fi
  rm -rf "$TMP"/*
  unzip -q -o "$zip" -d "$TMP"
  fw=$(ls "$TMP" | head -1)
  rm -rf "$VENDOR/${dst}.xcframework"
  mkdir -p "$VENDOR"
  mv "$TMP/$fw" "$VENDOR/${dst}.xcframework"
  echo "  ✓ Vendor/${dst}.xcframework"
done

echo "==> 完成。Vendor 目录:"
ls "$VENDOR"
