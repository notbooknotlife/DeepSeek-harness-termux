#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# dsh-diagnose.sh — DSH 状态"快照"(紧凑单行)
# 供 dsh-monitor.sh 后台持续调用; 也可手动跑一次看当前状态。
#   用法:  bash diagnose/dsh-diagnose.sh [端口]
#   输出:  单行快照(TS|mem|swap|procs|rss|cpu|http|portms)
# ============================================================
TP="${1:-3080}"
DSH_PAT="dsh/lib/bin.js"

now=$(date '+%H:%M:%S')

# --- 内存 / swap ---
if command -v free >/dev/null 2>&1; then
  read -r mtotal mavail swapused <<<"$(free -m | awk '/Mem:/{mt=$2;ma=$7} /Swap:/{su=$3} END{print mt,ma,su}')"
else
  mtotal="-"; mavail="-"; swapused="-"
fi

# --- dsh 进程 ---
pids=$(pgrep -f "$DSH_PAT" | grep -v $$ )
nproc=$(echo "$pids" | grep -c .)
[ "$nproc" = "0" ] && pids=""
rss=0; cpu=0
for pid in $pids; do
  r="$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ' )"; case "$r" in ''|*' '*) r=0;; esac; rss=$((rss+r))
  c="$(ps -o %cpu= -p $pid 2>/dev/null | tr -d ' ' | awk -F. '{print $1}')"; case "$c" in ''|*' '*) c=0;; esac
  [ -n "$c" ] && { [ "$c" -gt "$cpu" ] && cpu=$c; }
done
rss=$((rss/1024))

# --- 端口响应 ---
r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 8 "http://127.0.0.1:$TP/" 2>/dev/null)
code="${r% *}"; t="${r#* }"
if [ -z "$t" ]; then code="TO"; t="99.0"; fi
ms=$(awk "BEGIN{printf \"%.0f\",$t*1000}" 2>/dev/null)

# ---- 输出单行 ----
echo "TS=$now | memAvail=${mavail}MB/${mtotal}MB | swapUsed=${swapused}MB | dshProcs=$nproc | rssAll=${rss}MB | cpu=${cpu}% | http=$code port=${ms}ms | cwd=$(for pid in $pids; do readlink -f /proc/$pid/cwd 2>/dev/null; done | head -1 | sed 's#.*/home/##;s#/data/data/.*files/##')"
