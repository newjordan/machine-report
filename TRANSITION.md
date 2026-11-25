# TRANSITION

How `machine-report` was forked from TR-100, what changed, and how to add a target without turning the three scripts into one framework.

## Lineage

- **Upstream**: [usgraphics/TR-100](https://github.com/usgraphics/TR-100). One bash file, written for an AMD EPYC Debian host with ZFS on root, and sourced from `.bashrc` so the banner prints on an interactive shell.
- **Why a fork**: the upstream README says it is not maintained on purpose and that you should adapt the script. That is the contract.
- **Why one file per machine**: the same note. A config file and a pile of switches would be a second program. `linux.sh`, `spark.sh`, and `wsl.sh` are three complete scripts. Shared helpers are copied, not imported. `tests/common.bats` diffs the function bodies so a fix to a shared helper is applied in every copy, while `collect_cpu`, `read_gpu`, and `main` are allowed to differ. `spark.sh` also has `format_clock`.

## What changed from TR-100

| Section | TR-100 | This fork |
|---------|--------|-----------|
| OS | A Debian-shaped version string | `NAME`, `VERSION_ID`, and `VERSION_CODENAME` from `/etc/os-release` |
| Hypervisor row | `lscpu` hypervisor vendor | Replaced by `PLATFORM`, a string at the top of the file |
| ZFS | `zpool status` health | Removed. Disk is always `df -Pm /` |
| CPU model | First four awk fields of `Model name` | Linux and WSL clean `(R)`, `(TM)`, and a trailing clock. Spark reads every `Model name` line |
| CPU summary | A single core count | `nproc` against `Core(s) per socket` × `Socket(s)`, with threads shown only when there are more threads than cores. Plurals follow the count |
| CPU frequency | `cpu MHz` in `/proc/cpuinfo` | `CPU max MHz` from `lscpu`, then `CPU MHz`, then `/proc/cpuinfo`. `n/a` when none are present. aarch64 boxes often have no `cpu MHz` field |
| Load | Parsed from `uptime` | `/proc/loadavg`. The bar is clamped at 100% of the logical CPU count so a load spike cannot push the right border out |
| GPU | None | New panel. Linux and WSL show VRAM when the query returns a total. Spark shows the graphics clock and skips VRAM, because GB10 memory is the system memory row |
| `lastlog` | Whitespace fields, which broke on Ubuntu 24.04 | Cut with the `From` and `Latest` columns of the header. Empty From, a hostname, and an IPv6 peer all keep the timestamp intact. The peer is a `LOGIN FROM` row |
| Client address | `who` | `SSH_CONNECTION`, then `SSH_CLIENT`, then `who`. No peer prints `local` |
| Hostname | `hostname -f` | `uname -n`, so a broken resolver cannot stall the shell |
| Address | Skip `lo` and `docker*` | `ip -o addr show scope global`, then skip virtual names (`docker*`, `br-*`, `veth*`, `virbr*`, tunnels, and similar). Then `ifconfig` matching `inet` only, so an `inet6` line is not taken as IPv4. Then `hostname -I`, skipping link-local |
| Disk unit | Mixed | `df -Pm` counts 1,048,576-byte blocks, and the label says GiB |
| Width | Bars and long strings could disagree with the frame | Data column is at least `MIN_DATA_LEN` (24) and at most `MAX_DATA_LEN` (48). The vertical rule follows `MAX_NAME_LEN`. Values and bars are padded or ellipsized to that width |
| Locale | Whatever the user had | This process uses `C.UTF-8` when the locale exists, so `${#string}` counts characters. Parsers that match English field names run under `LC_ALL=C` |
| Missing tools | The script assumed they exist | A missing `nvidia-smi` skips the GPU panel. A missing `lastlog` prints `unavailable`. A missing CPU model prints `Unknown CPU`. The banner still closes the box |

## Per-target notes

### `spark.sh` — DGX Spark / GB10

- **Two clusters.** `lscpu` prints two `Model name` lines and two `Core(s) per socket` lines. The script labels the processor `NVIDIA GB10 Grace Blackwell`, prints the two model names on `ARCH`, and the core counts as `(<first>P + <second>E)`. That P-then-E order is the current GB10 firmware. A single `Model name` uses the generic summary and omits `ARCH`.
- **Unified memory.** `nvidia-smi` reports `N/A` for memory totals on GB10. The query asks for name, utilization, temperature, power, and `clocks.current.graphics`. There is no VRAM row.
- **No `cpu MHz` in `/proc/cpuinfo`.** Frequency comes from `lscpu`'s `CPU max MHz`.
- **`/proc/device-tree/model` is empty** on the Spark, unlike Jetson. `install.sh` detects a Spark from `GB10` in `nvidia-smi -L`.
- **`PLATFORM`** is the literal `NVIDIA DGX Spark`.

### `linux.sh` — generic workstation

- One CPU package. `Core(s) per socket` and `Socket(s)` are the physical topology. `nproc` is the logical count, which is what the load bars are divided by.
- The GPU panel runs only when `nvidia-smi` returns a CSV row. Memory rows are omitted when the total is missing or zero, which is what an `N/A` field becomes.

### `wsl.sh` — Windows Subsystem for Linux 2

Same script as `linux.sh` aside from the subtitle and `cpu_platform="WSL2 on Windows"`. The function bodies are kept identical, and a test fails if they drift.

`MACHINE IP` is the guest address (often a `172.x` NAT address), not the Windows host's LAN address.

## Adding a target

Copy the closest script, rename it to `<host>.sh`, and edit the identity block:

```bash
report_subtitle="..."
cpu_platform="..."
```

If the CPU or GPU query is different, change `collect_cpu`, `read_gpu`, and the render block in that file only. Then:

```bash
./install.sh <host>
```

That symlinks `~/.machine_report.sh`, installs the bashrc hook, and prints the banner. Do not extract a `lib/`. When a new `lscpu` format breaks one machine, the fix stays in that file. When the fix is in a shared helper (`print_data`, `bar_graph`, lastlog, the address parser), apply it to the other copies too. `make test` names the function that drifted.

## Updating

```bash
cd ~/machine-report && git pull
```

The symlink points at the working tree, so the next interactive terminal runs the new script. Run `./install.sh` again to refresh the bashrc hook. The hook is marked with `# >>> machine-report >>>` and is replaced in place when its text changes.

## Things deliberately not done

- **No colors.** The bars and the box are the whole visual system.
- **No multi-GPU loop.** Each script prints the first `nvidia-smi` row. A host with many GPUs can grow a loop in that file.
- **No emoji.** Width math stays in character counts.
- **No cache.** The banner is a straight read of `/proc` and a few commands. On the host where the README sample was captured, ten runs of `./linux.sh` took between 0.1009 and 0.1072 seconds.
- **No theme file.** Identity and layout are assignments at the top of the script you run.
