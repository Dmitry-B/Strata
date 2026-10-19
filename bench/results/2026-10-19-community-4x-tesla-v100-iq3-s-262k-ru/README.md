# Community benchmark: 4x NVIDIA Tesla V100-SXM2-16GB (Minisforum MS-01), Russian-style prompts

Measured on 2026-10-19 by [Dmitry-B](https://github.com/Dmitry-B). Same machine, same model, same config and the same swapped-tree A/B as [the code-style report](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/README.md), only with Russian prompt text: Strata 0.1.45 against 0.1.44.1, `qwen3.8-flash-next-iq3_s`, 262144-token context, greedy decoding, 256-token output cap, three runs per configuration. Synthetic workloads; they say nothing general about answer quality.

**Headline: the first ordering showed 0.1.45 reading long Russian prompts 6.5-7.1% slower than 0.1.44.1. That gap is not the release: measured seat by seat, 0.1.45 gives the same numbers whichever order it is run in (spread 0.02-0.5%), while 0.1.44.1 gains 1.9-7.8% just by being the second engine to run. Same-seat comparisons differ by at most 0.8%. Recall is unchanged (6/6 needles at 32K and 128K in both versions, 3/3 at 243990 tokens).**

## Hardware and software

Identical to the code-style run of the same session — see [../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/README.md](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/README.md) for the full provenance. Short version:

- Host: Minisforum MS-01 (DMI `Micro Computer (HK) Tech Limited` / `Venus Series`, board AHWSA, BIOS AHWSA.1.22 of 2024-03-12), i9-13900H (20 logical CPUs, one NUMA node), 96 GB DDR5 (`MemTotal` 91.7 GiB usable), one NVMe drive (SOLIDIGM `SSDPFKKW020X7`, 2.05 TB) which holds the model files, 2x10GbE SFP+ + 2.5GbE. Ubuntu 26.04.1, kernel 7.0.0-38-generic, driver 580.178.04.
- Cards and their path: 4x Tesla V100-SXM2-16GB (sm_70, 16384 MiB, 300 W limit, persistence enabled, NV2 NVLink between every pair - 6 links per card at 25.781 GB/s), on a 4-GPU SXM2 carrier board behind a PEX 8748 Gen3 switch; the host side of that switch is an x8 @ 8.0 GT/s root port, and each card links at x8 @ 8.0 GT/s too. Clocks were not fixed (sampled 1312/877 MHz). The raw probe output is in [host-provenance.txt](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/host-provenance.txt).
- No system CUDA: a private CUDA 12.8 toolkit (nvcc 12.8.93) and private gcc-14 under `~/strata185/`; **both engines built from source on this machine** for `sm_70` with `STRATA_EXPERIMENTAL_SM60=ON` (`BUILD.json` says `"source": "local"` in both trees). No git on this machine; versions read from `/props` and `BUILD.json`. No DCGM — no colouring or kernel-level profiling.
- Provenance of this run: [env.json](env.json) (`engine_version`, `model_alias`), server config: [config.json](config.json), driver scripts: [scripts/](scripts/).

## Model and configuration

`qwen3.8-flash-next-iq3_s`, context 262144, INT8 KV, `--layer-split auto` + `--expert-cache auto` + `--mmap-experts`, `--spec 4` with an MTP draft, control vector (`--cvec-mode project`, layers 4-44), GPU vision, one slot, port 8080, `draft_vocab=cyrillic` (set in the server config). Engine self-description at start is identical in both versions: `layer split: 97% of the experts resident, the prompt path's streamed ring 96 slots`, `prompt chunk auto: 8192 tokens`, `adaptive overlap: off: not on a layer split`. The same lines with their per-session counts are in [engine-start-lines-comparison.txt](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/engine-start-lines-comparison.txt); that file also explains that each tree keeps its own copy of the engine log (the config's `log` path lives inside the tree directory), so the 0.1.44.1 sessions of this cycle are recorded in the `.bak` tree's copy. The two run-config files are byte-identical.

## Method

Same script and the same protocol as the code report: warm-up (a 4K prompt, discarded), random marker in every prompt so nothing is reused, speeds from the engine's timing fields (`prompt_per_second` / `predicted_per_second` in the final stream chunk), TTFT measured at the client over streaming, temperature 0, `reasoning_effort=none`, 256-token cap (1024 in the generation-only case), VRAM/RAM sampled every 2 s.

Order in the session: warm-up → 0.1.45 → needles → **control run on the same 0.1.45 binary** → stop with SIGINT → swap the trees → warm-up → 0.1.44.1 → needles → swap back. After the 6.5-7.1% gap appeared, the long cases were measured again **with the order reversed** (`runs-reverse-0.1.44.1-first.json`, `runs-reverse-0.1.45-second.json`), and the short and middle cases a third time in the reversed order (`runs-reverse2-0.1.44.1-first.json`, `runs-reverse2-0.1.45-second.json`). **Observer traffic: none** — the agent running these measurements is served by a different machine (an RTX 4090 box).

The scripts in `scripts/` carry English comments and English log strings; every command in them is the command that was run. The Russian workload paragraph and the `[метка N]` marker stay exactly as they were sent to the model — they are the measured input.

## Results — 0.1.45 (first ordering)

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 4028 | 0 | 256 | 3 | 882.9 (range 874.5-884.3, n=3) | 74.9 (range 68.7-88.8, n=3) | 4.59 (range 4.6-4.6, n=3) s |
| 16384-prompt | 15928 | 0 | 102 | 3 | 1536.5 (range 1526.7-1542.4, n=3) | 88.4 (range 88.0-88.6, n=3) | 10.40 (range 10.4-10.5, n=3) s |
| 32768-prompt | 31828 | 0 | 102 | 3 | 1907.3 (range 1904.6-1910.7, n=3) | 84.3 (range 83.8-85.3, n=3) | 16.73 (range 16.7-16.8, n=3) s |
| 66560-prompt | 64628 | 0 | 102 | 3 | 2249.2 (range 2245.6-2257.0, n=3) | 86.6 (range 85.8-86.7, n=3) | 28.79 (range 28.7-28.8, n=3) s |
| 131072-prompt | 127228 | 0 | 102 | 3 | 2393.3 (range 2390.1-2395.9, n=3) | 83.4 (range 82.9-83.5, n=3) | 53.25 (range 53.2-53.3, n=3) s |
| 194560-prompt | 188828 | 0 | 102 | 3 | 2433.2 (range 2433.1-2436.4, n=3) | 81.4 (range 80.8-81.6, n=3) | 77.72 (range 77.6-77.7, n=3) s |
| 209715-prompt | 203528 | 0 | 102 | 3 | 2450.0 (range 2449.2-2451.8, n=3) | 81.0 (range 80.8-82.1, n=3) | 83.19 (range 83.1-83.2, n=3) s |
| 249037-prompt | 241728 | 0 | 256 | 3 | 2428.0 (range 2426.7-2429.2, n=3) | 68.3 (range 59.5-80.2, n=3) | 99.70 (range 99.7-99.8, n=3) s |
| 268000-prompt | 260128 | 0 | 256 | 3 | 2426.6 (range 2425.1-2427.9, n=3) | 65.5 (range 57.2-65.6, n=3) | 107.36 (range 107.3-107.4, n=3) s |
| gen-only | 228 | 0 | 449 | 3 | 236.6 (range 236.0-242.2, n=3) | 66.1 (range 65.3-72.7, n=3) | 0.99 (range 1.0-1.0, n=3) s |

- Total latency (client, wall): 4096 - 7.99 s (5.83-8.31); 16384 - 11.53 s (11.48-11.56); 32768 - 17.93 s (17.88-17.93); 66560 - 29.95 s (29.91-29.99); 131072 - 54.45 s (54.40-54.48); 194560 - 78.95 s (78.79-79.00); 209715 - 84.42 s (84.39-84.45); 249037 - 103.39 s (101.02-104.01); 268000 - 111.28 s (111.19-111.34); gen-only - 7.26 s (7.08-8.44).
- Draft acceptance: 4K 243/442 (55%); 16K 165/207 (80%); 32K 165/224 (74%); 66K 165/198 (83%); 131K 165/204 (81%); 194K 165/203 (81%); 209K 165/196 (84%); 249K 243/406 (60%); 268K 265/470 (56%); gen-only 441/1103 (40%).
- Memory peaks (2 s samples): 15258 / 15676 / 15914 / 16144 MiB per GPU (of 16384), RAM 11470820 KiB (10.9 GiB); the 7 MiB minimums are the window when the engine was stopped for the swap — [memory-samples.csv](memory-samples.csv).
- Raw per-run data: [runs.json](runs.json); control run of the same binary: [runs-0.1.45-control.json](runs-0.1.45-control.json); 0.1.44.1: [runs-0.1.44.1-baseline.json](runs-0.1.44.1-baseline.json). Recall: [needles.json](needles.json), [needles-long.json](needles-long.json), [needles-0.1.44.1.json](needles-0.1.44.1.json), [needles-long-245k.json](needles-long-245k.json).

## Comparison with 0.1.44.1

### First ordering (0.1.45 measured first)

| case (actual prompt tokens) | 0.1.45 | 0.1.45 control (same binary) | 0.1.44.1 | new vs baseline |
|---|---:|---:|---:|---:|
| 4096 (4028) | 882.9 | 884.5 | 893.2 | −1.15% |
| 16384 (15928) | 1536.5 | 1542.1 | 1563.5 | −1.73% |
| 32768 (31828) | 1907.3 | 1908.7 | 1986.2 | −3.97% |
| 66560 (64628) | 2249.2 | 2251.8 | 2369.2 | −5.07% |
| 131072 (127228) | 2393.3 | 2391.2 | 2573.1 | −6.99% |
| 194560 (188828) | 2433.2 | 2434.9 | 2619.1 | −7.10% |
| 209715 (203528) | 2450.0 | 2448.9 | 2630.1 | −6.85% |
| 249037 (241728) | 2428.0 | 2426.2 | 2592.8 | −6.36% |
| 268000 (260128) | 2426.6 | 2431.2 | 2596.5 | −6.54% |
| gen-only (228) | 236.6 | 241.9 | 249.1 | −5.02% |

The control run of the *same* 0.1.45 binary sat within 0.15-0.5% of the main run at every length, so this ordering really does show a 6-7% gap between the two trees — and it looked like a regression. Two things made it suspicious: the same session measured **no** difference at all in the code style (all deltas −0.10…−0.39%, see the code report), and 0.1.44.1 was always the second engine to run.

### Reversed ordering, long cases (0.1.44.1 measured first)

| case (actual prompt tokens) | 0.1.44.1 (first) | 0.1.45 (second) | first vs second |
|---|---:|---:|---:|
| 131072 (127228) | 2387.1 (n=3) | 2390.6 (n=3) | −0.15% |
| 194560 (188828) | 2430.1 (n=3) | 2432.8 (n=3) | −0.11% |
| 209715 (203528) | 2444.1 (n=3) | 2444.6 (n=3) | −0.02% |

Files: [runs-reverse-0.1.44.1-first.json](runs-reverse-0.1.44.1-first.json), [runs-reverse-0.1.45-second.json](runs-reverse-0.1.45-second.json). The script: [scripts/ab-ru-and-tests-185.sh](scripts/ab-ru-and-tests-185.sh).

Read the two tables together:

- 0.1.45 in the first seat: 2393.3 / 2433.2 / 2450.0. 0.1.45 in the second seat: 2390.6 / 2432.8 / 2444.6. **The same version lands in the same band whichever seat it is given.**
- 0.1.44.1 in the second seat: 2573.1 / 2619.1 / 2630.1. 0.1.44.1 in the first seat: 2387.1 / 2430.1 / 2444.1. **0.1.44.1 moved by 7.6-7.8% depending on the seat, while 0.1.45 moved by 0.02-0.11%.**

So the 6-7% is not a property of the release but of the machine state at the moment of measurement: an engine that runs after another engine of the same model and config has been working with the same prompts can get markedly faster at long Russian contexts (page cache and the learned expert profile are the plausible carriers; this was not isolated further). The seat-controlled comparison — the only one that separates version from order — shows **no difference between 0.1.45 and 0.1.44.1**; the full 2x2 is in the next section.

### Second reversal, short and middle cases (0.1.44.1 first, then 0.1.45)

The same check for 4096 / 32768 / 65792 target tokens (4028 / 31828 / 64628 actual), one session, warm-up + 3 reps per case: [runs-reverse2-0.1.44.1-first.json](runs-reverse2-0.1.44.1-first.json), [runs-reverse2-0.1.45-second.json](runs-reverse2-0.1.45-second.json), script [scripts/reverse2-185.sh](scripts/reverse2-185.sh), full transcript of that session: [reverse2-run.log](reverse2-run.log).

Two notes about that transcript: it keeps the machine's original stage markers, which were written in Russian when the session ran (the script committed here is the same script with its comments and log strings translated to English, every command unchanged), and the script is named `reverse3-185.sh` on the machine — `reverse2` is the name of this case in the report.

#### Every arm of the 2x2: version x seat in the session (prompt tok/s medians)

| actual prompt tokens | 0.1.45, first seat | 0.1.45, second seat | 0.1.44.1, first seat | 0.1.44.1, second seat |
|---:|---:|---:|---:|---:|
| 4028 | 882.9 (main), 884.5 (control) | 883.9 | 876.2 | 893.2 |
| 31828 | 1907.3, 1908.7 | 1915.4 | 1915.2 | 1986.2 |
| 64628 | 2249.2, 2251.8 | 2261.2 | 2255.8 | 2369.2 |
| 127228 | 2393.3, 2391.2 | 2390.6 | 2387.1 | 2573.1 |
| 188828 | 2433.2, 2434.9 | 2432.8 | 2430.1 | 2619.1 |
| 203528 | 2450.0, 2448.9 | 2444.6 | 2444.1 | 2630.1 |

- **0.1.45 is seat-independent**: its first-seat and second-seat medians differ by 0.02-0.5% at every length.
- **0.1.44.1 is not**: in the first seat it matches 0.1.45 to within 0.0-0.8%; in the second seat it is 1.9-7.8% faster than its own first-seat numbers — and that second-seat state is the only thing that produced the "regression".
- Same-seat deltas (0.1.45 vs 0.1.44.1): +0.76% (4028), −0.41% (31828), −0.29% (64628), +0.26% (127228), +0.13% (188828), +0.24% (203528). **No version effect.**
- The 16384-token case (15928 tokens) was not re-measured in the reversed order; its −1.73% in the first ordering sits between the 4028 and 31828 rows, both of which are neutral when measured seat by seat.
- The 249037 and 268000 cases were only run in the first ordering (with the 0.1.45 control confirming 0.1.45's own band); the pattern holds at all six lengths where both seats of both versions were measured.

### Recall

- 32K and 128K, depths 10/50/90: **6/6 in 0.1.45 and 6/6 in 0.1.44.1**.
- Far length: `tools/needle_bench.py` at 250000 in the first session ended 1/3 — two requests failed (HTTP 400 and HTTP 503) in 0.1.45 while the same call succeeded in the code-style session at 249262 tokens; it was not reproduced. A clean re-run at 245000 gave **3/3 at 243990 tokens** ([needles-long-245k.json](needles-long-245k.json), 95.1-101.0 s). The code-style report has the matching 249262-token result for both versions (3/3 each).
- A 260128-token prompt (99.2% of the window) is served without errors in both versions.

## Correctness and limitations

- Speed measurements say nothing about answer quality; only the recall checks above do.
- The dominant finding is a **method warning for this machine**: absolute numbers for long Russian prompts drift by up to 8% between sessions of the same build, and the direction depends on which engine ran first. Single-run comparisons of two versions on this box are not trustworthy; only order-reversed or interleaved A/B is. The drift is not limited to one cycle: the engine log of 2026-10-14 records a 260331-token prompt on the same version (0.1.44.1) read in 102.1-102.9 s (2529-2549 tok/s), against 106.5-107.3 s (2425-2445 tok/s) for the same length in this cycle.
- The mechanism of the seat effect was not isolated (page cache vs learned expert profile vs CUDA graph state). The expert profile file (`--expert-profile-save`) is rewritten during runs, so the profile present at a start differs between sessions — plausible, unproven here.
- Not measured: the release's new opt-ins, other configurations (`--kv q4_0`, `--prefill-pipe`, the new CLI flags), concurrency (one slot), 1M context, `serve.test_winjob` / `serve.test_lifecycle`. The Python test suite is reported in [../2026-10-19-community-4x-tesla-v100-test-suite/README.md](../2026-10-19-community-4x-tesla-v100-test-suite/README.md).
- Prompts are synthetic Russian text with a random marker; the model stops early on repetitive text (the real answer lengths are in the table). The OS was not isolated (SSH sessions, stock services), the GPUs were dedicated to Strata.

## Trend

Same-machine earlier reports: `bench/results/2026-10-14-community-4x-tesla-v100-iq3-s-262k-*` (0.1.43 → 0.1.44.1, branch `bench/2026-10-14-rtx4090-v100-upstream`, PR Niko1221/Strata#2525) and `bench/results/2026-10-17-community-4x-v100-nvlink-platform` (branch `bench/2026-10-17-v100-nvlink-platform`, PR Niko1221/Strata#2905). Release-level comparisons on other hardware: `../2026-10-18-community-rtx4090-iq3s-200k-code/README.md` (0.1.45 vs 0.1.44.1 on RTX 4090, where the only regression found was `STRATA_DEQUANT_WIDE`, which does not apply to sm_70) and `../2026-10-18-community-rtx4090-iq3xxs-200k-code/README.md` (branch `bench/2026-10-18-rtx4090-0145`, PR Niko1221/Strata#3109). Those live in earlier `bench/*` branches.
