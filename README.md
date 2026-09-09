# DeepSeek Harness macOS 一键安装包（自包含版 v0.2.0）

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）封装成
一个 **双击即可安装、离线开箱即用** 的 macOS App + DMG 安装包，专为 **Apple Silicon Mac
（M1/M2/M3/M4）** 设计。

> 本仓库是「安装包的开源工程」：包含全部构建脚本、App 源码与打包流程。
> 成品 `DeepSeekHarness-0.2.0.dmg`（约 620 MB）随 GitHub Releases 发布。

---

## ✨ 特性

| 特性 | 说明 |
|---|---|
| 🖥 免先决条件 | 内嵌 Node 26.5.0 + dsh CLI + 全部依赖，**不需要** Node、Homebrew、管理员密码 |
| 🧩 插件全家桶 | 内置 10 个 bundle：2077 主题、UI 全家桶、计算机控制、视觉路由、**AI 绘图、视频工作室、费用统计**、dshmarket 商城等 |
| 🤖 Agent 预设 | 内置「梁神模式」等用户级 agent preset，首启自动导入 |
| 🚀 一键安装 | 双击 DMG → 双击「安装 DeepSeek Harness.app」→ 自动拷贝到 `~/Applications`、初始化 `~/.dsh`、全屏启动 GUI |
| 🔒 隐私安全 | 种子 **不含** 任何 API Key / 会话记录 / 个人数据；已有 `~/.dsh` 时绝不覆盖 |
| 📦 体积更小 | 修复了 0.1.0 里重复嵌套的 profile 种子与 875MB 空分区，**620MB 比原 792MB 还小** |

## 🚀 安装（给使用者的）

1. 双击 `DeepSeekHarness-0.2.0.dmg`（Finder 自动挂载）
2. 右键 → 打开「安装 DeepSeek Harness.app」（首次需绕过 Gatekeeper，见下）
3. 等待拷贝完成，App 自动全屏启动
4. 首次进入设置页填入你自己的 DeepSeek / 其它 provider 的 API Key 即可开聊
   （无 Key 也能浏览界面，只是发消息会提示配置）

> ⚠️ **Gatekeeper**：安装包未做 Apple 公证（个人分发通常不做），首次打开会提示
> 「无法验证开发者」。**不要**双击，改为 **右键 → 打开 → 打开** 即可。

## 🧩 内置插件（profile-seed-web）

| bundle | 用途 |
|---|---|
| `@deepseek-ai/dsh-base` `@deepseek-ai/dsh-web-app` | 官方 Web 界面 |
| `dshmarket` | 插件商城（国内镜像） |
| `dsh-theme-cyberpunk2077` | 2077 赛博朋克主题 |
| `@linxin666/dsh-web-ui-all` | Web UI 全家桶 |
| `@anionex/dsh-computer-use` | 电脑操控 |
| `dsh-vision-router` | 视觉路由（v2.1.4）|
| `@hackerfish/dsh-video-studio` | 视频工作室 ★ v0.2.0 新增 |
| `dsh-image-gen` | AI 绘图 ★ v0.2.0 新增 |
| `dsh-cost-meter` | 费用统计 ★ v0.2.0 新增 |

## 🛠 自构建（给开发者的）

```bash
# 在装有 Homebrew 的 arm64 Mac 上：
brew install node   # 需要 Node 26（dsh 运行时的构建来源）
# 1. 先安装 DeepSeek Harness CLI
npm i -g @deepseek-ai/dsh
# 2. 初始化一个 web profile 并安装全家桶插件（见 docs/如何同步种子.md）
# 3. 从 electron 官方模板或已有 .app 开始组装
./scripts/build-all.sh \
   "<你的 DeepSeek Harness.app>" \
   "<你的 安装 DeepSeek Harness.app>" \
   ./out
```

### 目录结构

```
DeepSeek-Harness.app/Contents/Resources/
├── app/                     # Electron 主进程（自愈逻辑）
│   ├── main.js
│   └── package.json
├── runtime/                 # 内嵌运行时（v0.2.0 起完全自包含）
│   ├── bin/node             # Node 26.5.0 arm64
│   ├── lib/*.dylib          # libnode + 24 个 Homebrew 依赖（@loader_path 相对引用）
│   └── dsh/                 # dsh CLI + 194 个 npm 包
├── profile-seed-web/        # 干净 web profile 种子（10 个插件）
├── agent-presets-seed/      # 用户级 agent presets（梁神模式 等）
├── default_app.asar         # Electron runtime
└── app.icns ...
「安装 DeepSeek Harness.app」/Contents/MacOS/installer   # 免密安装器（bash）
```

## 🔧 v0.2.0 修复了什么（重点）

| # | 问题 | 修复 |
|---|---|---|
| 1 | **Homebrew 依赖泄漏**：内嵌 node 通过绝对路径链接 `/opt/homebrew/opt/*` 的 24 个 dylib，全新 Mac 直接崩溃（0.1.0 声称「不需要 Homebrew」实际不成立） | `scripts/bundle-homebrew-deps.sh` 递归收集所有 dylib 打进 `runtime/lib/`，用 `install_name_tool` 重写为 `@loader_path` 相对引用，再 ad-hoc 重签 |
| 2 | 种子缺 3 个常用插件（视频工作室 / AI 绘图 / 费用统计），visions-router 版本落后 | 用本机工作 profile 同步种子 |
| 3 | 打包时误把 `profile-seed-web/profile-seed-web/`（489MB 重复）拷进 app，且 DMG 预留 875MB 空分区 | 清理重复目录、重建 DMG |
| 4 | 没有用户级 agent presets | 新增 `agent-presets-seed/` + `main.js` 首启导入逻辑（缺失才拷贝） |

## 📄 License

本项目（安装器工程）为 MIT。DeepSeek Harness 本体及其插件版权归各作者所有。

## ⚠️ 免责声明

本安装包仅为技术分享，与 DeepSeek 官方无关联；请自行评估在可信来源下使用。