#!/bin/bash
# Inside the measurement session: switch to the old version (0.1.44.1) by swapping the tree.
#   Strata (0.1.45) -> dl/hold-0145, Strata-0.1.44.1.bak -> Strata
# Checked after the start: health, build_info from /props, a short test query.
# The way back is bin/to-0145-back.sh.
set -u
D="$HOME/strata185"; PAT="strata185/Strata/(.venv/bin/python|engine-cuda12/)"
KEY="removed"; MODEL="qwen3.8-flash-next-iq3_s"
say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
[ -d "$D/Strata-0.1.44.1.bak" ] || { say "no $D/Strata-0.1.44.1.bak - touching nothing"; exit 1; }
[ -d "$D/dl/hold-0145" ] && { say "$D/dl/hold-0145 already exists - sort that out first"; exit 1; }

say "stopping the server (SIGINT)"
for p in $(pgrep -f "$PAT" 2>/dev/null); do kill -INT "$p" 2>/dev/null; done
rm -f "$D/run/server-iq3_s.pid"
born=$(date +%s)
while pgrep -f "$PAT" >/dev/null 2>&1; do
  if [ $(( $(date +%s) - born )) -gt 240 ]; then for p in $(pgrep -f "$PAT" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done; sleep 20; break; fi
  sleep 3
done
say "processes stopped, VRAM: $(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader | tr '\n' ' ')"
say "25 s pause to give the pages back (a new engine sizes its resident layer from the free memory at start)"
sleep 25

say "swapping the directories"
mv "$D/Strata" "$D/dl/hold-0145" && mv "$D/Strata-0.1.44.1.bak" "$D/Strata" || { say "FAILED to swap the directories"; exit 1; }
"$D/bin/start-strata-iq3_s.sh"

for i in $(seq 1 120); do
  c=$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health -H "Authorization: Bearer $KEY")
  [ "$c" = "200" ] && { say "health 200 after $((i*5)) s"; break; }
  sleep 5
done
curl -s -m 10 http://127.0.0.1:8080/props -H "Authorization: Bearer $KEY" | grep -o '"build_info":[^,]*' | sed 's/^/props: /'
out=$(curl -s -m 180 http://127.0.0.1:8080/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
      # the query sent: "Сколько будет 17*23? Ответь только число." = "What is 17*23? Answer with the number only."
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Сколько будет 17*23? Ответь только число.\"}],\"max_tokens\":64,\"temperature\":0,\"reasoning_effort\":\"none\"}")
echo "$out" | head -c 300; echo
if echo "$out" | grep -q "391"; then say "SWITCH_TO_0144_DONE"; exit 0; else say "the test query did not pass"; exit 1; fi
