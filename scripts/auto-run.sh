#!/usr/bin/env bash
# Autonomous VIctory runner: each run picks up where the last one stalled.
#
# A run writes to auto/run-<n>.log. When that log goes quiet for STALL_SECS
# while the process is alive, the last "host pipeline: making" line names the
# pipeline that blocked the title; its shader hashes go into auto/skips.txt,
# which every later run passes as VICTORY_SKIP_PIPELINES. Every run's best
# frame and fps go to auto/ledger.txt. Crashes (process gone without a stall)
# are recorded and retried with the same skips.
set -u

repo=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
exe=${EXE:-$repo/target/x86_64-pc-windows-msvc/diag/victory.exe}
game=${GAME:-}
[ -n "$game" ] || game='Z:\path\to\GTA6.Xbox.v1.0.2.1\game_scarlett_master.exe'
work=${WORK:-$repo/auto-runs}
skips=$work/skips.txt
ledger=$work/ledger.txt
mkdir -p "$work"
touch "$skips" "$ledger"

max_runs=${MAX_RUNS:-20}
stall_secs=${STALL_SECS:-150}
loop_limit=${LOOP_LIMIT:-256}
same_stall_limit=${SAME_STALL_LIMIT:-3}

# Leftovers from an earlier manual run. The script's own command line has no
# game name, so this cannot match itself.
pkill -f 'game_scarlett_master.exe' 2>/dev/null
sleep 2

run=0
same_stall=0
best_frame=0
best_fps=0
while [ "$run" -lt "$max_runs" ]; do
    run=$((run + 1))
    now=$(date +%s)
    list=$(cat "$skips")
    log=$work/run-$run.log
    sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)
    echo "=== run $run  $(date -Is)  sha=$sha  exe=$(basename "$exe")  loop=$loop_limit  skips=$list" >>"$ledger"

    export VICTORY_LOG='info,victory_gpu::pipeline=debug'
    export VICTORY_NO_WATCHDOG=1
    export VICTORY_SHADER_LOOP_LIMIT="$loop_limit"
    export VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains
    export VKD3D_SHADER_CACHE_PATH="$HOME/.cache/victory-vkd3d"
    # xcl-dev/xcl#1701: shared fences hang under vkd3d-proton and the title's
    # watchdog kills it at +0x2215c35, the site this tree disables entirely.
    export VKD3D_CONFIG=ignore_shared_fence
    export VICTORY_TEXTURE_NO_WAIT=1
    export VICTORY_LATE_WAIT=3
    export VICTORY_RELAY=2
    export VICTORY_WIDE_BACK=1
    export VICTORY_WIDE_REFRESH=1
    export VICTORY_JOIN_COPIES=1
    export VICTORY_CARD_BUFFERS_MIN_MB=1
    export VICTORY_CARD_BUFFERS_MB=1024
    export VICTORY_SKIP_PIPELINES="$list"
    export VICTORY_CAPTURE="$work/capture-$run"
    export VICTORY_DUMP_TARGETS=1
    export VICTORY_CAPTURE_FRAMES='6500,7200'
    export VICTORY_KEYS=$(seq 20 5 300 | awk '{printf "%s:Enter,",$1}' | sed 's/,$//')
    mkdir -p "$VICTORY_CAPTURE"

    setsid --wait "${RUNNER:-/tmp/opencode/victory-slr.sh}" runinprefix "$exe" run "$game" --execute \
        >"$log" 2>&1 &
    pid=$!
    sleep 2
    child=$(pgrep -P "$pid" | head -1)
    echo "pid=$pid child=$child" >>"$ledger"

    last_progress=$now
    stalled=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 10
        [ -e "$log" ] || continue
        mtime=$(stat -c %Y "$log")
        if [ "$mtime" -gt "$last_progress" ]; then
            last_progress=$mtime
        fi
        idle=$(( $(date +%s) - last_progress ))
        if [ "$idle" -ge "$stall_secs" ]; then
            stalled=1
            break
        fi
    done

    frame=$(grep -oE 'frame=[0-9]+' "$log" | tail -1 | cut -d= -f2)
    frame=${frame:-0}
    fps=$(grep -oE '[0-9.]+ fps' "$log" | tail -1 | cut -d' ' -f1)
    fps=${fps:-0}
    echo "result frame=$frame fps=$fps best_frame=$best_frame best_fps=${best_fps:-0} stalled=$stalled" >>"$ledger"
    if [ "$frame" -gt "$best_frame" ]; then
        best_frame=$frame
        best_fps=$fps
        same_stall=0
    fi

    if [ "$stalled" -eq 1 ]; then
        line=$(grep -a 'host pipeline: making' "$log" | tail -1)
        hashes=$(printf '%s' "$line" | grep -oE '[0-9a-f]{16}' | tr '\n' ',' | sed 's/,$//')
        echo "stall idle=${idle}s last_making=[$line]" >>"$ledger"
        if [ -n "$hashes" ]; then
            added=0
            IFS=',' read -ra hs <<<"$hashes"
            for h in "${hs[@]}"; do
                case ",$list," in *",$h,"*) ;; *) list="${list:+$list,}$h"; added=1 ;; esac
            done
            printf '%s' "$list" >"$skips"
            echo "skip += $hashes (added=$added) now=[$list]" >>"$ledger"
            if [ "$added" -eq 0 ]; then
                same_stall=$((same_stall + 1))
            else
                same_stall=0
            fi
        else
            same_stall=$((same_stall + 1))
        fi
        target=${child:-$pid}
        kill -TERM -"$target" 2>/dev/null
        sleep 3
        kill -KILL -"$target" 2>/dev/null
        if [ "$same_stall" -ge "$same_stall_limit" ]; then
            echo "stopping: the same stall survived $same_stall_limit skips" >>"$ledger"
            exit 2
        fi
    else
        # Process ended on its own: a crash or a clean exit. Retry with the
        # same set; three runs with no new frame and no new skip stop the loop.
        echo "run ended without a stall" >>"$ledger"
        same_stall=$((same_stall + 1))
        if [ "$same_stall" -ge "$same_stall_limit" ]; then
            echo "stopping: $same_stall_limit runs ended without progress" >>"$ledger"
            exit 3
        fi
    fi
done
echo "stopping: $max_runs runs" >>"$ledger"
