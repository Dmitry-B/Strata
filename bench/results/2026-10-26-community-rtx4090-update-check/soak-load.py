#!/usr/bin/env python3
"""Soak: a long continuous load against a running Strata server.

Requests the profile of docs/TEST_REQUESTS.md: 60+ minutes of continuous traffic on a resident configuration,

Several streams, short questions plus cold 4K/16K/45K prompts; 131K/185K/196K are an extension of the
same profile. It records TTFT and speed drift over time, RAM/VRAM peaks, GPU temperature and engine restarts.

  python3 soak-load.py --url http://127.0.0.1:8080 --minutes 75 --out soak.jsonl

One JSON line per request, then a summary. The server is not restarted: the soak loads the running server.
"""
import argparse, json, os, statistics, subprocess, sys, threading, time, urllib.request

URL = "http://127.0.0.1:8080/v1/chat/completions"
FILLER = ("An article about the history of lighthouses and how Fresnel lenses worked. " * 400)

def profile(k):
    """(prompt text for a given length label)."""
    if k == "short":
        return "? ? 17*8? ? ? ?."
    n = int(k.rstrip("k")) * 1000
    # calibrated against this model's tokenizer: 3.705 characters per token (measured with vocab.json)
    body = (FILLER * (n // 1700 + 1))[: int(n * 3.705)]
    return body + "\n\nShortly: how many paragraphs about lighthouses are in the text? Answer with one number."

def gpu():
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu,memory.used,utilization.gpu",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10).stdout
        t, m, u = [x.strip() for x in out.split(",")]
        return int(t), int(m), int(u)
    except Exception:
        return None, None, None

def mem():
    try:
        s = open("/proc/meminfo").read()
        kv = dict((l.split(":")[0], int(l.split()[1])) for l in s.splitlines() if ":" in l)
        return kv["MemAvailable"] // 1024
    except Exception:
        return None

def one(url, key, prompt, max_tokens, out):
    body = json.dumps({"model": "strata", "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": max_tokens, "temperature": 0.0, "stream": True}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json",
                                                         "Authorization": "Bearer " + key})
    t0 = time.time(); first = None; n = 0
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            for raw in r:
                if not raw.startswith(b"data:"):
                    continue
                s = raw[5:].strip()
                if s == b"[DONE]":
                    break
                try:
                    dl = json.loads(s)["choices"][0]["delta"]
                    # thinking-? ? ? ? reasoning_content, ? ? ? content
                    d = (dl.get("content") or "") + (dl.get("reasoning_content") or "")
                except Exception:
                    continue
                if d:
                    if first is None:
                        first = time.time() - t0
                    n += 1
        out.append(dict(t0=t0 - START, wall=time.time() - t0, ttft=first, toks=n,
                        temp=mem(), gpu=gpu()))
    except Exception as e:
        out.append(dict(t0=t0 - START, wall=time.time() - t0, ttft=first, toks=n, error=str(e)[:200],
                        temp=mem(), gpu=gpu()))

ap = argparse.ArgumentParser()
ap.add_argument("--minutes", type=float, default=75)
ap.add_argument("--url", default="http://127.0.0.1:8080")
ap.add_argument("--out", required=True)
ap.add_argument("--streams", type=int, default=3)
ap.add_argument("--key", default="", help="the server's API key (or set STRATA_KEY)")
ap.add_argument("--engine-log", default="", help="engine log, to count restarts during the run")
args = ap.parse_args()

# the key is passed in, never read from a config file, so this script cannot publish one by accident
KEY = args.key or os.environ.get("STRATA_KEY", "")

# profile: short questions and cold prompts; lengths above 64K are our extension
SHORTS = ["short", "short", "short"]
COLD = ["4k", "16k", "45k", "4k", "16k", "45k", "131k", "185k", "196k"]
QUEUE = []
for i in range(200):
    QUEUE.append(COLD[i % len(COLD)])
    if i % 3 == 0:
        QUEUE.append("short")

START = time.time()
deadline = args.minutes * 60
results = []
lock = threading.Lock()
stop = time.time() + deadline

def worker(idx):
    while time.time() < stop:
        with lock:
            if not QUEUE:
                return
            kind = QUEUE.pop(0)
        prompt = profile(kind)
        if kind == "short":
            mt = 64
        else:
            mt = 96
        buf = []
        one(args.url + "/v1/chat/completions", KEY, prompt, mt, buf)
        rec = buf[0]; rec["kind"] = kind
        results.append(rec)
        with open(args.out, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(args.streams)]
for t in threads:
    t.start()
while time.time() < stop + 1200 and any(t.is_alive() for t in threads):
    time.sleep(10)
    print(f"   ... {time.time() - START:.0f} ?, ? {len(results)}", flush=True)

# did the engine restart during the run?
try:
    log = open(args.engine_log or "/dev/null", errors="replace").read()
    restarts = log.count("engine started:")
except Exception:
    restarts = None if not args.engine_log else "log unreadable"

buckets = {}
for r in results:
    if r.get("error") or not r.get("ttft"):
        continue
    buckets.setdefault(r["kind"], []).append(r)

print(f"soak {args.minutes:.0f} ?, {args.streams} ?: ? {len(results)}")
print(f"{'?':8} {'n':>4} {'TTFT p50':>9} {'TTFT max':>9} {'tok/s p50':>10}")
for k in sorted(buckets):
    b = buckets[k]
    tt = sorted(x["ttft"] for x in b)
    sp = [x["toks"] / x["wall"] for x in b if x["wall"] > 0]
    print(f"{k:8} {len(b):4} {statistics.median(tt):9.2f} {max(tt):9.1f} "
          f"{statistics.median(sp) if sp else 0:10.1f}")
errs = [r for r in results if r.get("error")]
print(f"?/?: {len(errs)}")
if errs:
    for e in errs[:5]:
        print("   ", e["kind"], e["error"])
temps = [r["gpu"][0] for r in results if r.get("gpu") and r["gpu"][0]]
vram = [r["gpu"][1] for r in results if r.get("gpu") and r["gpu"][1]]
ram = [r["temp"] for r in results if r.get("temp")]
print(f"GPU ?: max {max(temps) if temps else '?'} C, ? VRAM {max(vram) if vram else '?'} MiB, "
      f"?. ? RAM {min(ram) if ram else '?'} MiB")
print(f"? 'engine started' ? ? ?: {restarts}")

# drift: the first and the last third of the short and 16K requests
for k in ("short", "16k"):
    b = [r for r in buckets.get(k, []) if r.get("ttft")]
    if len(b) >= 4:
        third = len(b) // 3
        head = statistics.median(x["ttft"] for x in b[:third])
        tail = statistics.median(x["ttft"] for x in b[-third:])
        print(f"? TTFT {k}: ? {third} — {head:.2f} ?, ? {third} — {tail:.2f} ?")
print("SOAK_DONE")
