# Info-ZIP for 16-bit MS-DOS

> [!IMPORTANT]
> **This is an unofficial, community-produced build. It is not an Info-ZIP release and is not endorsed by or supported by Info-ZIP.**
> Please do not report problems with these binaries to Info-ZIP or to the Zip-Bugs address.
> The C sources are compiled **completely unmodified** from the official Zip 3.0 and UnZip 6.0 releases — the only edits are to the Watcom makefiles, so that they can run on a modern POSIX build host. [The exact diff is documented below.](#what-was-modified)

Ready-to-run **16-bit real-mode MS-DOS** builds of Info-ZIP's `zip` 3.0 and `unzip` 6.0, plus a reproducible, fully automated build pipeline that produces them.

## Why this exists

Info-ZIP's official distribution site, `ftp.info-zip.org`, is no longer reachable. The sources are widely mirrored, but working **16-bit DOS binaries** are increasingly hard to find — most surviving builds are 32-bit DOS-extender versions that won't run on an 8088, 8086 or 286.

This repository keeps both the binaries and the sources available, and — more importantly — keeps the *build* reproducible, so the binaries never have to be taken on trust.

## Download

Grab the latest [**release**](../../releases/latest) — everything is in one archive.

| Asset | Contents |
|---|---|
| `infozip-dos16-<tag>.zip` | All seven DOS executables, upstream manuals, and the license |
| `zip30-source.zip` | Pristine, unmodified Zip 3.0 source |
| `unzip60-source.zip` | Pristine, unmodified UnZip 6.0 source |
| `SHA256SUMS` | Checksums for all of the above |

## What's included

| Program | Size | Purpose |
|---|---:|---|
| `ZIP.EXE` | 204,792 | Create and update archives |
| `UNZIP.EXE` | 153,744 | List, test and extract archives |
| `ZIPCLOAK.EXE` | 95,798 | Encrypt / decrypt archive entries |
| `ZIPSPLIT.EXE` | 94,034 | Split an archive across several disks |
| `ZIPNOTE.EXE` | 92,130 | Read and write archive comments |
| `UNZIPSFX.EXE` | 55,080 | Stub for self-extracting archives |
| `FUNZIP.EXE` | 32,220 | Filter: extract first member to stdout |

### Versioning

Tags look like `zip3.0-unzip6.0-r1`: the genuine upstream Info-ZIP version of each
program, followed by this project's build revision. The `r<n>` suffix is the only
part this project owns — it bumps if the same upstream sources are rebuilt (new
toolchain, packaging fix). Info-ZIP itself has never published a "1.0" of anything
here, so no invented version number is used.

## Requirements

Any **8086/8088 or later** CPU. These are pure real-mode `MZ` executables compiled with the 8086 instruction set only (`-0`) in the large memory model (`-ml`):

- no DOS extender, no DPMI, no `PE`/`NE`/`LE` header
- no 186/286/386 instructions
- MS-DOS 3.0 or later recommended

`ZIP.EXE` wants roughly 200 KB of free conventional memory; the others less. Upstream's default 32 KB compression window (`MEDIUM_MEM`) is used. On a very tight machine you can rebuild with a smaller window — see [Build options](#build-options).

## Verification

Every executable is checked to be a genuine real-mode `MZ` image with no protected-mode header. Beyond that, `ZIP.EXE` and `UNZIP.EXE` are round-trip tested under DOSBox-X configured as an **8086** (`cputype=8086`): the DOS build compresses a text file, a 20 KB random binary and a 90 KB executable, and the resulting archive is then verified two ways — extracted by the DOS `UNZIP.EXE` and compared byte-for-byte against the originals, and independently validated by a modern host `unzip`.

`test-dos.sh` runs this end to end.

### Testing status

Being explicit about what is and isn't covered, since these binaries are meant to be trusted by strangers:

| Program | Status |
|---|---|
| `ZIP.EXE` | Round-trip tested on an emulated 8086 — deflate and store paths, archive validated by an independent host `unzip` |
| `UNZIP.EXE` | Round-trip tested on an emulated 8086 — `-l`, `-t` and extraction, output compared byte-for-byte |
| `FUNZIP.EXE` | Smoke tested — extracts a member to stdout, output compared byte-for-byte |
| `ZIPSPLIT.EXE` | **Not functionally tested** — see below |
| `ZIPNOTE.EXE` | **Not functionally tested** — see below |
| `ZIPCLOAK.EXE` | **Not functionally tested.** Builds cleanly and is a valid real-mode image |
| `UNZIPSFX.EXE` | **Not functionally tested.** Builds cleanly and is a valid real-mode image |

`ZIPSPLIT` and `ZIPNOTE` are excluded from the automated harness because they prompt for confirmation, and Info-ZIP reads those prompts directly from the DOS console rather than from standard input — so redirected input cannot answer them and the session blocks indefinitely. This is upstream behaviour, not a defect in these builds, but it does mean they are unverified here. Test them interactively if you rely on them.

Testing is done under emulation (DOSBox-X as an 8086), not on physical vintage hardware. Reports from real machines are very welcome — please open an issue.

### Tip: set `TZ`

Info-ZIP warns `TZ environment variable not found, cannot use UTC times!!` on DOS, because the OS has no timezone concept. Timestamps still work; to silence it and get correct UTC handling, add a line like this to `AUTOEXEC.BAT`:

```
SET TZ=EST5EDT
```

## Building it yourself

You need `docker` (any host) or an x86-64 Linux machine, plus `python3` and `curl`. No emulator and no vintage hardware are involved — this is a straight cross-compile.

```sh
./setup-toolchain.sh   # fetch Open Watcom V2 (~128 MB, not vendored here)
./build.sh             # cross-compile; binaries land in ./out
./package.sh zip3.0-unzip6.0-r1   # assemble release assets in ./dist
```

`build.sh` runs the Watcom tools natively on x86-64 Linux, and otherwise inside an `amd64` container, so it works unchanged on Apple Silicon.

### Reproducibility

The build is bit-for-bit reproducible. Every published executable is byte-identical whether produced natively on GitHub's x86-64 Linux runners or in a container on macOS/Apple Silicon — verified by comparing the CI artifacts against a local build:

```
8e2485e1b1767c13360c902d4873ce5779e11b4ae7e4f192af0fff82a150101a  Zip.exe
458c895b4e2f147e1846ff66151b665241b472dd5ce5069d5681707b7a8eb81c  UnZip.exe
4426f4731a2bc6cf7ae3eacfacdbd584bd193944351d489c25b996a7207b4be4  ZipCloak.exe
fb7f665682c66dd58a34b899fa2832ec7e85248261dc1da183ad000a9b1b8cc9  ZipSplit.exe
9c7a3f3d31a7c71b5a56b430e7bd714a2c9fc92df4d5aa4a1962487c02afc3c3  ZipNote.exe
31cd0b68ab0a86ecc4ed1b2cba40eee0d391530de84dc6c5b4fae13288b728c0  UnZipSFX.exe
c614470ea7fbe88cc9a71a41a9f2828e5831ca079de45d524e313df68d9ed5cd  fUnZip.exe
```

You don't have to take the published binaries on trust: run `./setup-toolchain.sh && ./build.sh` and compare. The one caveat is that `setup-toolchain.sh` pulls Open Watcom's rolling `Current-build` snapshot, so a much later toolchain may eventually produce different output.

### Why Open Watcom

Open Watcom V2 is the only actively maintained compiler that still targets 16-bit real-mode DOS, and Info-ZIP ships a Watcom makefile (`msdos/makefile.wat`) for exactly this purpose. There is no macOS build of the toolchain, hence the container.

One wrinkle worth recording: Open Watcom's Linux installer is a self-extracting ELF binary that fails with `SIGFPE` under Rosetta on Apple Silicon. Its payload is simply a ZIP archive appended to the ELF, so `setup-toolchain.sh` extracts that directly instead of executing the installer.

### Build options

Upstream's makefile knobs still apply, e.g. for a smaller memory footprint:

```sh
# inside build.sh's compile step
wmake -f msdos/makefile.wat WSIZE=8192 all   # 8 KB window, less RAM, weaker compression
wmake -f msdos/makefile.wat NOASM=1 all      # skip the hand-written 8086 assembly
```

The default build *does* include upstream's assembly hot-spots (`msdos/crc_i86.asm` and `msdos/match.asm`).

## What was modified

**No C source file is changed.** `src/` holds the upstream trees byte-for-byte; you can confirm this against any mirror.

The build copies `src/` to `build/` and applies `patch-makefile.py` to the two `msdos/makefile.wat` files only. It makes three mechanical substitutions so that DOS-hosted `wmake` syntax works on a POSIX host:

1. `O = $(OBDIR)\` → `O = $(OBDIR)/` — object-directory separator
2. `msdos\file.c` → `msdos/file.c` — platform subdirectory references
3. `del <file>` → `rm -f <file>` — only in the `clean` targets

None of this reaches the compiler's view of the code; it only changes how paths are spelled in the makefile. Compiler flags, defines and the object file list are upstream's.

## Provenance

| | |
|---|---|
| Zip | 3.0 (released 2008-07-07), `VERSION "3.0"` in `revision.h` |
| UnZip | 6.0 (released 2009-04-20), `UZ_MAJORVER 6` / `UZ_MINORVER 0` in `unzvers.h` |
| Compiler | Open Watcom V2, `Current-build` snapshot |
| Target flags | `-bt=DOS -ml -0 -zt -zq` |

The sources here were obtained from a local archive copy, not freshly from `ftp.info-zip.org` (which is down). They are mirrored verbatim so that anyone can diff them against another copy.

## License

Copyright © 1990-2009 Info-ZIP. All rights reserved.

Zip and UnZip are distributed under the [Info-ZIP license](LICENSE), a permissive BSD-style license that expressly allows redistribution of compiled binaries provided the license accompanies them. It also requires that altered versions be plainly marked and not be misrepresented as Info-ZIP releases — hence the notice at the top of this page, in every release, and in the `README.TXT` shipped inside the binary archive.

The build scripts in this repository (`build.sh`, `setup-toolchain.sh`, `package.sh`, `gen-readme.py`, `patch-makefile.py`, `verify.sh`, `test-dos.sh`) are placed in the public domain; do whatever you like with them.
