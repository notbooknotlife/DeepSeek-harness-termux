# dsh-termux-deploy

在 **Termux / Android** 上**一键部署 DeepSeek Harness（DSH）** 的脚本，并针对**手机端 Web UI 访问**做了适配。

> 为什么需要这个脚本？
> DSH 官方文档假设的是普通 Linux（有 sudo、完整 node-gyp、可用的文件沙箱内核）。
> Termux 既没有传统 root / npm 语义，又常缺 node-gyp，Android 内核还默认缺
> Landlock / bubblewrap，导致官方 `npm install -g @deepseek-ai/dsh` 直接跑不起来。
> 本脚本把这些 Termux 差异的处理全部封装好，做到一键可运行。

---

## 功能特性

- **一键安装**：自动补 `node-gyp`、配置 npm 原生模块编译白名单、从官方 npm 安装 `@deepseek-ai/dsh`、初始化 `web` profile。
- **幂等安全**：重复运行不报错；改动 `.npmrc` 前先备份，可一键还原。
- **手机端 UI 适配**：`serve` 支持绑定 `0.0.0.0`，让手机本机及同一 WiFi 下的电脑都能访问，并自动打印局域网访问地址。
- **可审计**：全程日志 + 生成改动清单 manifest。
- **自检**：`doctor` / `status` 诊断环境与运行状态。
- **模块化**：每个功能一个函数，配置集中在顶部，便于 Fork 后自定义重构。

---

## 快速开始

### 1. 临时执行（不落盘审阅前请先去仓库看源码）

```sh
bash dsh-termux-deploy.sh install
```

> **安全提醒**：`curl | bash` 会直接执行远程代码。强烈建议**先将脚本下载到本地审阅**，
> 或设置发布指纹（见下文「安全加固」）后再执行。

### 2. 推荐：先下载审阅再执行

```sh
# 下载到本地
curl -fsSL https://raw.githubusercontent.com/<你的用户名>/dsh-termux-deploy/main/dsh-termux-deploy.sh \
  -o ~/dsh-termux-deploy.sh

# 审阅内容后再执行
bash ~/dsh-termux-deploy.sh install
```

### 3. 启动 Web UI（含手机端访问）

```sh
# 仅本机访问
bash dsh-termux-deploy.sh serve

# 让同 WiFi 下的手机/电脑都能访问（绑定 0.0.0.0）
bash dsh-termux-deploy.sh serve --host 0.0.0.0

# 自定义端口
bash dsh-termux-deploy.sh serve --host 0.0.0.0 --port 8080
```

启动后脚本会打印类似：

```
--------------------------------------------------------------
  本机访问:      http://127.0.0.1:3080
  局域网设备访问: http://172.25.57.101:3080
--------------------------------------------------------------
```

用手机浏览器打开 `http://172.25.57.101:3080` 即可访问（需手机与该终端在同一网络）。

---

## 命令一览

| 命令 | 说明 |
|------|------|
| `install` | 安装 DSH + 初始化 profile |
| `serve` | 启动 Web UI（`--host 0.0.0.0` 令局域网可访问） |
| `uninstall` | 卸载 DSH 并还原 `.npmrc` |
| `doctor` | 环境自检（node/gcc/node-gyp/DSH 是否就绪） |
| `status` | 查看服务与进程状态 |
| `help` | 查看用法 |

通用参数：`--host <ip>`、`--port <端口>`（放子命令前，如 `bash dsh-termux-deploy.sh --host 0.0.0.0 serve`）。

---

## 安全加固（建议发布前阅读）

脚本顶部预留了发布指纹变量 `EXPECTED_SHA256`（当前为空 = 仅提示不强校验）。
如果你想对分发做强校验，请：

1. 本地跑一次指纹生成：
   ```sh
   sha256sum dsh-termux-deploy.sh
   ```
2. 将结果填到脚本顶部：
   ```sh
   EXPECTED_SHA256="<你的sha256>"
   ```
3. 这样脚本每次运行时都会自校验，发现被篡改即拒绝执行。

> 由于脚本在「上传 GitHub → 你本地下载」时内容可能因为换行/编码不同而改变指纹，
> 建议生成指纹的脚本与线上发布的是**同一份文件**，并在 CI 中校验。

---

## 手机端 UI 适配说明

- `dsh web` 本身就是响应式 Web 界面，手机浏览器直接可用。
- 但 DSH 默认只绑定 `127.0.0.1`，脚本通过 `--host 0.0.0.0` 放开绑定供局域网访问。
- 局域网 IP 自动检测：优先取 `wlan` 接口，回退取第一个非回环地址（已排除 docker/tun 等）。
- ⚠️ **防火墙/代理**：若手机网络有代理或防火墙，可能影响局域网访问。Termux 环境一般无需额外配置。

