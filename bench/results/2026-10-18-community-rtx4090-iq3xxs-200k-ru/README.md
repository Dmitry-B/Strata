# Community benchmark: NVIDIA GeForce RTX 4090

Measured on 2026-10-18 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.45 with qwen3.8-flash-next-iq3_xxs and a 204800-token context. Prompts are Russian prose; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

This run is part of a version comparison (0.1.44.1 -> 0.1.45): the same session
re-measured 0.1.44.1 by swapping the engine binaries, and re-ran 0.1.45 on the same
binary as a control. The full method, both style tables and the 4K-code anomaly are in
`../2026-10-18-community-rtx4090-iq3xxs-200k-code/README.md`. The auto prompt chunk is
8192 tokens in both versions, so the prompt columns are bit-comparable.

## Comparison with 0.1.44.1 (ru style, medians, tok/s)

| case | 0.1.45 | 0.1.44.1 (same session) | control (same binary) | delta |
|---|---|---|---|---|
| 4096-prompt | 2109.0 | 2131.2 | 2066.6 | −1.0% (inside the control band) |
| 32768-prompt | 3275.8 | 3298.9 | 3219.2 | −0.7% (inside the band) |
| 131072-prompt | 3308.2 | 3331.9 | 3296.4 | −0.7% (inside the band) |
| gen-only (163-token prompt) | 392.7 | 395.9 | 403.8 | −0.8% (inside the band) |

Generation columns: all deltas within the method's generation noise (±5–6% on identical
binaries); draft acceptance unchanged. Recall 6/6 at 32K and 128K in both versions.
No regression was measured in the ru style.

## Hardware and software

- GPU: NVIDIA GeForce RTX 4090; 23028 MiB reported VRAM; 480.00 W power limit; PCIe bus 00000000:01:00.0; PCIe link speed and width: not measured. GPU clocks were not fixed.
- CPU: AMD Ryzen 9 7950X 16-Core Processor (32 logical CPUs).
- RAM: 46464 MiB installed; storage layout: see env.json (lsblk output).
- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic; NVIDIA driver 615.71.09; release 13.4, V13.4.92.
- Strata commit `477ac13cbe8e582c20484871ce459d20d82df09d` (tag v0.1.45); engine 0.1.45 built from source (`engine/BUILD.json` `"source": "local"`, archs `[89]`).
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
| 4096-prompt | 4028 | 0 | 103 | 3 | 2109.0 (range 2038.6-2126.4, n=3) | 125.7 (range 115.4-134.4, n=3) | 1.92 s (range 1.91-1.99, n=3) |
| 32768-prompt | 31828 | 0 | 256 | 3 | 3275.8 (range 3233.7-3314.8, n=3) | 140.0 (range 128.9-141.1, n=3) | 9.74 s (range 9.62-9.87, n=3) |
| 131072-prompt | 127228 | 0 | 256 | 3 | 3308.2 (range 3230.0-3310.7, n=3) | 125.6 (range 105.5-130.4, n=3) | 38.51 s (range 38.49-39.44, n=3) |
| gen-only | 228 | 0 | 634 | 3 | 392.7 (range 390.7-399.7, n=3) | 135.5 (range 125.6-138.6, n=3) | 0.59 s (range 0.58-0.6, n=3) |

- Total latency (client, wall): 4096-prompt - 2.79 s (range 2.72-3.62, n=3); 32768-prompt - 11.67 s (range 11.44-11.71, n=3); 131072-prompt - 40.46 s (range 40.36-40.51, n=3); gen-only - 5.16 s (range 4.53-5.93, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22082, "ram_used_kib": 6192104}, "peak_vram_used_mib": 22082, "peak_ram_used_kib": 6944528, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).
- Recall check (needle): [needles.json](needles.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.