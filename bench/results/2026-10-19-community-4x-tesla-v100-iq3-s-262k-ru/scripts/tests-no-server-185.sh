#!/bin/bash
# D: the same 3 failed test modules of 0.1.45 on 4x V100, but with the production server REALLY stopped
# (stopped through ~/strata185/bin/stop-strata-iq3_s.sh - that one works and waits for the VRAM to be
# released; the SIGINT by pgrep in the previous script did not stop the server).
# Goal: separate "a live model on 8080 is in the way" from "the test fails on its own".
set -u
D=$HOME/strata185
PY=$D/Strata/.venv/bin/python
KEY="removed"
MODS="tools.test_strata_mcp tools.test_setup_golden tools.test_setup_engine_hash"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
props(){ curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }

say "before: health $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY"), props $(props)"
say "the tree configs before the tests:"; ls "$D/Strata" | grep -E "^strata-.*\.json$" | tr "\n" " "; md5sum "$D/Strata/strata-185-iq3_s.json"
say "--- stop through stop-strata-iq3_s.sh"
"$D/bin/stop-strata-iq3_s.sh" 2>&1 | tail -3
for i in $(seq 1 40); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | sort -n | tail -1)
  [ "${used:-0}" -lt 100 ] && break
  sleep 5
done
say "VRAM after the stop: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | tr '\n' ' ')"
say "health after the stop: $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY")"
cd "$D/Strata" || exit 1
say "--- running the modules"
"$PY" -m unittest -v $MODS > "$D/run/tests-0.1.45-without-production.log" 2>&1
say "summary: $(grep -oE 'Ran [0-9]+ tests' $D/run/tests-0.1.45-without-production.log) | $(grep -oE 'FAILED.*|^OK' $D/run/tests-0.1.45-without-production.log | tail -1)"
grep -E "^(FAIL|ERROR): " "$D/run/tests-0.1.45-without-production.log" | head -20
say "the tree configs after the tests:"; ls "$D/Strata" | grep -E "^strata-.*\.json$" | tr "\n" " "; md5sum "$D/Strata/strata-185-iq3_s.json"
say "--- restoring the production server"
cd "$D" || exit 1
"$D/bin/start-strata-iq3_s.sh"
c=000
for i in $(seq 1 80); do c=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY"); [ "$c" = "200" ] && break; sleep 5; done
say "health HTTP $c"
curl -s -m 20 http://127.0.0.1:8080/v1/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next-iq3_s","messages":[{"role":"user","content":"17*23?"}],"max_tokens":8,"temperature":0}' | head -c 200
say "props: $(props)"
say "D_DONE"
