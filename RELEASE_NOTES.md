# GitHub Release 发布说明 · v0.2.0

## 🎉 DeepSeek Harness macOS 一键安装包 v0.2.0

把 DeepSeek Harness 封装成**双击即可安装**的 macOS App（Apple Silicon / macOS 13+）。
本版修复了 0.1.0 的 Homebrew 依赖泄漏，真正做到**零先决条件、离线开箱即用**。

### ✨ 新增
- 插件全家桶升级到 10 个：新增 **视频工作室**（@hackerfish/dsh-video-studio）、
  **AI 绘图**（dsh-image-gen）、**费用统计**（dsh-cost-meter）；
  dsh-vision-router 升级至 2.1.4
- 内置 **Agent 预设**：「梁神模式」等，首次启动自动导入 `~/.dsh/.agent-presets`
- 新增可复现的构建脚本链（bundle-homebrew-deps / sync-profile-seed / build-app / build-dmg）

### 🐛 修复
- **Homebrew 依赖泄漏（核心）**：内嵌 Node 原本通过绝对路径链接
  `/opt/homebrew/opt/*` 的 24 个 dylib，在全新 Mac 上无法启动；
  现已全部打入 `runtime/lib/` 并改写为 `@loader_path` 相对引用，完全自包含
- 移除误拷的 489MB 重复种子目录、重建 DMG 去掉 875MB 空分区

### 📦 安装
1. 下载 `DeepSeekHarness-0.2.0.dmg`（约 620 MB）
2. 双击挂载 → **右键 → 打开**「安装 DeepSeek Harness.app」（首次需绕过 Gatekeeper）
3. 自动拷贝到 `~/Applications`、初始化 `~/.dsh`、全屏启动
4. 设置页填入你自己的 API Key 即可使用

SHA256: `7e848fb1bf4f3e986c915a6b7f379bf56d74eb295dc7eb4a78f3edaaeb3d4c0a`

### ⚠️ 说明
- 仅支持 Apple Silicon Mac（M1~M4），macOS 13+
- 未做 Apple 公证：首次打开需右键 → 打开（一次）
- 种子不含任何个人 API Key / 会话数据；已有 `~/.dsh` 时不会覆盖
