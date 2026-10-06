# Community benchmark: RTX 4090, Ryzen 9 7950X, 48 GB RAM — qwen3.8-flash-next-iq3_s, 143,360-token context

Measured on 2026-10-03 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata **0.1.38** with
`qwen3.8-flash-next-iq3_s` and a 143,360-token context in the resident-experts variant, in two prompt arms —
code-explanation text and Russian prose — three runs each at 4,096 / 32,768 / 131,072 prompt tokens plus a
generation-only case, and six recall checks per arm. Greedy decoding, a 256-token output cap (1,024 for the
generation-only case), TTFT measured over streaming.

Prompts were read at 2,059 / 2,948 / 3,048 tok/s (code) and 2,084 / 2,991 / 3,078 tok/s (ru) at 4K / 32K / 128K,
and decoded at 77–97 tok/s. Recall passed 6/6 at 32K and 128K in both arms. The prompts are synthetic; these runs
say nothing about answer quality.

This is the configuration this machine used before the 204,800-token IQ3_XXS one. The IQ3_XXS chain — 0.1.38 →
0.1.39 → 0.1.40 → 0.1.40.1 on the same PC — is in
[2026-10-03-community-rtx4090-iq3xxs-200k](../2026-10-03-community-rtx4090-iq3xxs-200k/README.md).

## Files in this folder

| File | What it is |
| --- | --- |
| `config.json` | the server config copy (was at `/home/dgbox/Strata/strata-iq3s-140k-resident.json`) |
| `runs-code.json`, `runs-ru.json` | every run: prompt and generated token counts, engine timings, TTFT, wall time, memory samples, draft accepted/total |
| `needles-code.json`, `needles-ru.json` | the recall check of that arm (32K and 128K, depths 10/50/90) |

The measurement script is
[benchmark.py](../2026-10-03-community-rtx4090-iq3xxs-200k/benchmark.py) — the same file used by the IQ3_XXS
reports; it was added to this machine on 2026-10-03 and not changed since.

## Hardware and software

- GPU: NVIDIA GeForce RTX 4090; 23028 MiB reported VRAM; 480.00 W power limit; PCIe bus `00000000:01:00.0`; PCIe
  link speed and width: not measured. GPU clocks were not fixed.
- CPU: AMD Ryzen 9 7950X 16-Core Processor (32 logical CPUs).
- RAM: 46464 MiB installed.
- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic; NVIDIA driver 610.57.04; CUDA release 13.4, V13.4.92.
- Strata commit `99f3dbd0b21d1401b3769e0c0d963913607f380b` (branch `main`); engine 0.1.38, the release binary from
  the repository's `engine/` directory.
- Background workloads: a dsh/Authentik/Caddy web stack and stock Ubuntu services. The GPU was dedicated to Strata,
  the operating system was not isolated.

## Model and configuration

