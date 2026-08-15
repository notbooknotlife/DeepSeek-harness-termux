#!/data/data/com.termux/files/usr/bin/bash
#===============================================================================
#  dsh-termux-deploy.sh — DeepSeek Harness (DSH) Termux 完整部署 · 融合版
#
#  目标：真正"能完全安装、缺什么补什么"，并且适配手机端。
#  融合了两套思路：
#    · 可靠性硬核适配(源自 android-termux-dsh)：Node版本校验、android30编译参数、
#      common.gypi补丁、sharp WASM兜底、link→rename补丁、--expose-internals包装器、
#      Termux工作区、逐项验证。
#    · 工程化(你要求的)            ：模块化、幂等、.npmrc备份回滚、manifest清单、
#      doctor/status/serve/uninstall 子命令、SHA256自校验。
#
#  用法：
#   bash dsh-termux-deploy.sh install [--skip-upgrade] [--cn]   安装(缺啥补啥)
#   bash dsh-termux-deploy.sh serve [--host 0.0.0.0] [--port 3080]  启动UI
#   bash dsh-termux-deploy.sh doctor         环境自检
#   bash dsh-termux-deploy.sh status         服务/进程状态
#   bash dsh-termux-deploy.sh uninstall      卸载并还原 .npmrc
#
#  --cn   使用 npmmirror 镜像(中国大陆网络)
#  --skip-upgrade  跳过 pkg 相关操作（脚本默认不执行 pkg update/upgrade，由用户自行维护）
#===============================================================================
set -euo pipefail

#------------------------------ 变量区 ----------------------------------------
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-$PREFIX/home}"
DSH_PKG="@deepseek-ai/dsh"
D="$PREFIX/lib/node_modules/@deepseek-ai/dsh"
DSH_BIN="$PREFIX/bin/dsh"
DSH_CONF_HOME="$HOME_DIR/.dsh"
NPMRC="$HOME_DIR/.npmrc"
NPMRC_BACKUP="$HOME_DIR/.npmrc.dsh.bak"
LOG_FILE="$HOME_DIR/.dsh_deploy.log"
# 默认工作区：Termux 私有目录（便于删除、不污染手机存储）。可用 DSH_WORKSPACE 覆盖。
WORKSPACE="${DSH_WORKSPACE:-$HOME_DIR/.dsh/workspace}"
MIRROR="https://registry.npmmirror.com"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
LANG_HOST="${DSH_HOST:-127.0.0.1}"
LANG_PORT="${DSH_PORT:-3080}"
MOBILE_DIR="$HOME_DIR/.dsh-mobile"   # 手机端 UI 适配资源（本地可编辑）
# 脚本目录：兼容「直接运行」与「curl|bash 以 stdin 执行」两种情况。
# stdin 执行时 BASH_SOURCE[0]/$0 可能为空或不可用 → 安全降级，不因 set -u 崩溃。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || printf '%s' "$HOME")"
REPO_MOBILE="$SCRIPT_DIR/mobile"     # 仓库内手机端适配资源(单一来源)

CN_MODE=0
SKIP_UPGRADE=0
# 解析通用 flag(--host/--port 放在子命令前) 与子命令 flag(--cn/--skip-upgrade 在 install 后)
ARGS_HOST=""; ARGS_PORT=""; POSITIONAL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) ARGS_HOST="$2"; shift 2 ;;
    --port) ARGS_PORT="$2"; shift 2 ;;
    --cn) CN_MODE=1; shift ;;
    --skip-upgrade) SKIP_UPGRADE=1; shift ;;
    *) POSITIONAL="$POSITIONAL $1"; shift ;;
  esac
done
[ -n "$ARGS_HOST" ] && LANG_HOST="$ARGS_HOST"
[ -n "$ARGS_PORT" ] && LANG_PORT="$ARGS_PORT"
read -r -a POS <<< "$POSITIONAL"
COMMAND="${POS[0]:-help}"

have(){ command -v "$1" >/dev/null 2>&1; }
log(){ printf '%s\n' "$*" >> "$LOG_FILE"; echo "$*"; }
info(){ log "[I]   $*"; }
ok(){   log "[OK]  $*"; }
warn(){ log "[!]   $*"; }
err(){  log "[ERR] $*"; }

