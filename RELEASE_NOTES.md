# GitHub Release 发布说明 · v0.3.0

## 🎉 DeepSeek Harness macOS 一键安装包 v0.3.0

把 DeepSeek Harness 封装成**双击即可安装**的 macOS App（Apple Silicon / macOS 13+）。
本版修掉了「界面打不开、一直停在 `dsh web authentication required`」这个最要命的问题，
并把内嵌运行时与插件全家桶整体升到 0.1.5 一代。

### 🐛 修复（重点）
- **401 打不开界面**：`dsh web` 每次启动都会随机生成一次性 access token，只印在自己
  的启动输出里；旧版固定加载不带 token 的裸地址，完全依赖会话里那个 30 天的 cookie。
  一旦 dsh 升级 / 换机器 / cookie 过期，App 就永久停在 401 页面且无法自愈。
  现在 App 会自己拉起服务、抓出带 token 的地址并交给窗口加载；
  端口已被**别的**实例占用时，会弹窗询问是否「接管并重启服务」。
- 顺带修掉三个只有跑沙盒才暴露的隐蔽坑：
  - 子进程 stdout 接管道时 node 按 64KB 块缓冲，导致 token 那行迟迟读不到
    → 改为直接写日志文件（同步写），并只在本次启动新增的日志区间里找 token；
  - `dsh web` 是**先绑定端口、后挂载路由**的，刚绑定时 `/` 会返回 404
    → 现在必须「服务可应答 + 已拿到 token」才算就绪，404 也会重试；
  - `net.request` 不会自动带上会话 cookie → 显式把 cookie 放进请求头，
    否则永远探测到 401。
- 构建链路：仓库里的 `app/main.js` 现在会真正覆盖进产物（此前改了不生效）。

### 🔄 运行时与插件更新
- 内嵌 dsh：**0.1.0-rc.6 → 0.1.5-rc.1**（内嵌 runtime 体积 333 MB → 279 MB）
- 插件全家桶 10 → **11 个**：新增 **语音**（dsh-voice）；
  `@linxin666/dsh-web-ui-all`（官方已废弃）→ 继任者 `@linxin666/dsh-web-all`；
  dsh-vision-router 2.1.6、dsh-cost-meter 1.7.21、dsh-image-gen 0.6.1、
  dshmarket 1.45.1、@anionex/dsh-computer-use 0.3.2、dsh-theme-cyberpunk2077 0.1.4
- 种子带 `patchReload: live`，避免被 dsh 0.1.5+ 的 profile 初始化流程重置

### ✅ 新增可重复的发布前验收
- `scripts/verify-selfcontained.sh` —— 7 类自包含自检（关键文件、越界符号链接、
  Homebrew 依赖、原生模块、种子绝对路径、隐私残留、嵌套目录 + 逐个 Mach-O 依赖解析）
- `scripts/sandbox-test.sh` —— 场景 A：全新机器端到端（12 项）
- `scripts/sandbox-test-reuse.sh` —— 场景 B：端口被占用时凭 cookie 复用（10 项）
- `scripts/sandbox-test-dmg.sh` —— 场景 C：拿**真实 DMG** 从只读卷安装并启动
- 本版发布前 A/B/C 三个场景全部通过，自检全绿

### 📦 安装
1. 下载 `DeepSeekHarness-0.3.0.dmg`（约 640 MB）
2. 双击挂载 → **右键 → 打开**「安装 DeepSeek Harness.app」（首次需绕过 Gatekeeper）
3. 自动拷贝到 `~/Applications`，首次启动自动初始化 `~/.dsh`（种子 + 11 个插件 + agent presets）
4. 设置页填入你自己的 API Key 即可使用

SHA256: `2e88e25a29c05770f72ae3f304a672d60bd93d86110d01ff905cfce7a5a9ca63`

### ⚠️ 说明
- 仅支持 Apple Silicon Mac（M1~M4），macOS 13+
- 未做 Apple 公证：首次打开需右键 → 打开（一次）
- 种子不含任何个人 API Key / 会话数据；已有 `~/.dsh` 时不会覆盖
