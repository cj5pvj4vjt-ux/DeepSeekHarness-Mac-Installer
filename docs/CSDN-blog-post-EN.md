# Packaging DeepSeek Harness into a One-Click macOS Installer, Step by Step (Apple Silicon Self-Contained Build, v0.2.0)

> Open-source project: [DeepSeekHarness-Mac-Installer](https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer) (build scripts + app source + 620 MB ready-made DMG)
>
> Requirements: macOS 13+ / Apple Silicon (M1–M4) / no prerequisites at all

---

## 1. Why I Built This Installer

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) is an open-source, full-stack AI agent workbench — sessions, memory management, marketing, themes, agent presets, image/video generation, cost tracking, and more. It's genuinely capable, but the official distribution is an npm package, which is a real barrier for non-programmers:

```bash
npm i -g @deepseek-ai/dsh   # first you need Node
dsh web                     # then start the server and open the browser
```

To let people who have never touched a terminal use it too, I wrapped it into a **macOS app you install by double-clicking**: double-click the DMG → double-click "Install" → everything is set up automatically and the fullscreen GUI opens.

The first version (0.1.0) came together quickly, but I soon uncovered a **fatal trap** — which is exactly the most valuable part of this post.

---

## 2. When v0.1.0 Went Up in Flames: Homebrew Dependency Leakage

### The Packaging Approach (v0.1.0)

```
DeepSeek Harness.app/
└── Contents/Resources/
    ├── app/main.js          # Electron main process: self-healing logic
    ├── runtime/bin/node     # Bundled Node 26.5.0 (arm64)
    ├── runtime/dsh/         # dsh CLI + 194 npm dependencies
    └── profile-seed-web/    # clean web profile seed (plugins)
```

What the Electron main process does:

1. On first launch, if the user has no `~/.dsh`, it copies the bundled seed over (**instant out-of-the-box for brand-new users**);
2. Probes port 3080; if nothing is listening, it boots `dsh web` with the bundled node;
3. Opens the GUI fullscreen and loads `http://127.0.0.1:3080`.

When packaging, I assumed that bundling node meant Homebrew didn't matter. Then I double-clicked the app on a **brand-new Mac (no Homebrew)** — the app vanished in a second, and the logs were completely empty.

### Investigation: `otool -L` Catches the Culprit

```bash
$ otool -L runtime/bin/node
    @rpath/libnode.147.dylib
    /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib      # ← absolute path!
    /opt/homebrew/opt/libuv/lib/libuv.1.dylib             # ← absolute path!
    /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib     # ← absolute path!
    ... (24 in total)
```

The truth: the **Homebrew-compiled node binary links 24 dynamic libraries under `/opt/homebrew/opt/*/lib` by absolute path** (openssl, icu4c, llhttp, libuv, simdjson, brotli, c-ares, zstd, sqlite, ngtcp2/nghttp3, etc.). On a fresh Mac with Homebrew none installed, dyld can't find those libraries and node just aborts — v0.1.0's "no Homebrew needed" claim simply didn't hold 😅.

> Lesson: **"I copied the binary" ≠ "self-contained"** — you must check the dynamic-library dependencies recursively.

---

## 3. The Core v0.2.0 Fix: Shipping All 24 dylibs Inside the App

### Three Steps

**① Collect dependencies recursively** (not just one level — dylibs depend on each other too):

```bash
scan() {
  otool -L "$1" | tail -n +2 | awk '/\/opt\/homebrew\//{print $1}' | while read -r d; do
    grep -qxF "$d" list.txt || { echo "$d" >> list.txt; scan "$d"; }
  done
}
```

**② Copy them all into `runtime/lib/` and rewrite the absolute paths to relative ones**:

```bash
# bin/node lives in bin/ → relative to lib is ../lib
install_name_tool -change /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib \
                              @loader_path/../lib/libllhttp.9.4.dylib  bin/node
# dylibs inside lib/ → same directory
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib \
                              @loader_path/libcrypto.3.dylib            lib/libnode.147.dylib
```

**③ Fill in the gaps and re-sign**: Homebrew also references sibling libraries via `@rpath` / `@loader_path` (icu's libicudata, brotli's libbrotlicommon) that an absolute-path scan can't see, so you must add them manually. And once you've modified a binary in an app on Apple Silicon, you **must re-sign it ad hoc** (`codesign --force --deep --sign -`) — otherwise the system SIGKILLs it on the spot.

After the fix:

```bash
$ otool -L bin/node | grep homebrew   # empty! All green ✅
$ runtime/bin/node --version          # v26.5.0 ✅
```

> All of this logic is baked into a reproducible script: `scripts/bundle-homebrew-deps.sh`.

---

## 4. Four Things I Fixed While I Was at It

