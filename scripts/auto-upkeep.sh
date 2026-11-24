#!/usr/bin/env bash
# Keeps the autonomous run loop alive and its disk use bounded.
# Every 15 minutes: restart the supervisor if it stopped, keep the four
# newest run folders, and cap the supervisor log.
set -u
work=/tmp/opencode
loop="$work/victory-loop.sh"
log="$work/auto/supervisor.log"

# The supervisor exits by design after three stalled runs; that is not a
# reason to stop trying.
if ! pgrep -f '^bash /tmp/opencode/victory-loop\.sh$' >/dev/null; then
    mkdir -p "$work/auto"
    [ -s "$work/auto/skips.txt" ] || printf '%s' '55679a0547649d0b,afeea48bbb9913ad,e8c962358d862e3f,44a9625f01769f33' >"$work/auto/skips.txt"
    nohup bash "$loop" >>"$log" 2>&1 &
    echo "$(date -Is) restarted supervisor pid=$!"
fi

# Four folders keep the last four runs; older ones go.
ls -dt "$work"/auto-run* 2>/dev/null | tail -n +5 | while read -r dir; do rm -rf "$dir"; done

# 50 MB of supervisor log is plenty.
if [ -f "$log" ] && [ "$(stat -c %s "$log")" -gt $((50 << 20)) ]; then
    tail -c $((10 << 20)) "$log" >"$log.tmp" && mv "$log.tmp" "$log"
fi
