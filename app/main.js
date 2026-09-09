const { app, BrowserWindow, Menu, dialog, shell } = require("electron");
const { spawn } = require("child_process");
const http = require("http");
const path = require("path");
const fs = require("fs");

// 可配置项（默认值即标准环境；测试时可用环境变量覆盖，不影响日常使用）
const URL = process.env.DSH_URL || "http://127.0.0.1:3080";
const DSH_PORT = process.env.DSH_PORT || "3080";
const DSH_AUTOCLOSE = process.env.DSH_AUTOCLOSE === "1"; // 测试钩子：就绪后自动退出

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

const LOG_DIR = path.join(app.getPath("home"), "Library", "Logs", "DeepSeek Harness");
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
  if (await isUp()) return "already-running";
  log(`探测 ${URL} 无服务 → 由本应用自动启动 dsh web`);
  const args = ["web", "--port", DSH_PORT];
  // 子进程输出落盘，便于排错
  try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch {}
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
  // 最多等 90 秒
  for (let i = 0; i < 180; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (await isUp()) return "started-by-app";
    if (childServer && childServer.exitCode !== null && childServer.exitCode !== 0) break;
  }
  return "timeout";
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
    fullscreen: true,
    icon: path.join(__dirname, "..", "Resources", "icon.png"),
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true }
  });
  win.setMenuBarVisibility(false);

  // 启动即全屏：窗口显示后再进入原生全屏（时序上更可靠），加载完成再兜底一次
  const goFullscreen = () => {
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
  const target = urlToLoad || URL;
  const loadGUI = () => win.loadURL(target);
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (!url.startsWith(URL)) shell.openExternal(url);
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
    log("GUI 就绪: " + URL + " (" + state + ")");
    const loadGUI = makeWindow(URL);
    // 等窗口完成首帧后立即载入真实界面；若 splash 还在也直接覆盖
    loadGUI();
    if (DSH_AUTOCLOSE) {
      setTimeout(() => app.quit(), 1500);
    }
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) makeWindow(URL)();
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