---

## 卸载

```sh
bash dsh-termux-deploy.sh uninstall
```

说明：卸载会删除程序本体并还原 `.npmrc`，但**保留 `~/.dsh` 配置目录**（含会话与凭据）。
如需彻底删除，手动执行：`rm -rf ~/.dsh`。

---

## 开发 / 贡献

本项目刻意写成**模块化、可重构**：

- **配置区**：脚本顶部集中所有路径 / 端口 / 白名单，改这里即可调行为。
- **函数划分**：`doctor` / `install_dsh` / `init_profile` / `serve` / `uninstall` / `status_cmd`。
- **子命令分发**：底部 `case "$COMMAND"` 统一路由。

你可以直接 Fork 本仓库，按需修改。建议调整点：

- 自定义 npm 镜像（如国内镜像）——修改 `configure_npm_for_dsh` 里的 `registry`。
- 自定义端口默认值——修改 `LANG_LISTEN_HOST` / `LANG_LISTEN_PORT`。
- 自定义原生模块白名单——修改 `NPM_ALLOW_SCRIPTS` 数组。

---

## 环境要求

- Termux（`PREFIX=/data/data/com.termux/files/usr`）
- 已安装：`node`、`npm`、`gcc`/`g++`/`make`（编译器，用于原生模块）
- 网络可达 `registry.npmjs.org`

## 许可证

MIT

---

## 一行远程部署（bootstrap 引导）

仓库里附带了 `bootstrap.sh` —— 一个**极短的引导器**，支持 `curl | bash` 一行调用，
同时仍做下载 + 校验 + 执行：

```sh
# 先改 bootstrap.sh 里的 RAW_BASE 为你自己的 raw 地址，再 push。

# 一键调用（把 install 换成 serve/uninstall/doctor 等任意命令）
bash -c "$(curl -fsSL https://raw.githubusercontent.com/<你的用户名>/dsh-termux-deploy/main/bootstrap.sh)" install
```

> 为什么用 bootstrap 而不是直接 curl 整个安装器？
> 安装器有数十 KB，直接 `$(curl ...)` 传参会有 shell 参数大小/引号风险。
> 把「引导」和「安装」分离：bootstrap 短到可安全内联，真正的逻辑在 install 里.
>
> **务必**：bootstrap 里把 `APPROVED_SHA256` 填上安装器的真实指纹开启强校验，
> 否则 curl | bash 仍绕过审阅，存在供应链被篡改的风险。

---

## 手机端 UI 适配

DSH 的 Web UI 在手机窄屏下，**设置面板**容易出现布局问题：左导航栏过宽挤压右栏、
文本竖排、Agent预设卡片在窄屏被截半。本仓库提供一套**专为设置面板优化**的移动端适配，
三种注入方式任选其一，且**样式源 `mobile.css` 本地可编辑**。

### 三种注入方式（任选其一）

| 方式 | 适用 | 操作 |
|------|------|------|
| **user.js（推荐）** | Kiwi / Firefox + Tampermonkey/Violentmonkey | 安装 `mobile/dsh-setting-mobile.user.js`，打开页面自动注入 |
| **书签** | 任意浏览器 | 把 `mobile/bookmarklet.txt` 内容存成书签，打开页面后点一下 |
| **手动控制台** | 调试/临时 | 浏览器控制台粘贴 `mobile/mobile.css` 内容后 enter |

> 三个文件（`dsh-setting-mobile.user.js` / `bookmarklet.txt` / `mobile.css`）内容一致，
> 都是同一套设置面板适配方案。

### 这套适配做了什么

- **设置面板**：顶部、底部各留 15% 视口高，面板固定 70vh、水平居中，不再盖满或贴顶。
- **左导航栏**：限宽约 128px（保留文字），让出右栏空间。
- **右内容区**：吃掉剩余空间，**禁止横向溢出**；内容多时在面板内**纵向滚动**。
- **Agent预设 卡片**：窄屏（<620px）改**单列自适应**，不再被截断成一半。
- **文本**：自适应字号 + 强制横排，杜绝竖排。

### 修改样式

编辑 `mobile/mobile.css` 即可调整（如左栏宽度、上下留空比例、字号）。
```

如果用的是 user.js（内联版），改样式后需在 Tampermonkey 里同步更新；若用书签/控制台，
重新复制最新 `mobile.css` 内容即可。

> 默认注入地址匹配 `http://*:3080/*`（覆盖本机 `127.0.0.1`、`localhost` 及局域网 IP）。
> 自定义端口请在 `dsh-setting-mobile.user.js` 里调整 `@match` 规则。
