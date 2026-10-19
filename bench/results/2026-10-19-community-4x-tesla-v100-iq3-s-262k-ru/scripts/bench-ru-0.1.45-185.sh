#!/bin/bash
# Second part of the 0.1.45 vs 0.1.44.1 session on 4x V100: the ru style (the first ru pass failed with HTTP 400
# at the 273000 limit - a ru-text prompt comes out ~2% longer than the target, so prompt+256 output tokens
# did not fit the window; runs.json was not written when it failed).
# Same scheme here, but the limit length for ru is chosen to fit the window: 268000
# (the engine trims it to ~260k - the same window boundary as in the code run).
#   0.1.45: warm-up -> ru measurement (+needles) -> control on the same binary
#   swap to 0.1.44.1: warm-up -> ru measurement (+needles)
#   back to 0.1.45
set -u
D=$HOME/strata185
PY=$D/Strata/.venv/bin/python
BENCH=$D/bin/strata-bench-community.py
KEY="removed"
DAY=2026-10-19
OUTR=$D/bench-community/$DAY-community-4x-tesla-v100-iq3-s-262k-ru
TMP=$D/bench-community/tmp-$DAY
LEN=4096,16384,32768,66560,131072,194560,209715,249037,268000
NEEDLE=32768,131072
mkdir -p "$TMP" "$OUTR"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
export STRATA_COMMIT=unknown-no-git-on-this-machine
export STRATA_BRANCH=v0.1.45
export STRATA_TREE_NOTE='release source tree v0.1.45 (no git metadata on this machine); the engine is built here from that tree with a private CUDA 12.8 toolkit and a private gcc-14 for sm_70 (engine-cuda12/BUILD.json says source=local)'

( while :; do echo "$(date +%s),$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr '\n' ',' | sed 's/,$//'),$(free -k | awk 'NR==2{print $3}')"; sleep 2; done ) > "$TMP/mem-sample-ru.csv" 2>/dev/null &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT
propsver() { curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }

say "props: $(propsver)"
say "lengths (ru): $LEN"

say "--- [0145] ru warm-up with a full run"
"$PY" "$BENCH" warm-ru-0145 --style ru --lengths "$LEN" --no-gen-case --out "$TMP/warm-ru-0145"
say "WARMUP_RU_0145_DONE"

say "--- [0145] ru measurement (+ needles 32K/131K)"
"$PY" "$BENCH" "$DAY-v100-0145-ru" --style ru --lengths "$LEN" --needle "$NEEDLE" --out "$OUTR"
say "MEASURE_RU_0145_DONE"

say "--- [0145] ru control: the same binary, the same config"
"$PY" "$BENCH" ctrl-ru-0145 --style ru --lengths "$LEN" --out "$TMP/ctrl-ru-0145"
cp "$TMP/ctrl-ru-0145/runs.json" "$OUTR/runs-0.1.45-control.json"
say "CONTROL_RU_0145_DONE"

say "--- swapping the tree to 0.1.44.1"
"$D/bin/to-0144-for-bench.sh" || say "SWAP TO 0.1.44.1 FAILED"
export STRATA_BRANCH=v0.1.44.1
export STRATA_TREE_NOTE='release source tree v0.1.44.1 (no git metadata on this machine); the engine is built here from that tree with the same private CUDA 12.8 toolkit and private gcc-14 for sm_70'
say "props after the swap: $(propsver)"

say "--- [0144] ru warm-up with a full run"
"$PY" "$BENCH" warm-ru-0144 --style ru --lengths "$LEN" --no-gen-case --out "$TMP/warm-ru-0144"
say "WARMUP_RU_0144_DONE"

say "--- [0144] ru measurement (+ needles)"
"$PY" "$BENCH" "$DAY-v100-0144-ru" --style ru --lengths "$LEN" --needle "$NEEDLE" --out "$TMP/0144-ru"
cp "$TMP/0144-ru/runs.json" "$OUTR/runs-0.1.44.1-baseline.json"
cp "$TMP/0144-ru/needles.json" "$OUTR/needles-0.1.44.1.json" 2>/dev/null
say "MEASURE_RU_0144_DONE"

say "--- restoring 0.1.45"
"$D/bin/to-0145-back.sh" || say "RESTORE FAILED"
say "props after the restore: $(propsver)"
say "md5: $(md5sum $D/Strata/engine-cuda12/strata | cut -c1-32)"

kill $SAMPLER 2>/dev/null
awk -F, 'NR>1{for(i=2;i<=6;i++) if($i>m[i]) m[i]=$i} END{printf "peak from the 2 s samples: CUDA0 %d CUDA1 %d CUDA2 %d CUDA3 %d MiB, RAM %d KiB\n", m[2],m[3],m[4],m[5],m[6]}' "$TMP/mem-sample-ru.csv"
say "RU_SESSION_DONE"