- Model: `qwen3.8-flash-next-iq3_s` (the Strata server's model name),
  `Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf` + `-00002-of-00002.gguf`. Filenames and sizes are in the
  config copy; hashes were not recorded. The native pack is `Strata-data/packs/iq3_s`, the MTP draft layer
  `Strata-data/mtp/rt`, the expert profile starts from `data/expert-profile-learned-iq3s.bin`.
- Context 143,360; INT8 KV; `--resident-experts` (the experts the GPU does not hold stay in RAM); GPU vision;
  `--prefill auto`; `--expert-cache auto`; `--spec 4 --spec-min-p 0.5`; `--vram-reserve-mib 989`; the experimental
  speed projection (`--control-vector-scaled … :1.0`, layers 4–44, `--cvec-mode project`).
- Draft vocabulary subset: `draft_vocab=cyrillic` (the English/code subset plus the whole Cyrillic script, ~106k
  rows). This is wider than the default `en` subset; draft acceptance on English text was unaffected (78–80%), but it
  can cost a few percent of decode speed.

```text
/home/dgbox/Strata/engine/strata --serve --pack /home/dgbox/Strata-data/packs/iq3_s --native /home/dgbox/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf --ple-gguf /home/dgbox/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf --expert-profile /home/dgbox/Strata/data/expert-profile-learned-iq3s.bin --expert-cache auto --prefill auto --spec 4 --mtp /home/dgbox/Strata-data/mtp/rt --max-context 143360 --kv int8 --resident-experts --vision --vram-reserve-mib 989 --control-vector-scaled /home/dgbox/Strata/data/experimental-speed-projection/Qwen3.8-Flash-Next-experimental-speed-projection.gguf:1.0 --control-vector-layer-range 4 44 --cvec-mode project --cvec-dir per-layer --spec-min-p 0.5 --expert-profile-save /home/dgbox/Strata/data/expert-profile-learned-iq3s.bin --expert-profile-save-every 10
```

Full server config: [config.json](config.json).

## Method

- Warm-up: one 4K-token prompt (64 generated tokens), excluded from the measurements.
- Every measured prompt carries a random marker, so the prompt-prefix cache is not reused; the `Reused tokens` column
  reports the actual reused counts from the engine (0 in every measured run).
- Throughput comes from the engine's timing fields (`prompt_per_second` / `predicted_per_second`). TTFT is the time
  to the first non-empty streaming delta, ignoring keep-alives and empty deltas. Total latency (wall) is the whole
  request time measured at the client.
- `temperature=0`, `reasoning_effort=none`, a 256-token output cap (1,024 for the generation-only case). The model
  often stops early on this repetitive text; the actual generated lengths are in every table.
- The expert cache was warmed by the warm-up run and earlier sessions; the expert profile state is in the config copy.
- Memory: peak VRAM/RAM sampled every 2 seconds during the measured runs, plus a start snapshot.

## Results

Code-explanation prompts ([runs-code.json](runs-code.json), [needles-code.json](needles-code.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 105 | 3 | 2058.6 (range 2057.9-2061.4, n=3) | 77.5 (range 77.5-96.6, n=3) | 1.95 s (range 1.95-1.95, n=3) |
| 32768-prompt | 31307 | 0 | 103 | 3 | 2948.0 (range 2944.4-2971.6, n=3) | 97.2 (range 96.0-97.6, n=3) | 10.71 s (range 10.63-10.72, n=3) |
| 131072-prompt | 125011 | 0 | 103 | 3 | 3047.8 (range 3047.7-3050.2, n=3) | 84.4 (range 83.6-92.5, n=3) | 41.32 s (range 41.29-41.33, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 226.0 (range 218.7-236.0, n=3) | 88.7 (range 67.9-92.3, n=3) | 0.74 s (range 0.71-0.77, n=3) |

Russian prose ([runs-ru.json](runs-ru.json), [needles-ru.json](needles-ru.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 102 | 3 | 2084.2 (range 2078.8-2086.5, n=3) | 76.1 (range 62.4-91.3, n=3) | 1.96 s (range 1.96-1.97, n=3) |
| 32768-prompt | 31828 | 0 | 102 | 3 | 2991.1 (range 2987.3-2997.6, n=3) | 102.5 (range 101.9-104.2, n=3) | 10.78 s (range 10.75-10.79, n=3) |
| 131072-prompt | 127228 | 0 | 102 | 3 | 3077.9 (range 3075.9-3079.6, n=3) | 102.2 (range 97.7-105.2, n=3) | 41.81 s (range 41.8-41.86, n=3) |
| gen-only | 228 | 0 | 826 | 3 | 312.6 (range 305.6-314.0, n=3) | 65.9 (range 54.6-66.5, n=3) | 0.75 s (range 0.74-0.77, n=3) |

- Total latency (client, wall): code — 3.3 / 11.77 / 42.45 / 11.82 s; ru — 3.29 / 11.77 / 42.82 / 13.18 s
  (4096 / 32768 / 131072 / gen-only; ranges in the JSON).
- Memory: peak VRAM 22116 MiB in both arms. RAM in use was 46.3 GiB at start and peaked at 46.9 GiB — this is the
  resident-experts variant, where the experts the card does not hold are held in system RAM. On a 48 GB PC that
  leaves very little headroom, and it is the reason this machine was later moved to the IQ3_XXS configuration.
- Every measured run stopped at ~103 generated tokens on its own, well below the 256-token cap. The decode column is
  therefore a measurement of short answers, and the `gen-only` case (which runs to the 1,024-token cap) is the only
  decode number here comparable with other reports.

## Correctness and limitations

- Speed measurements do not establish answer quality. The recall check passed 6/6 at 32K and 128K across depths
  10/50/90 in both arms; see the `needles-*.json` files.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and
  draft acceptance.
- One machine, one model, one context, three runs per configuration, one engine version. No version comparison was
  made in this report; the version chain for this PC is in the IQ3_XXS folder linked above.
