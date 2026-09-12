# Changelog

## 0.3.0 (2026-09-13)

### 🐛 修复：401「dsh web authentication required」导致界面打不开（重点）
- **背景**：`dsh web` 每次启动都会随机生成一个一次性 access token，只印在它自己的
  启动输出里；不带 token 访问根路径会直接返回 `401 dsh web authentication required`。
  0.2.0 的 `main.js` 固定加载裸地址 `http://127.0.0.1:3080`，完全依赖 Electron
  会话里那个 30 天有效的 `dsh-auth` cookie。
- **触发条件**：dsh 版本升级 / 换机器 / cookie 超过 30 天 —— 任一个发生，App 就会
  永远停在 401 页面且无法自愈（本次已实测复现：cookie 签名密钥存放在
  `~/.dsh/.credentials.yaml`，该文件被重写后旧 cookie 即失效）。
- **修复**：`main.js` 现在
  1. 自己拉起 `dsh web` 时，从它的启动输出里抓出带 token 的完整地址；
  2. 用该地址加载 GUI，顺带让 Electron 会话存下 cookie；
  3. 端口已被**别的** `dsh web` 占用且无令牌时，弹窗询问是否由本应用
     「接管并重启服务」（只结束占用端口的进程，不动 `~/.dsh` 数据）；
  4. 鉴权探测改走 Electron `net`（共享 cookie 罐），不再盲目加载。

### 🐛 沙盒验收又揪出四个更隐蔽的坑（同批修复）
- **子进程 stdout 的管道缓冲**：起先把 `dsh web` 的 stdout 接到**管道**再自己转发，
  但 node 在 stdout 是管道时按 64 KB 块缓冲，`dsh web: …?token=…` 这行会一直留在
  缓冲区里读不到（实测 90 秒都拿不到 token）。改为把 stdout/stderr 直接指向**日志
  文件**（node 对文件是同步写），并且只在「本次启动新增的日志区间」里找 token，
  避免捡到上一次运行遗留的旧 token。
- **启动竞态：端口先通、路由后挂**：`isUp()` 只要收到任何 HTTP 响应就算就绪，
  但 `dsh web` 是**先绑定端口、后挂载路由**的——刚绑定的瞬间 `/` 会返回 `404`，
  token 那行也还没打印。原先在这一瞬间就继续往下走，于是既没有 token、探测又拿到
  404，被误判成「端口被别的实例占用且无令牌」。现在必须**同时**满足「服务可应答 +
  已抓到 token」才算就绪；裸地址探测遇到 404 也会重试（每 2 秒一轮，共 8 轮），
  而不是立刻判失败。
- **不该靠探测定生死**：带 token 的地址会回 `303 → Location: /`，用 `net` 去探测时，
  默认跟随重定向会因为没有 cookie 而再请求一次 `/` 拿到 401；改成
  `redirect: "manual"` 又会让 Electron 的请求**直接失败**（返回 0）。
  最终设计是**根本不探测它**——带 token 的地址本身就是通行证，直接交给窗口加载
  （只有窗口加载才会真正把 cookie 存进会话）。只有「端口已被别的实例占用」时才用
  裸地址探测会话里的 30 天 cookie 是否仍然有效。
- **`URL` 与 `DSH_PORT` 不一致**：`URL` 原先硬编码 `3080`，只要外部设置了
  `DSH_PORT`，就会出现「探测 3080 发现有服务 → 既不复用也不启动自己的服务」
  的自相矛盾。现在 `URL` 默认跟随 `DSH_PORT`。
- 新增 `DSH_PORT` / `DSH_LOG_DIR` / `DSH_NO_FULLSCREEN` / `DSH_AUTOCLOSE` 等
  环境变量支持，日常使用不受影响，主要用于多实例与自动化沙盒测试。

### 🔄 运行时与插件更新
- 内嵌 dsh：**0.1.0-rc.6 → 0.1.5-rc.1**（其内部包为 0.1.5-rc.2）。
  内嵌 runtime/dsh 体积 333 MB → **279 MB**。
- 插件种子 10 → **11 个 bundle**：
  - `@linxin666/dsh-web-ui-all`（官方已标记 **废弃**）→ 继任者 `@linxin666/dsh-web-all`
  - 新增 `dsh-voice`
  - 其余全部升到与 0.1.5 兼容的版本：`dsh-vision-router` 2.1.6、
    `dsh-cost-meter` 1.7.21、`dsh-image-gen` 0.6.1、`dshmarket` 1.45.1、
    `@anionex/dsh-computer-use` 0.3.2、`dsh-theme-cyberpunk2077` 0.1.4
- 种子带上 `patchReload: live`，避免被 dsh 0.1.5+ 的 profile 初始化流程重置。

### ✅ 新增自检与沙盒验收（可重复执行）
- `scripts/verify-selfcontained.sh`：7 类发布前自检 —— 关键文件齐全、符号链接是否
  越出 app、node/lib 的 Homebrew 依赖、**runtime/dsh 内原生模块（*.node）**的
  Homebrew 依赖、种子绝对路径残留、隐私数据残留、嵌套重复目录；并逐一校验每个
  Mach-O 的 `@loader_path` / `@rpath` 依赖都能在 app 内解析到真实文件。
  任一项阻断即退出码 1，禁止分发。
- `scripts/sandbox-test.sh`（场景 A · 全新机器）：用全新 `HOME` / `DSH_HOME` /
  Electron userData / 端口模拟一台全新 Mac，端到端验证：安装器安装 → 首启种子
  （bundle 数 + `patchReload` + `node_modules` + `settings.yaml`）→ app **自己**
  完成鉴权（以 `app.log` 出现「GUI 就绪 … auth=token」为判据，而不是只看 curl）→
  会话里确实种下 `dsh-auth` cookie → 真实 `~/.dsh` 未被触碰 → 二次启动不重置用户配置。
- `scripts/sandbox-test-reuse.sh`（场景 B · 端口被占用）：先正常首启一次种下 cookie，
  再用内嵌运行时起一个**外部** `dsh web` 占住同一端口（它会生成全新 token），
  然后二次启动 app —— 应当**凭已有 cookie 直接复用**（日志出现「鉴权探测 → HTTP 200」、
  不出现「鉴权失败」），且不得误杀外部实例。这正是 v0.2.0 卡 401 的真实场景。

### 🔧 构建链路修复
- `build-app.sh` 现在会把**仓库 `app/` 覆盖进产物**（此前只拷贝源 app，导致仓库里
  改了 `main.js` 也不会生效），并统一写入版本号（`package.json` + `Info.plist`）。
- `sync-profile-seed.sh` 增加悬空符号链接清理，并校验 `patchReload` 与
  `allowBuilds` 两个关键字段（缺任一个，全新机器上插件会消失或后续装不上插件）。
- `build-all.sh` 支持版本号参数，自动产出 `DeepSeekHarness-<版本>.dmg` 与 `.sha256`。

### ⚠️ 已知限制
- 仍未做 Apple 公证，首次打开需「右键 → 打开」绕过 Gatekeeper。
- 仅支持 Apple Silicon（arm64）。

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