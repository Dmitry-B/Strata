# Python test suite for 0.1.45 on 4x Tesla V100 (Ubuntu 26.04, CUDA 12.8): 1703 tests, 13 failures + 1 error, none of them caused by the release

Measured on 2026-10-19 by [Dmitry-B](https://github.com/Dmitry-B), on the same machine and in the same cycle as [the code-style](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/README.md) and [the Russian-style](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-ru/README.md) benchmarks. Machine, model and configuration provenance: [../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/env.json](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/env.json); the host itself (platform, CPU, memory, storage, network, the PCIe path to the cards): [../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/host-provenance.txt](../2026-10-19-community-4x-tesla-v100-iq3-s-262k-code/host-provenance.txt).

**Headline: 1703 test cases in 118 modules pass except 13 failures and 1 error, all of them from three modules. The identical 14 failures reproduce in 0.1.44.1 with its own engine and its own venv, and 5 of them disappear when this machine's production server is stopped. Two real problems for the project are identified below: a golden-fixture bug (`strata-vision.exe` on Linux) that has been failing since before 0.1.45, and a new unmocked `os.cpu_count()` dependency in 0.1.45's `setup` that changes `vision.threads` (10 instead of the recorded 6 on a 20-CPU host).**

## What was run

- Tree: the freshly unpacked `v0.1.45` release source (`~/dl/Strata-0.1.45` → `~/strata185/Strata`), engine built locally for `sm_70` with a private CUDA 12.8 (nvcc 12.8.93) and private gcc-14 (`engine-cuda12/BUILD.json`: `"source": "local", "archs": [70]`).
- Modules: every `tools/test_*.py` and `serve/test_*.py` in the tree except `serve.test_winjob` (Windows-only) and `serve.test_lifecycle` (needs a live engine and free VRAM) — 70 `tools.*` modules (867 cases) and 48 `serve.*` modules (836 cases). Per-module case counts: [test-counts.csv](test-counts.csv).
- Engine under test: the production server on port 8080 with `strata-185-iq3_s.json` (`qwen3.8-flash-next-iq3_s`, 262144 context), running during the `serve.*` run.
- No git on this machine; the version is read from `/props` (`"build_info": "Strata 0.1.45"`) and `engine-cuda12/BUILD.json`.

## Results

| run | command scope | result | log |
|---|---|---|---|
| `tools.*` (70 modules) | `python -m unittest -v tools.test_*` in the fresh 0.1.45 tree | `Ran 867 tests in 55.638s` → `FAILED (failures=13, errors=1)`, skipped=2 | [tests-0.1.45-tools.log](tests-0.1.45-tools.log) |
| `serve.*` (48 modules) | `python -m unittest -v serve.test_*`, production server running | `Ran 836 tests in 277.559s` → `OK (skipped=12)` | [tests-0.1.45-serve.log](tests-0.1.45-serve.log) |
| merged | — | 1703 tests, 13 failures + 1 error, 14 skipped; combined log | [tests-0.1.45-raw.log](tests-0.1.45-raw.log) |

All 14 come from three modules: `tools.test_strata_mcp` (4 FAIL + 1 ERROR), `tools.test_setup_golden` (8 FAIL), `tools.test_setup_engine_hash` (2 FAIL).

## Why none of them is a 0.1.45 regression

1. **The same three modules in the 0.1.44.1 tree** — its own directory, its own built engine, its own `.venv`, same Python 3.14, same machine state: `Ran 58 tests in 16.470s` → `FAILED (failures=13, errors=1)`, and the failing test names are character-for-character the same set ([tests-0.1.44.1-same-modules.log](tests-0.1.44.1-same-modules.log) vs [tests-0.1.45-installed-tree.log](tests-0.1.45-installed-tree.log), the latter being the same three modules re-run in the installed 0.1.45 tree).
2. **The same modules with this machine's production server stopped** (VRAM verified free, port 8080 empty): `Ran 58 tests in 19.670s` → `FAILED (failures=10)` ([tests-0.1.45-without-production.log](tests-0.1.45-without-production.log)). The four `tools.test_strata_mcp.StartStop` failures and the teardown error are gone; the 8 golden and 2 engine-hash failures remain.
3. In a **freshly unpacked tree with no built engine**, the 16 tests of these modules error out in 0.001 s ([tests-0.1.45-failed-without-server.log](tests-0.1.45-failed-without-server.log)) — they need an installed engine and an installed config to say anything.

## What each group is

### `tools.test_strata_mcp` — 4 FAIL + 1 ERROR, only while the production server runs

`test_start_status_bench_stop`, `test_loading_then_ready`, `test_status_sees_other_programs_on_the_port`, `test_never_kills_an_unrelated_process` (+ `ERROR` in teardown of the same class). These tests manage a Strata MCP service on the machine's default install layout and expect the port to be theirs. On this machine port 8080 is permanently held by the production `iq3_s` server started from a non-default config name (`strata-185-iq3_s.json`), so the "nothing else is on the port" expectations cannot hold. Proof: with that server stopped, all five pass (item 2 above). Nothing to fix in 0.1.45; the suite has to be run with the port free on a server machine like this one.

### `tools.test_setup_golden` — 8 FAIL, two fixture problems

The test runs `setup.main()` with canned answers against mocked RAM and mocked GPUs, then compares the written config with `tools/test_setup_golden.json`. Re-running the same test class with `maxDiff=None` (a temporary subclass, `tools/_tmp_maxdiff_golden.py`, removed after the run) prints the full diffs for all 8 failing subtests in both versions: [golden-maxdiff-0.1.45.log](golden-maxdiff-0.1.45.log), [golden-maxdiff-0.1.44.1.log](golden-maxdiff-0.1.44.1.log) — `Ran 4 tests`, `FAILED (failures=8)`, the same 8 subtests: `test_yes` on the 64GB-1x32GB, 32GB-2x24GB, 47GB-2x16GB, 96GB-1x16GB and 128GB-1x24GB profiles, `test_enter_for_every_question` on 64GB-1x32GB, 96GB-1x16GB and 128GB-1x24GB.

- **Present in both versions** (8 mismatches out of 8 in each log; in 0.1.44.1 this is the *only* differing value):
  ```text
  -  'vision': {'exe': '<T>/engine/strata-vision',
  +  'vision': {'exe': '<T>/engine/strata-vision.exe',
  ```
  `setup` writes `strata-vision` on Linux, the golden records the Windows-suffixed name. `test_setup_golden.normalize()` replaces only `setup.EXE` (the main engine, via the `<EXE>` placeholder); the vision binary (`setup.VEXE`) is not normalized, so every golden record that contains a vision section fails on Linux. Suggested fix: normalize `VEXE` the same way, or store the vision exe as `<VEXE>` in the fixture.
- **New in 0.1.45** (3 of the 8 subtests: `test_yes` on 47GB-2x16GB and 96GB-1x16GB, `test_enter_for_every_question` on 96GB-1x16GB; masked by the previous problem, so the failing count is the same in both versions):
  ```text
  -             'threads': 10}}
  +             'threads': 6}}
  ```
  `setup.py:5906` (0.1.45) sets `cfg["vision"]["threads"] = max(1, (os.cpu_count() or 8) // 2)` on a code path 0.1.44.1 does not take under the same mocks; on this host `os.cpu_count()` is 20, so 10 is written where the fixture expects 6 (recorded on a 12-CPU machine). The golden profiles fix RAM and GPU cards but not the CPU count. Suggested fix: mock `os.cpu_count()` per profile, or normalize the threads value.

### `tools.test_setup_engine_hash` — 2 FAIL, machine-dependent network expectation

`test_a_first_install_stops_because_there_is_nothing_to_fall_back_to` and `test_updating_keeps_the_installed_engine_instead_of_stopping`. Both exercise what `setup` does when the engine download fails. On this machine the installed engine is a local build (`BUILD.json` `"source": "local"`), so `setup` asks GitHub for a prebuilt engine and gets **HTTP 404** (`no ready-made engine at https://github.com/Niko1221/Strata/releases/latest/download/` — the Linux release ships source only), which pushes the code down the "fall back to the latest release" branch the tests do not expect. Identical failures and identical messages in 0.1.44.1.

## Notes for the next cycle on this machine

- Run `tools.test_strata_mcp` with the production server stopped, or point the suite at a scratch install; otherwise 5 failures are noise from this machine's layout, not from the release.
- `tools.test_setup_golden` and `tools.test_setup_engine_hash` need the fixture fixes above (or an explicit allow-list documented in the report) before a count of failures can be used as a regression signal on Linux.
- `serve.*` passed completely (836 tests) with the live production server: the request-handling side of 0.1.45 shows no failures on this hardware.

## What was not covered

`serve.test_winjob` (Windows), `serve.test_lifecycle` (live engine + VRAM), the engine's C++ side (no C++ test target was run here), Windows-specific paths, and the new opt-in features of 0.1.45 that are off in this configuration.

## Files

- [tests-0.1.45-tools.log](tests-0.1.45-tools.log), [tests-0.1.45-serve.log](tests-0.1.45-serve.log), [tests-0.1.45-raw.log](tests-0.1.45-raw.log) — the full 0.1.45 suite run (verbose).
- [tests-0.1.45-installed-tree.log](tests-0.1.45-installed-tree.log) — the three failing modules in the installed 0.1.45 tree.
- [tests-0.1.45-without-production.log](tests-0.1.45-without-production.log) — the same with the production server stopped.
- [tests-0.1.44.1-same-modules.log](tests-0.1.44.1-same-modules.log) — the same modules in the 0.1.44.1 tree.
- [tests-0.1.45-failed-without-server.log](tests-0.1.45-failed-without-server.log) — the same modules in a tree without a built engine.
- [golden-maxdiff-0.1.45.log](golden-maxdiff-0.1.45.log), [golden-maxdiff-0.1.44.1.log](golden-maxdiff-0.1.44.1.log) — `tools.test_setup_golden` with the full diff printed, in both versions.
- [test-counts.csv](test-counts.csv) — per-module test case counts of the modules included.
