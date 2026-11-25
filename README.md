# machine-report

A login banner: one Unicode table for the machine you just opened a shell on. It shows the operating system, network, CPU, load, GPU when `nvidia-smi` works, disk, memory, last login, and uptime.

Each target is one bash script. There is no config file. Change a host by editing that script.

```
┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐
├┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┤
│                NEWJORDAN                 │
│           LINUX MACHINE REPORT           │
├───────────────┬──────────────────────────┤
│ OS            │ Ubuntu 24.04 Noble       │
│ KERNEL        │ Linux 6.12.113+          │
├───────────────┼──────────────────────────┤
│ HOSTNAME      │ cursor                   │
│ MACHINE IP    │ 172.30.0.2               │
│ CLIENT IP     │ local                    │
│ DNS 1         │ 198.18.0.53              │
│ USER          │ ubuntu                   │
├───────────────┼──────────────────────────┤
│ PROCESSOR     │ Intel Xeon Processor     │
│ CORES         │ 4 cores / 1 socket       │
│ PLATFORM      │ Linux Workstation        │
│ CPU FREQ      │ 2.40 GHz                 │
│ LOAD  1m      │ █░░░░░░░░░░░░░░░░░░░░░░░ │
│ LOAD  5m      │ ░░░░░░░░░░░░░░░░░░░░░░░░ │
│ LOAD 15m      │ ░░░░░░░░░░░░░░░░░░░░░░░░ │
├───────────────┼──────────────────────────┤
│ VOLUME        │ 7.08/253.29 GiB [2.8%]   │
│ DISK USAGE    │ █░░░░░░░░░░░░░░░░░░░░░░░ │
├───────────────┼──────────────────────────┤
│ MEMORY        │ 10.74/15.63 GiB [68.7%]  │
│ MEM USAGE     │ ████████████████░░░░░░░░ │
├───────────────┼──────────────────────────┤
│ LAST LOGIN    │ Never logged in          │
│ UPTIME        │ 21m                      │
└───────────────┴──────────────────────────┘
```

That block is the output of `./linux.sh` on the Ubuntu 24.04 host where this file was written (kernel `6.12.113+`). Ten runs of the same command on that host took between 0.1009 and 0.1072 seconds.

## Requirements

- bash 4.2 or newer. The suite below was run with bash 5.2.21.
- `awk`. That run used mawk 1.3.4.
- GNU coreutils (`df`, `nproc`, `uname`, `id`) and util-linux `lscpu`.
- Readable `/proc` and `/etc/os-release`.

Optional:

- `ip` from iproute2, or `ifconfig`, or `hostname -I`, for the machine address. With none of them the row says `No IP found`.
- `nvidia-smi` for the GPU panel.
- `lastlog` for the previous login. Without it the row says `unavailable`.

Column widths use Bash's character count, which follows the locale. When `C.utf8` is installed the script sets this process to `C.UTF-8` so a `LC_ALL=C` parent does not split the box. `lscpu`, `df`, and `lastlog` are still invoked with `LC_ALL=C` so their field names stay English.

## Targets

| File | Subtitle | CPU | GPU |
|------|----------|-----|-----|
| `linux.sh` | `LINUX MACHINE REPORT` | The first `Model name`. The summary is cores and sockets, and includes threads when `nproc` is higher than the core count. | Name, utilization, temperature, power, and VRAM when `nvidia-smi` returns a memory total. |
| `spark.sh` | `DGX SPARK MACHINE REPORT` | Two `Model name` lines become `NVIDIA GB10 Grace Blackwell` and an `ARCH` row. One line uses the same summary as `linux.sh`. | Utilization, temperature, power, and the graphics clock. No VRAM row: unified memory is already the memory row. |
| `wsl.sh` | `WSL2 MACHINE REPORT` | Same as `linux.sh`. | Same as `linux.sh`, so the panel stays hidden until `nvidia-smi` works inside WSL. |

On WSL, `MACHINE IP` is the address visible inside the guest.

## Install

```bash
git clone https://github.com/newjordan/machine-report.git ~/machine-report
cd ~/machine-report
./install.sh
```

With no argument, `./install.sh` chooses a target in this order:

1. `nvidia-smi -L` mentions `GB10` → `spark`
2. `/proc/version` mentions `microsoft` or `wsl` → `wsl`
3. otherwise → `linux`

Force a target with `./install.sh spark`, `./install.sh linux`, `./install.sh wsl`, or `./install.sh --target=linux`. The name must match `[a-z][a-z0-9_-]*`, and `<name>.sh` must be a file in this repository. `./install.sh --no-preview` skips the sample banner.

Install then:

1. Points `~/.machine_report.sh` at the chosen script. A regular file already at that path is moved to `~/.machine_report.sh.bak.<unix time>`.
2. Writes a marked block in `~/.bashrc`. The block runs the banner for an interactive shell whose stdout is a terminal. A later install rewrites the block only when the hook text changed, and it keeps the file mode.
3. Runs the banner once, unless you passed `--no-preview`.

Open a new interactive terminal to see it after that. `./install.sh --uninstall` removes the symlink and the marked block. The rest of `~/.bashrc` stays, including its permissions. A second uninstall prints `machine-report is not installed.`

