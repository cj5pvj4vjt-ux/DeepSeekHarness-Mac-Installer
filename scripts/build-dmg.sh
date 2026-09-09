#!/bin/bash
# =============================================================================
# build-dmg.sh — 把「DeepSeek Harness.app」+「安装 DeepSeek Harness.app」
# 打包成可双击安装的 UDZO DMG。
#
# 用法：./build-dmg.sh "<安装器.app>" "<DeepSeek Harness.app>" <输出.dmg> [卷名]
# =============================================================================
set -euo pipefail

INSTALLER_APP="${1:?用法: $0 <安装器.app> <DeepSeek Harness.app> <输出.dmg> [卷名]}"
APP="${2:?}"
DMG="${3:?}"
VOLNAME="${4:-DeepSeek Harness}"
HERE="$(cd "$(dirname "$0")" && pwd)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$INSTALLER_APP" "$STAGE/"
cp -R "$APP" "$STAGE/"

echo "== 创建 DMG: $DMG =="
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "完成: $(du -sh "$DMG" | cut -f1)"

echo "== 校验 =="
hdiutil verify "$DMG" 2>&1 | grep -E "checksum|valid|verified" | head -3 || true
echo "可通过: open \"$DMG\" 挂载后双击「安装 DeepSeek Harness.app」"