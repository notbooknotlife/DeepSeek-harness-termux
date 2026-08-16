# dsh-termux-deploy

在 **Termux / Android** 上一键部署 **DeepSeek Harness（DSH / `dsh web`）** 的脚本 +
手机端 UI 适配层。目标：**一条命令在干净的 Termux 上装好 DSH 并跑起来**。

DSH 官方文档假设的是普通 Linux；Termux（无传统 root、缺 node-gyp、Android 内核缺
Landlock/bubblewrap、原生模块需现场编译）无法直接 `npm install -g` 跑起来。
本仓库把这些 Termux 差异、缺包、编译坑全部封装进 `install`，并附手机端适配。

---

## 快速开始（一键）

在**干净的新装 Termux** 里，先做两步准备（**请务必先自己更新 Termux 软件源**，
脚本不再代劳）：

```sh
# ① 刷新并升级 Termux 软件源（确保环境索引正常，网络慢也可先只 update）
pkg update -y && pkg upgrade -y

# ② 可选：授权访问手机存储（默认工作区在 Termux 内部，不强制需要）
#    如要让 DSH 也读写手机存储再执行:
# termux-setup-storage
```

> **🚀 提速 Tip：`pkg update/upgrade` 太慢或卡住？请切换国内镜像源再执行：**
>
> ```sh
> termux-change-repo
> ```
> 选择 mirrors.tuna.tsinghua.edu.cn
> 按**回车**确认保存；
> 回终端重新执行：`pkg update -y && pkg upgrade -y`
> 想还原官方源，在列表里选 **`Mirrors by Termux (default repository)`** 即可。


然后一行部署（装缺失依赖→编译→装 DSH→打补丁→验证）：

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/notbooknotlife/DeepSeek-harness-termux/main/bootstrap.sh)" install
```

> **首次运行**：装编译链 + `npm install` DSH + 现场编译 koffi/node-pty 等原生模块
>（下载/编译阶段几分钟，**无输出属正常**，保持屏幕常亮）。
>
> **提速设计**：脚本**不执行 `pkg update/upgrade`**（由你自行维护、更快更可控），
> 只在需要时 `pkg install` 缺失依赖；`npm` 用 `--prefer-offline` 复用缓存；
> 已装的依赖对应步骤直接跳过。

安装完成后启动：

```sh
dsh web
```
手机浏览器打开 `http://127.0.0.1:3080`，首次使用在 **设置 → 模型** 配置 LLM API Key。

---

## 环境要求（Termux 干净环境需要哪些）

`install` 会自动安装/补齐以下内容（缺哪个补哪个）：

| 类别 | 包/工具 | 用途 |
|------|---------|------|
| **编译链** | `git curl cmake clang make gcc python binutils pkg-config termux-tools` | 编译 koffi/node-pty 等原生模块 |
| **运行时** | `nodejs`（自带 npm） | DSH 运行 |
| **库/头文件** | `libandroid-support`、`libandroid-spawn`、`libandroid-glob` | 提供 `spawn.h` 等 Bionic 缺失的 POSIX 头文件（koffi 编译必需） |
| **包管理** | `node-gyp`、`pnpm` | node-pty 编译、DSH profile |
| **存储** | （可选）`termux-setup-storage` | 如需读写手机存储；默认工作区在 Termux 私有 `~/.dsh/workspace`，无需手机存储 |
| **DSH 本体** | `npm install -g @deepseek-ai/dsh` | 主程序 |
| **sharp 运行时** | `@img/sharp-wasm32` + `@emnapi/runtime` | **android-arm64 无 sharp 原生二进制，必须 WASM 兜底** |

> 环境要求版本：Node ≥ 22.12（DSH 依赖）。

---

## 已知坑与自动修复（脚本已内嵌处理）

| 现象 | 原因 | 脚本处理 |
|------|------|---------|
| 一键命令 404 | bootstrap `RAW_BASE` 占位未填 | 已改为真实仓库地址 |
| `BASH_SOURCE[0]: unbound variable` | `curl \| bash` 经 stdin 执行时机目录为空 | `SCRIPT_DIR` 安全降级 |
| 一键只显示 usage、不装 | bootstrap 命令参数(`$0`)没透传 | 修复 bootstrap 参数透传 |
| `koffi: 'spawn.h' file not found` | 缺 `libandroid-support` 头文件 | `ensure_tools` 用 `dpkg -s` 补装库依赖 |
| `Could not load "sharp" ... android-arm64` | sharp 无 android 原生产物 | 随 D 阶段直接装 wasm32+emnapi 并 `import('sharp')` 验证 |
| `--expose-internals is required for HMR` | npm 默认 bin 不带该 flag | `install_launcher` 写带 flag 包装器，`serve` 启动前自检重建 |
| 会话保存 `EACCES link()` | 部分 ROM 禁用 link() 系统调用 | `patch_link_rename` 改 `rename()` |

---

## 命令一览

| 命令 | 说明 |
|------|------|
| `install` | 完整安装（自动装依赖/编译/装 DSH/打补丁/验证） |
| `serve [--host 0.0.0.0] [--port]` | 启动 Web UI（`--host 0.0.0.0` 供局域网访问） |
| `doctor` | 环境自检（node/编译链/DSH 是否就绪） |
| `status` | 查看服务/进程状态 |
| `mobile` | 重新生成手机端 UI 适配资源到 `~/.dsh-mobile` |
| `uninstall` | 卸载 DSH 并还原 `.npmrc` |

用法：`bash <脚本> 命令 [--host ip] [--port 端口]`。

---

## 安装后生成的文件/文件夹说明

`install` 默认会把工作区、手机端适配、DSH 控制菜单**收到 Termux 内部固定目录**，
方便统一管理/删除，且不污染手机存储。它们分别是什么、为什么生成：

