# Community benchmark: NVIDIA GeForce RTX 4090

Measured on 2026-10-18 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.45 with qwen3.8-flash-next-iq3_s and a 204800-token context. Prompts are code-explanation text; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

## Hardware and software

- GPU: NVIDIA GeForce RTX 4090; 23028 MiB reported VRAM; 480.00 W power limit; PCIe bus 00000000:01:00.0; PCIe link speed and width: not measured. GPU clocks were not fixed.
- CPU: AMD Ryzen 9 7950X 16-Core Processor (32 logical CPUs).
- RAM: 46464 MiB installed; storage layout: see env.json (lsblk output).
- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic; NVIDIA driver 615.71.09; release 13.4, V13.4.92.
- Strata commit `477ac13cbe8e582c20484871ce459d20d82df09d` (tag v0.1.45); engine 0.1.45 built from source (`engine/BUILD.json` `"source": "local"`, archs `[89]`).
- Background workloads: a dsh/Authentik/Caddy web stack and stock Ubuntu services; the GPU was dedicated to Strata but the operating system was not isolated.

## Model and configuration

- Model: qwen3.8-flash-next-iq3_s (the Strata server's model name); GGUF filenames, sizes, and modification times are in env.json (no hashes).
- Context 204800; INT8 KV; resident experts; GPU vision - see the config copy below.
- Draft vocabulary subset: `draft_vocab=cyrillic` (the English/code subset plus the whole Cyrillic script, ~106k rows). This is wider than the default `en` subset; draft acceptance on English text was unaffected (78-80%), but it can cost a few percent of decode speed.

```text
/home/dgbox/Strata/engine/strata --serve --pack /home/dgbox/Strata-data/packs/iq3_s --native /home/dgbox/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf --ple-gguf /home/dgbox/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf --expert-profile /home/dgbox/Strata/data/expert-profile-learned-iq3s.bin --expert-cache auto --prefill auto --spec 4 --mtp /home/dgbox/Strata-data/mtp/rt --max-context 204800 --kv int8 --mmap-experts --vision --vram-reserve-mib 989 --control-vector-scaled /home/dgbox/Strata/data/experimental-speed-projection/Qwen3.8-Flash-Next-experimental-speed-projection.gguf:1.0 --control-vector-layer-range 4 44 --cvec-mode project --cvec-dir per-layer --spec-min-p 0.5 --expert-profile-save /home/dgbox/Strata/data/expert-profile-learned-iq3s.bin --expert-profile-save-every 10
```

Full server config: [config.json](config.json) (was at /home/dgbox/Strata/strata-test-iq3s-200k.json), environment details: [env.json](env.json).

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
| 4096-prompt | 3971 | 0 | 158 | 3 | 330.8 (range 320.0-362.9, n=3) | 60.8 (range 55.2-62.6, n=3) | 12.02 s (range 10.96-12.43, n=3) |
| 32768-prompt | 31307 | 0 | 173 | 3 | 603.8 (range 603.3-630.2, n=3) | 60.4 (range 53.8-60.5, n=3) | 51.89 s (range 49.71-51.92, n=3) |
| 131072-prompt | 125011 | 0 | 165 | 3 | 546.5 (range 545.2-560.3, n=3) | 42.5 (range 39.8-46.5, n=3) | 228.83 s (range 223.17-229.37, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 130.9 (range 104.9-217.5, n=3) | 73.5 (range 67.8-91.9, n=3) | 1.27 s (range 0.77-1.57, n=3) |

- Total latency (client, wall): 4096-prompt - 15.28 s (range 12.62-16.11, n=3); 32768-prompt - 54.77 s (range 53.94-54.96, n=3); 131072-prompt - 232.19 s (range 227.09-233.5, n=3); gen-only - 11.9 s (range 2.86-15.49, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22100, "ram_used_kib": 6238132}, "peak_vram_used_mib": 22100, "peak_ram_used_kib": 6959120, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).
- Recall check (needle): [needles.json](needles.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
## Comparison with 0.1.44.1 (IQ3_S, same session, engine swapped via `engine/strata*.01441.bak`)

Protocol: warm-up (discarded) -> code -> ru -> control on the same 0.1.45 binary ->
swap to 0.1.44.1 -> warm-up -> code -> ru -> long-context, then swap back. The auto
prompt chunk is 8192 tokens in both versions. The agent works against another server;
no observer traffic.

### prompt reading (medians, tok/s) — code style, short through the context limit

| case (actual tokens where relevant) | 0.1.45 | 0.1.44.1 | control (same binary) | delta |
|---|---|---|---|---|
| 4096 | 330.8 | 323.4 | 345.6 | +2.3% (inside the band) |
| 32768 | 603.8 | 597.0 | 583.4 | +1.1% (inside the band) |
| 131072 | 546.5 | 530.1 | 531.6 | +3.1% (control spread here is ±2.7%, the delta sits inside it) |
| 163840 (156,291) | 534.2 | 531.2 | 537.8 | +0.6% |
| 194560 (185,531) | 537.5 | 531.0 | 532.2 | +1.2% |
| 209715 (200,015) | 529.6 | 530.8 | 522.3 | −0.2% |
| gen-only (163-token prompt) | 130.9 | 85.1 | 124.1 | +53.8% — see note |

TTFT at 200K: 377.8 s (0.1.45) vs 376.9 s (0.1.44.1); at 156K: 292.7 / 294.3 s. The
long lengths were run in the code style only for this release; under the current
single-suite protocol they are present for both styles.

### prompt reading — ru style

| case | 0.1.45 | 0.1.44.1 | control | delta |
|---|---|---|---|---|
| 4096-prompt | 344.1 | 375.3 | 379.0 | −8.3% (the 0.1.45 sample is below both the control and 0.1.44.1; not re-A/B'd — on the iq3_xxs config the 4K anomaly was isolated to `STRATA_DEQUANT_WIDE`, see `../2026-10-18-community-rtx4090-iq3xxs-200k-code/README.md`; not measured on this config) |
| 32768-prompt | 585.7 | 581.5 | 605.7 | +0.7% (inside the band) |
| 131072-prompt | 543.2 | 537.1 | 534.9 | +1.1% (inside the band) |
| gen-only | 119.6 | 122.4 | 174.3 | −2.3% (the control itself is far above both; this case's prompt column is unstable on this config) |

### notes

- The gen-only prompt column on this config is a 163-token prompt: its reading speed
  is dominated by warm-up state, and the control run of the same binary moved 124.1
  vs 130.9 (code) and 174.3 vs 119.6 (ru) — the +53.8% code delta is not a
  version effect, it is this case's known instability on a file-tier config.
- Generation columns: deltas from −6.7% to +40.1%; answer lengths and draft-accept
  ratios differ run to run (e.g. 4K ru 264/275 vs 388/500), so no generation
  conclusion is drawn.
- Recall: 6/6 at 32K and 128K (both styles, both versions) and 3/3 at 192K (both
  versions).
- Absolute speeds are far below the iq3_xxs reports because IQ3_S (~50 GB of experts)
  does not fit this machine's 48 GB RAM + 24 GB VRAM: the file tier and the expert
  cache do the work (decode hit rates 66–88% in the engine log). These numbers are
  comparable only within this config.
