# DeepSeek Harness macOS 一键安装包（自包含版 v0.3.0）

![平台](https://img.shields.io/badge/platform-macOS%2013%2B-007AFF)
![架构](https://img.shields.io/badge/arch-Apple%20Silicon-blue)
![许可](https://img.shields.io/badge/license-MIT-green)
![大小](https://img.shields.io/badge/大小-640MB-orange)

## 📥 下载

最新版（v0.3.0 · 约 640 MB · Apple Silicon）：

[⬇️ 点击下载 DeepSeekHarness-0.3.0.dmg](https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest/download/DeepSeekHarness-0.3.0.dmg)

[校验文件 sha256](https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest/download/DeepSeekHarness-0.3.0.dmg.sha256)

或直接访问 [Releases 页面](https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest)

---

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）封装成
一个 **双击即可安装、离线开箱即用** 的 macOS App + DMG 安装包，专为 **Apple Silicon Mac
（M1/M2/M3/M4）** 设计。

> 本仓库是「安装包的开源工程」：包含全部构建脚本、App 源码与打包流程。
> 成品 `DeepSeekHarness-0.3.0.dmg`（约 640 MB）随 GitHub Releases 发布。

---

## ✨ 特性

| 特性 | 说明 |
|---|---|
| 🖥 免先决条件 | 内嵌 Node 26.5.0 + dsh CLI + 全部依赖，**不需要** Node、Homebrew、管理员密码 |
| 🔑 自动鉴权 | 自己拉起 `dsh web` 并抓取一次性 token，**不会再卡在 401「authentication required」**（v0.3.0 修复） |
| 🧩 插件全家桶 | 内置 11 个 bundle：2077 主题、UI 全家桶、计算机控制、视觉路由、**AI 绘图、视频工作室、费用统计、语音**、dshmarket 商城等 |
| 🤖 Agent 预设 | 内置「梁神模式」等用户级 agent preset，首启自动导入 |
| 🚀 一键安装 | 双击 DMG → 双击「安装 DeepSeek Harness.app」→ 自动拷贝到 `~/Applications`、初始化 `~/.dsh`、全屏启动 GUI |
| 🔒 隐私安全 | 种子 **不含** 任何 API Key / 会话记录 / 个人数据；已有 `~/.dsh` 时绝不覆盖 |
| ✅ 发布前自检 | `verify-selfcontained.sh` 七类检查 + `sandbox-test.sh` 全新机器沙盒验收，任一不过禁止分发 |

## 🚀 安装（给使用者的）

1. 双击 `DeepSeekHarness-0.3.0.dmg`（Finder 自动挂载）
2. 右键 → 打开「安装 DeepSeek Harness.app」（首次需绕过 Gatekeeper，见下）
3. 等待拷贝完成，App 自动全屏启动
4. 首次进入设置页填入你自己的 DeepSeek / 其它 provider 的 API Key 即可开聊
   （无 Key 也能浏览界面，只是发消息会提示配置）

> ⚠️ **Gatekeeper**：安装包未做 Apple 公证（个人分发通常不做），首次打开会提示
> 「无法验证开发者」。**不要**双击，改为 **右键 → 打开 → 打开** 即可。

## 🧩 内置插件（profile-seed-web，共 11 个 bundle）

| bundle | 版本 | 用途 |
|---|---|---|
| `@deepseek-ai/dsh-base` `@deepseek-ai/dsh-web-app` | 0.1.5-rc.2 | 官方 Web 界面（随内嵌 dsh） |
| `dshmarket` | 1.45.1 | 插件商城（国内镜像） |
| `dsh-theme-cyberpunk2077` | 0.1.4 | 2077 赛博朋克主题 |
| `@linxin666/dsh-web-all` | 0.3.21 | Web UI 全家桶（`dsh-web-ui-all` 已被官方标记废弃，此为继任者）|
| `@anionex/dsh-computer-use` | 0.3.2 | 电脑操控 |
| `dsh-vision-router` | 2.1.6 | 视觉路由 |
| `dsh-voice` | 0.3.2 | 语音合成 / 识别 ★ v0.3.0 新增 |
| `@hackerfish/dsh-video-studio` | git `36198b8` | 视频工作室 |
| `dsh-image-gen` | 0.6.1 | AI 绘图 |
| `dsh-cost-meter` | 1.7.21 | 费用统计 |

## 🛠 自构建（给开发者的）

```bash
# 在装有 Homebrew 的 arm64 Mac 上：
brew install node   # 需要 Node 26（dsh 运行时的构建来源）
# 1. 先安装 DeepSeek Harness CLI
npm i -g @deepseek-ai/dsh
# 2. 初始化一个 web profile 并安装全家桶插件（见 docs/如何同步种子.md）
# 3. 从 electron 官方模板或已有 .app 开始组装
DSH_RUNTIME_SRC="$(npm root -g)/@deepseek-ai/dsh" \
./scripts/build-all.sh \
   "<你的 DeepSeek Harness.app>" \
   "<你的 安装 DeepSeek Harness.app>" \
   ./out 0.3.0
```

产出：`out/DeepSeekHarness-0.3.0.dmg` + `.sha256`。

### 发布前必跑的三个验收脚本

```bash
./scripts/verify-selfcontained.sh "out/DeepSeek Harness.app"      # 自包含自检（7 类）
./scripts/sandbox-test.sh        "out/DeepSeek Harness.app" \
                                 "<安装器.app>" 1                  # 场景 A：全新机器
./scripts/sandbox-test-reuse.sh  "out/DeepSeek Harness.app" 1      # 场景 B：端口被占用
```

`verify-selfcontained.sh` 覆盖：关键文件齐全、符号链接是否越出 app、node/lib 的
Homebrew 依赖、`runtime/dsh` 内原生模块的 Homebrew 依赖、种子绝对路径残留、
隐私数据残留、嵌套重复目录；并校验每个 Mach-O 的 `@loader_path` / `@rpath`
依赖都能在 app 内解析到真实文件。**任一阻断项即退出码 1，禁止分发。**

`sandbox-test.sh`（场景 A）用全新 `HOME` / `DSH_HOME` / Electron userData / 端口
模拟一台全新 Mac，端到端验证：安装器安装 → 首启种子（bundle 数 + `patchReload`
+ `node_modules` + `settings.yaml`）→ **app 自己**完成鉴权进入界面（以 `app.log`
出现「GUI 就绪 … auth=token」为判据，而不是只看 curl）→ 会话里确实种下
`dsh-auth` cookie → 真实 `~/.dsh` 未被触碰 → 二次启动不重置用户配置。

`sandbox-test-reuse.sh`（场景 B）验证最容易翻车的那条路径：先正常首启一次种下
cookie，再用内嵌运行时起一个**外部** `dsh web` 占住同一端口（它会生成全新 token），
然后二次启动 app —— 应当凭已有 cookie **直接复用**（日志出现「鉴权探测 → HTTP 200」、
不出现「鉴权失败」），且不得误杀外部实例。这正是 v0.2.0 卡在 401 的真实场景。

### 目录结构

```
DeepSeek-Harness.app/Contents/Resources/
├── app/                     # Electron 主进程（自愈 + 自动鉴权）
│   ├── main.js
│   └── package.json
├── runtime/                 # 内嵌运行时（v0.2.0 起完全自包含）
│   ├── bin/node             # Node 26.5.0 arm64
│   ├── lib/*.dylib          # libnode + 24 个 Homebrew 依赖（@loader_path 相对引用）
│   └── dsh/                 # dsh CLI 0.1.5-rc.1 + 241 个 npm 包
├── profile-seed-web/        # 干净 web profile 种子（11 个插件，含 patchReload）
├── agent-presets-seed/      # 用户级 agent presets（梁神模式 等）
├── default_app.asar         # Electron runtime
└── app.icns ...
「安装 DeepSeek Harness.app」/Contents/MacOS/installer   # 免密安装器（bash）
```

## 🔧 v0.3.0 修复了什么（重点）

| # | 问题 | 修复 |
|---|---|---|
| 1 | **401 卡死**：`main.js` 固定加载裸地址 `http://127.0.0.1:3080`，完全依赖 30 天 cookie；dsh 升级 / 换机器 / cookie 过期后永久停在「dsh web authentication required」页面 | 从自己拉起的 `dsh web` 输出里抓取带 token 的地址并直接交给窗口加载；端口被别人占用且无令牌时弹窗询问「接管并重启」；裸地址探测改走 Electron 会话并显式携带 cookie |
| 2 | 沙盒测试又揪出三个更隐蔽的坑：① 子进程 stdout 接管道时 node 按 64KB 块缓冲，token 那行迟迟读不到；② `dsh web` **先绑端口后挂路由**，刚绑定时 `/` 返回 404，被误判成「无令牌」；③ `net.request` 不会自动带上会话 cookie | ① stdout 直接写日志文件（同步写）+ 只看本次启动新增的日志区间；② 必须「服务可应答 + 已拿到 token」才算就绪，404 会重试；③ 显式把会话 cookie 放进请求头 |
| 3 | 仓库里改了 `app/main.js` 却不生效（构建只拷源 app） | `build-app.sh` 现在强制用仓库 `app/` 覆盖产物，并统一写入版本号 |
| 4 | 内嵌 dsh 停留在 0.1.0-rc.6，插件面已落后且 `dsh-web-ui-all` 被废弃 | 内嵌运行时升到 0.1.5-rc.1（体积 333MB→279MB）；种子升到 11 个 bundle，改用继任者 `dsh-web-all` |
| 5 | 种子缺 `patchReload`，在 0.1.5+ 上会被重置，插件全部消失 | 同步脚本强制校验 `patchReload` 与 `allowBuilds`，缺失即告警 |
| 6 | 没有可重复的发布前验收 | 新增 `verify-selfcontained.sh`（7 类自检）与三个沙盒场景脚本；本版 A/B/C 全场景通过 |

## 🔧 v0.2.0 修复了什么

| # | 问题 | 修复 |
|---|---|---|
| 1 | **Homebrew 依赖泄漏**：内嵌 node 通过绝对路径链接 `/opt/homebrew/opt/*` 的 24 个 dylib，全新 Mac 直接崩溃（0.1.0 声称「不需要 Homebrew」实际不成立） | `scripts/bundle-homebrew-deps.sh` 递归收集所有 dylib 打进 `runtime/lib/`，用 `install_name_tool` 重写为 `@loader_path` 相对引用，再 ad-hoc 重签 |
| 2 | 种子缺 3 个常用插件（视频工作室 / AI 绘图 / 费用统计），vision-router 版本落后 | 用本机工作 profile 同步种子 |
| 3 | 打包时误把 `profile-seed-web/profile-seed-web/`（489MB 重复）拷进 app，且 DMG 预留 875MB 空分区 | 清理重复目录、重建 DMG |
| 4 | 没有用户级 agent presets | 新增 `agent-presets-seed/` + `main.js` 首启导入逻辑（缺失才拷贝） |

## 📄 License

本项目（安装器工程）为 MIT。DeepSeek Harness 本体及其插件版权归各作者所有。

## ⚠️ 免责声明

本安装包仅为技术分享，与 DeepSeek 官方无关联；请自行评估在可信来源下使用。
