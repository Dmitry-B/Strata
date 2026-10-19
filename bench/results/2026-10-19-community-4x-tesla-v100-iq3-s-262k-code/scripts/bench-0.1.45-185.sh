#!/bin/bash
# Full measurement cycle 0.1.45 vs 0.1.44.1 on the dgbox-ai-server (4x Tesla V100 SXM2, IQ3_S, 262144 window).
#
# Protocol (skills/strata-update: references/checklist.md, references/measuring.md):
#   one session, one set of lengths, both prompt styles, 3 repetitions per length, a warm-up full run,
#   a control run on the same binary (the noise band), the previous version in the same session (tree swap),
#   needle recall at 32K/128K and at the window limit, RAM/VRAM peak sampled every 2 s.
#
# Lengths: the same as in the 2026-10-14 report for this machine (so the numbers are comparable with it),
# plus 249037 = 0.95 of the window (the rule "up to the context-window limit"). 273000 is a target above the window:
# the engine trims it to the limit itself (2026-10-14 gave 260331 tokens).
#
# Run: setsid nohup ~/strata185/bin/bench-0.1.45-185.sh >> ~/strata185/run/bench-0.1.45-<date>.log 2>&1 &
# Stages run one after another; each prints a "<STAGE>_DONE" marker. A failure in one stage does not cancel the rest.
set -u
D=$HOME/strata185
PY=$D/Strata/.venv/bin/python
BENCH=$D/bin/strata-bench-community.py
KEY="removed"
DAY=$(date +%Y-%m-%d)
OUTC=$D/bench-community/$DAY-community-4x-tesla-v100-iq3-s-262k-code
OUTR=$D/bench-community/$DAY-community-4x-tesla-v100-iq3-s-262k-ru
TMP=$D/bench-community/tmp-$DAY
LEN=4096,16384,32768,66560,131072,194560,209715,249037,273000
NEEDLE=32768,131072
NEEDLE_LONG=250000
mkdir -p "$TMP" "$OUTC" "$OUTR"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

export STRATA_COMMIT=unknown-no-git-on-this-machine
export STRATA_BRANCH=v0.1.45
export STRATA_TREE_NOTE='release source tree v0.1.45 (no git metadata on this machine); the engine is built here from that tree with a private CUDA 12.8 toolkit and a private gcc-14 for sm_70 (engine-cuda12/BUILD.json says source=local)'

# memory sampling for the whole session
( while :; do echo "$(date +%s),$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr '\n' ',' | sed 's/,$//'),$(free -k | awk 'NR==2{print $3}')"; sleep 2; done ) \
  > "$TMP/mem-sample.csv" 2>/dev/null &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT

