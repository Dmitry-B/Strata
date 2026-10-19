# Community benchmark: 4x NVIDIA Tesla V100-SXM2-16GB (Minisforum MS-01), code-style prompts

Measured on 2026-10-19 by [Dmitry-B](https://github.com/Dmitry-B). This tests Strata 0.1.45 against 0.1.44.1 with `qwen3.8-flash-next-iq3_s` and a 262144-token context on four Volta cards. Prompts are code-explanation text; greedy decoding, a 256-token output cap, three runs per configuration; TTFT measured over streaming. These are synthetic workloads; they do not establish general answer quality.

**Headline: prompt reading is unchanged at every length from 4K to 260K (every delta sits inside the same-binary control band), and the far-length recall is unchanged. One apparent effect in the Russian-style run of the same session turned out to be measurement order, not the release — that is isolated in [the ru report](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-ru/README.md).**

## Hardware and software

### The host — a Minisforum MS-01 mini-workstation

Everything in this block was read on 2026-10-19 from `/sys/class/dmi/id`, `lscpu`, `/proc/meminfo`, `lsblk`, `lspci`, sysfs PCIe attributes and `nvidia-smi`. The raw output is committed as [host-provenance.txt](host-provenance.txt), produced by [scripts/host-probe-185.sh](scripts/host-probe-185.sh); it was taken after the measurement session had finished, so the idle GPU numbers in it are not measurement data.

- Chassis (DMI): `sys_vendor = Micro Computer (HK) Tech Limited`, `product_name = Venus Series`, `board_name = AHWSA`, `board_vendor = Shenzhen Meigao Electronic Equipment Co.,Ltd`, `bios_vendor = American Megatrends International, LLC`, `bios_version = AHWSA.1.22` dated 2024-03-12, `chassis_type = 3` (server), UEFI boot. This is the machine sold as a **Minisforum MS-01**.
- CPU: 13th Gen Intel Core i9-13900H, 20 logical CPUs, one NUMA node, boost up to 5400 MHz, 24 MiB L3.
- RAM: 96 GB DDR5 installed; `MemTotal = 96228068 KiB` (91.7 GiB usable). Four DIMM slots are visible in the EDAC sysfs (`MC#0/1_Chan#0/1_DIMM#0`); module sizes are only readable with root and were not read (there is no sudo on this machine). RAM is not a limiting resource here: the whole cycle peaked at 11.0 GiB of the 91.7 available.
- Storage: one drive, NVMe `SOLIDIGM SSDPFKKW020X7` (P44 Pro), 2.05 TB, ext4 root; the model files used by this benchmark live on it (`model_path` under `~/strata185/Strata-data/models/IQ3_S/`). There is no second disk on this machine.
- Network: Intel Ethernet Controller X710 for 10GbE SFP+ x2, Intel I226-V (2.5GbE), Intel I226-LM. During the runs the only external traffic was the SSH sessions of the measurement scripts.
- Power and cooling: the four modules are liquid-cooled (a 360 mm AIO on the GPU board), which is what the carrier board's manual requires. This is a physical property of the build, recorded for this machine in the earlier cycle; the software side shows the cards holding their 300.00 W SXM2 power limit with clocks not fixed (sampled during the runs: SM 1312 MHz / memory 877 MHz against maximums 1530 / 877 MHz).

### The cards and the PCIe path to them

- 4x NVIDIA Tesla V100-SXM2-16GB, `GV100GL [10de:1db1]`, compute capability 7.0, 16384 MiB each, power limit 300.00 W, max clocks 1530 / 877 MHz, persistence mode Enabled. Serials `1323920036046`, `0324218160473`, `0323517036572`, `1422119022723` - so another report about "the same V100 box" can be checked against the same physical modules.
- These are SXM2 modules, not PCIe cards: they sit on a third-party 4-GPU SXM2 carrier board (Spring V100 SXM2 4-GPU, revision V100-SXM2-NVLINK_D V2.10). The board model itself is a physical fact recorded for this machine in the earlier cycle - what the OS can see is what is behind it: a **PLX/Broadcom PEX 8748** Gen3 switch (`[10b5:8748]`) at `0000:01:00.0`, with the four GPUs enumerated under it at `03:00.0`..`06:00.0`.
- Host side of that switch: the CPU root port `0000:00:01.0` (Raptor Lake PEG010). It trains as **x8 at 8.0 GT/s** (`current_link_width = 8`, `max_link_width = 8`), and each GPU also links at x8 / 8.0 GT/s. Four x8 downlinks share one x8 uplink - a 4:1 oversubscription with a ~7.9 GB/s ceiling per direction. The consequence was measured in the earlier cycle on this machine (PR Niko1221/Strata#2905): 6.29 GB/s host→device for one card alone, 1.56 GB/s per card when all four stream at once. That is why this machine is interesting for `--layer-split` and why its absolute numbers are not comparable with a desktop card on a full x16.
- NVLink is live on every pair: `nvidia-smi topo -m` reports `NV2` between any two of the four cards; `nvidia-smi nvlink -s` reports 6 links per GPU at 25.781 GB/s (the link throughput itself was measured in the earlier cycle, see "Trend").

### Software on this machine

- Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic, NVIDIA driver 580.178.04. There is **no system CUDA toolkit** on this machine (`nvcc` is not in PATH; the system compiler `gcc 15.2.0` is in PATH but is not what the engines were built with): a CUDA 12.8 toolkit (nvcc 12.8.93) and gcc-14 (14.3.0) are unpacked under `~/strata185/` and used only for these builds (`-DCMAKE_CUDA_COMPILER=$HOME/strata185/cuda-12.8/bin/nvcc -DCUDAToolkit_ROOT=$HOME/strata185/cuda-12.8 -DCMAKE_C_COMPILER=$HOME/strata185/gcc185/usr/bin/gcc-14`).
- **Both engines are built from source on this machine**, from the release source trees, for `sm_70` with `STRATA_EXPERIMENTAL_SM60=ON`. `engine-cuda12/BUILD.json` reads `"source": "local", "version": "0.1.45", "backend": "cuda", "archs": [70]` in the new tree and the same with `"version": "0.1.44.1"` in the previous tree — the two versions were built with the same private toolkit, the same compiler and the same build script. The GitHub v0.1.45 Linux archive contains no engine binary, so a local build is the only path here.
- **No git on this machine**: both trees are unpacked release source archives (`v0.1.45`, `v0.1.44.1`); versions are read from `/props` (`"build_info": "Strata 0.1.45"`) and from `BUILD.json`, not from `git describe`. `env.json` records the tree paths.
- DCGM / `genqprof` are not installed on this machine: **no colouring, PCIe or kernel-level profiling in this report** — only end-to-end timings.

## Model and configuration

- Model: `qwen3.8-flash-next-iq3_s` (the server's model name; GGUF names, sizes and mtimes in env.json, no hashes).
- Context 262144, INT8 KV, `--layer-split auto` with `--expert-cache auto` and `--mmap-experts`, `--spec 4` + an MTP draft model, `--spec-min-p 0.50`, control vector (`--cvec-mode project`, layers 4-44), GPU vision, `--vram-reserve-mib 512`, one slot, port 8080.
- Draft vocabulary subset: `draft_vocab=cyrillic` (set in the server config, not in the command line) — wider than the default `en` subset.
- Engine self-description at start matches between the two versions on every line that defines this configuration, and the two run-config files are byte-identical (`diff` empty):

  ```text
  strata serve: layer split: 97% of the experts resident, the prompt path's streamed ring 96 slots
  strata serve: prompt chunk auto: 8192 tokens, a 96-slot ring
  strata serve: the prompt path borrows 1954 CUDA0 cache slots (3.41 GiB)   # 1841 / 1710 / 1654 on CUDA1-3
  strata serve: adaptive overlap: off: not on a layer split
  ```

  The auto prompt chunk is 8192 tokens in 0.1.45 and in 0.1.44.1. What does vary is the free VRAM reported while the verify graphs are captured: 158-170 MiB in the 0.1.45 sessions of this cycle and 156-172 MiB in the 0.1.44.1 ones. Both versions log `strata verify: capturing the 6-token window (<N> MiB of VRAM free)` - the line does not name the card; the tight card in the 2 s samples is `CUDA3` (16144 of 16384 MiB). In some sessions of both versions the engine suggests `--vram-reserve-later-mib 1108`. Nothing was changed here for the measurements.

  [engine-start-lines-comparison.txt](engine-start-lines-comparison.txt) collects those lines per session and per version. It also records where the logs are, because it matters for reading them: the config's `"log"` is `/home/dgbox/strata185/Strata/strata-185-iq3_s.log`, a path **inside the tree directory**, so every session writes into the copy that belongs to whichever tree is installed at `~/strata185/Strata` at that moment. The two trees hold two copies of this machine log; they are identical up to 2026-10-19 02:10:31 (the last 0.1.44.1 session before the update) and diverge from there - the 0.1.45 copy carries the 9 0.1.45 sessions of this cycle, the 0.1.44.1 copy carries its 7. The resident share printed at start is 97% in every 0.1.45 session here and 96-99% across 0.1.44.1 sessions: it follows the memory free at start, so it is a start condition, not a version difference. The run config itself is the same: the two `strata-185-iq3_s.json` files, one per tree, are byte-identical (`diff` empty).
- Full server config: [config.json](config.json) (was at `~/strata185/Strata/strata-185-iq3_s.json`), provenance: [env.json](env.json), the driver scripts: [scripts/](scripts/).

## Method

- Warm-up: a 4K-token prompt (64 generated tokens), discarded.
- Every measured prompt carries a random marker, so the prompt-prefix cache is not reused; the "Reused" column reports the engine's own reused-token counts (0 in every run).
- Prompt and decode speeds come from the engine's own timing fields (`prompt_per_second` / `predicted_per_second` in the final stream chunk, with `/v1/status.last_timings` as a fallback). TTFT is the time to the first non-empty streaming delta at the client; `wall` is the whole request time.
- temperature=0, `reasoning_effort=none`, 256-token output cap (1024 for the generation-only case). The model stops early on repetitive text; the real answer lengths are in the table and in `runs.json`.
- Sequence in one session: warm-up → 0.1.45 measurement → needle checks → **control run on the same 0.1.45 binary** (this is the method's noise band) → stop with SIGINT, swap the tree (`Strata` → `Strata-0.1.44.1.bak`, `dl/Strata-0.1.45` → `Strata`), 25 s pause → warm-up → 0.1.44.1 measurement → needle checks → swap back and verify `/props` + a test query.
- Memory: VRAM per GPU and RAM sampled every 2 s across the whole session ([memory-samples.csv](memory-samples.csv)); the minimum (7 MiB) is the window when the engine was stopped for the swap.
- **Observer traffic: none.** The agent that ran these measurements is served by a different machine (an RTX 4090 box, `qwen3.8-flash-next-iq3_xxs`); nothing but the measurement scripts and their SSH sessions touched this server during the runs.
- The scripts here carry English comments and English log strings; every command in them is the command that was run. Text that is part of the measured input is kept as it was sent: the `[метка N]` marker inside every prompt (code style too), and the Russian verification query in the swap scripts.

## Results — 0.1.45

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT s median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 4096-prompt | 3971 | 0 | 182 | 3 | 873.2 (range 868.8-873.5, n=3) | 96.6 (range 94.3-108.8, n=3) | 4.57 (range 4.6-4.6, n=3) s |
| 16384-prompt | 15667 | 0 | 204 | 3 | 1523.3 (range 1520.6-1527.9, n=3) | 97.4 (range 93.8-108.7, n=3) | 10.32 (range 10.3-10.3, n=3) s |
| 32768-prompt | 31307 | 0 | 149 | 3 | 1896.8 (range 1895.2-1903.3, n=3) | 110.6 (range 103.9-111.1, n=3) | 16.55 (range 16.5-16.6, n=3) s |
| 66560-prompt | 63539 | 0 | 106 | 3 | 2235.4 (range 2230.2-2241.6, n=3) | 120.6 (range 119.7-121.8, n=3) | 28.48 (range 28.4-28.5, n=3) s |
| 131072-prompt | 125011 | 0 | 167 | 3 | 2376.6 (range 2370.6-2377.8, n=3) | 91.2 (range 90.3-100.0, n=3) | 52.70 (range 52.7-52.8, n=3) s |
| 194560-prompt | 185531 | 0 | 166 | 3 | 2452.0 (range 2448.6-2455.6, n=3) | 89.8 (range 88.9-91.8, n=3) | 75.79 (range 75.7-75.9, n=3) s |
| 209715-prompt | 200015 | 0 | 167 | 3 | 2439.8 (range 2438.6-2443.7, n=3) | 91.6 (range 88.0-101.4, n=3) | 82.11 (range 82.0-82.2, n=3) s |
| 249037-prompt | 237483 | 0 | 97 | 3 | 2455.8 (range 2449.9-2456.5, n=3) | 100.4 (range 87.8-103.0, n=3) | 110.58 (range 97.1-111.3, n=3) s |
| 273000-prompt | 260331 | 0 | 106 | 3 | 2438.7 (range 2438.4-2438.8, n=3) | 101.6 (range 88.9-102.8, n=3) | 106.92 (range 106.9-106.9, n=3) s |
| gen-only | 163 | 0 | 1024 | 3 | 195.5 (range 195.1-196.0, n=3) | 105.2 (range 104.0-119.5, n=3) | 0.85 (range 0.9-0.9, n=3) s |

- Total latency (client, wall): 4096-prompt - 6.44 s (6.25-6.49); 16384 - 12.48 s (11.20-12.86); 32768 - 17.81 s (17.59-18.08); 66560 - 29.35 s (29.26-29.41); 131072 - 54.40 s (54.33-54.68); 194560 - 77.51 s (77.47-77.75); 209715 - 83.86 s (83.12-83.92); 249037 - 112.20 s (98.03-112.46); 273000 - 107.95 s (107.86-108.53); gen-only - 10.57 s (1.75-10.69).
- Draft acceptance (accepted/total over all reps): 4K 360/506 (71%); 16K 357/497 (72%); 32K 295/354 (83%); 66K 239/257 (93%); 131K 320/441 (73%); 194K 311/428 (73%); 209K 288/385 (75%); 249K 249/319 (78%); 273K 244/305 (80%); gen-only 1416/1919 (74%).
- Memory peaks from the 2-second samples: per-GPU VRAM 15258 / 15694 / 15280 / 16144 MiB (of 16384), RAM peak 11531220 KiB (11.0 GiB). `CUDA3` is the tight card in both versions.
- Every run with draft statistics: [runs.json](runs.json); the control run of the same binary: [runs-0.1.45-control.json](runs-0.1.45-control.json); the 0.1.44.1 baseline: [runs-0.1.44.1-baseline.json](runs-0.1.44.1-baseline.json).
- Recall (needle) checks: [needles.json](needles.json) (32K/128K, depths 10/50/90), [needles-long.json](needles-long.json) (the far length), and the same files for 0.1.44.1: [needles-0.1.44.1.json](needles-0.1.44.1.json), [needles-long-0.1.44.1.json](needles-long-0.1.44.1.json).

## Comparison with 0.1.44.1 (same machine, same session, whole trees swapped)

Protocol: warm-up → code → needles → control on the same 0.1.45 binary → swap to 0.1.44.1 → warm-up → code → needles → swap back. Auto prompt chunk 8192 in both. No observer traffic.

### Prompt reading, medians (tok/s)

| case (actual prompt tokens) | 0.1.45 | 0.1.45 control (same binary) | 0.1.44.1 | new vs baseline |
|---|---:|---:|---:|---:|
| 4096 (3971) | 873.2 | 873.9 | 874.4 | −0.14% |
| 16384 (15667) | 1523.3 | 1521.2 | 1521.2 | +0.14% |
| 32768 (31307) | 1896.8 | 1898.5 | 1898.9 | −0.11% |
| 66560 (63539) | 2235.4 | 2236.0 | 2238.7 | −0.15% |
| 131072 (125011) | 2376.6 | 2380.7 | 2385.8 | −0.39% |
| 194560 (185531) | 2452.0 | 2457.0 | 2459.1 | −0.29% |
| 209715 (200015) | 2439.8 | 2443.4 | 2446.7 | −0.28% |
| 249037 (237483) | 2455.8 | 2461.6 | 2461.5 | −0.23% |
| 273000 (260331) | 2438.7 | 2444.4 | 2441.1 | −0.10% |
| gen-only (163) | 195.5 | 192.3 | 202.6 | −3.50% (see the note) |

- **The control band**: re-running the same 0.1.45 binary moved the medians by −0.17% … +0.24% at 4K-249K, +0.23% at 273K and by 1.66% in the gen-only case; the per-rep ranges inside a single case are 0.1-0.5% at every length above 32K. Every version delta in the table sits inside that band. **Verdict: no measurable change in prompt reading from 4K to 260K on this machine.**
- The speed curve peaks at ~185K and is ~1% lower at 260K — in 0.1.45, in its control and in 0.1.44.1 alike. That is a length effect, already recorded in the 0.1.43/0.1.44.1 cycle on this machine (see "Trend").
- **The gen-only case (163-token prompt) is not a usable comparison.** The same binary moved 195.5 vs 192.3 between the main and the control run, and the answer lengths differ between versions (the generated columns are in `runs.json`), so no conclusion is drawn from it.

### The suspicious case at the far lengths: repeated separately

In the main run, 0.1.45 at 237483 tokens had TTFT 110.58 s (97.11-111.26): two of its three reps were ~14 s slower than the third. The control run of the same binary measured 96.63 s at the same length, 0.1.44.1 measured 96.57-96.81 s, and the control run at 273K showed the same kind of one-off spread (106.81-120.25 s, median 117.81). The anomaly did not repeat when measured as separate probe runs (3 + 3 reps per version, scripts in [scripts/](scripts/)):

| case | 0.1.45 probe A | 0.1.45 probe B | 0.1.44.1 probe A | 0.1.44.1 probe B |
|---|---:|---:|---:|---:|
| 237483 tok/s | 2444.7 (2440.2-2445.3) | 2448.8 (2442.9-2448.8) | 2449.3 (2446.2-2451.4) | 2451.3 (2451.2-2455.5) |
| 237483 TTFT s | 97.30 | 97.13 | 97.12 | 97.04 |
| 260331 tok/s | 2428.6 (2426.3-2429.4) | 2425.8 (2425.5-2431.3) | 2432.7 (2429.1-2436.7) | 2430.7 (2429.6-2435.4) |
| 260331 TTFT s | 107.37 | 107.48 | 107.18 | 107.26 |

With 12 runs in total, both versions answer the first token of a 237483-token prompt in 96.9-97.5 s and of a 260331-token prompt in 107.0-107.5 s. Files: [runs-tail-0.1.45-a.json](runs-tail-0.1.45-a.json), [runs-tail-0.1.45-b.json](runs-tail-0.1.45-b.json), [runs-tail-0.1.44.1-a.json](runs-tail-0.1.44.1-a.json), [runs-tail-0.1.44.1-b.json](runs-tail-0.1.44.1-b.json). The one-off 13-14 s stalls are noise, not a version effect. A plausible carrier is the verify-graph work on the tight card: the sessions of both versions log `capturing the 6/3/1-token window` with 156-172 MiB free, and `CUDA3` is the card that reaches 16144 of 16384 MiB in the 2 s samples. This was not isolated further.

The engine's own log lines agree with the tables in this cycle: for a 260331-token prompt both trees log `read in 106.5-107.3 s (2425-2445 tok/s)`, which is what the client measures (106.9-107.5 s). The same log does contain 260331-token records at `102.1-102.9 s (2529-2549 tok/s)` - but those belong to the sessions of 2026-10-14, the previous cycle, and they sit in the shared history both log copies carry (see the note above about where the logs are). Read as what they are, they are a second instance of the same warning: a prompt of the same length, on the same version (0.1.44.1), read ~4% faster five days ago. The prompt content of those sessions is not recorded, so this is a machine-state comparison, not a like-for-like one.

### Generation columns are not used for conclusions

Answer lengths differ run to run and between versions (for example at 260331: 145 / 97 / 99 tokens in 0.1.45 probes vs 164 / 95 / 129 in 0.1.44.1), with draft acceptance 74-83%. Speeds of generation therefore vary 80-107 tok/s inside one version. No generation conclusion is drawn.

### What 0.1.45 changes that could touch this machine

The release source diff (0.1.44.1 → 0.1.45) was inspected for switches whose **default** changed: 9 variables look "on unless `=0`" in 0.1.45 and were absent or opt-in in 0.1.44.1 (`bin/new-defaults.py`). None applies to this configuration:

- `STRATA_ADAPT_EVICT_SYNC` — the fix applies to the adaptive copy tier that does not wait for its copies (`STRATA_ADAPT_NOWAIT=1`, `STRATA_ADAPT_LAG>1`, DETAILS.md); this config has no such tier: both engines print `adaptive overlap: off: not on a layer split`.
- `STRATA_DF_QB_Q4` (verify.cpp) — the batched verify path with q4_0 KV; this config uses `--kv int8`.
- `STRATA_PIPED_CONCURRENT`, `..._PRIO`, `..._UNPIN` — opt-in: `if (v == nullptr || atoi(v) == 0) return false`.
- `STRATA_RDNA2_SGEMM` — AMD only, default 0.
- `STRATA_SIMT2_TILE` — only reachable through `STRATA_SELECT_SIMT=1|2` (opt-in; the code path exists for `cc_major < 8`, but only when the variable is set).
- `STRATA_XN_F16` — the only one that can be active here (`bf16_converts_x()` path in `prefill.cpp`); measured: no difference in either prompt style, in either order. No A/B of `STRATA_XN_F16=0` was run, because nothing moved in the default configuration.
- `STRATA_DEQUANT_WIDE` is **not** a new default on this machine: the engine enables it for `major==6 && minor==1` and `major==8 && minor==6` only (`per_dev[] = ... ? 2 : 1`), so sm_70 keeps the previous path. The 4090 report's `STRATA_DEQUANT_WIDE` finding does not transfer here.
- New CLI flags of 0.1.45 (`--conversation-cache-park-gain`, `--prefill-pipe`, `--prompt-cache-spread`) are not used in this config and were not measured. The existing flags of this config are accepted unchanged by 0.1.45; `/props` and a test query were checked after the swap.

### Recall

- 32K and 128K, depths 10/50/90, both styles: **6/6 in 0.1.45 and 6/6 in 0.1.44.1** (`needles.json`, `needles-0.1.44.1.json`).
- Far length, `tools/needle_bench.py` at 250000: **3/3 at 249262 tokens in both versions** (97.3-97.5 s in 0.1.45, 95.8-95.9 s in 0.1.44.1) — `needles-long.json`, `needles-long-0.1.44.1.json`. In the Russian-style run of the first session the same call hit two request errors (HTTP 400 and 503) at 2 of 3 depths; a clean re-run at 245000 gave 3/3 at 243990 tokens (95-101 s), see the ru report.
- A 260331-token prompt (99.3% of the window) is served without errors in both versions.

## Correctness and limitations

- Speed measurements do not establish answer quality; only the recall checks above say anything about it.
- The engine's own state drifts between sessions on this machine: the *same* version reading the *same* long Russian prompt measured 2390-2450 tok/s in one seat and 2573-2630 tok/s in another (0.1.44.1), and the reversed-order measurements reduce the version gap to 0.0-0.8% (see [the ru report](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-ru/README.md)). Absolute numbers from different sessions are not comparable; same-session swapped-order A/B is.
- Not measured: the release's new opt-ins, other configs (no q4_0 KV, no `--prefill-pipe`), concurrency (one slot), 1M context, `serve.test_winjob` / `serve.test_lifecycle` (Windows-only and live-engine tests). The Python test suite is reported separately in [../2026-10-19-community-4x-tesla-v100-test-suite/README.md](../2026-10-19-community-4x-tesla-v100-test-suite/README.md).
- Prompts are synthetic (repeated text with a random marker); real workloads will show different prefix reuse and draft acceptance.
- The OS was not isolated: SSH sessions and stock Ubuntu services ran during the measurements; the GPUs were dedicated to Strata.

## Trend

Earlier reports for this machine and the same model: `bench/results/2026-10-14-community-4x-tesla-v100-iq3-s-262k-code` (0.1.43 → 0.1.44.1, branch `bench/2026-10-14-rtx4090-v100-upstream`, PR Niko1221/Strata#2525) and `bench/results/2026-10-17-community-4x-v100-nvlink-platform` (the NVLink/interconnect dossier, branch `bench/2026-10-17-v100-nvlink-platform`, PR Niko1221/Strata#2905). For the release-level trend on other hardware see `../2026-10-18-community-rtx4090-iq3s-200k-code/README.md` and `../2026-10-18-community-rtx4090-iq3xxs-200k-code/README.md` (same 0.1.45 cycle on RTX 4090, branch `bench/2026-10-18-rtx4090-0145`, PR Niko1221/Strata#3109). Those directories are not part of this branch; they live in the earlier `bench/*` branches.
