# Changelog

## 0.2.0 (2026-09-09)

### 🐛 修复：Homebrew 依赖泄漏（重点）
- 发现 0.1.0 内嵌的 node（26.5.0）通过**绝对路径**链接了 24 个
  `/opt/homebrew/opt/*/lib` 下的动态库（openssl@3、icu4c@78、llhttp、libuv、
  simdjson、simdutf、brotli、c-ares、hdrhistogram_c、merve、nbytes、nghttp2/3、
  ngtcp2、sqlite、libffi、uvwasi、zstd、ada-url 等）。
- **结论**：在没有 Homebrew 的全新 Mac 上，0.1.0 的 App 根本起不来。
- **修复**：新增 `scripts/bundle-homebrew-deps.sh`，递归收集所有依赖 dylib
  打进 `runtime/lib/`，使用 `install_name_tool` 把绝对路径重写为
  `@loader_path/../lib/...`（bin）与 `@loader_path/...`（lib），并做 ad-hoc 重签。
  修复后 `otool -L` 全绿、`node --version` 在新环境可离线运行。

### ✨ 新增
- 插件：`@hackerfish/dsh-video-studio`（视频工作室）、`dsh-image-gen`（AI 绘图）、
  `dsh-cost-meter`（费用统计）；`dsh-vision-router` 2.1.2 → 2.1.4。
- 内置 agent preset：「梁神模式」（`agent-presets-seed/liangshen`），
  `main.js` 首启自动导入 `~/.dsh/.agent-presets`（缺失才拷贝，绝不覆盖）。
- 完整构建脚本链：`build-all.sh` / `build-app.sh` / `sync-profile-seed.sh` /
  `bundle-homebrew-deps.sh` / `build-dmg.sh`，可复现打包。

### 🧹 体积优化
- 删除误拷的嵌套 `profile-seed-web/profile-seed-web/`（**-489 MB**）。
- 重建 DMG，不再预留 875 MB 空分区。
- 结果：620 MB（比 0.1.0 的 792 MB 更小，内容却更多）。

## 0.1.0 (2026-09-06)
- 首个 Electron 封装版：内嵌 Node + dsh CLI + web profile 种子。
- 双击 DMG 安装、首启自愈初始化 `~/.dsh`、全屏 GUI。
- 已知问题：Homebrew 依赖泄漏（见 0.2.0）、种子重复嵌套、缺插件。