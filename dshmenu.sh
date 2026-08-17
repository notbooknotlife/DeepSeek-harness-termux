#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  dshmenu — DSH 控制菜单
#  用法: bash dshmenu.sh  (或添加到 ~/.bashrc 后直接输 dshmenu)
#  不改动 dsh 本体，仅提供交互式启动/状态/卸载入口。
# ============================================================

# 部署脚本定位：自适应查找, 不依赖固定源码路径。
# 优先 DSH_DEPLOY_SCRIPT 环境变量; 否则在常见位置找; 找不到则置空(状态/卸载走内置逻辑)。
DEPLOY_SCRIPT="${DSH_DEPLOY_SCRIPT:-}"
if [ -z "$DEPLOY_SCRIPT" ] || [ ! -f "$DEPLOY_SCRIPT" ]; then
  for cand in \
    "$HOME/.dsh/dsh-termux-deploy.sh" \
    "$HOME/dsh-termux-deploy.sh" \
    "$HOME/storage/dsh-src/dsh-termux-deploy.sh" \
    "$(dirname "$0")/dsh-termux-deploy.sh" \
    "$(dirname "$0")/../dsh-termux-deploy.sh"; do
    if [ -f "$cand" ]; then DEPLOY_SCRIPT="$cand"; break; fi
  done
fi

# 提示文本颜色
C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_RED=$'\e[31m'; C_CYA=$'\e[36m'; C_RST=$'\e[0m'

menu_banner(){
  clear
  echo "╔══════════════════════════════════════════════════╗"
  echo "║               ${C_CYA}DSH 控制菜单${C_RST}                  ║"
  echo "╠══════════════════════════════════════════════════╣"
  echo "║  ${C_YEL}1)${C_RST} 直接启动        → ${C_CYA}dsh web${C_RST}"
  echo "║  ${C_YEL}2)${C_RST} 自定义端口启动  → ${C_CYA}dsh web --port <端口>${C_RST}"
  echo "║  ${C_YEL}3)${C_RST} 开启局域网      → ${C_CYA}风险确认→装caddy→注入配置→提示(需重启dsh)${C_RST}"
  echo "║  ${C_YEL}4)${C_RST} 局域网状态      → ${C_CYA}查看端口/一键关闭还原${C_RST}"
  echo "║  ${C_YEL}5)${C_RST} 查看状态        → ${C_CYA}bash $DEPLOY_SCRIPT status${C_RST}"
  echo "║  ${C_YEL}6)${C_RST} 完全卸载        → ${C_CYA}卸载 dsh(+清配置)${C_RST}"
  echo "║  ${C_YEL}0)${C_RST} 退出"
  echo "╚══════════════════════════════════════════════════╝"
}

# 读取端口：直接回车用默认 3080
ask_port(){
  local p
  read -rp "请输入端口 [默认3080]: " p
  if [ -z "$p" ]; then p=3080; fi
  echo "$p"
}

cmd_status(){
  if [ -n "$DEPLOY_SCRIPT" ] && [ -f "$DEPLOY_SCRIPT" ]; then
    bash "$DEPLOY_SCRIPT" status
  else
    echo "--- dsh 内部状态(未找到部署脚本, 用内置检查) ---"
    if pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1; then
      echo "  dsh web 运行中 (PID $(pgrep -f 'dsh/lib/bin.js' | head -1))"
    else
      echo "  dsh web 未运行"
    fi
    [ -d "$HOME/.dsh" ] && echo "  配置 ~/.dsh 存在" || echo "  配置 ~/.dsh 不存在"
    D=/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh
    [ -d "$D" ] && echo "  本体 $D 已安装" || echo "  本体未安装"
  fi
}

