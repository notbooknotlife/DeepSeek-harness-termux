#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# dsh-diagnose.sh — DSH "过段时间失效" 全自动诊断
#
#  高自动, 不依赖源码路径, 自动安装到脚本环境 ~/.dsh
#  用法:
#    bash dsh-diagnose.sh auto [分钟]     # 自动监控 N 分钟(默认60)后出报告(推荐)
#    bash dsh-diagnose.sh start [秒]      # 开始后台监控, 每 N 秒采样
#    bash dsh-diagnose.sh stop            # 停止监控
#    bash dsh-diagnose.sh report [行数]   # 打印监控日志(默认50行)
#    bash dsh-diagnose.sh status          # 查看监控状态
#    bash dsh-diagnose.sh install         # 安装到 ~/.dsh/diagnose/
#
#  日志: ~/.dsh/diagnose/monitor.log   状态: ~/.dsh/diagnose/monitor.pid
# ============================================================
SETUP_DIR="$HOME/.dsh/diagnose"
LOG="${DSH_MONITOR_LOG:-$SETUP_DIR/monitor.log}"
PIDFILE="${DSH_MONITOR_PID:-$SETUP_DIR/monitor.pid}"
PORT="${DSH_PORT:-3080}"

BIN="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

now(){ date '+%H:%M:%S'; }

do_install(){
  mkdir -p "$SETUP_DIR"
  cp -f "$BIN" "$SETUP_DIR/dsh-diagnose.sh" 2>/dev/null
  chmod +x "$SETUP_DIR/dsh-diagnose.sh" 2>/dev/null
  echo "[$(now)] 已安装诊断工具到 $SETUP_DIR/dsh-diagnose.sh"
  echo "       以后可直接: bash $SETUP_DIR/dsh-diagnose.sh start 15"
}

snapshot(){
  # 单行快照
  local mavail mtotal swapused
  if command -v free >/dev/null 2>&1; then
    read -r mtotal mavail swapused <<<"$(free -m | awk '/Mem:/{mt=$2;ma=$7} /Swap:/{su=$3} END{print mt,ma,su}')"
  else mtotal="-"; mavail="-"; swapused="-"; fi
  local pids nproc rss cpu cwd
  pids=$(pgrep -f "dsh/lib/bin.js" | grep -v $$)
  nproc=$(echo "$pids" | grep -c .); [ "$nproc" = "0" ] && pids=""
  rss=0; cpu=0
  for pid in $pids; do
    r="$(ps -o rss= -p $pid 2>/dev/null|tr -d ' ')"; case "$r" in ''|*' '*) r=0;; esac; rss=$((rss+r))
    c="$(ps -o %cpu= -p $pid 2>/dev/null|tr -d ' '|awk -F. '{print $1}')"; case "$c" in ''|*' '*) c=0;; esac
    [ -n "$c" ] && { [ "$c" -gt "$cpu" ] && cpu=$c; }
  done; rss=$((rss/1024))
  local code t ms
  r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 8 "http://127.0.0.1:$PORT/" 2>/dev/null)
  code="${r% *}"; t="${r#* }"; [ -z "$t" ] && { code="TO"; t="99.0"; }
  ms=$(awk "BEGIN{printf \"%.0f\",$t*1000}" 2>/dev/null)
  local cwd=""
  for pid in $pids; do cwd=$(readlink -f /proc/$pid/cwd 2>/dev/null); break; done
  echo "TS=$(date '+%H:%M:%S') | memAvail=${mavail}/${mtotal}MB | swapUsed=${swapused}MB | procs=$nproc | rss=$rss MB | cpu=${cpu}% | http=${code} ${ms}ms | $(basename "$cwd" 2>/dev/null)($cwd)"
}

do_start(){
  local interval="${1:-15}"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(now)] 监控已在运行 PID=$(cat "$PIDFILE")"; return 0
  fi
  mkdir -p "$SETUP_DIR"
  nohup bash -c "while true; do \"$BIN\" snap >> \"$LOG\" 2>/dev/null; sleep $interval; done" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"; touch "$LOG"
  echo "[$(now)] 监控已启动 PID=$! (每 ${interval}s; 日志=$LOG)"
}

do_stop(){
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"
    echo "[$(now)] 监控已停止"
  else echo "[$(now)] 监控未在运行"; fi
}

do_report(){
  local n="${1:-50}"
  echo "===== DSH 监控日志 (最近 $n 行, $LOG) ====="
  echo "判读: memAvail低/swapUsed高→内存吃紧; procs>1→端口冲突; http!=200或>3000ms→服务/网络异常; 全程正常仍卡→WebSocket/前端"
  echo "---"
  [ -f "$LOG" ] && tail -n "$n" "$LOG" || echo "(暂无日志)"
  echo "---"
}

do_status(){
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "[$(now)] 监控运行中 PID=$(cat "$PIDFILE"), 行数=$(wc -l < "$LOG" 2>/dev/null)"
  else echo "[$(now)] 监控未运行"; fi
}

do_auto(){
  local mins="${1:-60}" secs=$(( ${1:-60} * 60 )) interval="${2:-15}"
  echo "[$(now)] 自动诊断模式: 将监控 ${mins} 分钟 (每 ${interval}s), 到时自动出报告。"
  echo "       请保持 dsh 正常运行。若期间出现'加载不出来', 报告会如实记录。"
  do_start "$interval"
  sleep "$secs"
  do_stop
  do_report 500
}

case "${1:-help}" in
  install) do_install ;;
  snap)    snapshot ;;
  start)   do_start "${2:-15}" ;;
  stop)    do_stop ;;
  report)  do_report "${2:-50}" ;;
  status)  do_status ;;
  auto)    do_auto "${2:-60}" "${3:-15}" ;;
  *)
    echo "用法: bash $0 {auto|start|stop|report|status|install}"
    echo "  auto [分钟] [秒间隔]  一键: 监控指定时长后自动出报告"
    ;;
esac