## Update

```bash
cd ~/machine-report && git pull
```

`~/.machine_report.sh` points into the working tree, so the next shell runs the pulled script. Run `./install.sh` again when you want a different target, or when the bashrc hook itself changed.

## Rows

| Row | Where it comes from |
|-----|---------------------|
| OS | `NAME`, `VERSION_ID`, and `VERSION_CODENAME` in `/etc/os-release`. The codename's first letter is capitalized. |
| KERNEL | `uname -s` and `uname -r`. |
| HOSTNAME | `uname -n`. This does not ask DNS. |
| MACHINE IP | The first global address from `ip`, skipping loopback, docker, `br-*`, veth, and other virtual names. Then `ifconfig` (`inet` only). Then the first non-link-local address from `hostname -I`. |
| CLIENT IP | `SSH_CONNECTION`, then `SSH_CLIENT`, then `who`. `local` when there is no remote peer. |
| DNS | Every `nameserver` in `/etc/resolv.conf`, IPv4 and IPv6. |
| USER | `id -un`. |
| PROCESSOR | `lscpu` model name, with `(R)`, `(TM)`, and a trailing `GHz` removed. |
| ARCH | Spark only, and only when `lscpu` prints two model names. The first cluster is labeled P and the second E, which is the GB10 order. |
| CORES | Logical CPUs from `nproc`. Physical cores are `Core(s) per socket` times `Socket(s)`. |
| PLATFORM | The `cpu_platform` string at the top of that script. |
| CPU FREQ | `CPU max MHz` from `lscpu`, then `CPU MHz`, then `cpu MHz` in `/proc/cpuinfo`. `n/a` when all three are missing. |
| LOAD | The three fields of `/proc/loadavg`, each divided by the logical CPU count. The bar stops at full when load is above that count. |
| GPU | The first GPU from `nvidia-smi`. A failed query skips the panel. An `N/A` memory total skips the VRAM rows. Spark queries the graphics clock instead of memory. |
| VOLUME, DISK USAGE | `df -Pm /`. The unit is GiB because `-m` counts 1,048,576-byte blocks. |
| MEMORY, MEM USAGE | `MemTotal` and `MemAvailable` from `/proc/meminfo`. If `MemAvailable` is absent, free + buffers + cached is used. The unit is GiB. |
| LAST LOGIN, LOGIN FROM | `lastlog`, cut on the `From` and `Latest` header columns, so a blank From field does not slide the timestamp over. `LOGIN FROM` is omitted when From is empty. |
| UPTIME | `/proc/uptime`, printed as `1d 2h 3m`. A zero unit is left out, except a host that has been up for under a minute, which shows `0m`. |

Percentages use one decimal place. Sizes use two.

## Customize

The identity block is at the top of the target script:

```bash
report_title="NEWJORDAN"
report_subtitle="LINUX MACHINE REPORT"
cpu_platform="Linux Workstation"
```

Layout knobs next to it:

| Knob | What it controls | Value in these scripts |
|------|------------------|------------------------|
| `MAX_NAME_LEN` | Width of the label column. Longer labels end in `...`. | 13 |
| `MIN_DATA_LEN` | Narrowest data column. | 24 |
| `MAX_DATA_LEN` | Widest data column. Longer values end in `...`. | 48 |
| `BORDERS_AND_PADDING` | The `│` characters and spaces around the two columns. | 7 |

`BORDERS_AND_PADDING` is the punctuation in `print_data` (`│ `, ` │ `, ` │`). Leave it at 7 unless you change that format. The vertical rule follows `MAX_NAME_LEN`, so a wider label column stays lined up with the dividers.

Add or remove rows in the render block at the bottom of the file. It is one `print_data` per line. Copy the closest script when you add a machine, and keep that copy able to run by itself. [TRANSITION.md](TRANSITION.md) is the note on why the three files repeat the helpers instead of sharing a library.

## Development

```bash
sudo apt-get install shellcheck bats
make check
```

`make lint` is shellcheck on the four scripts. `make test` is the bats suite in `tests/`. This tree has 35 tests. The run recorded with this README used ShellCheck 0.9.0 and Bats 1.10.0. GitHub Actions runs `make check` on `ubuntu-24.04` (`.github/workflows/ci.yml`).

Tests feed fixtures through `MACHINE_REPORT_*` variables: paths for `/proc` and `lscpu` text, a canned `nvidia-smi` CSV, and stand-ins for `nproc` and `uname`. Leave them unset and the scripts read the live machine. They are a test seam, not settings to put in a shell profile.

Shared helpers are duplicated on purpose. `tests/common.bats` diffs `declare -f` so `linux.sh` and `wsl.sh` stay the same, and so `spark.sh` only diverges in `collect_cpu`, `read_gpu`, `main`, and `format_clock`. A helper fix has to land in each file the test compares.

## Font

The table uses box drawing (`U+2500`–`U+257F`) and block elements (`U+2580`–`U+259F`). A monospace font that includes both, Berkeley Mono among them, keeps the columns straight. Install it in the terminal you type in.

## License

BSD-3-Clause, inherited from [TR-100](https://github.com/usgraphics/TR-100). See `LICENSE`.
