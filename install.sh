#!/usr/bin/env bash
# Taskwarrior 2.6.2 on this machine: Termux gets the task2 deb, Linux builds the 2.6.2 release into
# ~/.local (no sudo).
#
#   curl -fsSL https://raw.githubusercontent.com/linuxcaffe/taskwarrior-2.6/main/install.sh | bash
#
# 2.6.x already there: says so, changes nothing. 3.x there: removes nothing without a yes, and saves
# your tasks (task export) before it removes anything. Missing build tools: prints the one line that
# installs them. Run it again any time; it only acts when there's something to do.
#
# TASK_PREFIX=/somewhere builds into /somewhere instead of ~/.local (it must be writable by you).
# Questions are read from the terminal; with none, each takes its default (no).
# Everything runs from main, called on the last line: a download cut short runs nothing.

set -euo pipefail

RAW="https://raw.githubusercontent.com/linuxcaffe/taskwarrior-2.6/main"
REPO="https://github.com/linuxcaffe/taskwarrior-2.6"
DEB="task2_2.6.2-3_aarch64.deb"
DEB_SHA256="bd80e37006fc59a4faaba4a74d99883bc1e4141c711c5fc4775625f667b594a8"
SRC="task-2.6.2.tar.gz"
SRC_SHA256="b1d3a7f000cd0fd60640670064e0e001613c9e1cb2242b9b3a9066c78862cfec"
PREFIX_DIR="${TASK_PREFIX:-$HOME/.local}"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/taskwarrior-2.6/build.log"
WORK=""   # a temp folder, removed on exit

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

tilde() { printf '%s' "${1/#$HOME/\~}"; }

is_termux() { [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == /data/data/com.termux* ]]; }

# ask "question" default(y|n): 0 for yes. Reads the terminal, not stdin (stdin is this script under curl | bash).
ask() {
    local q=$1 def=$2 hint reply
    [ "$def" = y ] && hint="Y/n" || hint="y/N"
    if { exec 3</dev/tty; } 2>/dev/null; then
        printf '%s [%s] ' "$q" "$hint" >/dev/tty
        read -r reply <&3 || reply=""
        exec 3<&-
    else
        say "$q [$hint] (no terminal: taking the default, $def)"
        reply=""
    fi
    reply=${reply:-$def}
    [[ $reply =~ ^[Yy] ]]
}

task_version() { command -v task >/dev/null 2>&1 && task --version 2>/dev/null </dev/null | head -1 || true; }

