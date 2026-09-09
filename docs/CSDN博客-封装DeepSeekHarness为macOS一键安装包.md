# 手把手把 DeepSeek Harness 封装成 macOS 一键安装包（Apple Silicon 自包含版 v0.2.0）

> 开源工程：[DeepSeekHarness-Mac-Installer](https://github.com)（构建脚本 + App 源码 + 620MB 成品 DMG）
> 适用：macOS 13+ / Apple Silicon（M1~M4）/ 不需要任何先决条件

---

## 一、为什么要做这个安装包

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）是一个开源的全栈
AI 智能体工作台：有会话、插件市场、主题、Agent 预设、图像/视频生成、费用统计……功能很强，
但官方分发方式是 npm 包，对非程序员同学有门槛：

```bash
npm i -g @deepseek-ai/dsh   # 先得有 Node
dsh web                     # 再起服务、开浏览器
```

为了让完全不懂命令行的同学（比如我的学生们）也能用上，我把它封装成了一个
**双击就能装的 macOS App**：双击 DMG → 双击「安装」→ 自动装好、自动全屏打开 GUI。

第一版（0.1.0）很快做好了，但我发现了一个**致命的坑**——正好是本文最有价值的部分。

---

## 二、0.1.0 的翻车现场：Homebrew 依赖泄漏

### 封装思路（0.1.0）

```
DeepSeek Harness.app/
└── Contents/Resources/
    ├── app/main.js          # Electron 主进程：自愈逻辑
    ├── runtime/bin/node     # 内嵌 Node 26.5.0（arm64）
    ├── runtime/dsh/         # dsh CLI + 194 个 npm 依赖
    └── profile-seed-web/    # 干净的 web profile 种子（插件）
```

Electron 主进程做的事：
1. 首次启动时，如果用户没有 `~/.dsh`，就把内嵌种子拷贝过去（**全新用户秒开箱**）；
2. 探测 3080 端口，没服务就用内嵌 node 拉起 `dsh web`；
3. 全屏打开 GUI，加载 `http://127.0.0.1:3080`。

打包时我想当然地以为「内嵌了 node 就不需要 Homebrew 了」。直到我在一台
**全新 Mac（没装 Homebrew）** 上双击测试——App 秒退，日志一片空白。

### 排查：`otool -L` 揪出真凶

```bash
$ otool -L runtime/bin/node
    @rpath/libnode.147.dylib
    /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib      # ← 绝对路径！
    /opt/homebrew/opt/libuv/lib/libuv.1.dylib             # ← 绝对路径！
    /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib     # ← 绝对路径！
    ...（一共 24 个）
```

真相：**Homebrew 编译的 node 通过绝对路径链接了 `/opt/homebrew/opt/*/lib` 下的
24 个动态库**（openssl、icu4c、llhttp、libuv、simdjson、brotli、c-ares、zstd、
sqlite、ngtcp2/nghttp3 等）。全新 Mac 上没有 Homebrew，dyld 找不到这些库，
node 直接 abort —— 0.1.0 声称的「不需要 Homebrew」根本不成立 😅。

> 经验：**「拷了二进制 ≠ 自包含」**，必须递归检查动态库依赖。

---

## 三、v0.2.0 核心修复：把 24 个 dylib 全部打进 App

### 三步走

**① 递归收集依赖**（不只一层，dylib 之间还会互相依赖）：

```bash
scan() {
  otool -L "$1" | tail -n +2 | awk '/\/opt\/homebrew\//{print $1}' | while read -r d; do
    grep -qxF "$d" list.txt || { echo "$d" >> list.txt; scan "$d"; }
  done
}
```

**② 全部拷进 `runtime/lib/`，并把绝对路径重写为相对路径**：

```bash
# bin/node 在 bin/ 下 → 相对 lib 是 ../lib
install_name_tool -change /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib \
                              @loader_path/../lib/libllhttp.9.4.dylib  bin/node
# lib 下的 dylib → 同目录
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib \
                              @loader_path/libcrypto.3.dylib            lib/libnode.147.dylib
```

**③ 补漏 + 重签**：Homebrew 内部还有 `@rpath` / `@loader_path` 引用的兄弟库
（icu 的 `libicudata`、brotli 的 `libbrotlicommon`），绝对路径扫描抓不到，得手动补；
改过二进制的 app 在 Apple Silicon 上**必须重新 ad-hoc 签名**（`codesign --force --deep --sign -`），
否则直接被系统 SIGKILL。

修完后：

```bash
$ otool -L bin/node | grep homebrew   # 空！全绿 ✅
$ runtime/bin/node --version          # v26.5.0 ✅
```

> 这些逻辑已固化成可复现脚本：`scripts/bundle-homebrew-deps.sh`。

---

## 四、顺手做了四件事

1. **补插件全家桶**：0.1.0 种子只有 7 个插件，我把自己在用的
   `@hackerfish/dsh-video-studio`（视频工作室）、`dsh-image-gen`（AI 绘图）、
   `dsh-cost-meter`（费用统计）补了进去，并把 `dsh-vision-router` 从 2.1.2 升到 2.1.4。
2. **内置 Agent 预设**：新增 `agent-presets-seed/`，首启自动把「梁神模式」等预设
   导入 `~/.dsh/.agent-presets`（缺失才拷贝，绝不覆盖用户自己的）。
3. **减肥**：0.1.0 打包时误把 `profile-seed-web/profile-seed-web/`（489MB 重复目录）
   拷了进去，DMG 还预留了 875MB 空分区。清理后 **620MB，比 0.1.0 的 792MB 还小**。
4. **加固隐私**：种子只含代码/插件/配置骨架，**不含任何 API Key、会话、历史**。

---

## 五、安装包内容结构（v0.2.0）

```
DeepSeek Harness.app/Contents/Resources/
├── app/main.js                    # Electron 主进程（自愈 + 自动拉起 web）
├── runtime/bin/node               # Node 26.5.0（arm64，自包含）
├── runtime/lib/*.dylib            # libnode + 24 个自包含 dylib（@loader_path 相对引用）
├── runtime/dsh/                   # dsh CLI v0.1.0-rc.6 + 194 个包
├── profile-seed-web/              # 干净 web profile 种子（10 个插件）
├── agent-presets-seed/            # 用户级 agent presets（梁神模式 等）
└── ...                            # Electron 运行时

「安装 DeepSeek Harness.app」/Contents/MacOS/installer   # 免密安装器（bash 脚本）
```

内置插件一览：

| 插件 | 用途 |
|---|---|
| `dsh-theme-cyberpunk2077` | 2077 赛博朋克主题 |
| `@linxin666/dsh-web-ui-all` | Web UI 全家桶 |
| `@anionex/dsh-computer-use` | 电脑操控 |
| `dsh-vision-router` v2.1.4 | 视觉路由 |
| `@hackerfish/dsh-video-studio` ★ | 视频工作室（新增） |
| `dsh-image-gen` ★ | AI 绘图（新增） |
| `dsh-cost-meter` ★ | 费用统计（新增） |
| `dshmarket` | 插件商城（国内镜像） |

---

## 六、使用说明（写给拿到安装包的同学）

1. 双击 `DeepSeekHarness-0.2.0.dmg`（Finder 自动挂载并弹出窗口）
2. **右键 → 打开**「安装 DeepSeek Harness.app」→ 弹窗点「打开」
   （⚠️ 未做 Apple 公证，直接双击会被 Gatekeeper 拦，右键打开即可，只需一次）
3. 安装器自动：拷贝到 `~/Applications` → 初始化 `~/.dsh` → 全屏启动 GUI
4. 右上角设置 → 模型 → 填入你自己的 API Key（DeepSeek 或任意兼容 provider）
5. 开聊！2077 主题 + 全家桶插件直接可用

不需要 Node、不需要 Homebrew、不需要管理员密码、全程离线。

---

## 七、如何从源码复现（开源工程）

```bash
git clone <仓库> DeepSeekHarness-Mac-Installer && cd DeepSeekHarness-Mac-Installer

# 1. 准备本机环境（arm64 Mac + Homebrew）
npm i -g @deepseek-ai/dsh
# 2. 初始化 web profile 并安装全家桶插件（见 docs/如何同步种子.md）
# 3. 一键构建
./scripts/build-all.sh "<原始 DeepSeek Harness.app>" "<安装器.app>" ./out
```

| 脚本 | 作用 |
|---|---|
| `bundle-homebrew-deps.sh` | 递归收集 + 重写 dylib 依赖，runtime 自包含 |
| `sync-profile-seed.sh` | 用本机工作 profile 同步插件种子 |
| `build-app.sh` / `build-dmg.sh` / `build-all.sh` | 组装 / 打包 / 一键全流程 |

---

## 八、踩坑总结（建议收藏）

1. **二进制自包含要递归查依赖**：`otool -L` 只查一层，dylib 之间还会互相依赖
   （node → libnode → icu → icudata），用脚本递归扫。
2. **Homebrew 内部还有相对引用**：icu 用 `@loader_path` 引 `libicudata`、
   brotli 用 `@rpath` 引 `libbrotlicommon`，绝对路径扫描抓不到，要手动补。
3. **Apple Silicon 改二进制必重签**：`install_name_tool` 之后原签名失效，
   不重签会被系统 SIGKILL（表现为「秒退、无日志」）。
4. **Electron 单实例锁**：同一 bundle id 的 App 已在运行时，新实例会静默退出
   （exit 0 无日志）——测试时给副本换 bundle id。
5. **`app.getPath('home')` 不一定认 `$HOME`**：macOS 上可能返回真实用户主目录，
   做「全新用户」测试时要注意日志落点。
6. **打包前清点体积**：`du -sh` 每个 Resources 子目录，别把重复目录拷进 .app。

---

## 九、免责声明

本安装包为个人技术分享，与 DeepSeek 官方无关联；请在可信来源下载使用。
DeepSeek Harness 及其插件版权归各作者所有。

**如果这篇文章对你有帮助，欢迎点赞、收藏、关注～**
