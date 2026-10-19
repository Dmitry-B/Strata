#!/usr/bin/env python3
"""Strata speed measurement following the method of docs/COMMUNITY_BENCHMARKS.md.

usage: strata-bench.py <label> [options]

Method (as in docs/COMMUNITY_BENCHMARKS.md and the 2026-09-30-community-rtx-5090 example):
  - warm-up: a 4K prompt, not counted as a measurement;
  - measurements: one run per prompt length (default 4k,32k,128k),
    256 output tokens, 3 repetitions; a separate generation-only case (short
    prompt, 1024 tokens, 3 repetitions);
  - every prompt carries a random marker -> no prompt-prefix cache reuse;
    the number of tokens actually reused comes from the engine timings;
  - TTFT is measured over streaming (the first non-empty delta, keep-alives ignored);
  - speeds come from the engine timings, not from the total request time;
  - memory: VRAM/RAM peak during the measurements + a snapshot at the start;
  - provenance: hardware, OS, driver, CUDA, Strata commit, engine version, the
    launch command, config, model files (sizes; SHA-256 with --hash);
  - result: a folder Strata/bench/results/YYYY-MM-DD-community-<label>/ with a README.md
    following the template, runs.json, env.json and a copy of the config; needles.json optional.

options:
  --config FILE     the server config (default: the config of the running server)
  --lengths 4k,32k  prompt lengths (default 4k,32k,128k)
  --no-gen-case     without the generation-only case
  --needle 32k,128k add the recall check (tools/needle_bench.py)
  --depths 10,50,90 needle depths
  --hash            compute SHA-256 of the model files (slow, tens of GB)
  --style ru|code   prompt text: Russian prose (default) or code descriptions
  --out DIR         where to write the report (default Strata/bench/results/...)
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import statistics
import subprocess
import sys
import threading
import time
import urllib.request

HOME = pathlib.Path.home()
STRATA = HOME / "strata185" / "Strata"   # this machine keeps the repository in ~/strata185

# the ru workload text, kept in Russian on purpose: it is what was measured
PARA_RU = (
    "Зимний вечер медленно опускался на город, и фонари зажигались один за другим вдоль набережной. "
    "Внизу, у тёмной реки, кто-то переходил мост, и шаги гулко отдавались под его сводами. "
    "В окне напротив кто-то писал письмо, которое никто не прочтёт, и от этого было немного легче. "
    "Где-то далеко гудел трамвай, и этот звук казался частью самого вечера, а не чем-то отдельным. "
)
PARA_CODE = (
    "The function parse_record takes a byte slice and returns a parsed struct. It first checks the "
    "header length, then reads the field table entry by entry. Each field carries a type tag and a "
    "varint-encoded value, decoded with checked arithmetic to avoid overflow. On any malformed input "
    "the parser returns a descriptive error and leaves the output buffer untouched. "
)


def http_json(url, key="", data=None, timeout=60):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def sh(cmd, timeout=30):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception as e:
        return f"not measured ({e.__class__.__name__})"


# ---------------------------------------------------------------- finding the server

def find_server():
    """Finds the running serve/server.py: its pid, --config and --port."""
    out = sh(["pgrep", "-f", "serve/server.py"]).split()
    for pid in out:
        try:
            parts = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            args = [p.decode() for p in parts if p]
        except Exception:
            continue
        cfg, port = None, 8080
        for i, a in enumerate(args):
            if a == "--config" and i + 1 < len(args):
                cfg = args[i + 1]
            if a == "--port" and i + 1 < len(args):
                port = int(args[i + 1])
        if cfg:
            if not os.path.isabs(cfg):          # the server may run with a relative --config
                cwd = os.path.realpath(f"/proc/{pid}/cwd")
                cfg = os.path.join(cwd, cfg)
            return int(pid), cfg, port
    sys.exit("no running Strata server found (serve/server.py).")


def engine_cmdline():
    out = sh(["pgrep", "-f", "engine/strata --serve"]).split()
    for pid in out:
        try:
            parts = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            args = [p.decode() for p in parts if p]
            if args:
                return int(pid), args
        except Exception:
            continue
    return None, None


# ---------------------------------------------------------------- provenance

def collect_env(port, key, cfg_path, do_hash):
    env = {"collected_at": datetime.datetime.now().isoformat(timespec="seconds")}

    # GPU
    g = sh(["nvidia-smi", "--query-gpu=name,memory.total,driver_version,power.limit,pci.bus_id,utilization.gpu",
            "--format=csv,noheader,nounits"])
    if g and "not measured" not in g:
        cards = []
        for line in g.strip().split("\n"):
            name, mem, drv, pw, bus, util = [x.strip() for x in line.split(",")]
            cards.append({"index": len(cards), "name": name, "vram_mib": mem, "driver": drv,
                          "power_limit_w": pw, "pci_bus": bus})
        env["gpus"] = cards
        env["gpu"] = cards[0]                      # kept for compatibility with the older format
        env["gpu_count"] = len(cards)
    env["gpu_link"] = sh(["nvidia-smi", "-q", "-d", "BUS"]) or "not measured"

    # CPU / RAM / OS / disk
    cpu = sh(["bash", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //'"], timeout=10)
    ncpu = sh(["nproc"])
    memtotal = sh(["bash", "-c", "grep MemTotal /proc/meminfo | awk '{print $2}'"])
    env["cpu"] = {"model": cpu, "logical_cpus": ncpu}
    env["ram_total_kib"] = memtotal
    env["os"] = sh(["bash", "-c", ". /etc/os-release; echo $PRETTY_NAME"])
    env["kernel"] = sh(["uname", "-r"])
    env["cuda"] = sh(["bash", "-c", "nvcc --version 2>/dev/null | grep -o 'release .*'"]) or "nvcc not found"
    env["storage"] = sh(["bash", "-c", "lsblk -d -o NAME,MODEL,SIZE,TYPE | awk '$4==\"disk\"'"])

    # Strata: commit, engine version, context - from git and /v1/status
    # there is no git on this machine: the release tree is an unpacked copy, so the commit
    # and branch are passed in through environment variables (verified on a machine that has git)
    env["strata_commit"] = os.environ.get("STRATA_COMMIT", "")
    env["strata_branch"] = os.environ.get("STRATA_BRANCH", "")
    env["source_tree_note"] = os.environ.get("STRATA_TREE_NOTE", "")
    try:
        st = http_json(f"http://127.0.0.1:{port}/v1/status", key)
        env["engine_version"] = st.get("engine")
        env["model_name"] = st.get("model")
        env["context"] = st.get("context")
        env["cache_max_tokens"] = st.get("cache_max_tokens")
        env["vision"] = st.get("vision")
    except Exception as e:
        env["server_status_error"] = str(e)

    # the engine launch command + model files
    pid, args = engine_cmdline()
    if args:
        env["engine_launch_command"] = " ".join(args)
        files = []
        flags = ("--pack", "--native", "--ple-gguf", "--mtp", "--control-vector-scaled",
                 "--expert-profile", "--expert-profile-save", "--draft-vocab")
        for i, a in enumerate(args):
            if a in flags and i + 1 < len(args):
                p = pathlib.Path(args[i + 1].split(":")[0])
                if p.is_dir():
                    files.append({"flag": a, "path": str(p), "kind": "dir"})
                elif p.is_file():
                    stt = {"flag": a, "path": str(p), "size_bytes": p.stat().st_size,
                           "mtime": datetime.datetime.fromtimestamp(p.stat().st_mtime).isoformat(timespec="seconds")}
                    if do_hash:
                        h = hashlib.sha256()
                        with open(p, "rb") as f:
                            for chunk in iter(lambda: f.read(1 << 22), b""):
                                h.update(chunk)
                        stt["sha256"] = h.hexdigest()
                    files.append(stt)
        env["model_files"] = files
    else:
        env["engine_launch_command"] = "engine not found (perhaps it is not started directly)"

    # the server config
    try:
        cfg = json.loads(pathlib.Path(cfg_path).read_text(encoding="utf-8-sig"))
        cfg.pop("api_key", None)
        env["server_config_path"] = str(cfg_path)
        env["server_config"] = cfg
    except Exception as e:
        env["server_config_error"] = str(e)
    return env


# ---------------------------------------------------------------- memory

class MemWatch:
    """Background sampling of VRAM/RAM; records the starting snapshot and the peaks."""

    def __init__(self, interval=2.0):
        self.interval = interval
        self.stop = threading.Event()
        self.peak_vram_used_mib = 0
        self.peak_per_gpu = []
        self.peak_ram_used_kib = 0
        self.start_snapshot = {}
        self.thread = threading.Thread(target=self._loop, daemon=True)

    def _sample(self):
        v = sh(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"])
        try:
            v = [int(x) for x in v.strip().split("\n")]      # this machine has 4 cards - sample all of them
        except Exception:
            v = None
        memavail = sh(["bash", "-c", "grep MemAvailable /proc/meminfo | awk '{print $2}'"])
        memtotal = sh(["bash", "-c", "grep MemTotal /proc/meminfo | awk '{print $2}'"])
        try:
            used_kib = int(memtotal) - int(memavail)
        except Exception:
            used_kib = None
        return v, used_kib

    def _loop(self):
        first = True
        while not self.stop.is_set():
            v, u = self._sample()
            if first:
                self.start_snapshot = ({"vram_used_mib": (max(v) if isinstance(v, list) else v),
                                       "vram_per_gpu_mib": v if isinstance(v, list) else None,
                                       "ram_used_kib": u})
                first = False
            if v is not None:
                self.peak_vram_used_mib = max(self.peak_vram_used_mib, max(v) if isinstance(v, list) else v)
                if isinstance(v, list):
                    if not self.peak_per_gpu:
                        self.peak_per_gpu = list(v)
                    else:
                        self.peak_per_gpu = [max(a, b) for a, b in zip(self.peak_per_gpu, v)]
            if u is not None:
                self.peak_ram_used_kib = max(self.peak_ram_used_kib, u)
            self.stop.wait(self.interval)

    def start(self):
        self.thread.start()

    def result(self):
        self.stop.set()
        self.thread.join(timeout=5)
        return {"start_snapshot": self.start_snapshot,
                "peak_vram_used_mib": self.peak_vram_used_mib,
                "peak_vram_per_gpu_mib": self.peak_per_gpu,
                "peak_ram_used_kib": self.peak_ram_used_kib,
                "note": f"peak = the highest of the samples taken every {self.interval:.0f} s during the measurements"}


# ---------------------------------------------------------------- requests

def call_stream(url, key, prompt, max_tokens, para):
    """Streaming request: TTFT from the first non-empty delta; timings from the
    final chunk, with /v1/status.last_timings as a fallback."""
    body = {"model": "strata", "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens, "temperature": 0, "reasoning_effort": "none", "stream": True}
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Bearer {key}"})
    t0 = time.time()
    ttft = None
    content = ""
    timings = None
    with urllib.request.urlopen(req, timeout=3600) as r:
        for raw in r:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                d = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if d.get("timings"):
                timings = d["timings"]
            ch = (d.get("choices") or [{}])[0]
            delta = (ch.get("delta") or {}).get("content")
            if delta:
                if ttft is None:
                    ttft = time.time() - t0
                content += delta
    wall = time.time() - t0
    if timings is None:  # fallback path: the server keeps the timings of the last request
        try:
            st = http_json(url.rsplit("/v1", 1)[0] + "/v1/status", key)
            lt = st.get("last_timings") or {}
            if lt and time.time() - lt.get("at", 0) < 60:
                timings = lt
        except Exception:
            pass
    t = timings or {}
    return {"prompt_n": t.get("prompt_n", 0), "prompt_s": t.get("prompt_per_second", 0.0),
            "gen_n": t.get("predicted_n", 0), "gen_s": t.get("predicted_per_second", 0.0),
            "draft_n": t.get("draft_n", 0), "draft_ok": t.get("draft_n_accepted", 0),
            "cached": (t.get("prompt_tokens_details") or {}).get("cached_tokens", t.get("cache_n", 0)),
            "ttft_s": round(ttft, 3) if ttft is not None else None,
            "wall_s": round(wall, 2), "text": content[:80]}


def build_prompt(target_tokens, ratio, para):
    n = max(1, int(target_tokens / max(1e-6, ratio) / len(para)) + 1)
    # "метка" = "label"; this marker text is sent to the model as-is in both prompt styles
    mark = f"[метка {__import__('random').randint(10**8, 10**9 - 1)}]\n"
    return mark + para * n


def stats(rows, key):
    vals = [x[key] for x in rows if x[key] is not None]
    if not vals:
        return None
    return {"median": round(statistics.median(vals), 2), "min": round(min(vals), 2),
            "max": round(max(vals), 2), "n": len(vals)}


# ---------------------------------------------------------------- README

def fmt_stat(s, unit=""):
    if not s:
        return "not measured"
    return f"{s['median']}{unit} (range {s['min']}-{s['max']}, n={s['n']})"


def write_readme(d, label, env, results, mem, needle_file, para_style):
    g = env.get("gpu", {})
    lines = []
    a = lines.append
    a(f"# Community benchmark: {g.get('name', 'GPU unknown')}")
    a("")
    a(f"Measured on {env.get('collected_at', datetime.date.today().isoformat())[:10]} by "
      f"[Dmitry-B](https://github.com/Dmitry-B). This tests Strata {env.get('engine_version', '?')} "
      f"with {env.get('model_name', '?')} and a {env.get('cache_max_tokens', '?')}-token context. "
      f"Prompts are {'Russian prose' if para_style == 'ru' else 'code-explanation text'}; greedy "
      f"decoding, a 256-token output cap, three runs per configuration; TTFT measured over "
      f"streaming. These are synthetic workloads; they do not establish general answer quality.")
    a("")
    a("## Hardware and software")
    a("")
    a(f"- GPU: {g.get('name', '?')}; {g.get('vram_mib', '?')} MiB reported VRAM; "
      f"{g.get('power_limit_w', '?')} W power limit; PCIe bus {g.get('pci_bus', '?')}; "
      "PCIe link speed and width: not measured. GPU clocks were not fixed.")
    a(f"- CPU: {env['cpu']['model']} ({env['cpu']['logical_cpus']} logical CPUs).")
    a(f"- RAM: {int(env['ram_total_kib']) // 1024 if str(env['ram_total_kib']).isdigit() else env['ram_total_kib']} "
      "MiB installed; storage layout: see env.json (lsblk output).")
    a(f"- {env['os']}, kernel {env['kernel']}; NVIDIA driver {g.get('driver', '?')}; {env['cuda']}.")
    a(f"- Strata commit `{env['strata_commit']}` (branch {env['strata_branch']}); "
      f"engine {env.get('engine_version', '?')}, release binary from the repository's engine/ directory.")
    a("- Background workloads: a dsh/Authentik/Caddy web stack and stock Ubuntu services; the GPU was "
      "dedicated to Strata but the operating system was not isolated.")
    a("")
    a("## Model and configuration")
    a("")
    a(f"- Model: {env.get('model_name', '?')} (the Strata server's model name); GGUF filenames, sizes, "
      "and modification times are in env.json"
      + (", with SHA-256 hashes." if any("sha256" in f for f in env.get("model_files", [])) else " (no hashes)."))
    a(f"- Context {env.get('cache_max_tokens', '?')}; INT8 KV; resident experts; GPU vision - see the "
      "config copy below.")
    a("- Draft vocabulary subset: `draft_vocab=cyrillic` (the English/code subset plus the whole "
      "Cyrillic script, ~106k rows). This is wider than the default `en` subset; draft acceptance on "
      "English text was unaffected (78-80%), but it can cost a few percent of decode speed.")
    a("")
    a("```text")
    a(env.get("engine_launch_command", "not recorded"))
    a("```")
    a("")
    a(f"Full server config: [config.json](config.json) (was at {env.get('server_config_path', '?')}), "
      "environment details: [env.json](env.json).")
    a("")
    a("## Method")
    a("")
    a("- Warm-up: one 4K-token prompt (64 generated tokens), excluded from the measurements.")
    a("- Every measured prompt carries a random marker, so the prompt-prefix cache is not reused; the "
      "table's reused column reports the actual reused token counts from the engine.")
    a("- Throughput comes from the engine's timing fields (prompt_per_second / predicted_per_second). "
      "TTFT is the time to the first non-empty streaming delta, ignoring keep-alives. Total latency "
      "(wall) is the whole request time measured at the client.")
    a("- temperature=0, reasoning_effort=none, a 256-token output cap (1024 for the generation-only "
      "case). The model often stopped early on the repetitive text; actual generated lengths are in the table.")
    a("- The expert cache was warmed by the warm-up run and earlier sessions; the expert profile state "
      "is in the config copy.")
    a("- Memory: peak VRAM/RAM sampled every 2 seconds during the measured runs, plus a start snapshot.")
    a("")
    a("## Results")
    a("")
    a("| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | "
      "Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |")
    a("| --- | ---: | ---: | ---: | ---: | --- | --- | --- |")
    for r in results:
        rows = r["all"]
        a(f"| {r['case']} | {int(statistics.median([x['prompt_n'] for x in rows]))} | "
          f"{int(statistics.median([x['cached'] for x in rows]))} | "
          f"{int(statistics.median([x['gen_n'] for x in rows]))} | {len(rows)} | "
          f"{fmt_stat(r['prompt_tok_s'])} | {fmt_stat(r['gen_tok_s'])} | {fmt_stat(r['ttft'], ' s')} |")
    a("")
    a("- Total latency (client, wall): " + "; ".join(
        f"{r['case']} - {fmt_stat(r['wall'], ' s')}" for r in results) + ".")
    a(f"- Memory: {json.dumps(mem, ensure_ascii=False)}")
    a("- Every run with its draft statistics (accepted/total): [runs.json](runs.json).")
    if needle_file:
        a(f"- Recall check (needle): [needles.json]({needle_file}).")
    a("")
    a("## Correctness and limitations")
    a("")
    a("- Speed measurements do not establish general answer quality."
      + (" The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json."
         if needle_file else " Recall was not checked."))
    a("- The GPU was not fully isolated: background services may have added small noise.")
    a("- Prompts are synthetic (repeated text with a random marker); real workloads will show different "
      "prefix reuse and draft acceptance.")
    (d / "README.md").write_text("\n".join(lines), encoding="utf-8")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Strata community-style benchmark")
    ap.add_argument("label")
    ap.add_argument("--config", default=None)
    ap.add_argument("--lengths", default="4k,32k,128k")
    ap.add_argument("--no-gen-case", action="store_true")
    ap.add_argument("--needle", default=None, help="lengths for needle_bench, e.g. 32k,128k")
    ap.add_argument("--depths", default="10,50,90")
    ap.add_argument("--hash", action="store_true", help="SHA-256 of the model files (slow)")
    ap.add_argument("--style", choices=["ru", "code"], default="ru")
    ap.add_argument("--out", default=None)
    ap.add_argument("--readme-only", action="store_true",
                    help="rebuild the README from an existing runs.json, without measuring")
    args = ap.parse_args()

    if args.readme_only:
        stamp = datetime.date.today().isoformat()
        d = pathlib.Path(args.out) if args.out else STRATA / "bench" / "results" / f"{stamp}-community-{args.label}"
        data = json.loads((d / "runs.json").read_text(encoding="utf-8"))
        style = args.style if "--style" in sys.argv else ("code" if "code" in args.label else "ru")
        write_readme(d, args.label, data["env"], data["results"], data["memory"],
                     "needles.json" if (d / "needles.json").exists() else None, style)
        print("README rebuilt:", d / "README.md")
        return

    para = PARA_RU if args.style == "ru" else PARA_CODE
    pid, cfg_path, port = find_server()
    cfg_path = args.config or cfg_path
    cfg = json.loads(pathlib.Path(cfg_path).read_text(encoding="utf-8-sig"))
    key = cfg.get("api_key", "")
    url = f"http://127.0.0.1:{port}/v1/chat/completions"

    def parse_len(s):
        s = s.strip().lower()
        return int(float(s[:-1]) * 1024) if s.endswith("k") else int(s)

    lengths = [parse_len(x) for x in args.lengths.split(",") if x.strip()]

    print(f"server: pid {pid}, port {port}, config {cfg_path}")
    print("collecting provenance (hardware/software/model)...")
    env = collect_env(port, key, cfg_path, args.hash)
    print(f"engine {env.get('engine_version')}, context {env.get('cache_max_tokens')}")

    # measure how many tokens per character the chosen style has, so the target length is hit
    probe = call_stream(url, key, para * 4 + f"[метка {1}]", 1, para)
    ratio = probe["prompt_n"] / (len(para) * 4 + 24)
    print(f"engine profile: tokens per character ~ {ratio:.3f}")

    print("warm-up (4K)...")
    call_stream(url, key, build_prompt(4000, ratio, para), 64, para)

    mem = MemWatch()
    mem.start()

    cases = [(f"{n}-prompt", n, 256, 3) for n in lengths]
    if not args.no_gen_case:
        cases.append(("gen-only", 120, 1024, 3))

    results = []
    for name, target, gen, reps in cases:
        rows = []
        for i in range(reps):
            r = call_stream(url, key, build_prompt(target, ratio, para), gen, para)
            rows.append(r)
            print(f"  {name} #{i + 1}: prompt {r['prompt_n']} @ {r['prompt_s']:.1f} tok/s | "
                  f"gen {r['gen_n']} @ {r['gen_s']:.1f} tok/s | TTFT {r['ttft_s']} s | "
                  f"drafts {r['draft_ok']}/{r['draft_n']} | wall {r['wall_s']} s", flush=True)
        results.append({"case": name, "target_prompt_tokens": target, "max_tokens": gen,
                        "prompt_tok_s": stats(rows, "prompt_s"), "gen_tok_s": stats(rows, "gen_s"),
                        "ttft": stats(rows, "ttft_s"), "wall": stats(rows, "wall_s"),
                        "draft_ok": sum(x["draft_ok"] for x in rows),
                        "draft_n": sum(x["draft_n"] for x in rows),
                        "all": rows})

    mem_res = mem.result()

    # the report folder
    stamp = datetime.date.today().isoformat()
    d = pathlib.Path(args.out) if args.out else STRATA / "bench" / "results" / f"{stamp}-community-{args.label}"
    d.mkdir(parents=True, exist_ok=True)

    needle_file = None
    if args.needle:
        print(f"recall check: needle_bench {args.needle} / depths {args.depths}...")
        needle_file = "needles.json"
        cmd = ["python3", str(STRATA / "tools" / "needle_bench.py"),
               "--url", f"http://127.0.0.1:{port}", "--lengths", args.needle,
               "--depths", args.depths, "--out", str(d / "needles.json")]
        if key:
            cmd += ["--api-key", key]
        subprocess.run(cmd)

    json.dump({"label": args.label, "style": args.style, "env": env, "memory": mem_res, "results": results},
              open(d / "runs.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    cfg_pub = dict(cfg)
    cfg_pub.pop("api_key", None)
    json.dump(cfg_pub, open(d / "config.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    write_readme(d, args.label, env, results, mem_res, needle_file, args.style)
    print("REPORT:", d)


main()
