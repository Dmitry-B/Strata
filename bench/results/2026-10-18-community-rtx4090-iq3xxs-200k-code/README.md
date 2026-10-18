# RTX 4090, Qwen3.8-Flash-Next IQ3_XXS, 204800 context — engine 0.1.44.1 -> 0.1.45

## Hardware and software

- RTX 4090 24 GB (sm_89), Ryzen 9 7950X, 48 GB RAM, Ubuntu 26.04.1
- NVIDIA driver 615.71.09, CUDA 13.4; both engines built from source the same way
  (`engine/BUILD.json` `"source": "local"`, archs `[89]`), versions verified in
  `git describe`, `engine/BUILD.json` and `/props`
- Engine under test: 0.1.45 (`477ac13`). Comparison: 0.1.44.1 re-measured in the same
  session by swapping `engine/strata*.bak` (and its published 2026-10-14 report:
  `../2026-10-14-community-rtx4090-iq3xxs-200k-code/README.md`).

## Model and configuration

`strata-200k.json` (copy: `config.json`): IQ3_XXS GGUF + learned expert profile,
context 204800, `--kv int8`, `--mmap-experts`, `--expert-cache auto`, `--spec 4` with
the RT MTP pack, control vector, `--pool-workers 10`, `--vram-reserve-mib 989`.
**The auto prompt chunk is 8192 tokens (96-slot ring) in both versions** — the prompt
columns below are bit-comparable across the two.

## Method

One session, same protocol as the 2026-10-14 report: full warm-up run (discarded) ->
`code` suite -> `ru` suite -> control re-runs on the SAME 0.1.45 binary -> engine swap
to 0.1.44.1 -> warm-up -> `code` -> `ru` -> engine swap back. A third 0.1.45 `code`
control was taken ~1 h later (`runs-0.1.45-control2.json`) to resolve the 4K anomaly
below. Needles (recall) only in the main runs. The agent driving the machine works
against a different server, so no observer traffic polluted these runs.

## Results (medians, tok/s) — one table per style, short through the context limit

The full length set (4K -> the 204800-window limit) belongs in one suite; this is now
the standing protocol. For this release the long lengths were measured in a second
session of the same protocol (warm-up discarded, same-binary control, 0.1.44.1
re-measured by swapping the engine in the same session) — disclosed here, not repeated
going forward.

### code-style prompts

| case (actual tokens where relevant) | 0.1.45 | 0.1.44.1 | control (same binary) | delta |
|---|---|---|---|---|
| 4096 | **1852.5** (1777–2008) | 2162.6 (2152–2168) | 1987.3 / 1815.5 (two extra controls) | **see anomaly** |
| 32768 | 3301.3 | 3343.3 | 3224.6 | −1.3% (inside the control band) |
| 131072 | 3280.4 | 3297.1 | 3277.4 | −0.5% (inside the band) |
| 163840 (156,291) | 3286.6 | 3285.2 | 3293.2 | +0.0% |
| 194560 (185,531) | 3298.3 | 3288.8 | 3299.2 | +0.3% |
| 209715 (200,015) | 3267.9 | 3267.2 | 3274.6 | +0.0% |
| gen-only (163-token prompt) | 287.7 | 281.8 | 285.4 | +2.1% (inside the band) |

TTFT at the limit: 61.30 s (0.1.45) vs 61.31 s (0.1.44.1); at 156K: 47.62 / 47.65 s.

### ru-style prompts

| case | 0.1.45 | 0.1.44.1 | control | delta |
|---|---|---|---|---|
| 4096 | 2109.0 | 2131.2 | 2066.6 | −1.0% (inside the band) |
| 32768 | 3275.8 | 3298.9 | 3219.2 | −0.7% (inside the band) |
| 131072 | 3308.2 | 3331.9 | 3296.4 | −0.7% (inside the band) |
| gen-only | 392.7 | 395.9 | 403.8 | −0.8% (inside the band) |

The long lengths (156K–200K) were run in the code style only for this release; under
the new single-suite protocol they will be present for both styles.

Generation columns (the 256/1024-token tails of the same cases): every delta between
−9.4% and +4.8%, which sits inside this method's generation noise (±5–6% measured on
identical binaries); draft acceptance is unchanged (e.g. gen-only 2053/2659 vs
2044/2644). No generation conclusion is claimed.

## The 4K code-prompt anomaly — isolated to `STRATA_DEQUANT_WIDE`

`4096-prompt`, code style: 0.1.44.1 is tight and fast — 2152 / 2163 / 2168 tok/s
across three repeats. 0.1.45 is unstable and slower — nine samples across three
independent runs of the same binary: 1380, 1777, 1815, 1852, 1880, 1966, 1987, 2008,
2119 (medians 1815–1987). The 0.1.45 sample range touches 0.1.44.1 only at its very
top; the medians do not overlap. The same case in the ru style is unchanged (−1.0%,
inside the band), and TTFT at 4K rose 1.85 -> 1.99–2.25 s.

**A/B result (same 0.1.45 binary, `STRATA_DEQUANT_WIDE=0` through the service
environment, delivery verified in `/proc/<engine>/environ`):** the case returns to
2107 / 2133 / 2145 and the control run to 2129–2145, tight, at the 0.1.44.1 level.
So the new default wide dequantization (`STRATA_DEQUANT_WIDE`, documented as on by
default on sm_86; sm_89 is not in the release's test set) is the cause on this RTX
4090: it costs ~10–15% of 4K-prompt reading and adds the instability. Other lengths
are unaffected by the switch (32K: 3289–3321 with it off vs 3301 default; 128K:
3271–3277 vs 3280; gen-only prompt 296–302 vs 288, inside the band). The ru-style 4K
case was not re-run with the switch off. Files:
`runs-0.1.45-no-dequant-wide.json`, `runs-0.1.45-no-dequant-wide-control.json`.

## Correctness and limitations

- Recall: 6/6 needles at 32K and 128K, both styles, both versions; 3/3 at 192K
  (code-style long runs), both versions.
- Generation was measured only up to 128K + gen-only; the long-context runs are
  prompt-reading only (`--no-gen-case`).
- The release's opt-in switches (`STRATA_HIP_WMMA`, the CUDA opt-in series,
  `--parallel`) were not measured. `STRATA_DEQUANT_WIDE=0` WAS measured (above).
- Sampling defaults changed in 0.1.45 for requests without sampling keys; the bench
  script pins its own sampling, so the runs above are unaffected.

## Files

- `runs.json` — 0.1.45 main run (code), `needles.json` — its recall.
- `runs-0.1.44.1-previous.json`, `needles-0.1.44.1.json` — 0.1.44.1, same session.
- `runs-0.1.45-control.json`, `runs-0.1.45-control2.json` — same-binary controls
  (the noise band; control2 is the extra 4K check).
- `runs-long-context*.json`, `needles-long*.json` — the 156K–200K runs (0.1.45,
  control, 0.1.44.1).
- `config.json` — the working config with the API key removed.
