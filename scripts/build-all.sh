#!/bin/bash
# =============================================================================
# build-all.sh — 从原始 .app 一键产出新 DMG
# 用法：./build-all.sh "<原始 DeepSeek Harness.app>" "<原始安装器.app>" <输出目录>
# =============================================================================
set -euo pipefail

SRC_APP="${1:?用法: $0 <原始 DeepSeek Harness.app> <安装器.app> <输出目录>}"
SRC_INSTALLER="${2:?}"
OUT_DIR="${3:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo ">>> [1/3] 组装并修复 app（种子 + preset + 自包含 runtime + 重签）"
"$HERE/build-app.sh" "$SRC_APP" "$OUT_DIR"

echo ">>> [2/3] 打包 DMG"
"$HERE/build-dmg.sh" "$SRC_INSTALLER" "$OUT_DIR/DeepSeek Harness.app" \
    "$OUT_DIR/DeepSeekHarness.dmg"

echo ">>> [3/3] 收尾"
echo "输出: $OUT_DIR/DeepSeekHarness.dmg"
echo "下一步: 上传 GitHub Releases 分发 / 直接拷贝给朋友"