#!/bin/bash
# Fourth part of the 0.1.45 cycle on 4x V100: two open questions.
#
# A) The unit tests that failed in the clean release tree (13 failures and 1 error in tools.*) are repeated
#    in the INSTALLED tree (~/strata185/Strata: it has .venv and a built engine) with the production
#    server stopped. That shows whether the code or the missing installed environment is to blame.
# B) In the ru style 0.1.45 read long prompts 6-7% slower than 0.1.44.1 (2391 vs 2573 tok/s at
#    127228 tokens, reproduced by a control run of the same version), while in the code style there is no difference.
#    The order of the measurements was: 0.1.45 first, then 0.1.44.1 - so the later run could have
#    benefited from a warmed page cache and an updated expert profile. So the measurements are repeated
#    in the REVERSE order: 0.1.44.1 first, then 0.1.45, at the same lengths (131072/194560/209715, ru).
#
# Run: setsid nohup ~/strata185/bin/ab-ru-and-tests-185.sh >> ~/strata185/run/ab-2026-10-19.log 2>&1 &
set -u
D=$HOME/strata185
PY=$D/Strata/.venv/bin/python
BENCH=$D/bin/strata-bench-community.py
KEY="removed"
DAY=2026-10-19
TMP=$D/bench-community/tmp-$DAY
PAT="strata185/Strata/(.venv/bin/python|engine-cuda12/)"
MODS="tools.test_strata_mcp tools.test_setup_golden tools.test_setup_engine_hash"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
propsver(){ curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }
stop_server(){
  for p in $(pgrep -f "$PAT" 2>/dev/null); do kill -INT "$p" 2>/dev/null; done
  rm -f "$D/run/server-iq3_s.pid"
  born=$(date +%s)
  while pgrep -f "$PAT" >/dev/null 2>&1 && [ $(( $(date +%s) - born )) -lt 240 ]; do sleep 3; done
  say "the server is stopped ($(nvidia-smi --query-gpu=memory.used --format=csv,noheader | tr '\n' ' '))"
}
ru_long(){
  local tag=$1
  say "--- ru measurements ($tag): 131072/194560/209715, warm-up + 3 repetitions"
  "$PY" "$BENCH" "warm-$tag" --style ru --lengths 131072,194560,209715 --no-gen-case --warm-reps 1 --measure-reps 1 --out "$TMP/warm-$tag"
  "$PY" "$BENCH" "ru-$tag" --style ru --lengths 131072,194560,209715 --no-gen-case --out "$TMP/ru-$tag"
  say "RUMEASURE_${tag}_DONE"
}

# ---------- A) tests in the installed tree ----------
say "=== A: repeating the failed modules in the INSTALLED tree with the server stopped"
say "props before: $(propsver)"
cp -a "$D/Strata/strata-185-iq3_s.json" "$D/run/strata-185-iq3_s.json.before-tests" 2>/dev/null
stop_server
cd "$D/Strata" || exit 1
"$PY" -m unittest -v $MODS > "$D/run/tests-0.1.45-installed-tree.log" 2>&1
say "summary: $(grep -oE 'Ran [0-9]+ tests' $D/run/tests-0.1.45-installed-tree.log) | $(grep -oE 'FAILED.*|^OK' $D/run/tests-0.1.45-installed-tree.log | tail -1)"
grep -E "^(FAIL|ERROR): " "$D/run/tests-0.1.45-installed-tree.log" | head -20
say "restoring the server"
"$D/bin/start-strata-iq3_s.sh"
for i in $(seq 1 60); do c=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY"); [ "$c" = "200" ] && break; sleep 5; done
say "health: $c, props: $(propsver)"
if ! cmp -s "$D/Strata/strata-185-iq3_s.json" "$D/run/strata-185-iq3_s.json.before-tests"; then
  say "WARNING: the config differs after the tests - restoring the copy"
  cp -a "$D/run/strata-185-iq3_s.json.before-tests" "$D/Strata/strata-185-iq3_s.json"
fi

# ---------- B) the reverse order of the ru measurements ----------
say "=== B: reverse order: 0.1.44.1 first"
export STRATA_COMMIT=unknown-no-git-on-this-machine
"$D/bin/to-0144-for-bench.sh" || say "SWAP TO 0.1.44.1 FAILED"
export STRATA_BRANCH=v0.1.44.1
export STRATA_TREE_NOTE='release source tree v0.1.44.1 (no git metadata on this machine); the engine is built here from that tree with the same private CUDA 12.8 toolkit and private gcc-14 for sm_70'
ru_long 0144-first

say "--- restoring 0.1.45 and measuring the same set second"
"$D/bin/to-0145-back.sh" || say "RESTORE FAILED"
export STRATA_BRANCH=v0.1.45
export STRATA_TREE_NOTE='release source tree v0.1.45 (no git metadata on this machine); the engine is built here from that tree with a private CUDA 12.8 toolkit and private gcc-14 for sm_70 (engine-cuda12/BUILD.json says source=local)'
ru_long 0145-second
say "health: $(curl -s -m 5 http://127.0.0.1:8080/health)"
say "props: $(propsver)"
say "AB_DONE"
