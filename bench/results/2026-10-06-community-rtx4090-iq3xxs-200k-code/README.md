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
/home/dgbox/Strata/engine/strata --serve --pack /home/dgbox/Strata-data/packs/iq3_xxs --native /home/dgbox/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf --ple-gguf /home/dgbox/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf --expert-profile /home/dgbox/Strata/data/expert-profile-learned.bin --expert-cache auto --prefill auto --spec 4 --mtp /home/dgbox/Strata-data/mtp/rt --max-context 204800 --kv int8 --mmap-experts --vision --vram-reserve-mib 989 --control-vector-scaled /home/dgbox/Strata/data/experimental-speed-projection/Qwen3.8-Flash-Next-experimental-speed-projection.gguf:1.0 --control-vector-layer-range 4 44 --cvec-mode project --cvec-dir per-layer --pcie-frac 0.00 --spec-min-p 0.50 --pool-workers 10 --expert-profile-save /home/dgbox/Strata/data/expert-profile-learned.bin --expert-profile-save-every 10
```

Full server config: [config.json](config.json) (was at /home/dgbox/Strata/strata-200k.json), environment details: [env.json](env.json).

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
| 4096-prompt | 3971 | 0 | 256 | 3 | 1978.6 (range 1944.2-1983.9, n=3) | 130.1 (range 115.8-131.3, n=3) | 2.04 s (range 2.02-2.06, n=3) |
| 32768-prompt | 31307 | 0 | 256 | 3 | 3136.3 (range 2925.4-3142.2, n=3) | 136.4 (range 132.7-138.3, n=3) | 10.07 s (range 10.05-10.79, n=3) |
| 131072-prompt | 125011 | 0 | 256 | 3 | 3118.5 (range 3082.3-3122.6, n=3) | 124.1 (range 110.0-127.9, n=3) | 40.38 s (range 40.34-40.86, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 212.5 (range 206.1-221.6, n=3) | 143.2 (range 137.3-146.3, n=3) | 0.79 s (range 0.75-0.81, n=3) |

- Total latency (client, wall): 4096-prompt - 4.02 s (range 3.98-4.22, n=3); 32768-prompt - 11.93 s (range 11.89-12.71, n=3); 131072-prompt - 42.32 s (range 41.66-42.91, n=3); gen-only - 7.94 s (range 7.77-8.19, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22026, "ram_used_kib": 5836344}, "peak_vram_used_mib": 22026, "peak_ram_used_kib": 6577944, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).
- Recall check (needle): [needles.json](needles.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
## Comparison with engine 0.1.39

The same PC, the same model and the same run configuration as
`2026-10-04-community-rtx4090-iq3xxs-200k-code` (engine 0.1.39; that report lives on the branch
`bench/2026-10-03-rtx4090-community`). Only the Strata version changed: 0.1.39 -> 0.1.40, source build, same
CUDA 13.4, same `sm_89`, same arguments, same `expert-profile-learned.bin`. The engine's auto prompt chunk is
unchanged in both (`prompt chunk auto: 8192 tokens, a 96-slot ring` in the server log), and the resident expert
count is the same (6915 slots now, 6919-6926 then), so the two runs measure the same memory layout.

| Configuration | Prompt tok/s 0.1.39 -> 0.1.40 | Decode tok/s 0.1.39 -> 0.1.40 | TTFT s 0.1.39 -> 0.1.40 |
| --- | --- | --- | --- |
| 4096-prompt | 1966.2 -> 1978.6 (+0.6%) | 123.6 -> 130.1 (+5.3%) | 2.04 -> 2.04 |
| 32768-prompt | 2973.7 -> 3136.3 (+5.5%) | 134.9 -> 136.4 (+1.1%) | 10.61 -> 10.07 |
| 131072-prompt | 3084.9 -> 3118.5 (+1.1%) | 120.3 -> 124.1 (+3.2%) | 40.82 -> 40.38 |
| gen-only | 205.3 -> 212.5 (+3.5%) | 135.8 -> 143.2 (+5.4%) | 0.81 -> 0.79 |

- Prompt throughput is the comparable column: it comes from the engine's own timing and the ranges are tight in both
  runs (3043-3109 and 3082-3123 tok/s at 131072-prompt). The gain is +0.6% at 4K, +5.5% at 32K, +1.1% at 128K.
- Decode medians are the least comparable column: on this repetitive text the model stops early at a different point
  each run (183-256 tokens at 131072-prompt in the 0.1.39 report, 142-256 here), and a shorter answer does not have
  the same draft acceptance as a longer one. The `gen-only` case, which runs to the 1024-token cap in both, is the
  cleanest decode comparison: +5.4%.
- Draft acceptance rose in every case (73.4% -> 75.2%, 77.2% -> 78.6%, 74.4% -> 75.6%).
- Recall: 6/6 at 32K and 128K across depths 10/50/90 in both versions.
- Unlike the 0.1.39 report, this one has no run contaminated by the interactive session this machine also serves:
  no other client's request was served between the measured runs, so the TTFT and wall columns here are clean and
  the 0.1.39 131072-prompt TTFT range (up to 91 s) is not a regression of 0.1.40 - it was queue waiting.