# fetch FILE-IN-REPO SHA256: download into $WORK (made by main: not here, this runs in $(…)), check it,
# print its path
fetch() {
    local name=${1##*/} url="$RAW/$1"
    local bar=-s; [ -t 2 ] && bar=--progress-bar
    curl -fSL --retry 3 "$bar" "$url" -o "$WORK/$name" || fail "could not download $url"
    printf '%s  %s\n' "$2" "$WORK/$name" | sha256sum -c --status \
        || fail "$name doesn't match its sha256 ($2): not using it"
    printf '%s' "$WORK/$name"
}

# The package manager that owns a file, as "manager package", or nothing
owner() {
    local f=$1 p
    if command -v dpkg >/dev/null 2>&1 && p=$(dpkg -S "$f" 2>/dev/null); then
        printf 'apt %s' "${p%%:*}"
    elif command -v pacman >/dev/null 2>&1 && p=$(pacman -Qqo "$f" 2>/dev/null); then
        printf 'pacman %s' "$p"
    elif command -v rpm >/dev/null 2>&1 && p=$(rpm -qf --qf '%{NAME}' "$f" 2>/dev/null); then
        printf 'dnf %s' "$p"
    fi
}

save_tasks() {  # save_tasks VERSION: task export into ~/tasks-from-VERSION.json, or stop
    local out="$HOME/tasks-from-$1.json"
    if task rc.hooks=off export >"$out" 2>/dev/null </dev/null && [ "$(head -c1 "$out")" = "[" ]; then
        ok "your tasks saved in $out ($(grep -c '"uuid"' "$out" || true) tasks)"
    else
        fail "couldn't save your tasks with task export (into $out): nothing removed"
    fi
}

# Taskwarrior $1 (not 2.6) is installed: offer to replace it. 0 when it's gone, else exits.
replace_other() {
    local v=$1 path pm pkg
    path=$(readlink -f "$(command -v task)")
    warn "Taskwarrior $v is installed ($path), not 2.6."
    read -r pm pkg <<<"$(owner "$path")" || true
    if [ -z "${pm:-}" ]; then
        say "        It doesn't belong to a package, so this leaves it alone. Save your tasks"
        say "        (task export > ~/tasks-from-$v.json), remove $path, then run this again."
        exit 1
    fi
    local remove
    case "$pm" in
        apt)    remove="apt remove -y $pkg"; is_termux || remove="sudo $remove" ;;
        pacman) remove="sudo pacman -R --noconfirm $pkg" ;;
        dnf)    remove="sudo dnf remove -y $pkg" ;;
    esac
    say "        Replacing it: your tasks are saved first (task export into ~/tasks-from-$v.json),"
    say "        then '$remove' (your ~/.task stays as it is), then 2.6.2 is installed."
    if ! ask "Replace Taskwarrior $v with 2.6.2?" n; then
        say "        Nothing changed. To do it yourself: task export > ~/tasks-from-$v.json; $remove;"
        say "        then run this again. More in $REPO#have-3x-already-save-your-tasks-first"
        exit 1
    fi
    save_tasks "$v"
    $remove </dev/null || fail "'$remove' failed; your tasks are saved, nothing else changed"
    hash -r
    ok "removed $pkg ($v)"
    if [ "$pm" = apt ] && ! is_termux; then  # Termux: task2 replaces it by name, nothing to pin
        local pin=/etc/apt/preferences.d/taskwarrior-2.6.pref
        printf 'Package: taskwarrior\nPin: version 3.*\nPin-Priority: -1\n' | sudo tee "$pin" >/dev/null \
            && ok "apt won't install taskwarrior 3.x again ($pin)" \
            || warn "couldn't write $pin; see $REPO#keeping-3x-away"
    elif [ "$pm" != apt ]; then
        say "        To keep 3.x from coming back: $REPO#keeping-3x-away"
    fi
}

install_termux() {
    local arch deb
    arch=$(uname -m)
    case "$arch" in
        aarch64|arm64) ;;
        *) fail "the task2 deb is for aarch64 (most phones); this device is $arch. termux/build.sh in $REPO is the recipe to build it." ;;
    esac
    say "Downloading $DEB"
    deb=$(fetch "termux/$DEB" "$DEB_SHA256")
    # apt installs its dependencies too (libc++, libgnutls, libuuid, libandroid-glob); dpkg -i would just fail
    apt install -y "$deb" </dev/null || fail "apt install $DEB failed"
    hash -r
    local v; v=$(task_version)
    [[ $v == 2.6.* ]] || fail "installed $DEB, but task --version says '${v:-nothing}'"
    ok "Taskwarrior $v ($(command -v task)), as task2: pkg upgrade never swaps it for 3.x"
}

# What to install for the build, as one line for this machine's package manager
deps_line() {
    if command -v apt-get >/dev/null 2>&1; then say "sudo apt install cmake make g++ uuid-dev libgnutls28-dev"
    elif command -v dnf >/dev/null 2>&1; then  say "sudo dnf install cmake make gcc-c++ libuuid-devel gnutls-devel"
    elif command -v pacman >/dev/null 2>&1; then say "sudo pacman -S --needed base-devel cmake util-linux-libs gnutls"
    else say "cmake, make, a C++ compiler, and the development files of libuuid and gnutls"
    fi
}

has_header() { printf '#include <%s>\n' "$1" | c++ -E -x c++ - >/dev/null 2>&1; }

