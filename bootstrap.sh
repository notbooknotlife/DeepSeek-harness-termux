#!/data/data/com.termux/files/usr/bin/bash
#===============================================================================
#  bootstrap.sh — DSH Termux 部署的"引导"脚本
#
#  用途：允许通过一行命令远程执行（curl | bash）而无需先把整个安装器落盘：
#       bash -c "$(curl -fsSL <raw-url>/bootstrap.sh)" <installer-args...>
#
#  设计：本文件保持"极短、可审阅"；它只做三件事——
#      1) 下载真正的安装器 install.sh（完整实现都在 install.sh 里）
#      2) 校验 SHA256（若配置了指纹）
#      3) 把它交给 bash 执行你传入的剩余参数
#
#  这样把"完整逻辑(install.sh"与"远程引导(bootstrap.sh"分离，
#  既便于审阅，又支持一行一键调用。
#===============================================================================
set -u

#------------------------------------------------------------------------------
# 配置：发布时改为你的仓库 raw 地址（并可选填入指纹）
#------------------------------------------------------------------------------
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/notbooknotlife/DeepSeek-harness-termux/main}"
INSTALL_NAME="dsh-termux-deploy.sh"        # 真正的安装器文件
APPROVED_SHA256="${APPROVED_SHA256:-}"     # 留空=跳过强校验；必填则启动前校验

#------------------------------------------------------------------------------
# 基础工具
#------------------------------------------------------------------------------
have(){ command -v "$1" >/dev/null 2>&1; }
err(){  echo "[ERR] $*"; }

main(){
  local dst
  dst="${TMPDIR:-$HOME}/.dsh-bootstrap-installer.sh"

  echo "== DSH 引导安装 =="
  echo "   下载安装器: $RAW_BASE/$INSTALL_NAME"

  # 1) 下载
  if ! curl -fsSL "$RAW_BASE/$INSTALL_NAME" -o "$dst"; then
    err "下载安装器失败。请检查网络或 RAW_BASE 是否正确。"
    return 1
  fi

  # 2) 指纹校验（可选）
  if [ -n "$APPROVED_SHA256" ]; then
    local actual
    actual="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')"
    if [ "$actual" != "$APPROVED_SHA256" ]; then
      err "安装器 SHA256 校验失败！"
      err "   期望: $APPROVED_SHA256"
      err "   实际: $actual"
      err "已中止执行，防止运行被篡改的脚本。"
      return 1
    fi
    echo "   指纹校验通过: $actual"
  else
    echo "   (跳过 SHA256 强校验：APPROVED_SHA256 未设置)"
  fi

  # 3) 交给 bash 执行（透传你的剩余参数：install / serve / uninstall ...）
  echo "   执行: bash $dst $*"
  bash "$dst" "$@"
  local code=$?
  rm -f "$dst"
  return $code
}

main "$@"
exit $?
