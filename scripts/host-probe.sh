# Sent to a server on stdin by poll_sessions and run there with sh, so the server needs nothing installed.
# It prints its tmux sessions, then one line of stats after a marker: cpu percent|memory used percent|load
tmux ls -F '#{session_name}|#{session_attached}|#{pane_current_path}|#{pane_title}' 2>/dev/null
echo '--stats--'
if [ -r /proc/stat ]; then
  read -r _ u n s i w q f _ </proc/stat
  a=$((u + n + s + i + w + q + f)) b=$i
  sleep 0.5
  read -r _ u n s i w q f _ </proc/stat
  t=$((u + n + s + i + w + q + f - a)) idle=$((i - b))
  cpu=0
  if [ "$t" -gt 0 ]; then
    cpu=$((100 * (t - idle) / t))
  fi
  mem=$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { printf "%d", 100 * (t - a) / t }' /proc/meminfo)
  read -r load _ </proc/loadavg
else
  cpu=$(top -l 2 -n 0 -s 1 | awk '/CPU usage/ { idle = $7 } END { sub("%", "", idle); printf "%d", 100 - idle }')
  mem=$(vm_stat | awk -v size="$(sysctl -n hw.pagesize)" -v total="$(sysctl -n hw.memsize)" '/Pages active|Pages wired|occupied by compressor/ { gsub("\\.", "", $NF); p += $NF } END { printf "%d", 100 * p * size / total }')
  load=$(sysctl -n vm.loadavg | awk '{ print $2 }')
fi
echo "$cpu|$mem|$load"
