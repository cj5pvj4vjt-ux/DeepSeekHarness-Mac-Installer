#!/bin/bash
# =============================================================================
# bundle-homebrew-deps.sh
# -----------------------------------------------------------------------------
# 让 DeepSeek Harness 内嵌 Node 运行时真正“自包含”（v0.2.0 核心修复）。
#
# 背景：用 Homebrew 构建的 Node（v26.5.0）的二进制通过绝对路径链接了
# /opt/homebrew/opt/*/lib 下的 24 个动态库（openssl、icu4c、llhttp、libuv、
# simdjson、brotli、c-ares、zstd、sqlite、libngtcp2 等）。原 0.1.0 包直接把这
# 个 node 塞进 .app，导致在【没有安装 Homebrew 的全新 Mac】上 dyld 找不到这些
# 库，App 根本无法启动——所谓“不需要 Homebrew”其实不成立。
#
# 本脚本把这些 dylib 全部拷贝进 <app>/Contents/Resources/runtime/lib/，并把
# 所有绝对路径依赖改写成 @loader_path 相对引用，再 ad-hoc 重签，使 node 在
# 任何 arm64 macOS 上都能离线运行。
#
# 用法：./bundle-homebrew-deps.sh "<path/to/DeepSeek Harness.app>"
# 依赖：otool / install_name_tool / codesign（macOS Xcode CLT 自带）
# =============================================================================
set -euo pipefail

APP="${1:?用法: $0 <DeepSeek Harness.app 路径>}"
RT="$APP/Contents/Resources/runtime"
LIB="$RT/lib"
BIN="$RT/bin"

[ -x "$BIN/node" ] || { echo "错误: 找不到 $BIN/node"; exit 1; }
[ -f "$LIB/libnode.147.dylib" ] || { echo "错误: 找不到 $LIB/libnode.147.dylib"; exit 1; }

# 本机 Homebrew 前缀（head 或非 head 均可，按需修改）
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}"

echo "== 1/4 递归收集所有 Homebrew 绝对路径依赖 =="
DEP_LIST="$(mktemp)"
scan() {
  local f="$1" deps d
  deps=$(otool -L "$f" 2>/dev/null | tail -n +2 | awk "/\/opt\/homebrew\//{gsub(/:$/,\"\"); print \$1}")
  for d in $deps; do
    if ! grep -qxF "$d" "$DEP_LIST"; then
      echo "$d" >> "$DEP_LIST"
      scan "$d"
    fi
  done
}
scan "$BIN/node"
scan "$LIB/libnode.147.dylib"
sort -u "$DEP_LIST" -o "$DEP_LIST"
echo "发现 $(wc -l < "$DEP_LIST" | tr -d ' ') 个依赖"

echo "== 2/4 拷贝 dylib 到 runtime/lib（解析符号链接）=="
chmod u+w "$LIB" "$LIB"/* 2>/dev/null || true
while read -r d; do
  base=$(basename "$d")
  cp -Lf "$d" "$LIB/$base"
  chmod u+w "$LIB/$base"
done < "$DEP_LIST"

echo "== 3/4 重写依赖为 @loader_path（含 Homebrew 内部相对路径的补漏：icu/brotli） =="
# 3a. 复制 icu4c 的 libicudata 与 brotli 的 libbrotlicommon（Homebrew 内部用
#     @loader_path / @rpath 引用它们，不会被上面的绝对路径扫描捕获）
cp -Lf "$HOMEBREW_PREFIX/opt/icu4c@78/lib/libicudata.78.dylib" "$LIB/" 2>/dev/null || true
cp -Lf "$HOMEBREW_PREFIX/opt/brotli/lib/libbrotlicommon.1.dylib" "$LIB/" 2>/dev/null || true
chmod u+w "$LIB" 2>/dev/null || true

# 3b. bin/node：/opt/homebrew/... -> @loader_path/../lib/<base>
while read -r d; do
  install_name_tool -change "$d" "@loader_path/../lib/$(basename "$d")" "$BIN/node" 2>/dev/null || true
done < "$DEP_LIST"

# 3c. lib 下每个 dylib：/opt/homebrew/... -> @loader_path/<base>；@rpath/libbrotlicommon -> @loader_path/...
for f in "$LIB"/*.dylib; do
  base=$(basename "$f")
  while read -r d; do
    install_name_tool -change "$d" "@loader_path/$(basename "$d")" "$f" 2>/dev/null || true
  done < "$DEP_LIST"
  install_name_tool -change "@rpath/libbrotlicommon.1.dylib" "@loader_path/libbrotlicommon.1.dylib" "$f" 2>/dev/null || true
  if [ "$base" = "libnode.147.dylib" ]; then
    install_name_tool -id "@rpath/libnode.147.dylib" "$f" 2>/dev/null || true
  else
    install_name_tool -id "@loader_path/$base" "$f" 2>/dev/null || true
  fi
done

echo "== 4/4 校验 + ad-hoc 重签 =="
if otool -L "$BIN/node" "$LIB"/*.dylib | grep -q "/opt/homebrew/"; then
  echo "!! 仍有 /opt/homebrew 残留引用，请人工检查"; exit 1
fi
for f in "$LIB"/*.dylib; do codesign --force --sign - "$f" 2>/dev/null; done
codesign --force --sign - "$BIN/node"

echo ""
echo "完成 ✓ 现在 $APP/Contents/Resources/runtime 完全自包含（无任何 Homebrew 依赖）"
echo "验证：$RT/bin/node --version"