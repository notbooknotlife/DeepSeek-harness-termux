#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# dsh-monitor.sh — DSH 持续后台监控器(诊断"过段时间失效")
#   用法:
#     bash diagnose/dsh-monitor.sh start [间隔秒]   # 启动后台监控(默认每15秒)
#     bash diagnose/dsh-monitor.sh stop             # 停止
#     bash diagnose/dsh-monitor.sh report [行数]    # 打印最近N行监控日志(默认50)
#     bash diagnose/dsh-monitor.sh status           # 查看监控是否在跑
#
#   说明: 建议在 dsh 启动时自动 start; 失效/卡住后 report 贴给维护者。
#   日志默认 ~/.dsh_monitor.log
# ============================================================
LOG="${DSH_MONITOR_LOG:-$HOME/.dsh_monitor.log}"
PIDFILE="${DSH_MONITOR_PID:-$HOME/.dsh_monitor.pid}"
PORT="${DSH_PORT:-3080}"
DIR="$(cd "$(dirname "$0")" && pwd)"

now() { date '+%H:%M:%S'; }

do_start(){
  INTERVAL="${1:-15}"
  # 已在运行则忽略
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(now)] 监控已在运行 PID=$(cat "$PIDFILE")"
    return 0
  fi
  # 后台循环采样
  nohup bash -c "
    while true; do
      bash '$DIR/dsh-diagnose.sh' '$PORT' >> '$LOG' 2>/dev/null
      sleep $INTERVAL
    done
  " >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  touch "$LOG"
  echo "[$(now)] 监控已启动 PID=$! (每 ${INTERVAL}s; 日志=$LOG)"
}

do_stop(){
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    echo "[$(now)] 监控已停止"
  else
    echo "[$(now)] 监控未在运行"
  fi
}

do_report(){
  n="${1:-50}"
  echo "===== DSH 监控日志 (最近 $n 行, 文件=$LOG) ====="
  echo "判读: memAvail可用内存低→内存吃紧; swapUsed高→压力大;"
  echo "      dshProcs>1→端口冲突; http!=200或port>3000ms→服务/网络异常; 全程port正常仍是数据卡→WebSocket/前端"
  echo "-----------------------------------------------------------"
  if [ -f "$LOG" ]; then tail -n "$n" "$LOG"; else echo "(暂无日志)"; fi
  echo "-----------------------------------------------------------"
}

do_status(){
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(now)] 监控运行中 PID=$(cat "$PIDFILE"), 日志行数=$(wc -l < "$LOG" 2>/dev/null)"
  else
    echo "[$(now)] 监控未运行"
  fi
}

case "${1:-start}" in
  start)  do_start "${2:-15}" ;;
  stop)   do_stop ;;
  report) do_report "${2:-50}" ;;
  status) do_status ;;
  *) echo "用法: $0 {start [sec]|stop|report [n]|status}";;
esac
