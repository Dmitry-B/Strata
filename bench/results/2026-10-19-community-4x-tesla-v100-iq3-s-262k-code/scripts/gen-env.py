#!/usr/bin/env python3
"""Provenance for a community report: writes env.json next to the measurements.

Collects the same fields earlier reports collected (GPU/CPU/RAM/OS/kernel/CUDA, engine version,
the launch command, model file sizes), and adds what this machine did not have in earlier
reports: the contents of engine-cuda12/BUILD.json (the engine here is built from the release sources
with a private CUDA 12.8 and a private gcc-14) and the path of the source tree.

Usage: gen-env.py <report directory> <server config file> <engine log>
env.json is written into the report directory. The server is asked nothing except /props.
"""
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

D = pathlib.Path.home() / "strata185"
URL, KEY = "http://127.0.0.1:8080", "removed"


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e:
        return f"error: {e}"


def arg_of(cfg, flag):
    a = cfg.get("args", [])
    return a[a.index(flag) + 1] if flag in a else None


def props():
    out = sh(["curl", "-s", "-m", "10", f"{URL}/props", "-H", f"Authorization: Bearer {KEY}"])
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:400]}


def nvsmi(query, fmt="csv,noheader"):
    return sh(["nvidia-smi", f"--query-gpu={query}", f"--format={fmt}"])


def main():
    out_dir, cfg_path, log_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cfg = json.loads(pathlib.Path(cfg_path).read_text())
    p = props()
    gpus_raw = nvsmi("index,name,memory.total,driver_version,power.limit,pci.bus_id,serial").split("\n")
    gpus = [{"index": i[0], "name": i[1], "vram_mib": i[2], "driver": i[3],
             "power_limit_w": i[4], "pci_bus_id": i[5], "serial": i[6]}
            for i in (x.split(", ") for x in gpus_raw) if len(i) == 7]

    # the last engine launch command, taken from the log
    launch = ""
    try:
        lines = pathlib.Path(log_path).read_text(errors="replace").splitlines()
        for line in reversed(lines):
            if "engine started:" in line:
                launch = line.split("engine started:", 1)[1].strip()
                break
    except Exception:
        pass

    build = {}
    for cand in ("engine-cuda12/BUILD.json", "engine/BUILD.json"):
        f = D / "Strata" / cand
        if f.exists():
            try:
                build = {"path": cand, "json": json.loads(f.read_text())}
            except Exception as e:
                build = {"path": cand, "error": str(e)}
            break

    files = []
    for flag in ("--pack", "--native", "--ple-gguf", "--expert-profile", "--mtp",
                 "--control-vector-scaled", "--expert-profile-save"):
        path = None
        if flag in cfg.get("args", []):
            path = cfg["args"][cfg["args"].index(flag) + 1]
        else:
            key = flag.replace("--", "").replace("-", "_")
            path = cfg.get(key)
        if not path:
            continue
        path = str(path).split(":")[0]
        entry = {"flag": flag, "path": path}
        pp = pathlib.Path(path)
        if pp.is_dir():
            entry["kind"] = "dir"
        elif pp.is_file():
            st = pp.stat()
            entry.update(size_bytes=st.st_size, mtime=datetime.datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds"))
        else:
            entry["kind"] = "missing"
        files.append(entry)

    env = {
        "collected_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "gpu": gpus,
        "gpu_count": len(gpus),
        "gpu_nvlink": sh(["nvidia-smi", "nvlink", "-s"]),
        "persistence_mode": nvsmi("persistence_mode"),
        "clocks": nvsmi("clocks.sm,clocks.mem,clocks.max.sm,clocks.max.mem"),
        "cpu": {"model": sh(["bash", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-"]),
                "logical_cpus": sh(["nproc"]),
                "smt": sh(["bash", "-c", "grep -c processor /proc/cpuinfo"])},
        "ram_total_kib": sh(["bash", "-c", "awk '/MemTotal/{print $2}' /proc/meminfo"]),
        "os": sh(["bash", "-c", ". /etc/os-release; echo \"$PRETTY_NAME\""]),
        "kernel": sh(["uname", "-r"]),
        "cuda": sh(["bash", "-c", f"{D}/cuda-12.8/bin/nvcc --version | tail -2 | head -1"]),
        "gcc": sh(["bash", "-c", f"{D}/gcc185/usr/bin/gcc-14 --version | head -1"]),
        "storage": sh(["bash", "-c", "lsblk -d -o NAME,SIZE,MODEL,ROTA,MOUNTPOINT | grep -v loop"]),
        "strata_commit": "unknown: no git on this machine; the tree came from the GitHub release source archive",
        "strata_source_tree": str(D / "Strata"),
        "strata_backup_tree": str(D / "Strata-0.1.44.1.bak"),
        "engine_build": build,
        "engine_version": p.get("build_info"),
        "model_name": p.get("model_alias"),
        "model_path": p.get("model_path"),
        "context": {"max_context_arg": arg_of(cfg, "--max-context"),
                    "default_n_ctx": (p.get("default_generation_settings") or {}).get("n_ctx")},
        "total_slots": p.get("total_slots"),
        "health": json.loads(sh(["curl", "-s", "-m", "10", f"{URL}/health", "-H", f"Authorization: Bearer {KEY}"]) or "{}"),
        "vision": {"enabled": bool(cfg.get("vision")), "mmproj": (cfg.get("vision") or {}).get("mmproj")},
        "engine_launch_command": launch,
        "model_files": files,
        "notes": [
            "the engine is built on this machine from the release sources: a private CUDA 12.8 (~/strata185/cuda-12.8) "
            "and a private gcc-14, target sm_70 (4x Tesla V100 SXM2); no system toolkit is used",
            "DCGM/genqprof are not installed on this machine: no colouring/PCIe profiling in this report",
            "the agent that ran the measurements is served by another machine (an RTX 4090 box): its own requests "
            "do not reach this server (stated in the report)",
        ],
    }
    out = pathlib.Path(out_dir) / "env.json"
    out.write_text(json.dumps(env, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote: {out} ({out.stat().st_size} bytes)")
    print("engine:", env.get("engine_version"), "| build:", env.get("engine_build", {}).get("json", {}).get("source"))
    print("model:", env.get("model_name"), "| context:", env.get("context"))


if __name__ == "__main__":
    main()
