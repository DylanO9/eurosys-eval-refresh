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

## What Still Needs Fresh Runs (for GSoC Benchmarking)

The plots currently use committed `paperresults/` data (2021 paper values) except for:
- `fig_10_unikraft-boot` — fresh data collected March 2026 (see `rawdata/`)
- `fig_11_compare-min-mem` — fresh data collected March 2026
- `fig_22_compare-vfs` — fresh data present in `results/`
- `fig_02`, `fig_03` — freshly regenerated dependency graphs from current Unikraft source

Experiments requiring full re-runs to compare against paper:
| Figure | What it measures | Expected regression area |
|--------|-----------------|--------------------------|
| fig_10 | Boot time per VMM | Firecracker/QEMU changes |
| fig_11 | Minimum memory | Memory layout / page table |
| fig_12 | Redis throughput | Networking stack |
| fig_13 | NGINX throughput | Networking stack |
| fig_14 | Boot time with allocators | Allocator APIs changed |
| fig_15 | NGINX with allocators | Allocator + networking |
| fig_16 | SQLite with allocators | Allocator performance |
| fig_17 | SQLite libc comparison | musl/newlib changes |
| fig_18 | Redis with allocators | Allocator performance |
| fig_19 | DPDK throughput | DPDK ABI / driver changes |
| fig_20 | 9pfs latency | Filesystem stack |
| fig_21 | Boot with page tables | Page table rework |
| fig_22 | VFS specialization | VFS refactoring |
| tab_01 | Syscall overhead | Platform/mitigations |

`fig_01` (Linux kernel dependency graph) requires cscope on 7.3 GB of kernel source; started in background — run `make plot -C experiments/fig_01_linux-deps` once it completes.
