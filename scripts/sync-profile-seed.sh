#!/bin/bash
# =============================================================================
# sync-profile-seed.sh
# -----------------------------------------------------------------------------
# 用本机正在运行的 web profile（$DSH_HOME/profiles/web，含全部插件）同步
# .app 内嵌的 profile-seed-web 种子：
#   - package.json / pnpm-lock.yaml / pnpm-workspace.yaml / cordis*.yml
#   - node_modules（pnpm hoisted 布局，符号链接完整保留）
#   - .dsh-market 状态
#
# v0.3.0 起额外做三件事：
#   - 清理悬空符号链接（本机装过又卸掉的插件会留下死链，进了种子会在别人机器上报警）
#   - 校验 patchReload 字段（0.1.5+ 缺这个字段会重置整个 profile，插件全部消失）
#   - 校验 allowBuilds（pnpm 11 缺它会 ERR_PNPM_IGNORED_BUILDS，导致后续装插件失败）
#
# 用法：./sync-profile-seed.sh "<path/to/DeepSeek Harness.app>" [本机 profile 路径]
# =============================================================================
set -euo pipefail

APP="${1:?用法: $0 <DeepSeek Harness.app> [profile 路径]}"
LOCAL="${2:-$HOME/.dsh/profiles/web}"
SEED="$APP/Contents/Resources/profile-seed-web"

[ -d "$LOCAL/node_modules" ] || { echo "错误: 找不到本机 profile $LOCAL"; exit 1; }

# 清理 0.1.0 构建时误带入的嵌套重复目录（-489MB）
rm -rf "$SEED/profile-seed-web"

# 替换 node_modules（本机 profile 是已验证可用的超集）
rm -rf "$SEED/node_modules"
cp -R "$LOCAL/node_modules" "$SEED/node_modules"

# 清理悬空符号链接
dangling=0
while IFS= read -r link; do
  if [ ! -e "$link" ]; then rm -f "$link"; dangling=$((dangling + 1)); fi
done < <(find "$SEED/node_modules" -type l 2>/dev/null)
[ "$dangling" -gt 0 ] && echo "  已清理 $dangling 个悬空符号链接"

# 同步配置文件
cp "$LOCAL/package.json" "$LOCAL/pnpm-lock.yaml" "$LOCAL/pnpm-workspace.yaml" \
   "$LOCAL/cordis.yml" "$LOCAL/cordis.patch.yml" "$SEED/"
rm -rf "$SEED/.dsh-market"
cp -R "$LOCAL/.dsh-market" "$SEED/" 2>/dev/null || true

# 关键字段校验（这两个字段缺一个，全新机器上插件就会消失或装不上）
python3 - "$SEED/package.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
prof = p.get("dsh", {}).get("profile", {})
if "patchReload" not in prof:
    print("  ⚠️  警告: 种子 package.json 缺 patchReload —— dsh 0.1.5+ 会重置整个 profile！")
else:
    print("  patchReload: %s" % prof["patchReload"])
print("  bundles: %d 个" % len(prof.get("bundles", [])))
PY
if ! grep -q "allowBuilds" "$SEED/pnpm-workspace.yaml" 2>/dev/null; then
  echo "  ⚠️  警告: pnpm-workspace.yaml 缺 allowBuilds —— 用户后续 dsh plugin add 会失败"
fi

echo "种子已同步: $SEED"
echo "顶层包 $(ls "$SEED/node_modules" | grep -vc '^\.pnpm$') 个，大小 $(du -sh "$SEED/node_modules" | cut -f1)"
