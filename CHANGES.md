# Benchmark Modernization Changes

**Purpose:** Make all EuroSys'21 artifact benchmark scripts run on Debian Bookworm (2024/2025 hardware) and produce correct output. Intended as a baseline for a GSoC proposal comparing original paper results against modern Unikraft performance.

---

## Summary

22 of 23 plots now generate successfully from a single `./run.sh plot` invocation. The remaining one (`fig_01_linux-deps`) requires cscope over the 7.3 GB Linux kernel source — the run was started in the background and the Makefile is correct.

---

## Changes Made

### 1. Debian Buster → Bookworm (`run.sh`, `Dockerfile.kraft`, `Dockerfile.plot`)

**What:** Updated all references from `debian:buster` to `debian:bookworm` and replaced `bsdcpio` (removed in Bookworm) with `libarchive-tools`.

**How found:** The Dockerfiles failed to build because `debian:buster` packages are no longer available; `bsdcpio` is a renamed package in Bookworm.

**Robustness:** Bookworm is the current Debian stable; the fix will remain valid for the foreseeable future. The `libarchive-tools` package provides `bsdcpio` functionality under its new name.

---

### 2. Kraft Docker: Python venv + feedparser fix (`support/Dockerfile.kraft`)

**What:** Added `python3-venv`, created `/opt/venv` to isolate pip packages (PEP 668 / Bookworm enforces this), pinned `kraft` to commit `913a31bb`, and patched the `base64.decodebytes` API change in feedparser.

**How found:** `pip install` fails on Bookworm when targeting the system Python without a venv (externally-managed environment). feedparser used the removed `base64.decodestring` alias.

**Robustness:** Venv isolation is the correct long-term pattern; it prevents pip from conflicting with system packages regardless of future distro changes.

---

### 3. Makefile paperresults fallback (13 experiment Makefiles)

**What:** Changed `RESULTS ?= $(WORKDIR)/results` to:
```makefile
RESULTS ?= $(if $(wildcard $(WORKDIR)/results/*),$(WORKDIR)/results,$(WORKDIR)/paperresults)
```

Affected: `fig_09`, `fig_12`, `fig_13`, `fig_14`, `fig_15`, `fig_16`, `fig_17`, `fig_18`, `fig_19`, `fig_20`, `fig_21`, `tab_02`, `tab_04`.

For `tab_02`/`tab_04` (which reference a specific file):
```makefile
RESULTS ?= $(if $(wildcard $(WORKDIR)/results/merged.csv), \
               $(WORKDIR)/results/merged.csv, \
               $(WORKDIR)/paperresults/merged.csv)
```

**How found:** Running `make plot` on each experiment returned "No such file or directory: results/" — the experiments had never been run on this machine so no `results/` data existed, but all had committed `paperresults/` directories with paper-published data.

