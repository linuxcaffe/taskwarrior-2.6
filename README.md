# Taskwarrior 2.6

The best source for the best version of `task`: **Taskwarrior 2.6.2**, on Linux or Android.

Taskwarrior 3.x is a different program behind the same name: a new storage engine, a new sync, and
features from 2.x dropped along the way. Distributions are replacing 2.6.2 with it (Termux already
has), and the hooks, scripts and clients written for 2.6 stop working when it lands. This repo keeps
2.6.2 within reach: the sources, a working Android package, recipes to build more, and how to keep 3.x
from coming back.

The tools that work with 2.6.2 (hooks, a wrapper, a web UI, sync between machines) live in
[awesome-taskwarrior](https://github.com/linuxcaffe/awesome-taskwarrior).

## One command

```bash
curl -fsSL https://raw.githubusercontent.com/linuxcaffe/taskwarrior-2.6/main/install.sh | bash
```

On Termux it installs the `task2` deb (below); on Linux it builds the 2.6.2 release into `~/.local`, without
sudo (a couple of minutes), or prints the one line that installs the build tools it's missing. 2.6.x already
there: it says so and changes nothing. A 3.x there: it offers to replace it, and on a yes saves your tasks
(`task export`) before removing anything; on Debian and Ubuntu it also stops apt from bringing 3.x back.
Running it again is harmless. With [awesome-taskwarrior](https://github.com/linuxcaffe/awesome-taskwarrior)'s
`tw`, the same thing is `tw -I taskwarrior`.

The sections below are what it does, by hand.

## Have 3.x already? Save your tasks first

3.x keeps tasks in `taskchampion.sqlite3`, which 2.6.2 can't read, and tasks added under 3.x aren't in
2.6's `*.data` files. Before removing 3.x, while it still runs:

```bash
task export > ~/tasks-from-3.json
```

`export` only reads. Bringing that file into 2.6.2 (`task import`) is being tested; until it is, keep
the file and a copy of `~/.task`.

## Android (Termux)

`task2` is Taskwarrior 2.6.2 for Termux on aarch64 (most phones): Termux's own `taskwarrior` 2.6.2-3
package, renamed so it can't be "upgraded" to 3.x.

```bash
pkg uninstall taskwarrior        # only if 3.x is installed (save your tasks first, above)
curl -fLO https://raw.githubusercontent.com/linuxcaffe/taskwarrior-2.6/main/termux/task2_2.6.2-3_aarch64.deb
echo "bd80e37006fc59a4faaba4a74d99883bc1e4141c711c5fc4775625f667b594a8  task2_2.6.2-3_aarch64.deb" | sha256sum -c
apt install ./task2_2.6.2-3_aarch64.deb
task --version                   # 2.6.2
```

`apt install` (not `dpkg -i`) also installs what it needs: `libc++`, `libgnutls`, `libuuid`,
`libandroid-glob`.

## Linux: build from source

Tested 2026-10-28 with CMake 3.22 and CMake 4.4.

**1. Build tools.** Debian, Ubuntu, Raspberry Pi OS:

```bash
sudo apt install cmake make g++ uuid-dev libgnutls28-dev
```

Fedora: `cmake make gcc-c++ libuuid-devel gnutls-devel`. Arch: `base-devel cmake util-linux-libs gnutls`.
(Not yet tested on those; corrections welcome.)

**2. Build.**

```bash
curl -fLO https://raw.githubusercontent.com/linuxcaffe/taskwarrior-2.6/main/source/task-2.6.2.tar.gz
echo "b1d3a7f000cd0fd60640670064e0e001613c9e1cb2242b9b3a9066c78862cfec  task-2.6.2.tar.gz" | sha256sum -c
tar xzf task-2.6.2.tar.gz && cd task-2.6.2
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .
make -j"$(nproc)"
```

**3. Install,** either for everyone (`/usr/local/bin/task`):

```bash
sudo make install
```

or just for you, no sudo (`~/.local/bin/task`; make sure `~/.local/bin` is on your `PATH`):

```bash
cmake -DCMAKE_INSTALL_PREFIX="$HOME/.local" . && make install
```

**Remove a distribution 3.x first,** or it may sit earlier on your `PATH`: `sudo apt remove taskwarrior`
(Debian, Ubuntu), `sudo pacman -R task` (Arch), `sudo dnf remove task` (Fedora). Save your tasks first.

### Why not upstream's own instructions?

The `INSTALL` and `README.md` inside the 2.6.2 tarball date from 2022 and no longer work as written:

- **CMake 4 refuses to configure it.** The tarball asks for `cmake_minimum_required(VERSION 3.0)`, and CMake
  4 dropped compatibility with anything below 3.5: `Compatibility with CMake < 3.5 has been removed`.
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` fixes it, and older CMake ignores it.
- **`libgnutls-dev` no longer exists** on Debian or Ubuntu; it's `libgnutls28-dev`.
- **Its "Install" section sends you to distribution packages,** which ship or will ship 3.x.

## Keeping 3.x away

- **Termux:** nothing to do. `task2` conflicts with `taskwarrior`, so `pkg upgrade` only ever offers newer
  `task2`; 3.x comes back only if you ask for `taskwarrior` by name.
- **Built from source:** your package manager doesn't know about it, so it never upgrades it. It can still
  install a 3.x alongside (as a dependency of something), so add the hold below too.
- **Debian, Ubuntu:** forbid 3.x of the `taskwarrior` package (a 2.6 one stays allowed). Create
  `/etc/apt/preferences.d/taskwarrior-2.6.pref` (the `.pref` matters: apt silently skips a file there
  whose name has any other extension, and `taskwarrior-2.6` would count as one):

  ```
  Package: taskwarrior
  Pin: version 3.*
  Pin-Priority: -1
  ```

- **Arch:** add `task` to `IgnorePkg` in `/etc/pacman.conf`.

## What's here

| Path | What | Source |
|---|---|---|
| `install.sh` | The one command above | this repo |
| `taskwarrior.meta`, `taskwarrior.install` | `tw -I taskwarrior`: its awesome-taskwarrior registry entry | this repo |
| `source/task-2.6.2.tar.gz` | The official 2.6.2 release, kept here in case it ever disappears | [GothenburgBitFactory/taskwarrior v2.6.2](https://github.com/GothenburgBitFactory/taskwarrior/releases/tag/v2.6.2) |
| `termux/task2_2.6.2-3_aarch64.deb` | Taskwarrior 2.6.2 for Termux, packaged as `task2` | Termux's `taskwarrior_2.6.2-3`, renamed by `repack-task2.sh` |
| `termux/repack-task2.sh` | Renames the Termux deb to `task2`, adds `Conflicts: taskwarrior` | this repo |
| `termux/build.sh` | Termux's recipe for 2.6.2-3 | [termux-packages @ 22a5438dae](https://github.com/termux/termux-packages/blob/22a5438daeff3cacd74c8316e044f76883f825dd/packages/taskwarrior/build.sh), the last before 3.x |
| `debian/task_2.6.2+dfsg-1.debian.tar.xz` | Debian's packaging of 2.6.2 (patches, rules, control) | Debian, `task` 2.6.2+dfsg-1 (2022-04-01) |
| `debian/task_2.6.2+dfsg.orig.tar.xz` | The source that packaging builds from (upstream minus `doc/ref`) | Debian |

Checksums of all of them: `SHA256SUMS` (`sha256sum -c SHA256SUMS`).

## Coming

- A `task2` deb for Debian, Ubuntu and Raspberry Pi OS (amd64, arm64), from Debian's packaging above.
- Rebuilding the Termux deb from its recipe, rather than keeping the one file.
- A tested way to bring tasks saved from 3.x into 2.6.2.

## License

MIT, like Taskwarrior. This repo's own files: see `LICENSE`. Taskwarrior is © 2006–2021 Tomas Babej, Paul
Beckingham, Federico Hernandez and contributors (MIT; the `LICENSE` inside the tarball). Debian's packaging is
© its Debian maintainers (MIT, `debian/copyright` inside it). Termux's recipe is under the package's own
license.