# 后台启动 dsh web + 自动开浏览器，然后等回车返回菜单
launch_dsh(){
  # mode=persist 常驻(输入1)；mode=test 启动后验证端口即关闭(输入2/3)
  local host="$1" port="$2" mode="${3:-persist}"
  # 工作区目录：dsh 的 workspaceRoot 取 process.cwd()，必须从干净工作区启动，
  # 否则会落到整个 $HOME(数GB)，导致前端工作区/目录/插件加载极慢或卡死。
  local WS="${DSH_WORKSPACE:-$HOME/.dsh/workspace}"
  mkdir -p "$WS"
  # 常驻模式: 若已在运行则不重复启动
  if command -v pgrep >/dev/null 2>&1 && pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1; then
    echo "${C_YEL}已有 dsh web 在运行。${C_RST}"
  else
    # 用子 shell：(cd 工作区 && nohup dsh web) —— 让 process.cwd()=工作区，且不影响本菜单 shell
    # dsh 始终监听本机 127.0.0.1(官方安全限制不支持0.0.0.0); 局域网访问由 caddy 反向代理(选项3)实现。
    # 自动附加 --trusted-host <局域网IP>: 让 dsh 信任来自局域网的 WebSocket(否则 caddy 转发时 /api 数据 403)。
    local TH=""
    TH=$(lan_get_ip)
    local trustarg=()
    [ -n "$TH" ] && trustarg=(--trusted-host "$TH")
    ( cd "$WS" && nohup dsh web --host 127.0.0.1 --port "$port" "${trustarg[@]}" >"$HOME/.dsh/dsh-web.log" 2>&1 ) &
    sleep 3   # 等端口起来
  fi
  echo "  本机访问:      http://127.0.0.1:$port"

  if [ "$mode" = "persist" ]; then
    # 常驻(1): 保持运行，打开浏览器
    command -v termux-open-url >/dev/null 2>&1 && { (termux-open-url "http://127.0.0.1:$port" >/dev/null 2>&1 &); }
    echo "${C_GRN}（1）已启动并常驻。可在浏览器使用 http://127.0.0.1:$port${C_RST}"
    echo
    read -rp "按回车返回菜单..." _
  else
    # 测试模式(2/3): 服务先保持运行，用户确认可用；按回车返回菜单时才关闭端口
    command -v termux-open-url >/dev/null 2>&1 && { (termux-open-url "http://127.0.0.1:$port" >/dev/null 2>&1 &); }
    echo "${C_YEL}（2/3）端口 $port 已开启，可先在浏览器测试。${C_RST}"
    echo
    read -rp "测试完按回车返回菜单(将自动关闭此端口): " _
    # 回车返回菜单 → 此刻关闭端口
    if command -v pgrep >/dev/null 2>&1; then
      pkill -f "dsh/lib/bin.js" 2>/dev/null
    fi
    echo "${C_YEL}已关闭端口 $port。${C_RST}"
  fi
}



# ================= 局域网启动(caddy 反向代理) =================
# 原理: dsh 固定监听 127.0.0.1:<DSH_PORT>, 用 caddy 在【局域网端口】反向代理到 dsh 本机端口。
#       不改 dsh 配置/不动 dsh 本体; caddy 是独立代理进程, 返回菜单时终止。
SOCAT_BIN="${DSH_SOCAT:-}"



lan_get_ip(){
  local ip=""
  ip=$(ifconfig 2>/dev/null | awk '/^wlan/{w=1} w&&/inet /{print $2;exit}')
  if [ -z "$ip" ]; then
    ip=$(ifconfig 2>/dev/null | awk '/^[a-z]/{ifc=$1} /inet /&&ifc!~/^(lo|docker|tun|virbr)/{print $2;exit}')
  fi
  echo "$ip"
}

# 确保 caddy 已安装(未装则 pkg install)
lan_ensure_caddy(){
  if command -v caddy >/dev/null 2>&1; then
    return 0
  fi
  echo "  caddy 未安装，正在安装..."
  if command -v pkg >/dev/null 2>&1; then
    pkg install -y caddy
  elif command -v apt >/dev/null 2>&1; then
    sudo apt-get install -y caddy 2>/dev/null || apt-get install -y caddy
  fi
  if command -v caddy >/dev/null 2>&1; then
    echo "  caddy 安装完成"
    return 0
  else
    echo "${C_RED}  caddy 安装失败，无法开启局域网${C_RST}"
    return 1
  fi
}

