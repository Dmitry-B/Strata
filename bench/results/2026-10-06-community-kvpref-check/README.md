# Community benchmark: NVIDIA GeForce RTX 4090

Measured on 2026-10-06 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.40 with qwen3.8-flash-next-iq3_xxs and a 204800-token context. Prompts are code-explanation text; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

## Hardware and software

- GPU: NVIDIA GeForce RTX 4090; 23028 MiB reported VRAM; 480.00 W power limit; PCIe bus 00000000:01:00.0; PCIe link speed and width: not measured. GPU clocks were not fixed.
- CPU: AMD Ryzen 9 7950X 16-Core Processor (32 logical CPUs).
- RAM: 46464 MiB installed; storage layout: see env.json (lsblk output).
- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic; NVIDIA driver 610.57.04; release 13.4, V13.4.92.
- Strata commit `1735d6471df29b42c26170efaac1f1446a58640f` (branch main); engine 0.1.40, release binary from the repository's engine/ directory.
- Background workloads: a dsh/Authentik/Caddy web stack and stock Ubuntu services; the GPU was dedicated to Strata but the operating system was not isolated.

## Model and configuration

- Model: qwen3.8-flash-next-iq3_xxs (the Strata server's model name); GGUF filenames, sizes, and modification times are in env.json (no hashes).
- Context 204800; INT8 KV; resident experts; GPU vision - see the config copy below.
- Draft vocabulary subset: `draft_vocab=cyrillic` (the English/code subset plus the whole Cyrillic script, ~106k rows). This is wider than the default `en` subset; draft acceptance on English text was unaffected (78-80%), but it can cost a few percent of decode speed.

```text
/bin/bash -c cd ~/Strata && echo /home/dgbox/Strata/strata-test-200k-kvpref.json > try-config && sudo -n systemctl restart strata.service && for i in $(seq 1 60); do curl -s -m 5 http://127.0.0.1:8080/health | grep -q '"loaded": true' && break; sleep 5; done; curl -s -m 5 http://127.0.0.1:8080/health; echo; tr '\0' '\n' < /proc/$(pgrep -f "engine/strata --serve" | head -1)/cmdline | grep -c STRATA || true; echo "--- замер 32k/128k с KV_PREFETCH=1 ---"; timeout 1200 .venv/bin/python -u ~/scripts/strata-bench.py kvpref-check --style code --lengths 32k,128k --no-gen-case 2>&1 | tail -12
```

Full server config: [config.json](config.json) (was at /home/dgbox/Strata/strata-test-200k-kvpref.json), environment details: [env.json](env.json).

## Method

- Warm-up: one 4K-token prompt (64 generated tokens), excluded from the measurements.
- Every measured prompt carries a random marker, so the prompt-prefix cache is not reused; the table's reused column reports the actual reused token counts from the engine.
- Throughput comes from the engine's timing fields (prompt_per_second / predicted_per_second). TTFT is the time to the first non-empty streaming delta, ignoring keep-alives. Total latency (wall) is the whole request time measured at the client.
- temperature=0, reasoning_effort=none, a 256-token output cap (1024 for the generation-only case). The model often stopped early on the repetitive text; actual generated lengths are in the table.
- The expert cache was warmed by the warm-up run and earlier sessions; the expert profile state is in the config copy.
- Memory: peak VRAM/RAM sampled every 2 seconds during the measured runs, plus a start snapshot.

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 32768-prompt | 31307 | 0 | 256 | 3 | 3001.8 (range 2936.9-3063.2, n=3) | 113.8 (range 110.1-128.5, n=3) | 10.51 s (range 10.31-10.75, n=3) |
| 131072-prompt | 125011 | 0 | 164 | 3 | 3052.3 (range 3030.3-3059.4, n=3) | 106.5 (range 87.0-113.4, n=3) | 41.26 s (range 41.16-85.58, n=3) |

- Total latency (client, wall): 32768-prompt - 12.75 s (range 12.29-13.06, n=3); 131072-prompt - 43.4 s (range 42.58-87.45, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22024, "ram_used_kib": 5749720}, "peak_vram_used_mib": 22040, "peak_ram_used_kib": 6587012, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. Recall was not checked.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
## What this report is

Not a version comparison: a check of one opt-in, `STRATA_KV_PREFETCH=1` (#732), on engine 0.1.40 with the machine's
working configuration (`strata-200k.json` plus that one environment variable). The arm it is compared against is
`2026-10-06-community-rtx4090-iq3xxs-200k-code`, measured on the same day with the same arguments and no such
variable.

| Configuration | Prompt tok/s without -> with `STRATA_KV_PREFETCH=1` |
| --- | --- |
| 32768-prompt | 3136.3 -> 3001.8 (-4.3%) |
| 131072-prompt | 3118.5 -> 3052.3 (-2.1%) |

The option overlaps streamed KV uploads with prefill (docs/KV_PREFETCH.md), so it can only help when part of the KV
cache lives in system RAM - that is `--kv-resident`. This configuration has no `--kv-resident`, so its KV cache
stays in VRAM and there is nothing to overlap; the measured result is a small loss, matching the -4..-5% the option's
author reported on an RTX 5070 and the reason it stays off by default. Conclusion for this machine: leave it off.