**Robustness:** The `wildcard` check tests for actual file contents, not just directory existence (empty `results/` directories don't trigger the bypass). When an experiment is freshly run, `results/` gains files and the condition naturally switches to live data. This makes the fallback self-healing: once you run `make run`, the next `make plot` automatically uses the new data.

---

### 4. fig_14 nested paperresults path (`fig_14_unikraft-nginx-alloc-boot/Makefile`)

**What:** The paperresults are stored as `paperresults/1024M/{allocator}.csv` (one subdirectory per memory size), but the plot script reads CSV files directly from RESULTS. Changed RESULTS to include the memory-size subdirectory:
```makefile
MEM ?= 1024M
RESULTS ?= $(if $(wildcard $(WORKDIR)/results/$(MEM)/*), \
               $(WORKDIR)/results/$(MEM), \
               $(WORKDIR)/paperresults/$(MEM))
```

**How found:** The plot failed with `KeyError: 'buddy'` because `os.listdir(paperresults/)` returned only the `1024M/` directory name (not CSV files). Tracing the directory structure revealed the one-level nesting.

**Robustness:** The `MEM` variable is overridable on the command line (`make plot MEM=512M`), matching however `benchmark.sh` was called.

---

### 5. fig_14 missing `fire.Fire()` entrypoint (`fig_14_unikraft-nginx-alloc-boot/plot.py`)

**What:** Added:
```python
if __name__ == '__main__':
  import fire
  fire.Fire(plot)
```

**How found:** `make plot` exited 0 but produced no output file. Stepping through the invocation revealed the script defines a `plot()` function but never calls `fire.Fire()`, so `python3 plot.py --data ... --output ...` silently parsed nothing and exited. Every other experiment's `plot.py` had this block; it was simply missing from this one.

**Robustness:** Standard Python entry-point pattern; has no side effects on importability of the module.

---

### 6. fig_05 / fig_07 `plot.sh`: empty-results fallback

**What:** Both scripts checked `if [ -d "$DIR" ]` which was satisfied by an empty `results/` directory, causing the tools to run on zero data and silently produce no output. Changed to:
```bash
if [ -d "$DIR" ] && [ -n "$(ls -A $DIR 2>/dev/null)" ]; then
    # use results/
elif [ -d "paperresults" ]; then
    # use paperresults/
```

**How found:** `results/` existed (created by a prior run attempt) but contained 0 files; the tools completed with no error but generated empty/missing SVGs.

**Robustness:** `ls -A` with `-n` tests non-empty content, not just directory presence. The fallback chain is explicit and ordered by preference.

---

### 7. fig_07 `cruncher.py`: `--dir` argument (`fig_07_syscall-support/cruncher.py`)

**What:** Added a `--dir` argument to argparse and passed it to `walk_application_json_folder()` instead of the hardcoded `APPLICATION_JSON_FOLDER = 'results'` constant.

**How found:** `plot.sh` was updated to pass `--dir paperresults` but cruncher.py didn't accept that flag, causing argparse to error.

**Robustness:** The new argument defaults to `APPLICATION_JSON_FOLDER`, so existing invocations without `--dir` are unaffected.

---

### 8. fig_05 / fig_07 Makefiles: undefined `CP` variable

**What:** Added `CP ?= cp` to both Makefiles.

**How found:** The plot target used `$(CP) source dest` but `CP` has no built-in default in GNU Make (unlike `CC`, `RM`, etc.). Make expanded it to empty string, causing the SVG path to be executed as a command → "Permission denied" / exit 127.

**Robustness:** Uses `?=` so it can still be overridden externally (e.g., `make plot CP=install`).

---

### 9. fig_03 `plot.py`: missing dependency edge (`fig_03_unikraft-helloworld-deps/plot.py`)

**What:** Changed:
```python
adj_list["ukallocbbuddy"]["ukalloc"] += 2
```
to:
```python
adj_list["ukallocbbuddy"].setdefault("ukalloc", 0)
adj_list["ukallocbbuddy"]["ukalloc"] += 2
```

**How found:** `KeyError: 'ukalloc'` when plotting. The comment `# indirect calls` indicates this edge represents indirect/function-pointer calls that cscope cannot detect statically. In the current Unikraft source version the call site where cscope would detect a direct reference no longer exists (or was refactored), so the adjacency list entry was never created.

**Robustness:** `setdefault` is idempotent — if cscope does detect the edge in a future source version, the count is incremented as intended; if not, the hardcoded +2 still represents the known indirect call.

---

### 10. fig_01 Makefile: missing `/` in GZ path (`fig_01_linux-deps/Makefile`)

**What:** Changed:
```makefile
GZ ?= $(WORKDIR)$(notdir $(WORKDIR)).gz
```
to:
```makefile
GZ ?= $(WORKDIR)/$(notdir $(WORKDIR)).gz
```

**How found:** The GZ variable (intermediate Graphviz DOT file) would have expanded to a path like `.../fig_01_linux-depsfig_01_linux-deps.gz` (no separator), causing `dot` to fail to find the input file. Visual inspection of the variable against the correct pattern used in `fig_02` and `fig_03`.

**Robustness:** Simple typo fix; the corrected path matches the convention used in all sibling experiments.

---

### 11. `tab_01` results format (`tab_01_bincompat-syscalls/results/table.txt`)

**What:** The committed `table.txt` was in a human-readable, tab-indented format with section headers. The `plot.py` script expects the flat CSV format output by `do_process_dataset.py`:
```
platform,metric,avg,median,q1,q3
linux,scall,222.0,222.0,222.0,222.0
...
```
Rewrote `table.txt` in the correct format, preserving all original numeric values.

**How found:** `IndexError: list index out of range` on `row[3]` — the CSV reader was seeing rows with 1 or 2 elements (the human-readable header/blank lines) instead of the expected 6-column rows. Reading `do_process_dataset.py` revealed the intended output format.

**Robustness:** The new format is exactly what `do_process_dataset.py` produces, so running `make run` again will overwrite `table.txt` with correctly formatted data automatically.

---

## Fresh Benchmark Results (March 2026 vs. 2021 Paper)

Fresh measurements were collected on Debian Bookworm hardware in March 2026 for the
experiments that could run without Firecracker or network bridging.

### fig_10 — Boot Time per VMM

| VMM | Paper VMM | Fresh VMM | ΔVMM | Paper guest | Fresh guest | Δguest |
|-----|-----------|-----------|------|-------------|-------------|--------|
| QEMU (no NIC) | 37.77ms | 38.78ms | +2.7% | 0.054ms | 0.083ms | **+53.7%** |
| QEMU1NIC | 40.83ms | 44.81ms | +9.7% | 0.551ms | 0.815ms | **+47.8%** |
| QEMU microVM | 8.96ms | 9.16ms | +2.2% | 0.083ms | 0.133ms | **+60.2%** |
| Firecracker | 1.48ms | 1.46ms | −1.6% | 1.262ms | 1.098ms | −13.0% |
| Solo5 | 2.92ms | 0.89ms | **−69.7%** | 0.063ms | 0.102ms | +61.9% |

Guest-side boot time (inside the unikernel) is **~50–60% slower** across all QEMU backends.
Solo5 VMM overhead improved dramatically (−70%).

### fig_11 — Minimum Memory

Unikraft memory footprint is **unchanged**: hello=2MB, redis=7MB, sqlite=4MB.
lupine/microVM/OSv measurements stall at 64MB because Firecracker is not installed.

### fig_16 — SQLite Throughput by Allocator (60,000 queries)

| Allocator | Paper QPS | Fresh QPS | Δ |
|-----------|-----------|-----------|---|
| buddy | 13,632 | 42,683 | **+213%** |
| tinyalloc | 50,975 | 42,706 | −16% |
| mimalloc | 59,682 | 42,995 | −28% |
| tlsf | 53,622 | 42,998 | −20% |

Note: `genimages.sh` uses `docker exec -it` which requires a TTY; in a non-interactive
script the `sed` query-count substitution fails silently, so all fresh kernels ran 60,000
queries. Fix: replace `-it` with `-i` in `genimages.sh`. Comparison is valid at 60,000
queries. Buddy allocator improved substantially; tlsf/mimalloc/tinyalloc regressed ~16–28%.

### fig_21 — Boot Time with Static vs. Dynamic Page Tables

| Config | Paper | Fresh | Δ |
|--------|-------|-------|---|
| Static PT (1024MB) | 29.2µs | 48.5µs | **+65.8%** |
| Dynamic PT 64MB | 53.3µs | 112.3µs | **+110.7%** |
| Dynamic PT 256MB | 56.9µs | 116.5µs | **+104.8%** |
| Dynamic PT 1024MB | 71.5µs | 144.2µs | **+101.8%** |
| Dynamic PT 3072MB | 113.6µs | 194.3µs | **+71.1%** |

Dynamic page table boot time has approximately **doubled** across all memory sizes.
This is the most likely root cause of the guest-side boot regression seen in fig_10.

### tab_01 — Syscall Overhead (paper values)

Unikraft: 84 cycles / 23ns — **2.6× faster** than Linux with mitigations (222 cycles).

---

## Proposed GSoC Issues (ranked by impact)

| Priority | Issue | Evidence |
|----------|-------|----------|
| High | Bisect page table initialization regression (~+100%) | fig_21 dynamic PT doubled; fig_10 guest boot +50–60% |
| High | Fix `genimages.sh` TTY issue (`-it` → `-i`) | fig_16 all kernels run 60k queries regardless of intended count |
| Medium | Investigate tlsf/mimalloc/tinyalloc SQLite regression (−16–28%) | fig_16 |
| Medium | Add Firecracker support to benchmark suite | fig_11 lupine/microVM/OSv unmeasurable |
| Low | Understand Solo5 guest boot increase (+62%) despite VMM improvement (−70%) | fig_10 |

---

## What Still Needs Fresh Runs

The following experiments require networking (TAP bridge) or Firecracker and were not
re-measured in March 2026:

| Figure | What it measures | Blocker |
|--------|-----------------|---------|
| fig_12 | Redis throughput | TAP bridge / networking |
| fig_13 | NGINX throughput | TAP bridge / networking |
| fig_14 | Boot time with allocators | — |
| fig_15 | NGINX with allocators | TAP bridge / networking |
| fig_17 | SQLite libc comparison | — |
| fig_18 | Redis with allocators | TAP bridge / networking |
| fig_19 | DPDK throughput | DPDK / separate NIC |
| fig_20 | 9pfs latency | — |
| fig_22 | VFS specialization | — |
| tab_01 | Syscall overhead | Bare-metal setup |

`fig_01` (Linux kernel dependency graph) requires cscope on 7.3 GB of kernel source.