health() { curl -s -m 5 http://127.0.0.1:8080/health; }
propsver() { curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*'; }

say "health: $(health)"
say "props: $(propsver)"
say "engine: $($D/Strata/engine-cuda12/strata --version 2>/dev/null)"
say "md5: $(md5sum $D/Strata/engine-cuda12/strata | cut -c1-32)"
say "prompt chunk (last start): $(grep -oE 'prompt chunk auto: [0-9]+ tokens' $D/Strata/strata-185-iq3_s.log | tail -1)"
say "VRAM before: $(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader | tr '\n' ' ')"
say "lengths: $LEN"

# ---------- stage 1: 0.1.45 ----------
say "--- [0145] warm-up with a full run (not part of the results)"
"$PY" "$BENCH" warm-0145 --style code --lengths "$LEN" --out "$TMP/warm-0145"
say "WARMUP_0145_DONE"

say "--- [0145] measurement code (+ needles 32K/128K)"
"$PY" "$BENCH" "$DAY-v100-0145-code" --style code --lengths "$LEN" --needle "$NEEDLE" --out "$OUTC"
say "MEASURE_0145_CODE_DONE"

say "--- [0145] needles at the window limit (code)"
python3 "$D/Strata/tools/needle_bench.py" --url http://127.0.0.1:8080 --api-key "$KEY" \
  --lengths "$NEEDLE_LONG" --depths 10,50,90 --out "$OUTC/needles-long.json"
say "NEEDLES_0145_LONG_CODE_DONE"

say "--- [0145] measurement ru (+ needles 32K/128K)"
"$PY" "$BENCH" "$DAY-v100-0145-ru" --style ru --lengths "$LEN" --needle "$NEEDLE" --out "$OUTR"
say "MEASURE_0145_RU_DONE"

say "--- [0145] needles at the window limit (ru: same needle setup, needle_bench uses its own prompt style)"
python3 "$D/Strata/tools/needle_bench.py" --url http://127.0.0.1:8080 --api-key "$KEY" \
  --lengths "$NEEDLE_LONG" --depths 10,50,90 --out "$OUTR/needles-long.json"
say "NEEDLES_0145_LONG_RU_DONE"

say "--- [0145] control: the same binary, the same config, code"
"$PY" "$BENCH" ctrl-0145-code --style code --lengths "$LEN" --out "$TMP/ctrl-0145-code"
cp "$TMP/ctrl-0145-code/runs.json" "$OUTC/runs-0.1.45-control.json"
say "CONTROL_0145_CODE_DONE"

say "--- [0145] control: the same binary, the same config, ru"
"$PY" "$BENCH" ctrl-0145-ru --style ru --lengths "$LEN" --out "$TMP/ctrl-0145-ru"
cp "$TMP/ctrl-0145-ru/runs.json" "$OUTR/runs-0.1.45-control.json"
say "CONTROL_0145_RU_DONE"

# ---------- stage 2: swap the tree to 0.1.44.1 and run the same protocol ----------
say "--- swapping the tree to 0.1.44.1"
"$D/bin/to-0144-for-bench.sh" || { say "SWAP TO 0.1.44.1 FAILED - skipping the comparison"; }
say "props after the swap: $(propsver)"
say "prompt chunk 0.1.44.1: $(grep -oE 'prompt chunk auto: [0-9]+ tokens' $D/Strata/strata-185-iq3_s.log | tail -1)"

say "--- [0144] warm-up with a full run"
"$PY" "$BENCH" warm-0144 --style code --lengths "$LEN" --out "$TMP/warm-0144"
say "WARMUP_0144_DONE"

say "--- [0144] measurement code (+ needles)"
"$PY" "$BENCH" "$DAY-v100-0144-code" --style code --lengths "$LEN" --needle "$NEEDLE" --out "$TMP/0144-code"
cp "$TMP/0144-code/runs.json" "$OUTC/runs-0.1.44.1-baseline.json"
cp "$TMP/0144-code/needles.json" "$OUTC/needles-0.1.44.1.json" 2>/dev/null
say "MEASURE_0144_CODE_DONE"

say "--- [0144] needles at the window limit"
python3 "$D/Strata/tools/needle_bench.py" --url http://127.0.0.1:8080 --api-key "$KEY" \
  --lengths "$NEEDLE_LONG" --depths 10,50,90 --out "$OUTC/needles-long-0.1.44.1.json"
say "NEEDLES_0144_LONG_DONE"

say "--- [0144] measurement ru"
"$PY" "$BENCH" "$DAY-v100-0144-ru" --style ru --lengths "$LEN" --needle "$NEEDLE" --out "$TMP/0144-ru"
cp "$TMP/0144-ru/runs.json" "$OUTR/runs-0.1.44.1-baseline.json"
cp "$TMP/0144-ru/needles.json" "$OUTR/needles-0.1.44.1.json" 2>/dev/null
say "MEASURE_0144_RU_DONE"

# ---------- stage 3: back to 0.1.45 ----------
say "--- restoring the 0.1.45 tree"
"$D/bin/to-0145-back.sh" || say "RESTORE FAILED - check by hand"
say "props after the restore: $(propsver)"
say "md5 after the restore: $(md5sum $D/Strata/engine-cuda12/strata | cut -c1-32)"
say "health after the restore: $(health)"

kill $SAMPLER 2>/dev/null
say "memory: peak from the 2 s samples (MiB GPU,GPU,GPU,GPU,RAM):"
awk -F, 'NR>1{for(i=2;i<=6;i++) if($i>m[i]) m[i]=$i} END{printf "  CUDA0 %d  CUDA1 %d  CUDA2 %d  CUDA3 %d  RAM %d KiB\n", m[2],m[3],m[4],m[5],m[6]}' "$TMP/mem-sample.csv"
say "SESSION_DONE"
