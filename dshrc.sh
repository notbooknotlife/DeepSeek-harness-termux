# ============================================================
#  dshrc.sh — DSH shell 集成片段
#  让 `dsh`(无参数)弹出交互菜单；`dsh 参数`仍走原生 dsh。
#  用法：
#    - 本机: 在 ~/.bashrc 加一行  source ~/storage/dsh-src/dshrc.sh
#    - 新手机 clone 后 source 同目录 dshrc.sh
# ============================================================

# 项目根（改这里指向实际 clone 位置）
DSH_PROJECT_DIR="${DSH_PROJECT_DIR:-$HOME/storage/dsh-src}"

# dshmenu 菜单脚本路径
DSH_MENU_PATH="$DSH_PROJECT_DIR/dshmenu.sh"

# 覆盖 dsh：无参数→菜单，有参数→原生命令
function dsh {
  if [ $# -eq 0 ]; then
    # 无参数：弹菜单
    if [ -f "$DSH_MENU_PATH" ]; then
      bash "$DSH_MENU_PATH"
    else
      echo "[dsh] 未找到菜单脚本: $DSH_MENU_PATH"
      command dsh "$@"
    fi
  else
    # 有参数：调原生 dsh（不递归、完全不变）
    command dsh "$@"
  fi
}
