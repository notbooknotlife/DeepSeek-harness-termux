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
  echo "║  ${C_YEL}3)${C_RST} 局域网启动      → ${C_CYA}dsh web --host 0.0.0.0 --port <端口>${C_RST}"
  echo "║  ${C_YEL}4)${C_RST} 查看状态        → ${C_CYA}bash $DEPLOY_SCRIPT status${C_RST}"
  echo "║  ${C_YEL}5)${C_RST} 局域网开/关    → ${C_CYA}开启/关闭局域网访问${C_RST}"
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
    # host=0.0.0.0 时【不传 --host】(dsh 命令行会拦截 0.0.0.0), 靠 cordis.patch.yml 配置的
    # webserver host 生效(已由 luangwei 开关写入); 本机/自定义端口才显式传 --host。
    local hostarg=()
    if [ "$host" != "0.0.0.0" ]; then hostarg=(--host "$host"); fi
    ( cd "$WS" && nohup dsh web "${hostarg[@]}" --port "$port" >"$HOME/.dsh/dsh-web.log" 2>&1 ) &
    sleep 3   # 等端口起来
  fi
  echo "  本机访问:      http://127.0.0.1:$port"
  local lanip=$(ifconfig 2>/dev/null | awk '/^[a-z]/{if=$1}/inet /{print if,$2}' | awk '$1~/^wlan/{print $2;exit}' | cut -d: -f2)
  [ -z "$lanip" ] && lanip=$(ifconfig 2>/dev/null | awk '/^[a-z]/{if=$1}/inet /{print if,$2}' | grep -vE '^(lo|docker|tun|virbr)' | awk '{print $2;exit}' | cut -d: -f2)
  [ -n "$lanip" ] && echo "  局域网设备访问: http://$lanip:$port"

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


# ================= 局域网 开/关 =================
# 原理: dsh 命令行 --host 0.0.0.0 会被 dsh 安全拦截; 但通过 profile 配置
#       cordis.patch.yml 给 webserver 设 host 可生效(启动时读配置, 不经命令行拦截)。
#       改动 cordis.patch.yml 后必须【重启 dsh】才生效。此处不改 dsh 本体, 只动配置。
PATCH_YML="${DSH_PATCH_YML:-$HOME/.dsh/profiles/web/cordis.patch.yml}"

# 检测当前局域网状态: on=开启; off=关闭(默认)
lan_status(){
  if [ -f "$PATCH_YML" ] && grep -q "0.0.0.0" "$PATCH_YML" 2>/dev/null; then
    echo on
  else
    echo off
  fi
}

# 写入 host 到 cordis.patch.yml(最小: 追加以 webserver 覆盖 host)
# mode=on→0.0.0.0 ; mode=off→127.0.0.1
lan_write_config(){
  local mode="$1"
  local hostval="127.0.0.1"
  [ "$mode" = "on" ] && hostval="0.0.0.0"
  # 移除已有 webserver host 行, 再追加
  if [ -f "$PATCH_YML" ]; then
    sed -i '/id: webserver/,/host:/d' "$PATCH_YML" 2>/dev/null || true
    sed -i '/- id: webserver/d;/host:/d' "$PATCH_YML" 2>/dev/null || true
  fi
  cat >> "$PATCH_YML" <<YEOF

- id: webserver
  config:
    host: $hostval
YEOF
}

# 开启/关闭 交互(默认关闭)
lan_toggle(){
  local cur now need
  cur=$(lan_status)
  if [ "$cur" = "off" ]; then
    now="开" ; need="开启"
  else
    now="关" ; need="关闭"
  fi
  clear
  echo "═══════════════════════════════════"
  echo "  ${C_YEL}${need}局域网访问需要【重启 dsh】才能生效${C_RST}"
  echo "═══════════════════════════════════"
  if [ "$cur" = "off" ]; then
    echo "  开启后,同一 Wi-Fi 设备可通过"
    echo "    http://<本机局域网IP>:<端口>  访问本 dsh。"
    echo ""
    echo "  ⚠ 安全提示: 局域网模式下同网络内"
    echo "    其他设备也能访问 dsh(官方警告存在"
    echo "    远程代码执行 RCE 风险),请仅在可信"
    echo "    网络中使用。"
  else
    echo "  关闭后 dsh 仅允许本机访问"
    echo "    (http://127.0.0.1:<端口>)。"
  fi
  echo ""
  echo "  已确认要${need}吗? 输入 ${C_GRN}y${C_RST} 确认 ${C_RST}(其他任意键返回菜单)"
  read -rp "> " k
  case "$k" in
    y|Y)
      if [ "$cur" = "off" ]; then lan_write_config on; else lan_write_config off; fi
      echo "  ${C_YEL}配置已${need},请【重启 dsh】让改动生效。${C_RST}"
      echo "  若要立即重启,请先退出菜单再运行: dshmenu 选项1 重新启动"
      ;;
    *)
      echo "${C_YEL}已取消,返回菜单(${need}局域网未改动)。${C_RST}"
      ;;
  esac
  read -rp "按回车返回菜单..." _
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
    3)  # 局域网启动: 需先开启局域网,输端口,输0返回
      if [ "$(lan_status)" = "off" ]; then
        echo "${C_YEL}当前局域网未开启,无法进行局域网启动。${C_RST}"
        echo "请先到【5 局域网开/关】开启局域网后,再回来使用本选项。"
        echo; read -rp "按任意键返回菜单..." _
      else
        while :; do
          read -rp "请输入端口(0=返回上一级,默认3080): " port
          if [ "$port" = "0" ]; then echo "已返回菜单。"; break; fi
          if [ -z "$port" ]; then port=3080; fi
          launch_dsh "0.0.0.0" "$port" test   # 测试后关端口
          break
        done
      fi;;
    4)  # 查看状态(保持原样,回车返回)
      echo "→ 查看状态"
      cmd_status
      echo; read -rp "按回车返回菜单..." _;;
    5)  # 局域网 开/关 切换(当前: 开→问关闭; 关→问开启)
      lan_toggle;;
    6)  # 完全卸载: 确认后卸载并退出菜单; 取消则回车返回
      cmd_uninstall;;
    0|q|quit)
      echo "退出。"; break;;
    *)
      echo "${C_YEL}无效输入，请重试($opt)。${C_RST}"; sleep 1;;
  esac
done
