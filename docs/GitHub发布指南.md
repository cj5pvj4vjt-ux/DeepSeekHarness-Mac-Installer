# GitHub 开源发布指南（一步步照做即可）

> 目标：把本地仓库推送到 GitHub，并在 Release 里放出 620MB 的安装包。
> 全程约 10 分钟。**GitHub 单个 Release 文件上限 2GB**，DMG 620MB 完全没问题。

---

## 第 0 步：准备（只做一次）

### 0.1 注册 GitHub 账号并用邮箱验证
https://github.com/signup

### 0.2 设置本地 git 用户（重要，否则提交不显示你的头像）

```bash
git config --global user.name "你的GitHub用户名"
git config --global user.email "你注册GitHub用的邮箱"
```

如果仓库之前用占位作者提交过，可以改掉第一次提交的作者：

```bash
cd ~/Desktop/AP计算机/付老师/Projects/Deepseekharness/DeepSeekHarness-Mac-Installer
git config user.name "你的GitHub用户名"
git config user.email "你注册GitHub用的邮箱"
git commit --amend --reset-author --no-edit   # 只改最近一条提交的作者
```

### 0.3 生成 Personal Access Token（PAT，推荐用 gh 之外也通用）
https://github.com/settings/tokens → **Generate new token (classic)**
- 勾选 `repo`（完整仓库权限）即可
- 复制生成的 `ghp_xxxx...`（只显示一次，马上存好）

> 用 PAT 当密码登录，比 SSH 简单，git 会记住它。

---

## 方式 A：用 gh 命令行（最省事，推荐）

```bash
# 安装 GitHub CLI（需要 Homebrew）
brew install gh

# 登录（选 HTTPS 方式，粘贴第0.3步的 Token）
gh auth login

# 在仓库目录里创建 GitHub 仓库并推送
cd /Users/maomao/Desktop/AP计算机/付老师/Projects/Deepseekharness/DeepSeekHarness-Mac-Installer
gh repo create DeepSeekHarness-Mac-Installer --public --source . --push --description "DeepSeek Harness macOS 一键安装包（Apple Silicon 自包含版）：双击安装、零依赖、内置10个插件全家桶"

# 打标签 + 发布 Release（DMG 会被直接传到 Release 附件）
git tag v0.2.0
git push origin v0.2.0
gh release create v0.2.0 "/Users/maomao/Desktop/AP计算机/付老师/Projects/Deepseekharness/DeepSeekHarness-0.2.0.dmg" \
  --title "v0.2.0 自包含版" \
  --notes-file RELEASE_NOTES.md
```

完成！打开 `https://github.com/你的用户名/DeepSeekHarness-Mac-Installer` 就能看到仓库；
Release 页面有你的 DMG，访客点一下就能下载。

---

## 方式 B：网页操作（不想装 gh）

### B1 创建空仓库
https://github.com/new
- Repository name：`DeepSeekHarness-Mac-Installer`
- Description：`DeepSeek Harness macOS 一键安装包（Apple Silicon 自包含版）：双击安装、零依赖、内置10个插件全家桶`
- Public（公开）
- **不要**勾选 "Add a README / .gitignore / license"（本地仓库已有）

### B2 推送本地仓库（在终端执行）

```bash
cd ~/Desktop/AP计算机/付老师/Projects/Deepseekharness/DeepSeekHarness-Mac-Installer
git remote add origin https://github.com/你的用户名/DeepSeekHarness-Mac-Installer.git
git branch -M main
git push -u origin main
```

> 弹窗登录时：用户名填你的 GitHub 用户名，密码粘贴第0.3步的 Token。

### B3 发布 Release 附上 DMG
1. 打开仓库页 → 右侧 **Releases** → **Create a new release**
2. Tag：填 `v0.2.0`（或点 "Choose a tag" 新建）
3. 标题：`v0.2.0 自包含版：修复 Homebrew 依赖 + 插件全家桶`
4. 说明：粘贴 `RELEASE_NOTES.md` 的内容
5. 把本地 `DeepSeekHarness-0.2.0.dmg` **拖进附件区**（620MB OK）
6. 点 **Publish release**

---

## 项目描述（About）怎么做 —— 直接抄

仓库页**右上角** → **About 栏的齿轮 ⚙️**：

- **Description**（一句话，≤350 字符）：
  ```
  DeepSeek Harness macOS 一键安装包（Apple Silicon 自包含版）：双击安装、零依赖、离线可用，内置 2077 主题 + 10 个插件全家桶 + Agent 预设
  ```
- **Website**（可选）：留空，或填你的 CSDN 博客 URL
- **Topics**（用回车分隔，可多选）：依次输入
  ```
  deepseek  deepseek-harness  electron  macos  dmg  installer  ai  agent  apple-silicon  open-source
  ```

保存后仓库首页右上角会出现标签，别人一搜就能找到。

---

## 四、收尾（可选但推荐）

1. **README 加徽章**：在 `README.md` 顶部加
   ```markdown
   ![平台](https://img.shields.io/badge/platform-macOS%2013%2B-007AFF)
   ![架构](https://img.shields.io/badge/arch-Apple%20Silicon-blue)
   ![许可](https://img.shields.io/badge/license-MIT-green)
   ```
2. **把博客里的占位链接替换**成你真实的仓库地址（`docs/CSDN博客-*.md` 里
   开头写的是 `https://github.com` 占位符）。
3. **<48h 内不要在博客里发太"硬广"**：CSDN 新号发带 GitHub 外链的文章容易风控，
   建议正文中只放仓库名，用"GitHub 搜索 DeepSeekHarness-Mac-Installer"代替直接外链（更安全）。
4. 文件服务器注意：DMG 在 GitHub Release 上会被限速，国内访客建议附上
   **夸克网盘/123网盘/蓝奏云** 备份链接（正文里提一下"网盘镜像"更贴心）。

---

## 五、仓库最终长这样

```
DeepSeekHarness-Mac-Installer/
├── README.md            ← 你的项目门面（已有，建议补徽章）
├── LICENSE              ← MIT（已有）
├── CHANGELOG.md         ← 版本记录（已有）
├── RELEASE_NOTES.md     ← Release 说明（已生成）
├── app/main.js          ← Electron 主进程源码
├── installer/           ← 安装器脚本
├── scripts/             ← 5 个可复现构建脚本
└── docs/                ← 种子同步指南 + CSDN 博客稿
```