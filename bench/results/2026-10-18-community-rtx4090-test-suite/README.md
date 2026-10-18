# Full Python test suite on engine 0.1.45 (RTX 4090) — no regressions; three test-side failures to note

This is a test-suite report, not a benchmark. It records the first full run of every
`tools/test_*.py` and `serve/test_*.py` module on this machine (previous releases were
tested with a subset of modules only), the comparison against the recorded 0.1.44.1
baseline, and the classification of every failure.

**Headline: 1703 tests, 16 failures, none of them a regression of 0.1.45.** Ten failures
are the known 0.1.44.1 baseline failures and reproduce unchanged. The six new ones are
machine state (a live production server on port 8080) or two test-side defects described
below, each with a reproduction and a suggested fix.

## Hardware and software

- RTX 4090 24 GB (sm_89), Ryzen 9 7950X, 48 GB RAM, Ubuntu 26.04.1
- NVIDIA driver 615.71.09, CUDA 13.4 (`nvcc 13.4`), Python 3.14.4 (the repo `.venv`)
- Engine built from source at tag `v0.1.45` (`477ac13`); `engine/BUILD.json` version
  matches `git describe` and `/props` (all three read 0.1.45)
- The production server (`strata-200k.json`, Qwen3.8-Flash-Next IQ3_XXS, context 204800)
  was running on port 8080 during the first run; that is the cause of four of the
  failures and is isolated below.

## Method

Two groups, run with the repo `.venv`:

```bash
.venv/bin/python -m unittest -v tools.test_*        # every tools/test_*.py
.venv/bin/python -m unittest -v serve.test_*        # every serve/test_*.py except:
```

- `serve.test_winjob` — Windows-only, not run (as before).
- `serve.test_lifecycle` — starts a live engine and competes with the loaded model for
  VRAM, not run (as before).

Per-module test counts: `test-counts.csv`. The complete raw output:
`tests-0.1.45-raw.log`.

## Results

| Group | Tests | Failures | Notes |
|---|---|---|---|
| `tools/*` | 867 | 14 failures + 1 error | all classified below |
| `serve/*` | 836 | 1 failure | `test_keepawake`, a test-side race |
| **Total** | **1703** | **16** | |

Baseline (0.1.44.1, subset of modules): 848 tests, 10 failures. The suite grew by 855
tests — new modules of this release (`test_setup_qwen36`, `test_setup_shard_check`,
`serve.test_model_card_sampling`, `serve.test_replicas`, `serve.test_parser_*`, …). The
growth is normal for a release; the comparison that matters is failure-by-failure, below.

## Every failure, classified

### 1–8. `tools.test_setup_golden` (8) — known, unchanged from 0.1.44.1

The golden fixture records Unsloth entries with `strata-vision.exe`; on Linux setup
writes `strata-vision`. Present since 0.1.43, identical set here (`test_enter_for_every_question`
×3, `test_yes` ×5, all `unsloth UD-Q4_K_XL`). Not re-analysed.

### 9–10. `tools.test_setup_engine_hash` (2) — known, machine-specific

Both expect `setup.get_prebuilt()` to try a download; this machine's `engine/BUILD.json`
has `"source": "local"`, so `get_prebuilt` returns before any network access. Unchanged
from the 0.1.44.1 baseline.

### 11–14. `tools.test_strata_mcp.StartStop` (4) — machine state, not a code issue

These tests start/stop servers on port 8080 and expect the port to be empty. The
production server was running (the failure output itself lists it:
`"started_by": "outside this MCP server (its own window, a start script or a service)"`).
**Verified:** with `systemctl stop strata.service`, the whole module passes (24/24 OK),
server restarted after. No action needed; noted so others don't chase it.

### 15. `tools.test_strata_bench.RedactionTests.test_paths_names_ips_and_keys` — test-side bug on repos under `$HOME`

```
AssertionError: '<strata>' not found in 'loading /home/<user>/Strata/strata-x.json'
```

`redactor()` registers `ROOT -> <strata>` first, but the username rule rewrites
`/home/dgbox/...` to `/home/<user>/...` before the literal `ROOT` is matched, so the
`ROOT` substitution can no longer fire. The test fails on any machine whose repo path
contains the current username — i.e. for most real installs. **Verified:** the same
module passes from a clean `git worktree` of `v0.1.45` at `/tmp/strata-v0145` (path
without the username), and fails in the home-path checkout deterministically.
Suggested fix: substitute `ROOT` before the username rules, or make the test build a
synthetic ROOT that cannot contain the username.

### 16. `serve.test_keepawake.test_service_holds_for_the_whole_request_including_early_close` — test-side race

```
AssertionError: False is not true   (wait_for(rec.calls == [ON, ES_CONTINUOUS]))
```

`KeepAwake` starts its daemon thread inside `acquire()`. The mock request completes in
well under a millisecond (MockEngine, ~94,000 tok/s), so `release()` runs before the
thread takes the lock for the first time; the thread then sees `count == 0 == held` and
never calls `ON`. Reproduced standalone 5/5 on this machine (a fast-CPU box loses the
race deterministically). A hand-written reproduction shows `rec.calls == []` after the
full run and `[ES_CONTINUOUS]` after `close()` — the production behaviour is correct
(a real request holds the CPU long enough), the test's expectation is timing-dependent.
Suggested fix: drive `KeepAwake` directly (as the first test does) or make the mock
generator hold briefly. Note: the defect is timing-dependent — in a later full-suite run
the same module passed (0 failures); the 5/5 standalone failures above are this machine
consistently winning the race.

## What was not run

- `serve.test_winjob` (Windows), `serve.test_lifecycle` (live engine, VRAM contention).
- The C++ engine self-tests (`tools/*_parity` kernel checks run inside the engine build;
  not re-run here beyond the build's own checks).
- Other configs and the release's opt-in switches (`STRATA_HIP_WMMA`, the CUDA opt-in
  series, `--parallel`): not exercised by this suite and not measured here.

## Files

- `tests-0.1.45-raw.log` — complete unittest output, both groups, verbatim.
- `test-counts.csv` — per-module test counts (1703 total).
