#!/bin/bash
# install.sh — pick a target and wire it into ~/.machine_report.sh + ~/.bashrc
#
# Usage:
#   ./install.sh                  # auto-detect
#   ./install.sh spark            # force target
#   ./install.sh --target=linux   # equivalent
#   ./install.sh --no-preview     # skip the sample banner
#   ./install.sh --uninstall      # remove symlink + bashrc snippet
#
# What it does:
#   1) Symlinks ~/.machine_report.sh → <repo>/<target>.sh
#   2) Ensures an interactive-terminal guard in ~/.bashrc
#   3) Runs the script once so you can see it (unless --no-preview)
#
# Re-running is safe. The bashrc snippet is fenced with markers and is
# rewritten in place when this script's hook changes.

MARK_BEGIN="# >>> machine-report >>>"
MARK_END="# <<< machine-report <<<"

usage() {
    cat <<'EOF'
Usage: ./install.sh [spark|linux|wsl] [--target=NAME] [--no-preview] [--uninstall]

  (no target)     auto-detect: GB10 GPU → spark, WSL → wsl, otherwise linux
  spark|linux|wsl install that target
  --target=NAME   same, NAME must match [a-z][a-z0-9_-]*
  --no-preview    do not run the banner at the end
  --uninstall     remove ~/.machine_report.sh symlink and the bashrc hook
EOF
}

detect_target() {
    local version_file="${MACHINE_REPORT_PROC_VERSION:-/proc/version}" smi
    smi=$(command -v nvidia-smi 2>/dev/null || true)
    if [[ -n "$smi" ]] && "$smi" -L 2>/dev/null | grep -qi 'GB10'; then
        printf '%s\n' spark
        return
    fi
    if [[ -r "$version_file" ]] && grep -qiE 'microsoft|wsl' "$version_file"; then
        printf '%s\n' wsl
        return
    fi
    printf '%s\n' linux
}

valid_target_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_-]*$ ]]
}

bash_hook() {
    cat <<EOF
$MARK_BEGIN
# Machine report for interactive terminals (managed by machine-report/install.sh).
if [[ \$- == *i* && -t 1 && -x "\$HOME/.machine_report.sh" ]]; then
    "\$HOME/.machine_report.sh"
fi
$MARK_END
EOF
}

remove_bashrc_block() {
    local bashrc="$1" tmp
    [[ -f "$bashrc" ]] || return 0
    if ! grep -qF "$MARK_BEGIN" "$bashrc"; then
        return 0
    fi
    tmp=$(mktemp)
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip { print }
    ' "$bashrc" > "$tmp"
    cat "$tmp" > "$bashrc"
    rm -f "$tmp"
}

sync_bashrc() {
    local bashrc="$1" hook current
    hook=$(bash_hook)
    if [[ ! -e "$bashrc" ]]; then
        touch "$bashrc"
    fi
    if grep -qF "$MARK_BEGIN" "$bashrc"; then
        current=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
            $0 == b { capture = 1 }
            capture { print }
            $0 == e { capture = 0 }
        ' "$bashrc")
        if [[ "$current" == "$hook" ]]; then
            printf '%s\n' "bashrc snippet already current."
            return 0
        fi
        remove_bashrc_block "$bashrc"
        printf '%s\n' "Updated bashrc snippet."
    else
        printf '%s\n' "Added bashrc snippet."
    fi
    # Keep a blank line between the user's rc and the hook.
    if [[ -s "$bashrc" ]] && [[ -n "$(tail -c 1 "$bashrc")" ]]; then
        printf '\n' >> "$bashrc"
    fi
    printf '\n%s\n' "$hook" >> "$bashrc"
}

main() {
    set -euo pipefail
    local repo_dir link bashrc target="" uninstall=0 preview=1 arg src repo_real src_real backup removed=0
    repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

    for arg in "$@"; do
        case "$arg" in
            --uninstall) uninstall=1 ;;
            --no-preview) preview=0 ;;
            --target=*)
                target="${arg#--target=}"
                if [[ -z "$target" ]]; then
                    printf '%s\n' "empty --target" >&2
                    exit 2
                fi
                ;;
            spark|linux|wsl) target="$arg" ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'unknown arg: %s\n' "$arg" >&2
                usage >&2
                exit 2
                ;;
        esac
    done

    : "${HOME:?HOME is not set}"
    link="$HOME/.machine_report.sh"
    bashrc="$HOME/.bashrc"

    if (( uninstall )); then
        if [[ -L "$link" ]]; then
            rm -- "$link"
            removed=1
        elif [[ -e "$link" ]]; then
            printf 'Left %s in place (it is not a symlink).\n' "$link" >&2
        fi
        if [[ -f "$bashrc" ]] && grep -qF "$MARK_BEGIN" "$bashrc"; then
            remove_bashrc_block "$bashrc"
            removed=1
        fi
        if (( removed )); then
            printf '%s\n' "Uninstalled. Start a new shell to drop the banner."
        else
            printf '%s\n' "machine-report is not installed."
        fi
        exit 0
    fi

    if [[ -z "$target" ]]; then
        target=$(detect_target)
        printf 'Auto-detected target: %s\n' "$target"
    fi
    if ! valid_target_name "$target"; then
        printf 'invalid target name: %s\n' "$target" >&2
        exit 2
    fi

    src="$repo_dir/$target.sh"
    if [[ ! -f "$src" ]]; then
        printf 'No such target: %s (%s missing)\n' "$target" "$src" >&2
        printf 'Available:' >&2
        local available
        available=$(find "$repo_dir" -maxdepth 1 -name '*.sh' -printf '%f\n' | sed 's/\.sh$//' | grep -vx install | tr '\n' ' ')
        printf ' %s\n' "$available" >&2
        exit 1
    fi
    repo_real=$(readlink -f "$repo_dir")
    src_real=$(readlink -f "$src")
    case "$src_real" in
        "$repo_real"/*) ;;
        *)
            printf 'refusing target outside the repo: %s\n' "$src_real" >&2
            exit 2
            ;;
    esac

    chmod +x "$src"

    if [[ -e "$link" && ! -L "$link" ]]; then
        backup="$link.bak.$(date +%s)"
        printf 'Backing up existing %s → %s\n' "$link" "$backup"
        mv "$link" "$backup"
    fi
    ln -sfn "$src" "$link"
    printf 'Linked %s → %s\n' "$link" "$src"

    sync_bashrc "$bashrc"

    if (( preview )); then
        printf '\n── preview ─────────────────────────────────────────────────\n'
        bash "$link"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