| 路径 | 内容 | 为什么生成 |
|------|------|-----------|
| **`~/.dsh/workspace`** | DSH 的工作区根（fs-sandbox 默认目录） | DSH Web UI 读写文件都在这里，便于删除、不散到手机存储。可用 `DSH_WORKSPACE` 覆盖。 |
| **`~/.dsh/profiles/web/cordis.patch.yml`** | DSH 设置面板的 patch 配置（cwd 指向 workspace） | DSH 启动必需的 profile 配置。 |
| **`~/.dsh-mobile/`** | 手机端 UI 适配资源 | 手机浏览器注入用：`mobile.css`(样式)、`dsh-mobile.user.js`(Tampermonkey)、`bookmarklet.txt`(书签)。**一键安装会从 GitHub 自动下载**，无需 clone。 |
| **`~/.dsh/dshmenu.sh`** | DSH 交互控制菜单脚本 | 让 `dsh`(无参数) 弹出：启动 / 自定义端口 / 局域网 / 状态 / 卸载 的菜单。 |
| **`~/.dsh/dshrc.sh`** | shell 集成片段（定义 `dsh` 函数） | 让 `dsh` 无参数弹菜单、带参数走原生。由 install 自动 source 进 `~/.bashrc`。 |
| **`~/.bashrc` 追加的一行** | `source ~/.dsh/dshrc.sh` | 每次开 Termux 自动启用 dsh 控制菜单。幂等，不会重复添加。 |
| **`~/.npmrc`** | npm 配置(registry/镜像/超时) | 安装 DSH 时的网络配置，安装前会先备份为 `.npmrc.dsh.bak`，卸载可还原。 |

> **为什么放在 `~/.dsh` / `~/.dsh-mobile` 而不是手机存储**：① 删除方便（`rm -rf`）；② 与 DSH 本体一致，数据不散溢；③ 卸载脚本能统一清理。

---

## DSH 控制菜单（dshmenu）

安装后输入 **`dsh`**（不带参数）或在菜单里操作，会弹出交互式控制菜单：

```
╔══════════════════════════════════╗
║          DSH 控制菜单            ║
║  1) 直接启动        → dsh web   ║
║  2) 自定义端口启动  → 输入端口   ║
║  3) 局域网启动      → 输入端口   ║
║  4) 查看状态                    ║
║  5) 完全卸载                    ║
║  0) 退出                        ║
╚══════════════════════════════════╝
```

### 各选项行为

| 输入 | 行为 |
|------|------|
| **1** | 后台**常驻**启动（默认 `127.0.0.1:3080`），自动打开浏览器，回车返回菜单 |
| **2** | 提示输入端口，**测试模式**：开启端口供测试，**按回车返回菜单那一刻才关闭端口**；输 `0` 返回上一层 |
| **3** | 同 2（局域网 `0.0.0.0`），测试模式，回车返回时关端口 |
| **4** | 查看 DSH 服务/安装状态，回车返回菜单 |
| **5** | 完全卸载（**5 确认卸载并退出菜单/0 返回菜单/其他无效**） |
| **0** | 退出菜单 |

### 卸载范围（选项5）
完全卸载会清理：**DSH 本体、`dsh` 命令、`~/.dsh`(配置/会话/工作区/menu)、`~/.dsh-mobile`，并移除 `~/.bashrc` 里的 dsh 菜单引用**。**npm 全局包（pnpm/node-gyp 等）保留**，不会误删环境工具。

> 启动命令 `dsh web` 由 install 自动启用（写入 `~/.bashrc`）。若手动 clone 使用，请先 `source ~/.dsh/dshrc.sh`。

---

## 手机端 UI 适配

DSH 的 Web UI 默认仅绑 `127.0.0.1`；`serve --host 0.0.0.0` 放开供手机/局域网访问，
并自动打印访问地址。手机窄屏下设置面板易出现布局问题（左栏过宽、文本竖排、
卡片被截半），仓库提供**本地可编辑**的适配方案（`mobile/`），三种注入方式：

| 方式 | 适用 | 操作 |
|------|------|------|
| **user.js** | Kiwi/Firefox + Tampermonkey | 安装 `mobile/dsh-setting-mobile.user.js`，页面自动注入 |
| **书签** | 任意浏览器 | 把 `mobile/bookmarklet.txt` 存成书签，打开后点一下 |
| **控制台** | 调试 | 浏览器控制台粘贴 `mobile/mobile.css` |

三份内容一致；改 `mobile/mobile.css` 即可调样式。注入默认匹配 `http://*:3080/*`。

---

## 卸载

```sh
bash <脚本> uninstall
```
删除程序本体并还原 `.npmrc`，但保留 `~/.dsh`（会话/凭据）。彻底删除：`rm -rf ~/.dsh`。

---

## 安全加固（可选）

脚本顶部预留 `APPROVED_SHA256`（位于 `bootstrap.sh`）与 `EXPECTED_SHA256`（位于主脚本）。
填上安装器的真实指纹后，分发时强校验，防篡改：

```sh
sha256sum dsh-termux-deploy.sh
```

---

## 开发 / 贡献

- **模块化**：每个功能一个函数（`doctor`/`ensure_tools`/`npm 安装`/`ensure_sharp_wasm`/`patch_*`/`install_launcher`/`setup_workspace`/`verify`/`serve`）。
- **配置区**：脚本顶部集中路径/端口/仓库地址，改这里调行为。
- **子命令**：底部 `case "$COMMAND"` 统一路由。

可直接 Fork 修改后 push。若改动 `dsh-termux-deploy.sh` / `bootstrap.sh`，请**在纯净 Termux 上实测 `install`** 并更新本 README 的「已知坑」表。

---

## 许可证

MIT
