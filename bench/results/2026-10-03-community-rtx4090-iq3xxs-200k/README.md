# Community benchmark: RTX 4090, Ryzen 9 7950X, 48 GB RAM — qwen3.8-flash-next-iq3_xxs, 204,800-token context

Measured 2026-10-03 → 2026-10-06 by [Dmitry-B](https://github.com/Dmitry-B). Four arms of one configuration on one
PC: Strata **0.1.38, 0.1.39, 0.1.40 and 0.1.40.1**, each with two prompt arms — code-explanation text and Russian
prose — three runs per configuration at 4,096 / 32,768 / 131,072 prompt tokens plus a generation-only case, and six
recall checks per arm. Greedy decoding, a 256-token output cap (1,024 for the generation-only case), TTFT measured
over streaming.

Prompt throughput (the comparable column, from the engine's own timing) moved from 1,844 / 2,976 / 2,962 tok/s at
4K / 32K / 128K on 0.1.38 to 1,978 / 3,136 / 3,118 on 0.1.40; 0.1.40 → 0.1.40.1 moved nothing, which is the
expected result — that hotfix does not touch the engine, and the binary is byte-identical in both reports. Recall
passed 6/6 at 32K and 128K in every arm. The prompts are synthetic; these runs say nothing about answer quality.

## Files in this folder

| File | What it is |
| --- | --- |
| `benchmark.py` | the measurement script; one file, unchanged since 2026-10-03, used for all four arms (its comments are in Russian) |
| `config-0138.json` | the server config copy used for the 0.1.38 arm |
| `config-0139.json` | the server config copy used for the 0.1.39, 0.1.40 and 0.1.40.1 arms (identical in all three) |
| `env.json` | hardware / driver / model-file snapshot, collected once on 2026-10-04 |
| `runs-<version>-<arm>.json` | every run: prompt and generated token counts, engine timings, TTFT, wall time, memory samples, draft accepted/total |
| `runs-01401-code-cold.json`, `needles-01401-code-cold.json` | the discarded cold-start run of the 0.1.40.1 arm, published separately (see below) |
| `needles-<version>-<arm>.json` | the recall check of that arm (`tools/needle_bench.py`-style, 32K and 128K, depths 10/50/90) |

`<version>` is `0138`, `0139`, `0140`, `01401`; `<arm>` is `code` or `ru`.

## Hardware and software

Same machine for all four arms:

- GPU: NVIDIA GeForce RTX 4090; 23028 MiB reported VRAM; 480.00 W power limit; PCIe bus `00000000:01:00.0`; PCIe
  link speed and width: not measured. GPU clocks were not fixed.
- CPU: AMD Ryzen 9 7950X 16-Core Processor (32 logical CPUs); the engine used 10 expert-pool workers.
- RAM: 46464 MiB installed. Storage layout and model file list: [env.json](env.json).
- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic; NVIDIA driver 610.57.04; CUDA release 13.4, V13.4.92.
- Background workloads: a dsh/Authentik/Caddy web stack and stock Ubuntu services. The GPU was dedicated to Strata,
  the operating system was not isolated.
- Engine per arm: 0.1.38 and 0.1.39 — the release binaries from the repository's `engine/` directory; 0.1.40 — the
  release binary (md5 `196504f2822cbf15fb49b873e0000f41`); 0.1.40.1 — the **same binary**, not rebuilt (v0.1.40.1
  changes only the Python server; `git diff v0.1.40 v0.1.40.1 -- engine src tools/vision third_party
  CMakeLists.txt` is empty).
- Checkouts: 0.1.38 at `1d5e1ea`, 0.1.39 at `2900da3` (both on the branch `bench/2026-10-03-rtx4090-community`,
  i.e. upstream `main` of that day plus these report files); 0.1.40 at `1735d64` and 0.1.40.1 at `82f46a8`
  (upstream `main`).

## Model and configuration

- Model: `qwen3.8-flash-next-iq3_xxs` (the Strata server's model name),
  `Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf` + `-00002-of-00002.gguf`. Filenames, sizes and
  modification times are in `env.json`; hashes were not recorded. The native pack is `Strata-data/packs/iq3_xxs`,
  the MTP draft layer `Strata-data/mtp/rt`, the expert profile starts from `data/expert-profile.bin` and is saved
  to `data/expert-profile-learned.bin` every 10 requests.
- Context 204,800; INT8 KV, no `--kv-resident`; `--mmap-experts` with the experts resident in VRAM; GPU vision;
  `--prefill auto` (the engine logs `prompt chunk auto: 8192 tokens, a 96-slot ring` in every arm);
  `--expert-cache auto` (6,915–6,926 resident slots across the arms); `--spec 4 --spec-min-p 0.50`;
  `--vram-reserve-mib 989`; `--pcie-frac 0.00`; the experimental speed projection
  (`--control-vector-scaled … :1.0`, layers 4–44, `--cvec-mode project`) is on in every arm.
- Draft vocabulary subset: `draft_vocab=cyrillic` (the English/code subset plus the whole Cyrillic script, ~106k
  rows). This is wider than the default `en` subset; draft acceptance on English text was unaffected (78–80%), but
  it can cost a few percent of decode speed.
- Engine command line, identical in all four arms (as the server prints it at start):

```text
/home/dgbox/Strata/engine/strata --serve --pack /home/dgbox/Strata-data/packs/iq3_xxs --native /home/dgbox/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf --ple-gguf /home/dgbox/Strata-data/models/IQ3_XXS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00002-of-00002.gguf --expert-profile /home/dgbox/Strata/data/expert-profile-learned.bin --expert-cache auto --prefill auto --spec 4 --mtp /home/dgbox/Strata-data/mtp/rt --max-context 204800 --kv int8 --mmap-experts --vision --vram-reserve-mib 989 --control-vector-scaled /home/dgbox/Strata/data/experimental-speed-projection/Qwen3.8-Flash-Next-experimental-speed-projection.gguf:1.0 --control-vector-layer-range 4 44 --cvec-mode project --cvec-dir per-layer --pcie-frac 0.00 --spec-min-p 0.50 --pool-workers 10 --expert-profile-save /home/dgbox/Strata/data/expert-profile-learned.bin --expert-profile-save-every 10
```

- **The server config is not identical in all four arms.** [config-0138.json](config-0138.json) and
  [config-0139.json](config-0139.json) differ in three keys, none of which reaches the engine command line:
  `mcp_servers` (two MCP servers added to the server process), `"reasoning_effort": "low"` and
  `"fit_max_tokens": true`. The measured requests set `reasoning_effort: none`, `max_tokens` and `temperature: 0`
  themselves, so none of the three applied to a measured run; the MCP servers are extra host processes. The 0.1.39,
  0.1.40 and 0.1.40.1 arms use the same config file. The published copies have the MCP bearer token replaced with
  `removed`.

## Method

- Warm-up: one 4K-token prompt (64 generated tokens), excluded from the measurements.
- Every measured prompt carries a random marker, so the prompt-prefix cache is not reused; the `Reused tokens`
  column reports the actual reused counts from the engine (0 in every measured run).
- Throughput comes from the engine's timing fields (`prompt_per_second` / `predicted_per_second`). TTFT is the time
  to the first non-empty streaming delta, ignoring keep-alives and empty deltas; the first token is answer text
  (reasoning is off). Total latency (wall) is the whole request time measured at the client.
- `temperature=0`, `reasoning_effort=none`, a 256-token output cap (1,024 for the generation-only case). The model
  often stops early on this repetitive text; the actual generated lengths are in every table.
- The expert cache was warmed by the warm-up run and earlier sessions; the expert profile state is in the config
  copies.
- Memory: peak VRAM/RAM sampled every 2 seconds during the measured runs, plus a start snapshot.
- Measurement script: [benchmark.py](benchmark.py).

## Results

### 0.1.38 — measured 2026-10-03

Code-explanation prompts ([runs-0138-code.json](runs-0138-code.json), [needles-0138-code.json](needles-0138-code.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 256 | 3 | 1844.3 (range 1817.0-1880.3, n=3) | 118.0 (range 107.0-129.6, n=3) | 2.18 s (range 2.13-2.21, n=3) |
| 32768-prompt | 31307 | 0 | 256 | 3 | 2976.2 (range 2806.6-3016.6, n=3) | 127.9 (range 124.2-129.5, n=3) | 10.6 s (range 10.46-11.24, n=3) |
| 131072-prompt | 125011 | 0 | 256 | 3 | 2962.3 (range 2906.5-2964.9, n=3) | 108.4 (range 101.5-114.8, n=3) | 42.5 s (range 42.46-43.31, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 200.0 (range 194.1-213.8, n=3) | 133.0 (range 130.2-138.9, n=3) | 0.83 s (range 0.78-0.86, n=3) |

Russian prose ([runs-0138-ru.json](runs-0138-ru.json), [needles-0138-ru.json](needles-0138-ru.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 142 | 3 | 1823.8 (range 1797.2-1892.1, n=3) | 94.2 (range 80.1-95.2, n=3) | 2.24 s (range 2.16-2.27, n=3) |
| 32768-prompt | 31828 | 0 | 256 | 3 | 2912.0 (range 2793.9-2962.9, n=3) | 85.6 (range 74.9-86.8, n=3) | 11.06 s (range 10.87-11.52, n=3) |
| 131072-prompt | 127228 | 0 | 119 | 3 | 2984.2 (range 2957.9-2986.1, n=3) | 90.3 (range 86.2-102.8, n=3) | 43.11 s (range 43.08-43.5, n=3) |
| gen-only | 228 | 0 | 450 | 3 | 279.7 (range 274.0-297.8, n=3) | 82.9 (range 82.8-85.8, n=3) | 0.83 s (range 0.78-0.85, n=3) |

- Total latency (client, wall): code — 4.37 / 12.57 / 44.72 / 8.46 s; ru — 3.75 / 14.04 / 44.52 / 6.27 s
  (4096 / 32768 / 131072 / gen-only; ranges in the JSON).
- Memory: peak VRAM 22022 MiB in both arms; peak RAM 6.58 / 6.53 GiB.

### 0.1.39 — measured 2026-10-04

Code ([runs-0139-code.json](runs-0139-code.json), [needles-0139-code.json](needles-0139-code.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 256 | 3 | 1966.2 (range 1952.4-1967.7, n=3) | 123.6 (range 109.6-134.3, n=3) | 2.04 s (range 2.04-2.06, n=3) |
| 32768-prompt | 31307 | 0 | 256 | 3 | 2973.7 (range 2952.3-3130.1, n=3) | 134.9 (range 123.8-136.0, n=3) | 10.61 s (range 10.09-10.69, n=3) |
| 131072-prompt | 125011 | 0 | 183 | 3 | 3084.9 (range 3043.4-3109.1, n=3) | 120.3 (range 91.5-124.1, n=3) | 40.82 s (range 40.51-91.16, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 205.3 (range 204.7-219.0, n=3) | 135.8 (range 135.2-138.6, n=3) | 0.81 s (range 0.76-0.82, n=3) |

Russian prose ([runs-0139-ru.json](runs-0139-ru.json), [needles-0139-ru.json](needles-0139-ru.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 256 | 3 | 1907.8 (range 1851.9-1994.3, n=3) | 81.1 (range 80.6-90.5, n=3) | 2.14 s (range 2.05-2.2, n=3) |
| 32768-prompt | 31828 | 0 | 237 | 3 | 3128.0 (range 3086.6-3128.4, n=3) | 90.5 (range 87.3-105.8, n=3) | 10.31 s (range 10.3-10.44, n=3) |
| 131072-prompt | 127228 | 0 | 157 | 3 | 3126.4 (range 3057.4-3147.3, n=3) | 87.8 (range 85.3-94.5, n=3) | 41.17 s (range 40.89-42.09, n=3) |
| gen-only | 228 | 0 | 858 | 3 | 296.2 (range 291.7-306.6, n=3) | 93.6 (range 83.3-97.6, n=3) | 0.78 s (range 0.76-0.8, n=3) |

- Total latency (client, wall): code — 4.1 / 12.48 / 42.87 / 8.29 s; ru — 5.19 / 12.91 / 42.54 / 9.92 s.
- Memory: peak VRAM 22031 / 22030 MiB; peak RAM 6.67 / 6.70 GiB.
- **One code run is contaminated:** a 139,527-token request from this machine's own interactive client was served
  between two 131072-prompt runs (the server answers one sequence at a time), which is why that case's TTFT and
  wall ranges reach 91 s and 93 s. The engine-side timings of that run are unaffected (125,011 tokens at
  3,043 tok/s, in line with its two neighbours); only the client-side waiting is inflated.

### 0.1.40 — measured 2026-10-06

Code ([runs-0140-code.json](runs-0140-code.json), [needles-0140-code.json](needles-0140-code.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 256 | 3 | 1978.6 (range 1944.2-1983.9, n=3) | 130.1 (range 115.8-131.3, n=3) | 2.04 s (range 2.02-2.06, n=3) |
| 32768-prompt | 31307 | 0 | 256 | 3 | 3136.3 (range 2925.4-3142.2, n=3) | 136.4 (range 132.7-138.3, n=3) | 10.07 s (range 10.05-10.79, n=3) |
| 131072-prompt | 125011 | 0 | 256 | 3 | 3118.5 (range 3082.3-3122.6, n=3) | 124.1 (range 110.0-127.9, n=3) | 40.38 s (range 40.34-40.86, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 212.5 (range 206.1-221.6, n=3) | 143.2 (range 137.3-146.3, n=3) | 0.79 s (range 0.75-0.81, n=3) |

Russian prose ([runs-0140-ru.json](runs-0140-ru.json), [needles-0140-ru.json](needles-0140-ru.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 256 | 3 | 1893.8 (range 1554.3-1897.3, n=3) | 85.8 (range 78.1-94.1, n=3) | 2.16 s (range 2.15-2.62, n=3) |
| 32768-prompt | 31828 | 0 | 256 | 3 | 3125.6 (range 2923.2-3154.9, n=3) | 91.4 (range 85.1-93.1, n=3) | 10.31 s (range 10.22-11.03, n=3) |
| 131072-prompt | 127228 | 0 | 123 | 3 | 3136.4 (range 3092.2-3138.9, n=3) | 89.9 (range 89.3-110.6, n=3) | 41.06 s (range 41.03-41.62, n=3) |
| gen-only | 228 | 0 | 468 | 3 | 298.5 (range 290.6-301.1, n=3) | 87.8 (range 85.9-89.3, n=3) | 0.78 s (range 0.77-0.8, n=3) |

- Total latency (client, wall): code — 4.02 / 11.93 / 42.32 / 7.94 s; ru — 5.42 / 12.96 / 42.4 / 6.21 s.
- Memory: peak VRAM 22026 MiB in both arms; peak RAM 6.27 / 6.28 GiB.
- No run of this arm is contaminated: no other client's request was served between the measured runs, so its TTFT
  and wall columns are clean, and the 0.1.39 131072-prompt TTFT range (up to 91 s) is not a regression of 0.1.40.

### 0.1.40.1 — measured 2026-10-06

Code ([runs-01401-code.json](runs-01401-code.json), [needles-01401-code.json](needles-01401-code.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 256 | 3 | 1943.4 (range 1589.5-1949.7, n=3) | 123.6 (range 109.8-128.6, n=3) | 2.07 s (range 2.06-2.52, n=3) |
| 32768-prompt | 31307 | 0 | 256 | 3 | 3072.4 (range 2984.3-3093.0, n=3) | 131.8 (range 129.2-133.4, n=3) | 10.28 s (range 10.21-10.58, n=3) |
| 131072-prompt | 125011 | 0 | 256 | 3 | 3083.8 (range 3029.8-3087.1, n=3) | 117.2 (range 107.6-123.1, n=3) | 40.85 s (range 40.81-41.57, n=3) |
| gen-only | 163 | 0 | 1024 | 3 | 198.4 (range 181.6-209.5, n=3) | 138.7 (range 134.6-142.0, n=3) | 0.84 s (range 0.8-0.92, n=3) |

Russian prose ([runs-01401-ru.json](runs-01401-ru.json), [needles-01401-ru.json](needles-01401-ru.json)):

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 142 | 3 | 1909.2 (range 1872.4-1970.8, n=3) | 93.2 (range 85.3-93.8, n=3) | 2.14 s (range 2.07-2.18, n=3) |
| 32768-prompt | 31828 | 0 | 238 | 3 | 3105.2 (range 3097.1-3151.9, n=3) | 91.3 (range 79.1-91.9, n=3) | 10.38 s (range 10.22-10.41, n=3) |
| 131072-prompt | 127228 | 0 | 119 | 3 | 3119.7 (range 3098.4-3121.1, n=3) | 95.0 (range 82.5-95.3, n=3) | 41.26 s (range 41.26-41.54, n=3) |
| gen-only | 228 | 0 | 777 | 3 | 287.3 (range 282.5-302.5, n=3) | 95.1 (range 90.2-97.3, n=3) | 0.81 s (range 0.77-0.82, n=3) |

- Total latency (client, wall): code — 4.38 / 12.25 / 43.02 / 8.16 s; ru — 3.73 / 12.98 / 42.78 / 9.28 s.
- Memory: peak VRAM 22024 / 22022 MiB; peak RAM 6.40 / 6.40 GiB. RAM in use is the only column that moved between
  0.1.40 and 0.1.40.1, and it is the Python server process, not the engine.
- **Two earlier attempts of this arm are not in the table above.** 13:59, two minutes after the service restart:
  TTFT 60.9–62.1 s at 4096-prompt — contaminated by a large request from this machine's own interactive client, and
  discarded. 14:42: clean TTFT but a cold engine — kept aside as its own arm, below. The table above is the third
  attempt, after a full warm pass.

#### The cold run (kept aside): 14:42, right after an engine restart

([runs-01401-code-cold.json](runs-01401-code-cold.json), [needles-01401-code-cold.json](needles-01401-code-cold.json))

| Configuration | Actual prompt tokens | Generated tokens | Runs | Prompt tok/s median and range | TTFT s median |
| --- | ---: | ---: | ---: | --- | ---: |
| 4096-prompt | 3971 | 256 | 3 | 1812.7 (range 1751.8-1823.2, n=3) | 2.21 s |
| 32768-prompt | 31307 | 256 | 3 | 3076.5 (range 3033.6-3105.4, n=3) | 10.26 s |
| 131072-prompt | 125011 | 183 | 3 | 3056.6 (range 3046.5-3096.4, n=3) | 41.21 s |
| gen-only | 163 | 1024 | 3 | 209.6 (range 201.0-213.5, n=3) | 0.8 s |

TTFT is clean here (2.2 s), so this is not queue waiting: the engine had just been restarted, its expert cache and
the OS page cache were cold, and the short-prompt case came out 6.7% below the warm run of the same version
(1812.7 against 1943.4 at 4096-prompt). Recall 6/6. It is published as a measurement of a cold start, not as a
0.1.40.1 number.

## Prompt throughput across versions

The medians from the tables above, prompt tok/s only — the column that comes from the engine's own timing and whose
ranges are tight in every arm:

| Prompt tokens | 0.1.38 code | 0.1.39 code | 0.1.40 code | 0.1.40.1 code | 0.1.38 ru | 0.1.39 ru | 0.1.40 ru | 0.1.40.1 ru |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4,096 | 1,844 | 1,966 | 1,979 | 1,943 | 1,824 | 1,908 | 1,894 | 1,909 |
| 32,768 | 2,976 | 2,974 | 3,136 | 3,072 | 2,912 | 3,128 | 3,126 | 3,105 |
| 131,072 | 2,962 | 3,085 | 3,119 | 3,084 | 2,984 | 3,126 | 3,136 | 3,120 |
| gen-only (163 tok) | 200 | 205 | 213 | 198 | 280 | 296 | 299 | 287 |

## What moved between the versions

**0.1.38 → 0.1.39** (source build, same CUDA 13.4, same `sm_89`, same engine arguments, same expert profile; the
engine's auto prompt chunk is 8192 in both, so the byte-budget ring of #583 does not apply to this configuration):

| Configuration | Prompt tok/s code | Prompt tok/s ru | Decode tok/s code | TTFT s code |
| --- | --- | --- | --- | --- |
| 4096-prompt | 1844.3 → 1966.2 (+6.6%) | 1823.8 → 1907.8 (+4.6%) | 118.0 → 123.6 (+4.7%) | 2.18 → 2.04 |
| 32768-prompt | 2976.2 → 2973.7 (-0.1%) | 2912.0 → 3128.0 (+7.4%) | 127.9 → 134.9 (+5.5%) | 10.6 → 10.61 |
| 131072-prompt | 2962.3 → 3084.9 (+4.1%) | 2984.2 → 3126.4 (+4.8%) | 108.4 → 120.3 (+11.0%) | 42.5 → 40.82 |
| gen-only | 200.0 → 205.3 (+2.7%) | 279.7 → 296.2 (+5.9%) | 133.0 → 135.8 (+2.1%) | 0.83 → 0.81 |

**0.1.39 → 0.1.40** (source build, same arguments, same `expert-profile-learned.bin`, same auto prompt chunk):

| Configuration | Prompt tok/s code | Prompt tok/s ru | Decode tok/s code | TTFT s code |
| --- | --- | --- | --- | --- |
| 4096-prompt | 1966.2 → 1978.6 (+0.6%) | 1907.8 → 1893.8 (-0.7%) | 123.6 → 130.1 (+5.3%) | 2.04 → 2.04 |
| 32768-prompt | 2973.7 → 3136.3 (+5.5%) | 3128.0 → 3125.6 (-0.1%) | 134.9 → 136.4 (+1.1%) | 10.61 → 10.07 |
| 131072-prompt | 3084.9 → 3118.5 (+1.1%) | 3126.4 → 3136.4 (+0.3%) | 120.3 → 124.1 (+3.2%) | 40.82 → 40.38 |
| gen-only | 205.3 → 212.5 (+3.5%) | 296.2 → 298.5 (+0.8%) | 135.8 → 143.2 (+5.4%) | 0.81 → 0.79 |

- On code prompts 0.1.40 gained +0.6% at 4K, +5.5% at 32K and +1.1% at 128K; on Russian prompts prompt throughput
  is unchanged within noise (-0.7% … +0.8%).
- Draft acceptance on code prompts rose in every case (73.4% → 75.2%, 77.2% → 78.6%, 74.4% → 75.6%). On Russian
  text it fell at 4K and 32K (47.5% → 39.5%, 63.9% → 55.3%) and rose at 128K (58.8% → 61.5%) — with different
  generated lengths that is not a clean comparison either.

**0.1.40 → 0.1.40.1** (the engine binary is byte-identical, `196504f2822cbf15fb49b873e0000f41`; only
`serve/server.py` and `serve/frontend.py` changed):

| Configuration | Prompt tok/s code | Prompt tok/s ru | Draft accepted code |
| --- | --- | --- | --- |
| 4096-prompt | 1978.6 → 1943.4 (-1.8%) | 1893.8 → 1909.2 (+0.8%) | 498/662 → 496/672 |
| 32768-prompt | 3136.3 → 3072.4 (-2.0%) | 3125.6 → 3105.2 (-0.7%) | 503/640 → 499/652 |
| 131072-prompt | 3118.5 → 3083.8 (-1.1%) | 3136.4 → 3119.7 (-0.5%) | 409/541 → 407/559 |
| gen-only | 212.5 → 198.4 (-6.6%) | 298.5 → 287.3 (-3.8%) | 2049/2657 → 2050/2631 |

- The movement is -2.0% … +0.8%, which stays inside the spread of the 0.1.40 run itself (its own 32768-prompt
  range was 2925.4–3142.2, the 0.1.40.1 run's is 2984.3–3093.0). With an identical engine binary the honest reading
  is: **no change**. Draft acceptance is the same in every case, which is what an unchanged engine should produce.
- Peak VRAM 22026 → 22024 MiB. Recall 6/6 at 32K and 128K in both.

## What is comparable here and what is not

- **Prompt throughput is the comparable column.** It comes from the engine's own timing, the prompts are the same
  text at the same lengths, and the ranges are tight (for example 3043–3109 and 3082–3123 tok/s at 131072-prompt).
- **Decode medians are the least comparable column.** On this repetitive text the model stops early at a different
  point every run — at 131072-prompt the 0.1.39 arm generated 183 tokens in its median run and the 0.1.40 arm 256,
  and in the 0.1.40.1 arm the three repeats produced 256/256/142. A shorter answer does not have the same draft
  acceptance as a longer one. The `gen-only` case, which runs to the 1,024-token cap in every arm, is the only
  clean decode comparison; even there the amount of text decoded differs on Russian prompts (1306 tokens across the
  0.1.40 repeats against 2389 in 0.1.40.1), so its decode column moves for a reason that is not the version.
- **TTFT and wall time include queue waiting.** This machine also serves an interactive client; where such a request
  was in flight it is named in the arm that was affected, and only that arm's client-side columns are inflated.
- **A fresh restart is a measurement error, not a version difference.** A cold engine (empty expert cache, cold OS
  page cache) measured ~7% slower at short prompts; an agent request in flight made TTFT 30× larger. Both happened
  during this work and both are described above.
- **Russian prose is a separate workload, not a translation of the code arm.** At the same lengths it decodes
  81–95 tok/s against 117–143 for code-explanation text, in 0.1.39, 0.1.40 and 0.1.40.1 alike, while prompt
  throughput is the same. It is kept in every arm because that gap is the part a user of this model would notice.

## Correctness and limitations

- Speed measurements do not establish answer quality. The recall check passed 6/6 at 32K and 128K across depths
  10/50/90 in every arm of every version; see the `needles-*.json` files.
- The GPU was not fully isolated: background services may have added small noise.
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and
  draft acceptance.
- One machine, one model, one context, three runs per configuration. The 0.1.38 arm used a slightly different server
  config (see above) and was measured three days before the 0.1.40 arms.
