# machine-report

Tabular SSH-login banner. Forked from [usgraphics/TR-100](https://github.com/usgraphics/TR-100), rewritten per-machine. One self-contained bash script per target — no config, no abstractions, edit the source.

```
┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐
├┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┤
│                  NEWJORDAN                  │
│          DGX SPARK MACHINE REPORT           │
├───────────────┬─────────────────────────────┤
│ OS            │ Ubuntu 24.04 Noble          │
│ KERNEL        │ Linux 6.17.0-1014-nvidia    │
├───────────────┼─────────────────────────────┤
│ HOSTNAME      │ spark-2949                  │
│ MACHINE IP    │ 192.168.1.165               │
│ USER          │ frosty40                    │
├───────────────┼─────────────────────────────┤
│ PROCESSOR     │ NVIDIA GB10 Grace Blackwell │
│ ARCH          │ Cortex-X925 + Cortex-A725   │
│ CORES         │ 20 (10P + 10E)              │
│ PLATFORM      │ NVIDIA DGX Spark            │
│ CPU FREQ      │ 3.90 GHz                    │
│ LOAD  1m      │ ████████████████░░░░░░░░░░░ │
├───────────────┼─────────────────────────────┤
│ GPU           │ NVIDIA GB10                 │
│ GPU UTIL      │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ GPU TEMP      │ 58 °C                       │
│ GPU POWER     │ 15.27 W                     │
│ GPU CLOCK     │ 2411 MHz                    │
└───────────────┴─────────────────────────────┘
```

## Targets

| File       | For                                                               |
|------------|-------------------------------------------------------------------|
| `spark.sh` | NVIDIA DGX Spark (GB10, aarch64, hybrid Cortex-X925/A725, unified memory) |
| `linux.sh` | Generic x86_64 Linux workstation, optional discrete NVIDIA GPU    |
| `wsl.sh`   | WSL2 on Windows. GPU section only renders if CUDA-on-WSL is set up |

## Install on a new box

```bash
git clone https://github.com/newjordan/machine-report.git ~/machine-report
cd ~/machine-report && ./install.sh
```

`install.sh` auto-detects (Spark via GB10 in `nvidia-smi -L`, WSL via `/proc/version`, else generic Linux). Force a target with `./install.sh spark|linux|wsl`. Re-running is idempotent. Uninstall with `./install.sh --uninstall`.

After install, **start a new shell** (or `source ~/.bashrc`) to see the banner.

## Update everywhere

```bash
cd ~/machine-report && git pull
```

That's it — `~/.machine_report.sh` is a symlink into the repo, so a `git pull` updates the next login banner. No re-install needed.

## Customize per host

Edit the top of `<target>.sh`:

```bash
report_title="NEWJORDAN"
report_subtitle="DGX SPARK MACHINE REPORT"
cpu_platform="NVIDIA DGX Spark"
```

Layout knobs (`MAX_DATA_LEN` etc.) are right below. Want a wider table? Bump `MAX_DATA_LEN` to 40+. Want different rows? Edit the render block at the bottom — it's 1:1 `printf`s, no loops to chase.

## Font

Designed for **Berkeley Mono** (or any monospace with full Unicode box-drawing `U+2500–257F` and block elements `U+2580–259F`). Berkeley Mono is the same studio that wrote the original TR-100 — perfect fit. Install on **client** terminals (where you're typing), not on the SSH'd-into machines.

See [`TRANSITION.md`](TRANSITION.md) for the philosophy, the diff against TR-100, and per-target gotchas.

## License

BSD-3-Clause (inherited from TR-100). See `LICENSE`.
