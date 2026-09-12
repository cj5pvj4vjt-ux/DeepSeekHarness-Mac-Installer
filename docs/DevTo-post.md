---
title: "Shipping a Self-Contained macOS App: How 24 Homebrew dylibs Broke My DeepSeek Harness Installer"
published: false
description: "I packaged DeepSeek Harness (dsh) into a double-clickable macOS installer for Apple Silicon. It worked on my machine — then died instantly on a clean Mac. Here's the otool -L investigation that found 24 absolute Homebrew paths, and how to bundle them properly."
tags: macos, electron, opensource, ai
cover_image: ""
canonical_url: ""
---

**TL;DR** — I wrapped an npm-distributed AI agent workbench into a double-click macOS installer. It worked on my machine, then quit instantly with zero logs on a clean Mac. `otool -L` revealed 24 dynamic libraries linked by absolute Homebrew paths. Fixing it meant copying every dylib into the app bundle, rewriting paths to `@loader_path`, and re-signing. The installer got *smaller* (792 MB → 620 MB) while gaining three plugins. Repo and build scripts are open source.

---

## The Problem With "Just `npm i -g`"

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) is an open-source full-stack AI agent workbench: sessions, a plugin marketplace, themes, agent presets, image/video generation, cost tracking. It's genuinely powerful — but the official distribution is an npm package:

```bash
npm i -g @deepseek-ai/dsh   # requires Node
dsh web                     # then start the server and open a browser
```

That's a non-starter for anyone who has never opened a terminal. Some of the people I wanted to share it with fall into exactly that category, so I wrapped it into a **macOS app you install by double-clicking**: mount the DMG → double-click "Install" → the GUI opens fullscreen, no questions asked.

Version 0.1.0 came together in an evening. Then I tested it on a machine that had never seen Homebrew.

## It Worked on My Machine (the Worst Kind of Bug)

The Electron main process is deliberately boring:

1. On first launch, if `~/.dsh` doesn't exist, copy the bundled seed profile into place (instant out-of-the-box experience for new users).
2. Probe `127.0.0.1:3080`; if nothing is listening, boot `dsh web` using the bundled Node binary.
3. Open a fullscreen window on that URL.

The bundle layout:

```
DeepSeek Harness.app/
└── Contents/Resources/
    ├── app/main.js          # Electron main process: self-healing logic
    ├── runtime/bin/node     # bundled Node 26.5.0 (arm64)
    ├── runtime/dsh/         # dsh CLI + 194 npm dependencies
    └── profile-seed-web/    # clean web profile seed (plugins)
```

I assumed that bundling `node` meant Homebrew was irrelevant. On the clean Mac, the app vanished in about a second, and the log file was empty. Not *missing* — empty. Electron never even got far enough to write anything.

## `otool -L` Finds the Culprit

```bash
$ otool -L runtime/bin/node
    @rpath/libnode.147.dylib
    /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib      # ← absolute path!
    /opt/homebrew/opt/libuv/lib/libuv.1.dylib             # ← absolute path!
    /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib     # ← absolute path!
    ... (24 in total)
```

Homebrew's `node` build links **24 dynamic libraries by absolute path** under `/opt/homebrew/opt/*/lib` — OpenSSL, ICU, llhttp, libuv, simdjson, brotli, c-ares, zstd, SQLite, ngtcp2/nghttp3, and friends. No Homebrew on the target machine means `dyld` can't resolve them, and the process aborts before Electron can log a thing.

So 0.1.0's "no Homebrew required" claim was simply false. 😅

> **Lesson:** copying a binary into your app bundle does **not** make it self-contained. You have to walk the dependency graph.

## The Fix: Bundle Every dylib and Rewrite the Paths

### Step 1 — Collect dependencies recursively

One `otool -L` pass isn't enough: dylibs depend on other dylibs (`node → libnode → icu → icudata`).

```bash
scan() {
  otool -L "$1" | tail -n +2 | awk '/\/opt\/homebrew\//{print $1}' | while read -r d; do
    grep -qxF "$d" list.txt || { echo "$d" >> list.txt; scan "$d"; }
  done
}
```

### Step 2 — Copy them in and rewrite absolute paths to relative ones

```bash
# bin/node lives in bin/ → relative path to lib is ../lib
install_name_tool -change /opt/homebrew/opt/llhttp/lib/libllhttp.9.4.dylib \
                              @loader_path/../lib/libllhttp.9.4.dylib  bin/node

# dylibs inside lib/ → same directory
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib \
                              @loader_path/libcrypto.3.dylib            lib/libnode.147.dylib
```

