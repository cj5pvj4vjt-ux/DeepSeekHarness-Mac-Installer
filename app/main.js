const { app, BrowserWindow, Menu, dialog, shell, net, session } = require("electron");
const { spawn } = require("child_process");
const http = require("http");
const path = require("path");
const fs = require("fs");

// 可配置项（默认值即标准环境；测试时可用环境变量覆盖，不影响日常使用）
const DSH_PORT = process.env.DSH_PORT || "3080";
// 注意：URL 必须与 DSH_PORT 保持一致。旧版把 URL 写死成 3080，导致只要外部
// 设置了 DSH_PORT，就会出现「探测 3080 有服务 → 不复用也不启动」的自相矛盾。
const URL = process.env.DSH_URL || `http://127.0.0.1:${DSH_PORT}`;
const DSH_AUTOCLOSE = process.env.DSH_AUTOCLOSE === "1"; // 测试钩子：就绪后自动退出
const DSH_NO_FULLSCREEN = process.env.DSH_NO_FULLSCREEN === "1"; // 测试钩子：不全屏
let APP_VERSION = "0.0.0";
try { APP_VERSION = require("./package.json").version || APP_VERSION; } catch {}

// =============================================================================
// 认证（v0.3.0 新增，修复「dsh web authentication required」打不开界面）
// -----------------------------------------------------------------------------
// dsh web 每次启动都会随机生成一个一次性 access token，只印在它自己的启动输出里：
//     dsh web: http://127.0.0.1:3080/?token=xxxxxxxx
// 不带 token 访问根路径会返回 401（"dsh web authentication required"）。
// 带 token 访问一次后，服务端会下发一个 30 天有效的 dsh-auth cookie；
// 此前版本正是靠这个 cookie 才能打开，所以一旦 cookie 失效（换 dsh 版本、
// 换机器、超过 30 天），封装 App 就永远停在 401 页面且无法自愈。
//
// 现在改为：
//   1) 由本应用拉起 dsh web 时，从子进程 stdout 里抓出带 token 的完整地址；
//   2) 用这个地址加载界面，顺带让 Electron 会话存下 cookie；
//   3) 服务已由别处启动时，先试已有 cookie；仍被拒则询问用户是否由本应用接管。
// =============================================================================
let AUTH_URL = null; // 由本应用拉起的 dsh web 输出的带 token 地址
const TOKEN_URL_RE = /https?:\/\/[^\s"'`<>]*[?&]token=[A-Za-z0-9._~%+-]+/g;

function extractTokenUrl(text) {
  if (!text) return null;
  const m = String(text).match(TOKEN_URL_RE);
  return m && m.length ? m[m.length - 1] : null;
}

// 从落盘的服务日志里取「最后一次」输出的 token 地址
function tokenFromServerLog() {
  try {
    if (!fs.existsSync(SERVER_LOG)) return null;
    return extractTokenUrl(fs.readFileSync(SERVER_LOG, "utf8"));
  } catch { return null; }
}

// 只读本次启动之后**新增**的那段日志，避免捡到上一次运行遗留的旧 token
let SERVER_LOG_OFFSET = 0;
function tokenFromServerLogSince() {
  try {
    const size = fs.statSync(SERVER_LOG).size;
    if (size <= SERVER_LOG_OFFSET) return null;
    const len = size - SERVER_LOG_OFFSET;
    const buf = Buffer.alloc(len);
    const fd = fs.openSync(SERVER_LOG, "r");
    fs.readSync(fd, buf, 0, len, SERVER_LOG_OFFSET);
    fs.closeSync(fd);
    return extractTokenUrl(buf.toString("utf8"));
  } catch { return null; }
}

function originOf(u) {
  try { return new URL(u).origin; } catch { return URL; }
}

// 用 Electron 会话探测**裸地址**的状态码，判断会话里的 30 天 cookie 是否仍然有效。
// 两个坑：
//  1. 不要探测「带 token 的地址」：它会 303 到 /，跟随之后在没有 cookie 的情况下
//     只会拿到 401，会把一次完全正常的启动误判成鉴权失败。
//  2. net.request 并不会自动带上会话里的 cookie（实测如此），所以这里显式把
//     session 里的 cookie 取出来放进请求头；否则永远探测到 401。
//  另外 redirect: "manual" 在 Electron 里会让请求直接失败（返回 0），不要用。
async function probeStatus(target) {
  let cookieHeader = "";
  try {
    const jar = await session.defaultSession.cookies.get({ url: URL });
    if (jar && jar.length) {
      cookieHeader = jar.map((c) => c.name + "=" + c.value).join("; ");
    }
  } catch {}
  return new Promise((resolve) => {
    let settled = false;
    const finish = (v) => { if (!settled) { settled = true; resolve(v); } };
    try {
      const opts = { method: "GET", url: target };
      if (cookieHeader) opts.headers = { Cookie: cookieHeader };
      const req = net.request(opts);
      req.on("response", (res) => {
        res.on("data", () => {});
        res.on("end", () => finish(res.statusCode || 0));
        res.on("error", () => finish(0));
      });
      req.on("error", () => finish(0));
      try { req.setTimeout(6000, () => { try { req.abort(); } catch {} finish(0); }); } catch {}
      req.end();
    } catch { finish(0); }
  });
}

// 内嵌运行时解析：优先使用 App 自带的 node + dsh（Contents/Resources/runtime/），
// 找不到再回退到环境变量或 /opt/homebrew（开发机）。这样分发给别人也能独立运行。
const RUNTIME_DIR = path.join(__dirname, "..", "runtime");
function pick(explicit, candidates) {
  if (explicit) return explicit;
  for (const c of candidates) {
    try { if (fs.existsSync(c)) return c; } catch {}
  }
  return candidates[candidates.length - 1];
}
const NODE = pick(process.env.DSH_NODE, [
  path.join(RUNTIME_DIR, "bin", "node"),
  "/opt/homebrew/bin/node",
  "/usr/local/bin/node"
]);
const DSH = pick(process.env.DSH_BIN, [
  path.join(RUNTIME_DIR, "dsh", "lib", "bin.js"),
  "/opt/homebrew/bin/dsh",
  "/usr/local/bin/dsh"
]);
const RUNTIME_HOME = process.env.DSH_HOME || path.join(app.getPath("home"), ".dsh");

// 首次启动自愈：若用户还没有 ~/.dsh（全新用户/分享安装），用 App 内嵌的
// profile 种子初始化一个干净环境（不含任何个人凭证/会话），再启动 web。
// 已有 ~/.dsh 时完全不动，绝不覆盖用户自己的配置。
const SEED_PROFILE = path.join(__dirname, "..", "profile-seed-web");
const PRESET_SEED = path.join(__dirname, "..", "agent-presets-seed");

// 从内嵌种子导入用户级 agent presets（如 梁神模式），缺失才拷贝，绝不覆盖已有 preset
function ensureFreshAgentPresets() {
  try {
    const presetsDir = path.join(RUNTIME_HOME, ".agent-presets");
    if (!fs.existsSync(presetsDir)) fs.mkdirSync(presetsDir, { recursive: true });
    if (!fs.existsSync(PRESET_SEED)) return false;
    let copied = false;
    for (const entry of fs.readdirSync(PRESET_SEED)) {
      const target = path.join(presetsDir, entry);
      if (!fs.existsSync(target)) {
        fs.cpSync(path.join(PRESET_SEED, entry), target, { recursive: true });
        log("已从内嵌种子初始化 agent preset: " + entry);
        copied = true;
      }
    }
    return copied;
  } catch (err) {
    log("初始化 agent presets 失败: " + err.message);
    return false;
  }
}

function ensureFreshDshHome() {
  try {
    const profilesDir = path.join(RUNTIME_HOME, "profiles");
    const webDir = path.join(profilesDir, "web");
    const settings = path.join(RUNTIME_HOME, "settings.yaml");
    let created = false;
    if (!fs.existsSync(profilesDir)) fs.mkdirSync(profilesDir, { recursive: true });
    if (!fs.existsSync(webDir)) {
      if (fs.existsSync(SEED_PROFILE)) {
        fs.cpSync(SEED_PROFILE, webDir, { recursive: true });
        log("已从内嵌种子初始化 " + webDir);
        created = true;
      } else {
        log("未找到内嵌 profile 种子，且用户无 web profile：" + webDir);
      }
    }
    if (!fs.existsSync(settings)) {
      const s = [
        "locale:",
        "  preference: zh",
        "ui-conversation:",
        "  busyEnter: steer",
        "agent-presets:",
        "  default: cordis",
        "ui-theme:",
        "  preference: system",
        ""
      ].join("\n");
      fs.writeFileSync(settings, s);
      log("已生成默认 " + settings);
      created = true;
    }
    // 种子内置插件：梁神模式等 agent presets（缺失才补）
    ensureFreshAgentPresets();
    return { created, webReady: fs.existsSync(webDir) };
  } catch (err) {
    log("初始化 ~/.dsh 失败: " + err.message);
    return { created: false, webReady: false };
  }
}

// 日志目录：macOS 上 app.getPath("home") 返回真实家目录（不随 $HOME 变化），
// 因此额外提供 DSH_LOG_DIR 覆盖，让沙盒测试可以完全隔离。
const LOG_DIR = process.env.DSH_LOG_DIR
  || path.join(app.getPath("home"), "Library", "Logs", "DeepSeek Harness");
const LOG_FILE = path.join(LOG_DIR, "app.log");
const SERVER_LOG = path.join(LOG_DIR, "app-spawned-web.log");

let childServer = null; // 仅记录本应用拉起的 dsh web
let win = null;
let readyResolve = null;

function log(msg) {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`);
  } catch {}
}

function isUp() {
  return new Promise((resolve) => {
    const req = http.get(URL, (res) => { res.resume(); resolve(true); });
    req.setTimeout(1500, () => { req.destroy(); resolve(false); });
    req.on("error", () => resolve(false));
  });
}

// 双击后：如果 dsh web 没在跑，就在这里自动把它拉起来（本应用专属实例）
async function ensureServer() {
  if (await isUp()) {
    log("探测到 " + URL + " 已有服务 → 直接复用（不接管）");
    return "already-running";
  }
  log(`探测 ${URL} 无服务 → 由本应用自动启动 dsh web`);
  const args = ["web", "--port", DSH_PORT];
  try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch {}
  // 关键：子进程的 stdout/stderr 必须指向**文件**，不能用管道。
  // node 在 stdout 是管道时按 64KB 块缓冲，`dsh web: …?token=…` 这行会一直留在
  // 缓冲区里不落盘（实测管道模式下 90 秒都读不到 token，而 cost-meter 那行是同步
  // 写所以能出来）。指向文件时 node 是同步写，token 立刻可见。
  try { SERVER_LOG_OFFSET = fs.statSync(SERVER_LOG).size; } catch { SERVER_LOG_OFFSET = 0; }
  const out = fs.openSync(SERVER_LOG, "a");
  childServer = spawn(NODE, [DSH, ...args], {
    detached: true,
    stdio: ["ignore", out, out],
    env: { ...process.env, DSH_HOME: RUNTIME_HOME, HOME: app.getPath("home") }
  });
  childServer.on("error", (err) => {
    log("启动 dsh web 失败: " + err.message);
    if (win) {
      dialog.showErrorBox("DeepSeek Harness", "无法启动 dsh web：\n" + err.message);
    }
  });
  childServer.unref();
  // 最多等 90 秒。注意判据不能只是「端口有人应答」：dsh web 是**先绑定端口、
  // 后挂载路由**的，刚绑定时 / 会返回 404、token 也还没打印，这时就往下走会被
  // 误判成「端口被别的实例占用且无令牌」。
  for (let i = 0; i < 180; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (!AUTH_URL) {
      const found = tokenFromServerLogSince();
      if (found) {
        AUTH_URL = found;
        log("已从服务输出捕获认证地址（端口 " + DSH_PORT + "）");
      }
    }
    const up = await isUp();
    // 真正就绪 = 既能应答、又已经拿到 token
    if (up && AUTH_URL) return "started-by-app";
    // 兜底：服务早已可用但 30 秒都没打印 token（其它版本可能如此）→ 交给后续探测重试
    if (up && i >= 60) {
      if (!AUTH_URL) AUTH_URL = tokenFromServerLogSince() || tokenFromServerLog();
      return "started-by-app";
    }
    if (childServer && childServer.exitCode !== null && childServer.exitCode !== 0) break;
  }
  return "timeout";
}

// 结束占用端口的进程（仅在本应用无法鉴权、且用户明确点「接管」后才调用）
function killPortOccupant() {
  return new Promise((resolve) => {
    const lsof = fs.existsSync("/usr/sbin/lsof") ? "/usr/sbin/lsof" : "lsof";
    let p;
    try { p = spawn(lsof, ["-ti", "tcp:" + DSH_PORT]); } catch { return resolve(0); }
    let out = "";
    p.stdout.on("data", (d) => { out += d; });
    p.on("error", () => resolve(0));
    p.on("close", () => {
      const pids = out.split(/\s+/).filter(Boolean).map(Number)
        .filter((n) => Number.isInteger(n) && n > 0 && n !== process.pid);
      for (const pid of pids) {
        try { process.kill(pid, "SIGTERM"); log("已结束占用端口 " + DSH_PORT + " 的进程 " + pid); } catch {}
      }
      setTimeout(() => resolve(pids.length), pids.length ? 2000 : 0);
    });
  });
}

// 取得可用的界面地址；彻底失败返回 null（此时已提示过用户）。
// serverState 来自 ensureServer()：
//   "started-by-app"   —— 服务是本应用本次拉起的，AUTH_URL 必定属于这个实例
//   "already-running"  —— 端口上已经有一个（可能是别人的）实例，本应用没有它的令牌
async function ensureAuthenticated(serverState) {
  // 情况 1：本次启动抓到了 token。
  // 带 token 的地址本身就是通行证：服务端会 303 → 种下 cookie → 进入界面。
  // 因此直接交给窗口加载即可，不需要事先探测。
  if (serverState === "started-by-app" && AUTH_URL) {
    log("使用本应用抓到的带 token 地址加载界面");
    return AUTH_URL;
  }

  // 情况 2：端口上已有别的实例 → 只能试裸地址（靠会话里的 30 天 cookie）。
  // 服务刚起步时路由可能还没挂完（表现为 404），所以要重试几轮。
  // 注意此时**不能**用日志里的旧 token：那属于上一次运行，对新实例无效。
  for (let a = 0; a < 8; a++) {
    const code = await probeStatus(URL);
    log("鉴权探测 → HTTP " + code + "（裸地址）");
    if (code >= 200 && code < 400) return URL;
    if (code !== 404) break;
    await new Promise((r) => setTimeout(r, 2000));
  }

  log("鉴权失败：端口被其它 dsh web 实例占用且无令牌");
  const { response } = await dialog.showMessageBox({
    type: "warning",
    title: "DeepSeek Harness",
    message: "本地服务需要重新授权",
    detail:
      "端口 " + DSH_PORT + " 上已有另一个 dsh web 实例在运行，但本应用没有它的访问令牌" +
      "（该令牌每次启动都会重新生成）。\n\n" +
      "选择「接管」会结束那个实例，并由本应用重新启动一个；" +
      "~/.dsh 里的会话与配置不受影响。",
    buttons: ["接管并重启服务", "退出"],
    defaultId: 0,
    cancelId: 1,
    noLink: true
  });
  if (response !== 0) return null;

  await killPortOccupant();
  const state = await ensureServer();
  log("接管后重启服务: " + state);
  if (state !== "started-by-app") return null;
  if (AUTH_URL) {
    log("接管后取得带 token 的地址");
    return AUTH_URL;
  }
  return null;
}

function splashHTML(text) {
  return `data:text/html;charset=utf-8,${encodeURIComponent(`<!doctype html><html><body style="margin:0;background:#06070f;color:#e8ecf5;font-family:-apple-system,'PingFang SC',sans-serif;display:flex;align-items:center;justify-content:center;height:100vh"><div style="text-align:center"><div style="font-size:34px;margin-bottom:14px">⬡</div><div>${text}</div></div></body></html>`)}`;
}

function makeWindow(urlToLoad) {
  win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    title: "DeepSeek Harness",
    backgroundColor: "#06070f",
    autoHideMenuBar: true,
    fullscreen: !DSH_NO_FULLSCREEN,
    icon: path.join(__dirname, "..", "Resources", "icon.png"),
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true }
  });
  win.setMenuBarVisibility(false);

  // 启动即全屏：窗口显示后再进入原生全屏（时序上更可靠），加载完成再兜底一次
  const goFullscreen = () => {
    if (DSH_NO_FULLSCREEN) return;
    if (!win || win.isDestroyed()) return;
    if (!win.isFullScreen()) {
      win.setFullScreen(true);
      log("已请求进入全屏");
    } else {
      log("已在全屏状态");
    }
  };
  win.once("ready-to-show", () => {
    win.show();
    setTimeout(goFullscreen, 250);
  });
  win.webContents.once("did-finish-load", () => setTimeout(goFullscreen, 400));
  win.on("enter-full-screen", () => log("进入全屏完成"));

  // 先显示"正在启动…"占位，服务就绪后再载入真实 GUI
  win.loadURL(splashHTML("正在启动 DeepSeek Harness …"));
  const target = urlToLoad || AUTH_URL || URL;
  const guiOrigin = originOf(target);
  const loadGUI = () => win.loadURL(target);
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (!url.startsWith(guiOrigin)) shell.openExternal(url);
    return { action: "deny" };
  });
  win.on("closed", () => { win = null; });
  return loadGUI;
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  });

  app.whenReady().then(async () => {
    Menu.setApplicationMenu(null);
    // 全新用户（分享安装）先初始化干净 ~/.dsh；老用户不受影响
    const boot = ensureFreshDshHome();
    if (!boot.webReady) {
      log("警告：无可用 web profile（seed 也未提供）。将尝试启动 dsh 查看错误。");
    }
    const state = await ensureServer();
    if (state === "timeout") {
      if (win) win.destroy();
      dialog.showErrorBox("DeepSeek Harness",
        "等待 Web 服务启动超时（90 秒）。\n日志：" + LOG_FILE + "\n服务日志：" + SERVER_LOG);
      app.quit();
      return;
    }
    // v0.3.0：解决 401 —— 没有可用令牌时（例如端口已被别的 dsh web 占用）询问用户
    const guiUrl = await ensureAuthenticated(state);
    if (!guiUrl) {
      if (win) win.destroy();
      dialog.showErrorBox("DeepSeek Harness",
        "无法获得本地服务的访问授权，已退出。\n\n" +
        "请关闭其它 dsh web 实例后重试，或查看日志：\n" + LOG_FILE);
      app.quit();
      return;
    }
    log("GUI 就绪 v" + APP_VERSION + " (state=" + state +
        ", auth=" + (guiUrl === URL ? "cookie" : "token") + ")");
    const loadGUI = makeWindow(guiUrl);
    // 等窗口完成首帧后立即载入真实界面；若 splash 还在也直接覆盖
    loadGUI();
    if (DSH_AUTOCLOSE) {
      setTimeout(() => app.quit(), 1500);
    }
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) makeWindow(guiUrl)();
    });
  });

  // 退出时：只停掉本应用拉起的 dsh web；用户手动/开机自启的实例绝不碰
  app.on("before-quit", () => {
    if (childServer) {
      log("退出，停止本应用拉起的 dsh web (pid " + childServer.pid + ")");
      try { childServer.kill("SIGTERM"); } catch {}
      childServer = null;
    }
  });

  app.on("window-all-closed", () => { app.quit(); });
}