1. **Upgraded the plugin set**: the v0.1.0 seed shipped only 7 plugins; I added three commonly used ones — video editor, AI image generation, and cost tracking — and bumped dsh-vision-router to 2.1.4.
2. **Bundled agent presets**: added `agent-presets-seed/`; on first launch it imports presets like "LiangShen Mode" into `~/.dsh/.agent-presets` (copies only if missing, never overwrites the user's own).
3. **Slimmed it down**: v0.1.0 accidentally shipped a duplicated 489 MB profile directory and an 875 MB empty partition inside the DMG. After cleanup it's **620 MB — smaller than v0.1.0's 792 MB**.
4. **Hardened privacy**: the seed contains only code/plugins/skeleton that config — **no API keys, no sessions, no history**.

---

## 5. Installer Contents (v0.2.0)

```
DeepSeek Harness.app/Contents/Resources/
├── app/main.js                    # Electron main process (self-healing + auto-start web)
├── runtime/bin/node               # Node 26.5.0 (arm64, self-contained)
├── runtime/lib/*.dylib                # libnode + 24 self-contained dylibs (relative refs)
├── runtime/dsh/                   # dsh CLI v0.1.0-rc.6 + 194 packages
├── profile-seed-web/              # clean web profile seed (dumped at build time)
├── agent-presets-seed/            # user-level agent presets (LiangShen Mode, etc.)
└── ...
```

`安装 DeepSeek Harness.app`/Contents/MacOS/installer  # password-free installer (bash script)

Built-in plugins at a glance:

| Plugin | Purpose |
|---|---|
| dsh-theme-cyberpunk2077 | Cyberpunk 2077 theme |
| @linxin666/dsh-web-ui-all | Web UI all-in-one kit |
| @anionex/dsh-computer-use | Computer control |
| dsh-vision-router v2.1.4 | Vision routing |
| @hackerfish/dsh-video-studio ★ | Video editor (new) |
| dsh-image-gen ★ | AI image generation (new) |
| dsh-cost-meter ★ | Cost tracking (new) |
| dshmarket | Plugin marketplace (China mirror) |

---

## 6. Downloading the Installer

- Project repo: https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer
- Direct download: https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest/download/DeepSeekHarness-0.2.0.dmg
- Release page: https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest

---

## 7. Usage Instructions (For Anyone Who Gets the Installer)

1. Double-click `DeepSeekHarness-0.2.0.dmg` (Finder auto-mounts it and pops the window open)
2. **Right-click → Open**「安装 DeepSeek Harness.app」→ click "Open" in the dialog
   (⚠️ it's not Apple-notarized, so a plain double-click gets blocked by Gatekeeper; right-click → Open once and you're in)
3. The installer automatically does everything: copy to `~/Applications` → initialize `~/.dsh` → launch the GUI fullscreen
4. Top-right settings → Models → paste in your own API key (DeepSeek or any compatible provider)
5. Start chatting! The 2077 theme and the full plugin kit work right out of the box

No Node, no Homebrew, no admin password, and completely offline.

---

## 8. Reproducing the Build from Source (Open-Source Project)

> ⚠️ This repo is the **open-source project behind the installer** (build scripts + app source + packaging workflow). **Just want the finished installer?** Grab the [DMG from Releases](https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest/download/DeepSeekHarness-0.2.0.dmg) and double-click to install.
> **Want to audit or build a customized version?** That's when the steps below apply.

```bash
# Clone it (github.com is flaky from some networks — retry, or use the Source.zip on the Releases page)
git clone https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer.git
cd DeepSeekHarness-Mac-Installer

# ① Environment: arm64 Mac + Homebrew + Node ≥ 20 (22/26 recommended)
brew install node
npm i -g @deepseek-ai/dsh

# ② Initialize your local web profile and install the full plugin kit
#    Full steps: docs/如何同步种子.md

# ③ One-command build (produces a new DMG)
#    ⚠️ Requires a pre-assembled "base DeepSeek Harness.app" as a template
./scripts/build-all.sh "<base DeepSeek Harness.app>" "<installer.app>" ./out
# Output: out/DeepSeekHarness.dmg
```

**Reproduction limitations**: a truly from-scratch rebuild requires you to first prepare a "base DeepSeek Harness.app" (an Electron shell wrapping dsh), and this repo does not include that Electron shell — that piece isn't in the repo. For most readers, **the release-ready installer is the recommended route**.

---

## 9. Pitfalls Worth Saving (You'll Thank Me Later)

1. **Check dependencies recursively for self-containment**: `otool -L` only shows one level, and dylibs depending on each other (node → libnode → icu → icudata), so sweep them with a script.
2. **Homebrew also has relative references internally**: icu uses `@loader_path` to reference libicudata, and brotli uses `@rpath` to reference libbrotlicommon — which an absolute-path scan misses, so patch them in by hand.
3. **Re-sign after modifying ANY binary**: after `install_name_tool`, the original signature is dead; skipping the re-sign on Apple Silicon gets you SIGKILLed (symptom: instant quit, no logs).
4. **Electron's single-instance lock**: if another instance of the same bundle ID is already running, the new one exits silently (exit 0, no logs) — give test copies a different group bundle ID.
5. **`app.getPath('home')` doesn't always respect `$HOME`**: on macOS it may return the user's real home directory, so mind where your logs land when simulating a fresh user.
6. **Inventory disk footprint before packaging**: `du -sh` every subdirectory and don't copy duplicate directories into the .app.

---

## 10. Disclaimer

This installer is a personal technical share; it is not affiliated with DeepSeek. Please only download and use it when served from trusted sources. DeepSeek Harness and its plugins are copyrighted by their respective owners.

**If this post helped you, a like, bookmark, and follow are all welcome～**