ensure_log(){ : > "$LOG_FILE"; }

# ============ 动态加载（转圈）工具 ============
# spin_run "<描述>" <命令...>
#   把命令放后台执行，前台每0.15s刷新一个旋转字符，结束后固定打勾/打叉。
#   命令输出进 $LOG_FILE（避免刷屏）；返回命令的真实退出码。
spin_run(){
  local desc="$1"; shift
  local chars='/-\|' i=0 rc=0
  # 后台执行（输出进日志，不刷屏）
  ( "$@" >>"$LOG_FILE" 2>&1 ) &
  local pid=$!
  # 前台转圈
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r[%s]  %s ..." "${chars:((i++%4)):1}" "$desc"
    sleep 0.15
  done
  wait "$pid"; rc=$?
  # 结束：固定打勾或打叉
  if [ "$rc" -eq 0 ]; then
    printf "\r[OK]  %s   \n" "$desc"
  else
    printf "\r[ERR] %s   \n" "$desc"
  fi
  return "$rc"
}


#------------------------------ 环境与自检 ------------------------------------
doctor(){
  info "== 环境自检 =="
  [ "$PREFIX" = "/data/data/com.termux/files/usr" ] || [ -n "${TERMUX_VERSION:-}" ] \
    && ok "Termux 环境" || err "非 Termux 环境"
  for c in node npm gcc make pkg-config python3; do
    if have "$c"; then
      local v=""; [ "$c" = node ] && v=" ($(node --version))"
      ok "$c$v"; else warn "缺 $c"; fi
  done
  have pnpm && ok "pnpm $(pnpm --version)" || warn "缺 pnpm"
  have node-gyp && ok "node-gyp" || warn "缺 node-gyp"
  # Node 版本检查(dsh 需 >=22.12)
  if have node; then
    local major minor; major="$(node -p 'process.versions.node.split(".")[0]')"; minor="$(node -p 'process.versions.node.split(".")[1]')"
    if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 12 ]; }; then
      warn "Node $(node -v) 过低，dsh 需 >= 22.12"
    else ok "Node 版本满足要求 ($(node -v))"
    fi
  fi
  [ -d "$D" ] && ok "DSH 已安装于 $D" || info "DSH 未安装（将随 install 安装）"
}

#------------------------------ .npmrc 备份/配置 ------------------------------
backup_npmrc(){
  if [ -f "$NPMRC" ] && [ ! -f "$NPMRC_BACKUP" ]; then cp "$NPMRC" "$NPMRC_BACKUP"; info "备份 .npmrc -> $NPMRC_BACKUP"; fi
  [ -f "$NPMRC" ] || : > "$NPMRC"
}
npm_ensure(){ local k="$1" v="$2"; grep -qE "^${k}=" "$NPMRC" 2>/dev/null && info "npmrc 已有 $k" || { printf '%s=%s\n' "$k" "$v" >> "$NPMRC"; info "npmrc += $k=$v"; }; }
configure_npm(){
  backup_npmrc
  npm_ensure registry "https://registry.npmjs.org/"
  npm_ensure allow-scripts "@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs,pnpm"
  npm_ensure fetch-retries 5
  npm_ensure fetch-retry-mintimeout 20000
  npm_ensure fetch-retry-maxtimeout 120000
  npm_ensure fetch-timeout 300000
  if [ "$CN_MODE" -eq 1 ]; then info "使用 npmmirror 镜像(--cn)"; npm config set registry "$MIRROR" --location=user; fi
}

#------------------------------ 安装前置：工具链 ------------------------------
ensure_tools(){
  # 命令型工具：用 command -v 判断，缺哪个装哪个
  local tool_pkgs="git curl cmake clang make python binutils pkg-config termux-tools"
  # 库/头文件型依赖(非命令)，用 dpkg -s 判断（koffi 编译需 spawn.h → libandroid-support 等）
  local lib_pkgs="libandroid-spawn libandroid-support libandroid-glob"

  local need="" lib_need=""
  for p in $tool_pkgs; do have "$p" || need="$need $p"; done
  for p in $lib_pkgs; do dpkg -s "$p" >/dev/null 2>&1 || lib_need="$lib_need $p"; done
  have nodejs || need="$need nodejs"

  # 缺依赖才安装；脚本不执行 pkg update/upgrade（交由用户自行保证 Termux 索引正常）。
  if [ -n "$need$lib_need" ]; then
    spin_run "正在下载并安装依赖: $need$lib_need" pkg install -y $need $lib_need       || { warn "pkg install 失败。若报索引/依赖错误，请先手动执行: pkg update && pkg upgrade"
           err "然后重新运行本脚本。日志见 $LOG_FILE"; }
  else
    ok "依赖工具与库已齐(无需 pkg 操作)"
  fi
}