### Step 3 — Plug the gaps, then re-sign

Two libraries slip past an absolute-path grep because Homebrew already references them relatively:

- ICU: `libicuuc` → `@loader_path/libicudata.78.dylib`
- brotli: `libbrotlidec`/`libbrotlienc` → `@rpath/libbrotlicommon.1.dylib`

Copy those in by hand and rewrite the `@rpath` reference. Then, because you've modified Mach-O binaries inside an app bundle, on Apple Silicon you **must** re-sign ad hoc:

```bash
codesign --force --deep --sign -
```

Skip that step and the OS sends `SIGKILL` — which looks exactly like the original bug: instant quit, empty logs.

Verification:

```bash
$ otool -L bin/node | grep homebrew   # empty — all green ✅
$ runtime/bin/node --version          # v26.5.0 ✅
```

All of this is wrapped in a reusable script: `scripts/bundle-homebrew-deps.sh`.

## Three Plugins In, 172 MB Out

While I was in there:

1. **Plugin set upgraded** — the 0.1.0 seed shipped 7 plugins; I added a video editor, AI image generation, and cost tracking, and bumped `dsh-vision-router` to 2.1.4.
2. **Bundled agent presets** — a new `agent-presets-seed/` directory is imported into `~/.dsh/.agent-presets` on first launch. It only copies what's missing and never overwrites a user's own presets.
3. **Slimmed down** — 0.1.0 accidentally embedded a duplicated 489 MB profile directory and an 875 MB empty partition inside the DMG. After cleanup: **620 MB, down from 792 MB**, with *more* functionality.
4. **Privacy hardening** — the seed contains code, plugins, and a config skeleton. No API keys, no sessions, no history.

## What Ships Inside

```
DeepSeek Harness.app/Contents/Resources/
├── app/main.js                    # Electron main process
├── runtime/bin/node               # Node 26.5.0 (arm64, self-contained)
├── runtime/lib/*.dylib            # libnode + 24 bundled dylibs
├── runtime/dsh/                   # dsh CLI v0.1.0-rc.6 + 194 packages
├── profile-seed-web/              # clean web profile seed
└── agent-presets-seed/            # user-level agent presets
```

Plugins included out of the box: a Cyberpunk 2077 theme, a web UI kit, computer control, vision routing v2.1.4, a video studio, AI image generation, cost tracking, and the plugin marketplace.

## Installing It

1. Mount the DMG (Finder opens the window for you).
2. **Right-click → Open** the installer → click "Open" in the dialog. It isn't Apple-notarized, so a plain double-click is blocked by Gatekeeper — this is a one-time step.
3. The installer copies the app to `~/Applications`, initializes `~/.dsh`, and launches the GUI fullscreen.
4. Settings → Models → paste your own API key (DeepSeek or any compatible provider).

No Node, no Homebrew, no admin password, fully offline.

- **Repo:** https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer
- **Release:** https://github.com/cj5pvj4vjt-ux/DeepSeekHarness-Mac-Installer/releases/latest

## Six Things I'd Tell My Past Self

1. **Verify self-containment recursively.** `otool -L` shows one level. Dylibs depend on dylibs — script the sweep.
2. **Homebrew has internal relative references.** ICU's `libicudata` and brotli's `libbrotlicommon` are referenced via `@loader_path`/`@rpath` and won't show up in an absolute-path grep.
3. **Re-sign after touching any binary.** `install_name_tool` invalidates the signature; on Apple Silicon the OS kills unsigned binaries outright — symptom: instant quit, no logs.
4. **Electron's single-instance lock will fool you.** If an app with the same bundle ID is already running, the new instance exits silently with code 0. Give test copies a different bundle ID.
5. **`app.getPath('home')` doesn't always respect `$HOME`.** On macOS it can return the real user home, so your "fresh user" test may be writing logs somewhere else entirely.
6. **Audit bundle size before you ship.** `du -sh` every Resources subdirectory — duplicate directories hide easily.

## Closing Thoughts

The interesting part of this project wasn't the Electron shell — it was discovering that "self-contained" is a claim you have to *prove*, not assume. A 24-line dependency scan and a `codesign` call were the difference between an app that works on the author's laptop and one that works on a stranger's.

If you're packaging anything with native dependencies for macOS, run the recursive scan before you ship. It takes two minutes and saves a very confusing bug report.

The build scripts, the Electron main process, and the plugin-seeding logic are all in the repo — issues and PRs welcome, especially if you've solved the notarization problem more elegantly than "right-click → Open."

*Not affiliated with DeepSeek. DeepSeek Harness and its plugins belong to their respective authors.*
