# Community benchmark: NVIDIA GeForce RTX 4090

Measured on 2026-10-18 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.45 with qwen3.8-flash-next-iq3_s and a 204800-token context. Prompts are Russian prose; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

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
| 4096-prompt | 4028 | 0 | 102 | 3 | 344.1 (range 342.7-446.1, n=3) | 57.8 (range 54.2-63.0, n=3) | 11.73 s (range 9.05-11.77, n=3) |
| 32768-prompt | 31828 | 0 | 102 | 3 | 585.7 (range 568.5-611.9, n=3) | 68.8 (range 58.2-79.2, n=3) | 54.38 s (range 52.05-56.02, n=3) |
| 131072-prompt | 127228 | 0 | 102 | 3 | 543.2 (range 542.8-555.4, n=3) | 47.4 (range 45.5-52.1, n=3) | 234.28 s (range 229.13-234.48, n=3) |
| gen-only | 228 | 0 | 268 | 3 | 119.6 (range 93.4-275.7, n=3) | 80.3 (range 58.3-90.3, n=3) | 1.93 s (range 0.84-2.46, n=3) |

- Total latency (client, wall): 4096-prompt - 13.48 s (range 10.92-13.81, n=3); 32768-prompt - 57.3 s (range 53.32-57.49, n=3); 131072-prompt - 236.42 s (range 231.26-236.5, n=3); gen-only - 5.25 s (range 3.34-8.59, n=3).
- Memory: {"start_snapshot": {"vram_used_mib": 22100, "ram_used_kib": 6299396}, "peak_vram_used_mib": 22100, "peak_ram_used_kib": 7087800, "note": "пик — максимум опросов каждые 2 с во время замеров"}
- Every run with its draft statistics (accepted/total): [runs.json](runs.json).
- Recall check (needle): [needles.json](needles.json).

## Correctness and limitations

- Speed measurements do not establish general answer quality. The recall check passed 6/6 at 32K and 128K across depths 10/50/90; see needles.json.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
## Comparison with 0.1.44.1 (ru style, medians, tok/s)

Same session, engine swapped via `engine/strata*.01441.bak`; the auto prompt chunk is
8192 in both versions; no observer traffic (the agent works against another server).

| case | 0.1.45 | 0.1.44.1 | control (same binary) | delta |
|---|---|---|---|---|
| 4096-prompt | 344.1 | 375.3 | 379.0 | −8.3% (0.1.45 below both control and 0.1.44.1; on the iq3_xxs config the 4K anomaly was isolated to `STRATA_DEQUANT_WIDE` — not A/B'd on this config) |
| 32768-prompt | 585.7 | 581.5 | 605.7 | +0.7% (inside the band) |
| 131072-prompt | 543.2 | 537.1 | 534.9 | +1.1% (inside the band) |
| gen-only | 119.6 | 122.4 | 174.3 | −2.3% (this case is unstable on this config: the control of the same binary is +42% above the main run) |

Long context (156K/185K/200K) and the full method are in
`../2026-10-18-community-rtx4090-iq3s-200k-code/README.md` — no change at the context
limit. Recall 6/6 at 32K and 128K in both versions. Generation columns are inside the
method's noise; no generation conclusion.