# 启动 caddy 反向代理: 局域网 <lanport> -> dsh 127.0.0.1:<dshport>
lan_caddy_start(){
  local lanport="$1" dshport="${2:-3080}"
  if ! lan_ensure_caddy; then return 1; fi
  # 端口校验: 不能等于 dsh 本体端口(冲突)
  if [ "$lanport" = "$dshport" ]; then
    echo "${C_RED}  ⚠ ${lanport} 是 dsh 本体端口，不能用于反向代理。${C_RST}"
    return 1
  fi
  # 终止可能的残留 caddy
  lan_caddy_stop
  # 写 Caddyfile
  local cdir="$HOME/.dsh/caddy"
  mkdir -p "$cdir"
  cat > "$cdir/Caddyfile" <<'CADDY'
:{LANPORT} {
	reverse_proxy {DSHPORT}
}
CADDY
  sed -i "s/{LANPORT}/$lanport/;s|{DSHPORT}|127.0.0.1:$dshport|" "$cdir/Caddyfile"
  local lanip
  lanip=$(lan_get_ip)
  setsid caddy run --config "$cdir/Caddyfile" >"$cdir/caddy.log" 2>&1 &
  sleep 2
  echo "${C_GRN}  ✅ 局域网已开启：caddy :${lanport} → 127.0.0.1:${dshport}${C_RST}"
  echo "     本机访问:      http://127.0.0.1:${dshport}   (dsh 本体)"
  [ -n "$lanip" ] && echo "     局域网访问:    http://${lanip}:${lanport}   (其它设备)"
}

# 终止 caddy(关闭局域网)
lan_caddy_stop(){
  ps -eo pid,comm | awk '$2=="caddy"{print $1}' | xargs -r kill 2>/dev/null
  true
}

# 读当前注入的局域网转发端口(从 Caddyfile 解析)
lan_caddy_get_port(){
  local cdir="$HOME/.dsh/caddy"
  if [ -f "$cdir/Caddyfile" ]; then
    grep -oE ':[0-9]+' "$cdir/Caddyfile" | head -1 | tr -d ':'
  fi
}

# 局域网状态: 显示注入端口 + y一键关闭还原/其他返回
lan_caddy_status(){
  local port
  port=$(lan_caddy_get_port)
  local running
  running=$(ps -eo comm | grep -c '^caddy$')
  echo "═══════════════════════════════════"
  echo "  局域网状态"
  echo "═══════════════════════════════════"
  if [ -n "$port" ] && [ "$running" -gt 0 ]; then
    echo "  ${C_GRN}状态: 已开启${C_RST}   caddy 转发端口: ${port}"
    echo "  本机访问: http://127.0.0.1:3080"
    echo "  局域网:   http://$(lan_get_ip):${port}"
  elif [ -n "$port" ]; then
    echo "  状态: 已配置端口 ${port}，但 caddy 未运行"
  else
    echo "  ${C_YEL}状态: 未开启局域网（无注入配置）${C_RST}"
  fi
  echo ""
  echo "  输入 ${C_GRN}y${C_RST} 一键关闭局域网(还原)，其他任意键返回菜单"
  read -rp "> " k
  case "$k" in
    y|Y)
      lan_caddy_stop
      lan_dsh_restore   # 先从备份还原 dsh
      rm -f "$HOME/.dsh/caddy/Caddyfile" "$HOME/.dsh/caddy/caddy.log" "$DSH_ORIG" 2>/dev/null
      echo "${C_YEL}  ✅ 局域网已关闭并还原(dsh/caddy)。${C_RST}"
      ;;
    *)
      echo "${C_YEL}  已取消，返回菜单。${C_RST}"
      ;;
  esac
  read -rp "按回车返回菜单..." _
}



