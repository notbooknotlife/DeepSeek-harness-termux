#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  dshmenu — DSH 控制菜单
#  用法: bash dshmenu.sh  (或添加到 ~/.bashrc 后直接输 dshmenu)
#  不改动 dsh 本体，仅提供交互式启动/状态/卸载入口。
# ============================================================

# 部署脚本路径（可改成你 clone 的位置）
DEPLOY_SCRIPT="${DSH_DEPLOY_SCRIPT:-$HOME/storage/dsh-src/dsh-termux-deploy.sh}"

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
  echo "║  ${C_YEL}5)${C_RST} 完全卸载        → ${C_CYA}bash $DEPLOY_SCRIPT uninstall (+清配置)${C_RST}"
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

cmd_status(){ bash "$DEPLOY_SCRIPT" status; }

# 后台启动 dsh web + 自动开浏览器，然后等回车返回菜单
launch_dsh(){
  # mode=persist 常驻(输入1)；mode=test 启动后验证端口即关闭(输入2/3)
  local host="$1" port="$2" mode="${3:-persist}"
  # 常驻模式: 若已在运行则不重复启动
  if command -v pgrep >/dev/null 2>&1 && pgrep -f "dsh/lib/bin.js" >/dev/null 2>&1; then
    echo "${C_YEL}已有 dsh web 在运行。${C_RST}"
  else
    nohup dsh web --host "$host" --port "$port" >"$HOME/.dsh/dsh-web.log" 2>&1 &
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

cmd_uninstall(){
  echo
  echo "${C_RED}⚠  即将完全卸载 DSH(全局，含会话/配置 ~/.dsh)${C_RST}"
  read -rp "确认卸载？再输入 5 确认: " c2
  if [ "$c2" = "5" ]; then
    echo "执行卸载..."
    [ -f "$DEPLOY_SCRIPT" ] && bash "$DEPLOY_SCRIPT" uninstall
    # 完全(全局)卸载：连配置/会话一起清掉
    rm -rf "$HOME/.dsh" "$HOME/.dsh-mobile" 2>/dev/null
    echo "${C_GRN}已完全卸载(含 ~/.dsh)。${C_RST}"
  else
    echo "${C_YEL}已取消卸载。${C_RST}"
  fi
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
    3)  # 局域网启动: 输端口,输0返回
      while :; do
        read -rp "请输入端口(0=返回上一级,默认3080): " port
        if [ "$port" = "0" ]; then echo "已返回菜单。"; break; fi
        if [ -z "$port" ]; then port=3080; fi
        launch_dsh "0.0.0.0" "$port" test   # 测试后关端口
        break
      done;;
    4)  # 查看状态(保持原样,回车返回)
      echo "→ 查看状态"
      cmd_status
      echo; read -rp "按回车返回菜单..." _;;
    5)  # 完全卸载(双重确认后返回菜单)
      cmd_uninstall
      echo; read -rp "按回车返回菜单..." _;;
    0|q|quit)
      echo "退出。"; break;;
    *)
      echo "${C_YEL}无效输入，请重试($opt)。${C_RST}"; sleep 1;;
  esac
done