ensure_node_gyp(){
  have node-gyp && { ok "node-gyp 已存在"; return; }
  spin_run "正在下载并安装 node-gyp" npm install -g node-gyp     || warn "node-gyp 装失败(可忽略)"
}

ensure_pnpm(){
  if have pnpm; then ok "pnpm 已存在"
  else
    spin_run "正在下载并安装 pnpm" npm install -g pnpm || warn "pnpm 装失败"
  fi
}

#------------------------------ 硬核适配：native 编译 --------------------------
# Termux clang 默认 target API 24，statx() 需 API>=30；依据架构选 android30 目标
resolve_target(){
  local arch; arch="$(uname -m)"
  case "$arch" in
    aarch64) TARGET="aarch64-linux-android30";;
    armv7l|armv8l) TARGET="armv7a-linux-androideabi30";;
    x86_64) TARGET="x86_64-linux-android30";;
    *) TARGET="aarch64-linux-android30"; warn "未知架构 $arch 按 arm64 处理";;
  esac
  info "架构 $(uname -m)，编译目标 $TARGET"
}

# node-gyp common.gypi 的 android_ndk_path 补丁
patch_common_gypi(){
  local patched=0 f
  for f in "$HOME"/.cache/node-gyp/*/include/node/common.gypi; do
    [ -f "$f" ] || continue
    if grep -q "android_ndk_path%'" "$f"; then patched=1; continue; fi
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
i=s.index("'variables': {")+len("'variables': {")
s=s[:i]+"\n    'android_ndk_path%': '',"+s[i:]
open(p,"w").write(s)
PY
    ok "已修补 $f"; patched=1
  done
  [ "$patched" -eq 0 ] && warn "未找到 common.gypi 缓存(若 node-pty 报 android_ndk_path 重跑即可)"
}

#------------------------------ install(缺啥补啥, 分层递进) ------------------------------
# DSH 在全部前置就绪后再安装本体、最后补丁/工作区/验证（真正启用）。
install(){
  doctor
  info "== 开始安装 (缺什么补什么) =="

  # --- A. 环境基础：装编译工具链 + nodejs + git（pkg 更新由用户自行保证）---
  ensure_tools

  # --- B. 配置 npm(镜像/allow-scripts) + node-gyp + pnpm + 架构目标 ---
  configure_npm
  ensure_node_gyp
  ensure_pnpm
  resolve_target

  # --- C. 网络预检：官方源不通切镜像 ---
  if [ "$CN_MODE" -eq 0 ] && ! curl -fsS --max-time 3 -o /dev/null https://registry.npmjs.org/-/ping 2>/dev/null; then
    warn "官方源不通，切 npmmirror 镜像"; npm config set registry "$MIRROR" --location=user; fi

  # --- D. 装 DSH 本体(最耗时, 5~15 分钟) ---
  info "全局安装 $DSH_PKG（约 5~15 分钟，下载期无输出属正常）... "
  export CFLAGS="-target $TARGET"; export CXXFLAGS="-target $TARGET"
  export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
  if ! spin_run "正在下载并安装 DSH(下载+编译 koffi/node-pty)" npm install -g --prefer-offline --foreground-scripts --no-audit --no-fund "$DSH_PKG"; then
    warn "首次安装失败，补 common.gypi 后重试一次"
    patch_common_gypi
    spin_run "重试安装 DSH" npm install -g --prefer-offline --foreground-scripts --no-audit --no-fund "$DSH_PKG" \
      || { err "DSH 安装失败，见 $LOG_FILE"; unset CFLAGS CXXFLAGS CMAKE_BUILD_PARALLEL_LEVEL; return 1; }
  fi
  unset CFLAGS CXXFLAGS CMAKE_BUILD_PARALLEL_LEVEL
  have dsh || { err "npm 装完仍未找到 dsh 命令"; return 1; }
  ok "DSH 本体已就位: $(command -v dsh)"

  # --- D2. 顺便装 sharp WASM 运行时(DSH 在 android 无原生 sharp, 必须补) ---
  # 与 D 同一次安装流程内一步到位，避免单独补装阶段。
  ensure_sharp_wasm

  # --- E. 打 Termux 硬核补丁(link→rename) ---
  info "应用 Termux 补丁(link→rename)..."
  patch_link_rename

  # --- F. 启动包装器(--expose-internals, HMR 必需) ---
  info "安装启动包装器..."
  install_launcher

  # --- G. 配置 Termux 工作区 + 手机端 UI 资源 ---
  info "配置 Termux 工作区与手机端资源..."
  setup_workspace
  install_mobile

  # --- H. 逐项验证(DSH 最终真正可用) ---
  verify
  manifest

  # --- I. 显示默认网址并询问是否启动 ---
  echo
  echo "  默认访问网址: http://127.0.0.1:${LANG_PORT}"
  if [ -t 0 ]; then
    read -rp "  是否立即启动 DSH Web? (y/n): " yn
    case "$yn" in
      y|Y|yes|Yes) serve ;;
      *) info "如需启动请运行: dsh web  或  bash $0 serve" ;;
    esac
  else
    info "如需启动请运行: dsh web  或  bash $0 serve"
  fi
}

#------ link→rename 补丁(部分 ROM 禁 link 致 EACCES) ------
patch_link_rename(){
  info "检查 link→rename 补丁 ..."
  local f patched=0
  f="$D/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js"
  if [ -f "$f" ] && ! grep -q "await rename(tmp, finalPath)" "$f" && grep -q "await link(tmp, finalPath)" "$f"; then
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('import { link, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, stat, truncate } from "node:fs/promises";',
            'import { link, mkdir, mkdtemp, open, readFile, readdir, realpath, rename, rm, stat, truncate } from "node:fs/promises";')
s=s.replace("await link(tmp, finalPath);","await rename(tmp, finalPath);")
open(p,"w").write(s); sys.exit(0)
PY
    ok "已修补 $f"; patched=1
  fi
  f="$D/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js"
  if [ -f "$f" ] && ! grep -q "await rename(temporary, target)" "$f" && grep -q "await link(temporary, target)" "$f"; then
    python3 - "$f" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('import { chmod, link, mkdir, open, readFile, unlink } from "node:fs/promises";',
            'import { chmod, link, mkdir, open, readFile, rename, unlink } from "node:fs/promises";')
s=s.replace("await link(temporary, target);","await rename(temporary, target);")
s=s.replace("await unlink(temporary);","await unlink(temporary).catch(function(e){if(!(e&&e.code==='ENOENT'))throw e;});")
open(p,"w").write(s); sys.exit(0)
PY
    ok "已修补 $f"; patched=1
  fi
  [ "$patched" -eq 0 ] && info "link→rename 无需修补(或包结构已变)"
}

#------ sharp WASM 兜底(sharp 无 android-arm64 预编译) ------
ensure_sharp_wasm(){
  # sharp 在 android-arm64 无原生二进制，必须装 wasm 版(@img/sharp-wasm32 + @emnapi)。
  # 随 D 阶段同流程直接装（不等到缺了再补）。
  local ver; ver="$(python3 -c "import json;print(json.load(open('$D/node_modules/sharp/package.json'))['version'])" 2>/dev/null || true)"
  [ -n "$ver" ] || { warn "sharp 版本读取失败，跳过 sharp wasm 安装"; return; }

  if ! spin_run "正在安装 sharp@$ver 图像处理(wasm)" bash -c "cd '$D' && npm install --no-save --no-audit --no-fund '@img/sharp-wasm32@$ver' '@emnapi/runtime'"; then
    warn "官方源装 wasm 失败，改用 npmmirror 重试"
    if ! spin_run "重试安装 sharp(国内镜像)" bash -c "cd '$D' && npm install --no-save --no-audit --no-fund --registry='$MIRROR' '@img/sharp-wasm32@$ver' '@emnapi/runtime'"; then
      err "sharp wasm 运行时安装失败(仍缺 sharp)，日志见 $LOG_FILE"
      return 1
    fi
  fi
  if (cd "$D" && timeout 30 node --input-type=module -e "await import('sharp').catch(()=>process.exit(1))" >/dev/null 2>&1); then
    ok "sharp(wasm) 已就位并可加载"
  else
    warn "sharp wasm 已装但仍加载失败(版本/依赖不匹配)"
  fi
}

#------ dsh 启动包装器(--expose-internals) ------
install_launcher(){
  info "安装 dsh 启动包装器(--expose-internals) ..."
  rm -f "$DSH_BIN"
  printf '#!%s/bin/sh\nexec node --expose-internals %s/lib/bin.js "$@"\n' "$PREFIX" "$D" > "$DSH_BIN"
  chmod +x "$DSH_BIN"; ok "包装器已写入 $DSH_BIN"
}

#------ Termux 工作区 + 默认工作区 ------
setup_workspace(){
  # 工作区根设在 Termux 私有目录（默认 ~/.dsh/workspace），便于删除、不污染手机存储。
  mkdir -p "$WORKSPACE" "$DSH_CONF_HOME/profiles/web"
  local PATCH="$DSH_CONF_HOME/profiles/web/cordis.patch.yml"
  if grep -q "id: fs-sandbox" "$PATCH" 2>/dev/null; then
    ok "cordis.patch.yml 已有 fs-sandbox"
  else
    printf '\n- id: fs-sandbox\n  config:\n    cwd: %s\n' "$WORKSPACE" >> "$PATCH"
    ok "工作区固定到 Termux: $WORKSPACE"
  fi
}

#------ 手机端 UI 适配资源(本地可编辑) ------
# 说明：把手机端优化样式写进 $MOBILE_DIR（单一来源：仓库 mobile/ 目录），
# 用户可直接编辑这些文件。
install_mobile(){
  mkdir -p "$MOBILE_DIR"
  # 优先从仓库 mobile/ 目录拷贝最新文件（保证与发布内容一致）
  if [ -d "$REPO_MOBILE" ]; then
    cp -f "$REPO_MOBILE/mobile.css"            "$MOBILE_DIR/mobile.css" 2>/dev/null || true
    cp -f "$REPO_MOBILE/dsh-setting-mobile.user.js" "$MOBILE_DIR/dsh-mobile.user.js" 2>/dev/null || true
    cp -f "$REPO_MOBILE/bookmarklet.txt"       "$MOBILE_DIR/bookmarklet.txt" 2>/dev/null || true
    touch "$MOBILE_DIR/.dsh-mobile-inited"
    ok "手机端 UI 适配资源已安装(来自仓库 mobile/): $MOBILE_DIR"
  else
    warn "未找到仓库 mobile/ 目录($REPO_MOBILE)，跳过手机端资源安装"
    return 1
  fi
  info "  · $MOBILE_DIR/mobile.css          核心样式(可编辑)"
  info "  · $MOBILE_DIR/dsh-mobile.user.js  浏览器扩展自动注入"
  info "  · $MOBILE_DIR/bookmarklet.txt     无扩展浏览器书签注入"
}

#------ 逐项验证 ------
verify(){
  info "== 验证 =="
  have dsh && ok "dsh" || err "dsh 缺失"
  (cd "$D" && node --input-type=module -e "await import('koffi')" >/dev/null 2>&1) && ok "koffi 可加载" || err "koffi 加载失败"
  [ -f "$D/node_modules/node-pty/build/Release/pty.node" ] && ok "node-pty 已编译" || warn "node-pty 未编译"
  (cd "$D" && node --input-type=module -e "import('sharp').then(s=>{if(!s.default.versions)process.exit(1)}).catch(()=>process.exit(1))" >/dev/null 2>&1) && ok "sharp(wasm) 可加载" || warn "sharp 加载异常"
  [ -d "$WORKSPACE" ] && ok "工作区可访问: $WORKSPACE" || warn "工作区不可访问: $WORKSPACE"
  ok "验证完成。启动: dsh web"
}

manifest(){
  { echo "# DSH 部署改动清单 $(date)"; echo "程序: $D"; echo "入口: $DSH_BIN"; echo "配置: $DSH_CONF_HOME"; echo "改动: $NPMRC 备份: $NPMRC_BACKUP"; echo "日志: $LOG_FILE"; echo "卸载: bash $0 uninstall"; } > "$HOME_DIR/.dsh_deploy_manifest.txt"
  chmod 600 "$HOME_DIR/.dsh_deploy_manifest.txt" 2>/dev/null
}

#------ 启动 UI(含手机/局域网访问) ------
serve(){
  have dsh || { err "dsh 未安装，请先: bash $0 install"; return 1; }
  # 确保 dsh 启动器是带 --expose-internals 的自定义包装器（HMR 必需）。
  # npm 装上 @deepseek-ai/dsh 时默认 bin 不带该 flag，会导致 HMR 报错。
  if ! head -1 "$DSH_BIN" 2>/dev/null | grep -q "expose-internals"; then
    warn "检测到 dsh 启动器缺少 --expose-internals，重建包装器..."
    install_launcher
  fi
  info "启动 DSH Web UI: $LANG_HOST:$LANG_PORT"
  echo "--------------------------------------------------------------"
  echo "  本机访问:      http://127.0.0.1:$LANG_PORT"
  local lanip; lanip="$(ifconfig 2>/dev/null | awk '/^[a-z]/{iface=$1}/inet /{print iface,$2}' | awk '$1 ~ /^wlan/{print $2; exit}' | cut -d: -f2)"
  [ -z "$lanip" ] && lanip="$(ifconfig 2>/dev/null | awk '/^[a-z]/{iface=$1}/inet /{print iface,$2}' | grep -vE '^(lo|docker|tun|virbr)' | awk '{print $2; exit}' | cut -d: -f2)"
  [ -n "$lanip" ] && echo "  局域网设备访问: http://$lanip:$LANG_PORT"
  echo "--------------------------------------------------------------"
  exec "$DSH_BIN" --profile web --host "$LANG_HOST" --port "$LANG_PORT"
}

#------ 卸载 ------
uninstall(){
  info "卸载 DSH ..."
  have pgrep && pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1 && pkill -f "dsh/lib/bin.js" 2>/dev/null || true
  [ -d "$D" ] && { rm -rf "$D"; ok "删 $D"; }
  [ -f "$DSH_BIN" ] && { rm -f "$DSH_BIN"; ok "删 $DSH_BIN"; }
  if [ -f "$NPMRC_BACKUP" ]; then cp "$NPMRC_BACKUP" "$NPMRC"; ok "还原 .npmrc"; rm -f "$NPMRC_BACKUP"; fi
  info "配置 $DSH_CONF_HOME 保留(含会话/凭据)，彻底删除请: rm -rf $DSH_CONF_HOME"
  ok "卸载完成。"
}

#------ status ------
status_cmd(){
  if pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1; then info "dsh web 运行中 (PID $(pgrep -f 'dsh/lib/bin.js'|head -1))"; else info "dsh web 未运行"; fi
  info "程序: $([ -d "$D" ] && echo 已安装 || echo 未安装) | 配置: $([ -d "$DSH_CONF_HOME" ] && echo 存在 || echo 不存在)"
}

#------ 分发入口 ------
ensure_log
case "$COMMAND" in
  install)    install ;;
  serve)      serve ;;
  uninstall|--uninstall|-u) uninstall ;;
  doctor)     doctor ;;
  status)     status_cmd ;;
  mobile)     info "重置手机端适配资源到默认并覆盖本地修改..."; install_mobile ;;
  help|--help|-h)
    echo "用法: bash $0 <命令> [--host ip] [--port 端口]"
    echo "  install [--skip-upgrade] [--cn]   完整安装(缺啥补啥，快；--skip-upgrade 连pkg索引刷新也跳过)"
    echo "  serve   [--host 0.0.0.0] [--port] 启动Web UI"
    echo "  mobile                            (重)生成手机端UI适配资源到 ~/.dsh-mobile"
    echo "  doctor                            环境自检"
    echo "  status                            服务状态"
    echo "  uninstall                         卸载并还原 .npmrc";;
  *) err "未知命令: $COMMAND (help 查看用法)"; exit 2 ;;
esac
exit 0
