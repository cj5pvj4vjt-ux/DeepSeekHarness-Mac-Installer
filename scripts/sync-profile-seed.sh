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

# 同步配置文件
cp "$LOCAL/package.json" "$LOCAL/pnpm-lock.yaml" "$LOCAL/pnpm-workspace.yaml" \
   "$LOCAL/cordis.yml" "$LOCAL/cordis.patch.yml" "$SEED/"
rm -rf "$SEED/.dsh-market"
cp -R "$LOCAL/.dsh-market" "$SEED/" 2>/dev/null || true

echo "种子已同步: $SEED"
echo "顶层包 $(ls "$SEED/node_modules" | grep -vc '^\.pnpm$') 个，大小 $(du -sh "$SEED/node_modules" | cut -f1)"
echo "已安装插件:"
node -e "const p=require('$SEED/package.json'); console.log(p.dsh.profile.bundles.join(' '))" 2>/dev/null || cat "$SEED/package.json"