# ================= dsh 本体 注入/备份/还原(局域网开启事务) =================
DSH_INDEX="/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js"
DSH_ORIG="$HOME/.dsh/caddy/dsh-connection.index.orig"

lan_dsh_backup(){
  mkdir -p "$HOME/.dsh/caddy"
  if [ ! -f "$DSH_ORIG" ] && [ -f "$DSH_INDEX" ]; then
    cp -f "$DSH_INDEX" "$DSH_ORIG" 2>/dev/null
  fi
}

lan_dsh_inject(){
  lan_dsh_backup
  [ -f "$DSH_INDEX" ] || { echo "  ${C_RED}找不到 dsh 文件: $DSH_INDEX${C_RST}"; return 1; }
  sed -i     -e 's/!isTrustedApiRequest(request, \[\])/!isTrustedApiRequest(request, this.trustedHosts)/g'     -e 's/const trustedHosts = options.authority === "loopback" ? \[\] : this.trustedHosts;/const trustedHosts = this.trustedHosts;/'     "$DSH_INDEX"
  echo "  dsh 已注入(放行局域网设置接口)"
}

lan_dsh_restore(){
  if [ -f "$DSH_ORIG" ]; then
    cp -f "$DSH_ORIG" "$DSH_INDEX" 2>/dev/null
    echo "  dsh 已还原到初始"
  else
    echo "  ${C_YEL}  无 dsh 备份，跳过还原${C_RST}"
  fi
}

lan_dsh_modified(){
  [ ! -f "$DSH_ORIG" ] && return 0
  [ ! -f "$DSH_INDEX" ] && return 0
  if cmp -s "$DSH_INDEX" "$DSH_ORIG"; then return 0; else return 1; fi
}

lan_current_port(){
  lan_caddy_get_port
}

cmd_uninstall(){
  echo
  echo "${C_RED}⚠  即将完全卸载 DSH(全局，含会话/配置 ~/.dsh)${C_RST}"
  read -rp "确认卸载？再输入 5 确认(0=返回菜单): " c2
  case "$c2" in
    5)
      echo "执行卸载..."
      # ① 停运行中的 dsh 进程
      command -v pgrep >/dev/null 2>&1 && pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1 && pkill -f "dsh/lib/bin.js" 2>/dev/null || true
      # ② 直接删 DSH 本体 + 命令(不依赖部署脚本是否存在)
      local D=/data/data/com.termux/files/usr/lib/node_modules/@deepseek-ai/dsh
      local BIN=/data/data/com.termux/files/usr/bin/dsh
      [ -d "$D" ] && { rm -rf "$D"; echo "  已删本体 $D"; }
      [ -f "$BIN" ] && { rm -f "$BIN"; echo "  已删命令 $BIN"; }
      # 若部署脚本存在, 顺手还原 .npmrc
      if [ -n "$DEPLOY_SCRIPT" ] && [ -f "$DEPLOY_SCRIPT" ]; then
        bash "$DEPLOY_SCRIPT" uninstall --config-only >/dev/null 2>&1
      fi
      # ③ 清配置/会话/工作区/手机端资源/菜单
      rm -rf "$HOME/.dsh" "$HOME/.dsh-mobile" 2>/dev/null
      # ④ 清部署残留辅助文件
      rm -f "$HOME/.dsh-bootstrap-installer.sh" "$HOME/.dsh_deploy_manifest.txt" 2>/dev/null || true
      # ⑤ 清 .bashrc 里 dsh 菜单的 source 行
      [ -f "$HOME/.bashrc" ] && sed -i '/dshrc.sh/d' "$HOME/.bashrc" 2>/dev/null || true
      echo
      echo "${C_GRN}✅ 已完全卸载 DSH(本体/命令/配置/工作区/~/.dsh-mobile/菜单/.bashrc引用 全清)。${C_RST}"
      echo "npm 全局包(pnpm 等)已保留。返回初始界面。"
      echo
      exit 0
      ;;
    0)
      echo "${C_YEL}已取消卸载，返回菜单。${C_RST}"
      ;;
    *)
      echo "${C_YEL}输入无效(需 5 确认/0 返回)，已取消。${C_RST}"
      echo; read -rp "按回车返回菜单..." _
      ;;
  esac
}

