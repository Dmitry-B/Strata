#!/bin/bash
# reverse2 (the script is named reverse3-185.sh on the machine): the reverse order of the short/medium ru measurements (0.1.44.1 first,
# then 0.1.45). The previous attempt (reverse2) stopped working: SIGINT did not stop the engine (it stops
# only on TERM, from bin/stop-strata.sh), and the tree swap happened while the server was still running.
# Here the stop is done with the machine's own script, and the version is checked in BUILD.json before and after.
#
# Run: setsid nohup ~/strata185/bin/reverse3-185.sh >> ~/strata185/run/reverse3-2026-10-19.log 2>&1 &
set -u
D=$HOME/strata185
BENCH=$D/bin/strata-bench-community.py
OUT=$D/bench-community/reverse3-short-ru
KEY="removed"
BAK=$D/Strata-0.1.44.1.bak
LEN=4k,32k,65k
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
treever(){ sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$D/Strata/engine-cuda12/BUILD.json" 2>/dev/null | head -1; }
propsver(){ curl -s -m 15 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }
stop_server(){
  say "stopping through bin/stop-strata.sh"; bash "$D/bin/stop-strata.sh"
  rm -f "$D/run/server-iq3_s.pid"
  nvidia-smi --query-gpu=memory.used --format=csv,noheader | tr '\n' ' '; echo
  sleep 10
}
start_server(){
  bash "$D/bin/start-strata-iq3_s.sh"
  for _ in $(seq 1 40); do
    sleep 5
    [ "$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8080/health || true)" = "200" ] && {
      say "health 200; engine version: $(propsver)"; return 0; }
  done
  say "ERR: health is not 200"; return 1
}
ensure_version(){ # $1 = the tree version wanted
  [ "$(treever)" = "$1" ] && { say "the tree is already $(treever)"; return 0; }
  stop_server
  [ -e "$D/Strata-hold" ] && { say "ERR: Strata-hold is occupied"; exit 1; }
  mv "$D/Strata" "$D/Strata-hold" && mv "$BAK" "$D/Strata" && mv "$D/Strata-hold" "$BAK"
  ln -sfn "$D/Strata/strata-185-iq3_s.json" "$D/strata-config.json"
  say "installed tree: $(treever) (backup: $BAK)"
}
run_ru(){ # $1 = label
  say "--- ru measurements ($1): 4096/32768/66560 tokens, internal warm-up + 3 repetitions"
  "$D/Strata/.venv/bin/python" "$BENCH" "reverse3-$1" --style ru --lengths "$LEN" --no-gen-case --out "$OUT/$1"
  say "RU_REVERSE3_${1}_DONE"
}

say "=== reverse order, short and medium lengths, ru style ==="
ensure_version 0.1.44.1
start_server || exit 1
sleep 20
run_ru "0.1.44.1-first"
ensure_version 0.1.45
start_server || exit 1
sleep 20
run_ru "0.1.45-second"
say "=== done; installed $(treever); engine: $(propsver) ==="
