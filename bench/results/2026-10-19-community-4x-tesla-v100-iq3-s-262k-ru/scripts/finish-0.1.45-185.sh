#!/bin/bash
# Third part of the 0.1.45 cycle on 4x V100: looking into one suspicious case + the unit tests.
#
# 1) The suspicious case: in the 0.1.45 runs at 237K/260K tokens the TTFT is sometimes 14-24 s longer
#    than the prompt-read time the engine itself reports (it reads in the same 96.6/106.6 s), while
#    0.1.44.1 showed nothing like it in any of its nine runs. The protocol repeats such a case with
#    separate runs on both versions: here 6 repetitions per version at 249037 and 273000 (code).
# 2) Unit tests of 0.1.45: the whole tools/test_*.py and serve/test_*.py set (except serve.test_winjob -
#    Windows, and serve.test_lifecycle - a live engine and VRAM), in a CLEAN copy of the v0.1.45 tree
#    (~/strata185/dl/test-0145): there is no git on this machine, so the unpacked release is the clean tree.
#    The first pass runs with the production server up (port 8080 busy), then every failed module is
#    repeated with the server stopped - that separates machine state from the code.
#
# Run: setsid nohup ~/strata185/bin/finish-0.1.45-185.sh >> ~/strata185/run/finish-0.1.45-<date>.log 2>&1 &
set -u
D=$HOME/strata185
PY=$D/Strata/.venv/bin/python
BENCH=$D/bin/strata-bench-community.py
KEY="removed"
DAY=2026-10-19
TMP=$D/bench-community/tmp-$DAY
TESTDIR=$D/dl/test-0145
PAT="strata185/Strata/(.venv/bin/python|engine-cuda12/)"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
propsver(){ curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }

export STRATA_COMMIT=unknown-no-git-on-this-machine
export STRATA_BRANCH=v0.1.45
export STRATA_TREE_NOTE='release source tree v0.1.45 (no git metadata on this machine); the engine is built here from that tree with a private CUDA 12.8 toolkit and a private gcc-14 for sm_70 (engine-cuda12/BUILD.json says source=local)'

tail_probe(){
  local tag=$1
  say "--- tail probe ($tag): 249037 and 273000, 3+3 repetitions, code"
  "$PY" "$BENCH" "tail-$tag-a" --style code --lengths 249037,273000 --no-gen-case --out "$TMP/tail-$tag-a"
  "$PY" "$BENCH" "tail-$tag-b" --style code --lengths 249037,273000 --no-gen-case --out "$TMP/tail-$tag-b"
  say "TAIL_PROBE_${tag}_DONE"
}

say "props: $(propsver)"
tail_probe 0145-first

say "--- swapping the tree to 0.1.44.1"
"$D/bin/to-0144-for-bench.sh" || say "SWAP TO 0.1.44.1 FAILED"
export STRATA_BRANCH=v0.1.44.1
export STRATA_TREE_NOTE='release source tree v0.1.44.1 (no git metadata on this machine); the engine is built here from that tree with the same private CUDA 12.8 toolkit and private gcc-14 for sm_70'
say "props after the swap: $(propsver)"
tail_probe 0144

say "--- restoring 0.1.45"
"$D/bin/to-0145-back.sh" || say "RESTORE FAILED"
export STRATA_BRANCH=v0.1.45
export STRATA_TREE_NOTE='release source tree v0.1.45 (no git metadata on this machine); the engine is built here from that tree with a private CUDA 12.8 toolkit and private gcc-14 for sm_70 (engine-cuda12/BUILD.json says source=local)'
say "props after the restore: $(propsver)"