# ---- 主循环 ----
while :; do
  menu_banner
  read -rp "请输入数字(0=退出): " opt
  case "$opt" in
    1)  # 直接启动(本机,默认3080) —— 常驻
      launch_dsh "127.0.0.1" 3080 persist;;
    2)  # 自定义端口: 提示输端口,输0=返回上一层重来
      while :; do
        echo "（局域网/本机启动）"; read -rp "请输入端口(0=返回上一级): " port
        if [ "$port" = "0" ]; then echo "已返回菜单。"; break; fi
        if [ -z "$port" ]; then port=3080; fi
        launch_dsh "127.0.0.1" "$port" test   # 测试后关端口
        break
      done;;
    3)  # 开启局域网: 预检→风险→y→端口→备份+注入dsh→装caddy→提示
      # 预检: 若 dsh 已被注入(局域网已开), 探出端口并返回
      if lan_dsh_modified; then
        echo "═══════════════════════════════════"
        echo "  ${C_YEL}当前局域网已开启${C_RST}"
        echo "═══════════════════════════════════"
        local curport
        curport=$(lan_current_port)
        if [ -n "$curport" ]; then
          echo "  已开启端口: ${curport}"
          echo "  局域网访问: http://$(lan_get_ip):${curport}"
        fi
        echo "  如需关闭,请到【4 局域网状态】一键还原。"
        echo; read -rp "按回车返回菜单..." _
      else
        echo "═══════════════════════════════════"
        echo "  ${C_YEL}开启局域网访问${C_RST}"
        echo "═══════════════════════════════════"
        echo "  ⚠ 风险提示: 开启后同一 Wi-Fi 内其它"
        echo "    设备可访问本 dsh；部分敏感接口将"
        echo "    放行(需改 dsh 鉴权),退出时在【4】还原。"
        echo ""
        read -rp "确认开启吗? 输入 ${C_GRN}y${C_RST} 确认(其他任意键返回菜单): " k
        case "$k" in
          y|Y)
            while :; do
              read -rp "局域网端口(0=返回, 不可用3080, 默认8080): " lport
              if [ "$lport" = "0" ]; then echo "已返回菜单。"; break; fi
              if [ -z "$lport" ]; then lport=8080; fi
              if [ "$lport" = "3080" ]; then
                echo "${C_YEL}  ⚠ 3080 是 dsh 本体端口,不能用于局域网转发,请换一个。${C_RST}"
                continue
              fi
              # 先注入 dsh(放行局域网设置接口), 再起 caddy
              if lan_dsh_inject; then
                lan_caddy_start "$lport" 3080
                echo ""
                echo "${C_YEL}  ✅ 局域网已开启。请【重启 dsh(选项1)】让配置生效。${C_RST}"
              else
                echo "${C_RED}  dsh 注入失败，未开启局域网。${C_RST}"
              fi
              break
            done
            ;;
          *)
            echo "${C_YEL}  已取消，返回菜单。${C_RST}"
            ;;
        esac
        read -rp "按回车返回菜单..." _
      fi;;
    4)  # 局域网状态: 显示端口 + y一键关闭还原/其他返回
      lan_caddy_status;;
    5)  # 查看状态(原有)
      echo "→ 查看状态"
      cmd_status
      echo; read -rp "按回车返回菜单..." _;;
    6)  # 完全卸载: 确认后卸载并退出菜单; 取消则回车返回
      cmd_uninstall;;
    0|q|quit)
      echo "退出。"; break;;
    *)
      echo "${C_YEL}无效输入，请重试($opt)。${C_RST}"; sleep 1;;
  esac
done
