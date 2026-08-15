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
  read -rp "请输入数字: " opt
  case "$opt" in
    1)
      echo "→ 启动: dsh web"
      dsh web
      break;;
    2)
      port=$(ask_port)
      echo "→ 启动: dsh web --port $port"
      dsh web --port "$port"
      break;;
    3)
      port=$(ask_port)
      echo "→ 启动: dsh web --host 0.0.0.0 --port $port"
      dsh web --host 0.0.0.0 --port "$port"
      break;;
    4)
      echo "→ 查看状态"
      cmd_status
      echo; read -rp "按回车返回菜单..." _;;
    5)
      cmd_uninstall
      echo; read -rp "按回车返回菜单..." _;;
    0|q|quit)
      echo "退出。"; break;;
    *)
      echo "${C_YEL}无效输入，请重试($opt)。${C_RST}"; sleep 1;;
  esac
done
