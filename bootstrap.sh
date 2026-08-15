#!/data/data/com.termux/files/usr/bin/bash
#===============================================================================
#  bootstrap.sh — DSH Termux 部署的"引导"脚本
#
#  用途：允许通过一行命令远程执行（curl | bash）而无需先把整个安装器落盘：
#       bash -c "$(curl -fsSL <raw-url>/bootstrap.sh)" install
#
#  它做三件事：1) 下载真正的安装器(dsh-termux-deploy.sh)
#              2) 可选 SHA256 指纹校验
#              3) 把命令参数透传给安装器并执行
#  兼容两种调用方式：
#     bash bootstrap.sh install            （直接跑，命令在 $@）
#     bash -c "$(curl ...bootstrap.sh)" install  （一键，命令在 $0）
#===============================================================================
set -u

#------------------------------------------------------------------------------
# 配置：发布时改为你的仓库 raw 地址（并可选填入指纹）
#------------------------------------------------------------------------------
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/notbooknotlife/DeepSeek-harness-termux/main}"
INSTALL_NAME="dsh-termux-deploy.sh"
APPROVED_SHA256="${APPROVED_SHA256:-}"     # 留空=跳过强校验

have(){ command -v "$1" >/dev/null 2>&1; }
err(){ echo "[ERR] $*"; }

main(){
  local dst cmd rest
  dst="${TMPDIR:-$HOME}/.dsh-bootstrap-installer.sh"

  # 组装要传给安装器的命令：
  #   - 若 $@ 有参数（bash bootstrap.sh install），用 $@
  #   - 若 $@ 为空但 $0 是命令名（bash -c \"内容\" install），用 $0
  if [ "$#" -gt 0 ]; then
    cmd="$1"; shift
    rest="$@"
  else
    cmd="$0"
    rest=""
  fi
  # 若 $0 不是命令名（如 bin/bash 或 /usr/bin/bash），回退 help
  case "$cmd" in
    */*|bash|sh|-bash|*".sh") cmd="help" ;;
  esac

  echo "== DSH 引导安装 =="
  echo "   下载安装器: $RAW_BASE/$INSTALL_NAME"

  if ! curl -fsSL "$RAW_BASE/$INSTALL_NAME" -o "$dst"; then
    err "下载安装器失败。请检查网络或 RAW_BASE 是否正确。"
    return 1
  fi

  if [ -n "$APPROVED_SHA256" ]; then
    local actual
    actual="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')"
    if [ "$actual" != "$APPROVED_SHA256" ]; then
      err "安装器 SHA256 校验失败！期望=$APPROVED_SHA256 实际=$actual"
      return 1
    fi
    echo "   指纹校验通过: $actual"
  else
    echo "   (跳过 SHA256 强校验：APPROVED_SHA256 未设置)"
  fi

  echo "   执行: bash $dst $cmd $rest"
  bash "$dst" "$cmd" $rest
  local code=$?
  rm -f "$dst"
  return $code
}

main "$@"
exit $?
