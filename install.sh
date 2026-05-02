#!/bin/bash
# install.sh — pick a target and wire it into ~/.machine_report.sh + ~/.bashrc
#
# Usage:
#   ./install.sh                  # auto-detect
#   ./install.sh spark            # force target
#   ./install.sh --target=linux   # equivalent
#   ./install.sh --uninstall      # remove symlink + bashrc snippet
#
# What it does:
#   1) Symlinks ~/.machine_report.sh → <repo>/<target>.sh
#   2) Appends an interactive-shell guard to ~/.bashrc (only if not already present)
#   3) Runs the script once so you can see it
#
# Re-running is safe; the bashrc snippet is fenced with markers and only added once.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$HOME/.machine_report.sh"
BASHRC="$HOME/.bashrc"
MARK_BEGIN="# >>> machine-report >>>"
MARK_END="# <<< machine-report <<<"

target=""
uninstall=0
for arg in "$@"; do
    case "$arg" in
        --uninstall)        uninstall=1 ;;
        --target=*)         target="${arg#--target=}" ;;
        spark|linux|wsl)    target="$arg" ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

remove_bashrc_block() {
    if grep -qF "$MARK_BEGIN" "$BASHRC" 2>/dev/null; then
        # delete the marker block in place
        local tmp
        tmp=$(mktemp)
        awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
            $0 == b {skip=1; next}
            $0 == e {skip=0; next}
            !skip {print}
        ' "$BASHRC" > "$tmp"
        mv "$tmp" "$BASHRC"
    fi
}

if [ "$uninstall" = "1" ]; then
    [ -L "$LINK" ] && rm -- "$LINK"
    remove_bashrc_block
    echo "Uninstalled. (You may need to start a new shell.)"
    exit 0
fi

# Auto-detect target if not supplied
if [ -z "$target" ]; then
    if command -v nvidia-smi &>/dev/null && nvidia-smi -L 2>/dev/null | grep -qi 'GB10'; then
        target="spark"
    elif grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        target="wsl"
    else
        target="linux"
    fi
    echo "Auto-detected target: $target"
fi

src="$REPO_DIR/$target.sh"
if [ ! -f "$src" ]; then
    echo "No such target: $target ($src missing)" >&2
    echo "Available: $(ls "$REPO_DIR"/*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | grep -v '^install$' | tr '\n' ' ')" >&2
    exit 1
fi

chmod +x "$src"

# Symlink
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    backup="$LINK.bak.$(date +%s)"
    echo "Backing up existing $LINK → $backup"
    mv "$LINK" "$backup"
fi
ln -sfn "$src" "$LINK"
echo "Linked $LINK → $src"

# bashrc snippet (idempotent via markers)
if ! grep -qF "$MARK_BEGIN" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<EOF

$MARK_BEGIN
# Machine Report on interactive login (managed by machine-report/install.sh)
if [[ \$- == *i* ]] && [ -x "\$HOME/.machine_report.sh" ]; then
    "\$HOME/.machine_report.sh"
fi
$MARK_END
EOF
    echo "Added bashrc snippet."
else
    echo "bashrc snippet already present — leaving it alone."
fi

echo
echo "── preview ─────────────────────────────────────────────────"
"$LINK"