install_linux() {
    local missing=() c
    for c in cmake make c++ tar; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    if command -v c++ >/dev/null 2>&1; then
        has_header uuid/uuid.h     || missing+=("uuid headers")
        has_header gnutls/gnutls.h || missing+=("gnutls headers")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        warn "building 2.6.2 needs: ${missing[*]}"
        say "        $(deps_line)"
        fail "install those, then run this again"
    fi
    ok "build tools"
    mkdir -p "$PREFIX_DIR" 2>/dev/null && [ -w "$PREFIX_DIR" ] \
        || fail "$PREFIX_DIR isn't writable by you; this doesn't use sudo (pick another TASK_PREFIX)"

    say "Downloading $SRC"
    local tgz jobs
    tgz=$(fetch "source/$SRC" "$SRC_SHA256")
    tar xzf "$tgz" -C "$WORK"
    jobs=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
    mkdir -p "${LOG%/*}"
    say "Building Taskwarrior 2.6.2 (a couple of minutes; the log is $(tilde "$LOG"))"
    # CMAKE_POLICY_VERSION_MINIMUM: CMake 4 refuses 2.6.2's cmake_minimum_required(3.0); older CMake ignores it
    if ! ( cd "$WORK/task-2.6.2" &&
           cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
                 -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR" . &&
           make -j"$jobs" && make install ) >"$LOG" 2>&1 </dev/null; then
        tail -25 "$LOG" >&2
        fail "the build failed (the last lines are above, all of it in $(tilde "$LOG"))"
    fi
    # What make install put where, kept with it: removing it is xargs rm -f < this file
    local list="$PREFIX_DIR/share/doc/task/install_manifest.txt"
    { cat "$WORK/task-2.6.2/install_manifest.txt"; printf '%s\n' "$list"; } >"$list" 2>/dev/null || true
    local bin="$PREFIX_DIR/bin/task" v
    v=$("$bin" --version 2>/dev/null </dev/null | head -1 || true)
    [[ $v == 2.6.* ]] || fail "built and installed, but $bin --version says '${v:-nothing}'"
    ok "Taskwarrior $v in $(tilde "$bin")"

    hash -r
    local first; first=$(command -v task || true)
    if [ -z "$first" ]; then
        warn "$(tilde "$PREFIX_DIR/bin") isn't on your PATH; add this to your shell's rc file:"
        if [ "$PREFIX_DIR" = "$HOME/.local" ]; then say '        export PATH="$HOME/.local/bin:$PATH"'
        else say "        export PATH=\"$PREFIX_DIR/bin:\$PATH\""; fi
    elif [ "$(readlink -f "$first")" != "$(readlink -f "$bin")" ]; then
        warn "another task comes first on your PATH: $first ($("$first" --version 2>/dev/null </dev/null | head -1))"
        say "        Put $(tilde "$PREFIX_DIR/bin") before it, or remove that one."
    fi
    say "        Your package manager doesn't know about this task, so it never upgrades it to 3.x."
    say "        Removing it, should you ever: xargs rm -f < $(tilde "$list")"
}

main() {
    say "Taskwarrior 2.6.2"
    say ""
    command -v curl >/dev/null 2>&1 || fail "curl not found: install it, then run this again"
    trap '[ -z "$WORK" ] || rm -rf "$WORK"' EXIT

    local v; v=$(task_version)
    case "$v" in
        2.6.*) ok "Taskwarrior $v is installed ($(command -v task)): nothing to do"; return 0 ;;
        "")    ;;
        *)     replace_other "$v" ;;
    esac

    case "$(uname -s)" in
        Linux) ;;
        *) fail "this installs on Linux and Termux; $(uname -s) isn't either yet" ;;
    esac
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/taskwarrior-2.6.XXXXXX")
    if is_termux; then install_termux; else install_linux; fi

    say ""
    if [ -f "$HOME/.taskrc" ]; then say "Done."; else say "Done. task makes ~/.taskrc the first time you run it."; fi
}

main "$@"
