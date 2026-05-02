# TRANSITION

How `machine-report` was forked from TR-100, what changed and why, and how to add a new target without breaking the philosophy.

## Lineage

- **Upstream**: [usgraphics/TR-100](https://github.com/usgraphics/TR-100). One bash file, ~330 lines. Designed for AMD EPYC + Debian + ZFS-on-root + VMware. Wired into `.bashrc` so the banner prints on every interactive login.
- **Why fork instead of contribute**: the upstream README literally says *"NOT MAINTAINED ON PURPOSE. DIG INTO THE SCRIPT AND ADAPT IT."* That's the contract. We adapt.
- **Why per-machine files instead of a config-driven script**: same contract. *"When you build a templating engine, a config file, a bunch of switches, etc; it adds 1) bloat 2) complexity 3) limits customization."* So instead of one branchy script with `if HOST == spark`, we keep one full standalone script per target. Three files, three forks of the same starting point. Diffs stay obvious; nothing to debug across hosts.

## What changed from TR-100

Tracked as a logical diff, not file-by-file:

| Section        | TR-100 (upstream)                            | This fork                                                         |
|----------------|----------------------------------------------|-------------------------------------------------------------------|
| OS detection   | Hardcoded Debian-shaped `${ID^} ${VERSION}`  | Uses `${NAME}` so Ubuntu/Debian/Fedora all render readably         |
| Hypervisor row | `lscpu | grep 'Hypervisor vendor'`           | **Replaced with `PLATFORM`** — hardcoded, easier to read on bare metal |
| ZFS branch     | First-class, with `zpool status` health row  | **Removed**. Falls back to `df /` always; re-add per-host if needed |
| CPU model      | `awk '{print $1" "$2" "$3" "$4}'`            | Per-target. Spark handles two `Model name` lines (hybrid cores); Linux/WSL collapse `(R)/(TM)/@ X.YGHz` noise |
| CPU freq       | `/proc/cpuinfo` "cpu MHz"                    | `lscpu` "CPU max MHz" (aarch64 has no `/proc/cpuinfo` MHz field)   |
| GPU            | None                                         | **New panel.** name + util bar + temp + power. Linux/WSL also show VRAM bar; Spark skips it (unified memory == system RAM, already shown) |
| `lastlog`      | awk fields broken on Ubuntu 24.04 (showed "2 16:09:13  -0500") | Reworked field indices; explicit "Never logged in" branch |
| IP filter      | Skips `lo`, `docker*`                        | Also skips `br-*`, `veth*` (cleaner output on hosts running containers) |

## Per-target notes

### `spark.sh` — DGX Spark / GB10

Quirks the parsers handle:

- **Hybrid cores**: `lscpu` prints **two** `Model name:` lines (one per cluster — Cortex-X925 perf + Cortex-A725 efficiency). Vanilla TR-100 takes the first 4 awk fields and produces garbage. Fix: read both into an array, render `NVIDIA GB10 Grace Blackwell` on the PROCESSOR row and the cluster pair on a new ARCH row.
- **`nvidia-smi` returns `[N/A]`** for `memory.total`, `memory.used`, `memory.free`, `power.limit` on GB10 — the GPU shares system RAM, so VRAM as a separate concept doesn't apply. The Spark panel uses only the fields that *do* work: `name, utilization.gpu, temperature.gpu, power.draw, clocks.current.graphics`. The MEMORY row already shows the unified pool.
- **No `cpu MHz` in `/proc/cpuinfo`** on aarch64. Use `lscpu`'s `CPU max MHz` (3900 on the X925 cluster).
- **`/proc/device-tree/model`** is empty on the Spark (unlike Jetson). Don't try to detect Spark from it; use the GB10 GPU as the marker (that's what `install.sh` does).
- **PLATFORM** is hardcoded `NVIDIA DGX Spark`. There's no clean DMI/device-tree string to read from.

### `linux.sh` — generic x86_64 workstation

Defaults assume:

- Single non-hybrid CPU package. `Core(s) per socket` × `Socket(s)` makes sense.
- Optional discrete NVIDIA GPU. Section is gated on `command -v nvidia-smi && nvidia-smi -L`.
- Standard `df /` for disk. If you want NVMe-specific or `/raid` rows, add them in the render block — that's exactly the philosophy.

### `wsl.sh` — Windows Subsystem for Linux 2

Same as `linux.sh` plus:

- `cpu_platform="WSL2 on Windows"`.
- GPU section will only fire if you've installed the WSL2 NVIDIA driver and `nvidia-smi` works inside WSL. Most Windows boxes won't pass that check; the GPU panel will silently disappear.
- `MACHINE IP` shows the WSL2 NAT'd address (e.g. `172.x.x.x`), not the Windows host's LAN IP. Getting the host IP from inside WSL is fragile; not worth the parser. Add a static row if you really want it.

## Adding a new target

The whole machinery: copy `spark.sh` (or whichever is closest to the new box), rename to `<host>.sh`, edit four things at the top:

```bash
report_subtitle="..."   # the banner subtitle
cpu_platform="..."      # the PLATFORM row value
```

Then run:

```bash
./install.sh <host>     # forces this target, symlinks ~/.machine_report.sh, wires bashrc
```

Done. Don't be tempted to extract shared utilities into a `lib/` — the duplication *is* the design. When `Cortex-Z9000` ships and a new lscpu format breaks the parser, you fix one file, not a fragile shared helper that has to handle every machine you've ever touched.

## Updating

```bash
cd ~/machine-report && git pull
```

`~/.machine_report.sh` is a symlink into the working tree, so the next login picks up changes. No re-install needed.

## Things deliberately not done

- **No colors.** Per upstream design philosophy. The bar chars + box drawing are all the visual structure needed.
- **No multi-GPU loop.** The Spark has one GPU; if you adapt this for an 8×H100 pod, write a loop over `nvidia-smi -L` lines in that target file. Don't bake it into shared code.
- **No emoji.** Upstream rule. Keeps width math simple.
- **No async / no caching.** Banner runs in <100ms; not worth the complexity.
- **No fallback for systems missing `lscpu`/`nvidia-smi`/`lastlog`.** If you're on a system without these, you'll know — and you'll edit the script. That's the whole point.
