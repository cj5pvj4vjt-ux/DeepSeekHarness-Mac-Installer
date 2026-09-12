#!/bin/bash
# =============================================================================
# build-all.sh — 从原始 .app 一键产出新 DMG
#
# 用法：./build-all.sh "<原始 DeepSeek Harness.app>" "<原始安装器.app>" <输出目录> [版本号]
# 环境变量：
#   DSH_RUNTIME_SRC   可选。用指定目录的 dsh 安装替换内嵌 runtime/dsh
#   APP_VERSION       可选。等价于第 4 个参数
#
# 例（用本机全局 dsh 作为内嵌运行时，产出 v0.3.0）：
#   DSH_RUNTIME_SRC=/opt/homebrew/lib/node_modules/@deepseek-ai/dsh \
#     ./build-all.sh "DeepSeek Harness.app" "安装 DeepSeek Harness.app" ./out 0.3.0
# =============================================================================
set -euo pipefail

SRC_APP="${1:?用法: $0 <原始 DeepSeek Harness.app> <安装器.app> <输出目录> [版本号]}"
SRC_INSTALLER="${2:?}"
OUT_DIR="${3:?}"
VERSION="${4:-${APP_VERSION:-0.3.0}}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DMG="$OUT_DIR/DeepSeekHarness-$VERSION.dmg"

echo ">>> [1/4] 组装并修复 app（源码覆盖 + 种子 + preset + runtime + 自包含 + 重签）"
"$HERE/build-app.sh" "$SRC_APP" "$OUT_DIR" "$VERSION"

echo ">>> [2/4] 打包 DMG → $(basename "$DMG")"
"$HERE/build-dmg.sh" "$SRC_INSTALLER" "$OUT_DIR/DeepSeek Harness.app" "$DMG"

echo ">>> [3/4] 生成 sha256"
( cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
cat "$OUT_DIR/$(basename "$DMG").sha256"

echo ">>> [4/4] 收尾"
echo "输出: $DMG"
echo "下一步: 上传 GitHub Releases 分发 / 直接拷贝给朋友"