# ---------- unit tests in the clean release tree ----------
say "--- preparing a clean test tree: $TESTDIR (a fresh unpacking of v0.1.45)"
rm -rf "$TESTDIR"
mkdir -p "$TESTDIR"
tar xzf "$D/dl/strata-0.1.45.tar.gz" -C "$TESTDIR" --strip-components=1 || say "could not unpack"
mkdir -p "$TESTDIR/third_party"
ln -sfn "$D/Strata/third_party/llama.cpp" "$TESTDIR/third_party/llama.cpp"
say "tests per module (countTestCases):"
cd "$TESTDIR" || exit 1
mods=$(ls tools/test_*.py serve/test_*.py 2>/dev/null | sed 's/\.py$//; s/\//./' | grep -vE "serve\.test_winjob|serve\.test_lifecycle" | sort)
echo "$mods" | wc -l | sed 's/^/modules: /'
: > test-counts.csv
echo "module,test_cases" >> test-counts.csv
for m in $mods; do
  n=$("$PY" -c "import unittest,importlib;print(unittest.defaultTestLoader.loadTestsFromName('$m').countTestCases())" 2>/dev/null || echo error)
  echo "$m,$n" >> test-counts.csv
done
cat test-counts.csv | tail -5
say "TOTAL tests: $(awk -F, 'NR>1 && $2 ~ /^[0-9]+$/{s+=$2} END{print s+0}' test-counts.csv)"

say "--- running tools.* (with the production server up)"
"$PY" -m unittest -v $(echo "$mods" | grep '^tools\.') > "$D/run/tests-0.1.45-tools.log" 2>&1
say "tools: $(grep -cE '^(FAILED|ERROR)' $D/run/tests-0.1.45-tools.log) failure summary lines; $(grep -oE 'Ran [0-9]+ tests' $D/run/tests-0.1.45-tools.log)"
say "--- running serve.* (with the server up)"
"$PY" -m unittest -v $(echo "$mods" | grep '^serve\.') > "$D/run/tests-0.1.45-serve.log" 2>&1
say "serve: $(grep -cE '^(FAILED|ERROR)' $D/run/tests-0.1.45-serve.log) failure summary lines; $(grep -oE 'Ran [0-9]+ tests' $D/run/tests-0.1.45-serve.log)"
cat "$D/run/tests-0.1.45-tools.log" "$D/run/tests-0.1.45-serve.log" > "$D/run/tests-0.1.45-raw.log"
say "the failed modules:"
grep -oE "^(FAILED|ERROR) \([^)]*\)|^(FAILED|ERROR): [A-Za-z0-9_.]+" "$D/run/tests-0.1.45-raw.log" | head -40
failed_mods=$(grep -oE "^(FAIL|ERROR): [A-Za-z0-9_.]+" "$D/run/tests-0.1.45-raw.log" | sed 's/^(FAIL|ERROR): //' | awk -F. '{print $1"."$2}' | sort -u | head -8)
say "repeating the failed modules with the production server STOPPED: $failed_mods"
if [ -n "$failed_mods" ]; then
  for p in $(pgrep -f "$PAT" 2>/dev/null); do kill -INT "$p" 2>/dev/null; done
  rm -f "$D/run/server-iq3_s.pid"
  born=$(date +%s)
  while pgrep -f "$PAT" >/dev/null 2>&1 && [ $(( $(date +%s) - born )) -lt 240 ]; do sleep 3; done
  say "the server is stopped ($(nvidia-smi --query-gpu=memory.used --format=csv,noheader | tr '\n' ' '))"
  cd "$TESTDIR" || exit 1
  "$PY" -m unittest -v $failed_mods > "$D/run/tests-0.1.45-failed-without-server.log" 2>&1
  say "repeated without the server: $(grep -oE 'Ran [0-9]+ tests' $D/run/tests-0.1.45-failed-without-server.log) | $(grep -oE 'FAILED.*|OK' $D/run/tests-0.1.45-failed-without-server.log | tail -1)"
  say "restoring the server"
  "$D/bin/start-strata-iq3_s.sh"
  for i in $(seq 1 60); do c=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY"); [ "$c" = "200" ] && break; sleep 5; done
fi
say "health: $(curl -s -m 5 http://127.0.0.1:8080/health)"
say "props: $(propsver)"
say "FINISH_DONE"
