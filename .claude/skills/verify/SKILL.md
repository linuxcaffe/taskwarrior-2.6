---
name: verify
description: How to test install.sh and taskwarrior.install without touching the real machine — a throwaway HOME, a PATH without task, fakes for apt/dpkg/sudo/uname to simulate Termux and a packaged 3.x, a pty to answer "y". Read before changing either installer.
---

# Verifying the installers

Nothing here touches the real `task`, `~/.task` or `/etc`. Worked out 2026-10-28 (the first release);
every case below passed then, and testing caught two real bugs (a temp dir made inside `$(…)`, and CMake's
`install_manifest.txt` lacking a final newline).

## The pieces

- **Throwaway HOME:** `H=$(mktemp -d)`, run with `env -i HOME=$H PATH=…`.
- **A PATH without task:** a folder of symlinks to everything in `/usr/bin` except `task`
  (`for f in /usr/bin/*; do [ "${f##*/}" = task ] || ln -s "$f" farm/; done`). Drop `cmake` from a copy for
  the "missing build tools" case; a fake `c++` that fails on `uuid` input for missing headers (`CPATH` can't
  hide headers, it only adds).
- **A 3.x:** a fake `task` printing `3.4.1` (and a JSON array for `export`). Owned by a package: a fake
  `dpkg` printing `taskwarrior: $2`; a fake `sudo` that logs its arguments, swallows stdin, and deletes the
  fake task when asked to `apt remove`. Set `TASK_PREFIX=/proc/nope` to stop right after the replace part
  instead of building.
- **Answering "y":** `printf 'y\n' | /usr/bin/script -qec "bash install.sh" /dev/null` (a pty, so
  `/dev/tty` works). **No terminal:** `setsid -w bash install.sh </dev/null` (`-w`, or the exit code is lost).
- **Termux:** `TERMUX_VERSION=0.118.1`, a fake `uname` (`-m` → `aarch64`, else `Linux`) and a fake `apt` that
  checks the deb with `dpkg-deb -f "$3" Package Version Conflicts` and then writes a fake `task` printing
  2.6.2. The real thing ran on s5 via tw-mobilize before this repo existed.

## The cases

2.6.x present (nothing to do) · no task → full build (~1m50s on 4 cores; then
`xargs rm -f < $H/.local/share/doc/task/install_manifest.txt` must leave 0 files) · missing cmake · missing
headers · 3.x unowned (left alone, exit 1) · 3.x packaged, no terminal (default no, exit 1) · 3.x packaged,
"y" (tasks saved first, remove, apt pin) · Termux aarch64 · Termux x86_64 (refused) · `taskwarrior.install`
from a staged folder: install, remove, and a failing run that must leave no command and no manifest line.

## Live, after a release

`curl … awesome-taskwarrior/main/install.sh | bash` into a throwaway HOME, then `tw -I taskwarrior`,
`tw -l`, `tw --verify taskwarrior`, `tw -r taskwarrior`. GitHub's raw cache can serve the previous registry
for ~5 minutes after a release.
