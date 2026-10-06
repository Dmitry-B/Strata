# Community benchmark: NVIDIA GeForce RTX 4090

Measured on 2026-10-06 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.40 with qwen3.8-flash-next-iq3_xxs and a 204800-token context. Prompts are Russian prose; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

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
| 4096-prompt | 4028 | 0 | 256 | 3 | 1893.8 (range 1554.3-1897.3, n=3) | 85.8 (range 78.1-94.1, n=3) | 2.16 s (range 2.15-2.62, n=3) |
| 32768-prompt | 31828 | 0 | 256 | 3 | 3125.6 (range 2923.2-3154.9, n=3) | 91.4 (range 85.1-93.1, n=3) | 10.31 s (range 10.22-11.03, n=3) |
| 131072-prompt | 127228 | 0 | 123 | 3 | 3136.4 (range 3092.2-3138.9, n=3) | 89.9 (range 89.3-110.6, n=3) | 41.06 s (range 41.03-41.62, n=3) |
| gen-only | 228 | 0 | 468 | 3 | 298.5 (range 290.6-301.1, n=3) | 87.8 (range 85.9-89.3, n=3) | 0.78 s (range 0.77-0.8, n=3) |

- Total latency (client, wall): 4096-prompt - 5.42 s (range 3.65-5.59, n=3); 32768-prompt - 12.96 s (range 11.75-13.82, n=3); 131072-prompt - 42.4 s (range 42.11-43.23, n=3); gen-only - 6.21 s (range 3.61-7.44, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22026, "ram_used_kib": 5841100}, "peak_vram_used_mib": 22026, "peak_ram_used_kib": 6560156, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).
- Recall check (needle): [needles.json](needles.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
## Comparison with engine 0.1.39

The same PC, the same model and the same run configuration as
`2026-10-04-community-rtx4090-iq3xxs-200k-ru` (engine 0.1.39; that report lives on the branch
`bench/2026-10-03-rtx4090-community`). Only the Strata version changed: 0.1.39 -> 0.1.40, source build, same
CUDA 13.4, same `sm_89`, same arguments, same `expert-profile-learned.bin`, same auto prompt chunk (8192).

| Configuration | Prompt tok/s 0.1.39 -> 0.1.40 | Decode tok/s 0.1.39 -> 0.1.40 | TTFT s 0.1.39 -> 0.1.40 |
| --- | --- | --- | --- |
| 4096-prompt | 1907.8 -> 1893.8 (-0.7%) | 81.1 -> 85.8 (+5.8%) | 2.1 -> 2.16 |
| 32768-prompt | 3128.0 -> 3125.6 (-0.1%) | 90.5 -> 91.4 (+1.0%) | 10.3 -> 10.22 |
| 131072-prompt | 3126.4 -> 3136.4 (+0.3%) | 87.8 -> 89.9 (+2.4%) | 41.2 -> 41.06 |
| gen-only | 296.2 -> 298.5 (+0.8%) | 93.6 -> 87.8 (-6.2%) | 0.8 -> 0.778 |

- Prompt throughput on Russian text is unchanged within noise (-0.7% .. +0.8%) in every case.
- The `gen-only` -6.2% is not a measured slowdown: the 0.1.39 run generated 2057 tokens across its three repeats,
  this one 1306 - the model stopped early at a different point, and the two arms therefore did not decode the same
  amount of text. Decode in the three prompt cases (which are capped at 256 tokens and so comparable in length)
  went up by 1-6%.
- Draft acceptance on Russian text fell at 4K and 32K (47.5% -> 39.5%, 63.9% -> 55.3%) and rose at 128K
  (58.8% -> 61.5%). With different generated lengths this is not a clean comparison either; it is recorded because
  Russian decode is far behind code decode on this model (86-91 against 130-143 tok/s) in both versions.
- Recall: 6/6 at 32K and 128K across depths 10/50/90 in both versions.
