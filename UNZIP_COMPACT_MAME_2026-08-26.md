# Compact-model UNZIP inflate VERIFIED on real MAME rc759 (2026-08-26)

## Result — PASS
The compact-model UNZIP (`-mcmodel=c`, the "skift model" fix) **inflates a
>32 KB DEFLATE archive correctly on the real Concurrent CP/M-86 3.1 truth
witness (MAME rc759, 384 KB / 293 KB TPA)** and returns cleanly to `A>`.

Screen (proof `UNZIP_COMPACT_MAME_BIG_PASS.png`):
```
Start Kommando: menu imenu
Archive:  BIG.ZIP
    testing: BIG.TXT                  OK
No errors detected in compressed data of BIG.ZIP.
A>
```
`BIG.ZIP` = BIG.TXT (47000 B) DEFLATE'd → its inflate drives the 32 KB slide
window (`slide[WSIZE]`) out of the compact-model far heap (BDOS-128 M_ALLOC) —
the exact path that could not fit in the small model's near DGROUP. It works on
real hardware, matching emu2 `-m 190`.

## ⚠ Process lesson (this cost a wrong conclusion first)
**rc759 CCP/M boots in ~290 EMULATED seconds** — the turnkey `menu.cmd`
autostart (our UNZIP) does not run until ~t175–290 s. An initial run capped at
`-seconds_to_run 45` caught only the ROM-monitor / POST screen
(`*** PICCOLINE TEST, V.2.1 ***`) *mid-boot* and I mis-read it as a UNZIP crash.
It was not — UNZIP had not run yet. Always use `-seconds_to_run 400` and read a
LATE frame. This is documented in `tasks/memory/reference_rc759_mame_c_verification.md`
("Boot is slow: ~290 emulated seconds; post-boot appears around frame
12500–15000"); see also `[[reference_rc759_ccpm_boot_290s]]`.

## How to reproduce
```
cd infozip-cpm86-builds
OUT="$PWD/out-cpm86-autorun" EXTRA_DEFS="-DCPM86_AUTORUN" bash build-cpm86.sh
bash /Users/ravn/z80/scripts/rc759_unzip_autorun.sh    # SECS defaults to 400
# read the newest mame/snap/rc759/00NN.png
```
`unzip.c` carries a gated `#ifdef CPM86_AUTORUN` argv-override in `unzip()`
(mirrors the `zip.c` hook) that self-invokes `unzip -t BIG.ZIP`; production
builds never define it. `scripts/rc759_unzip_autorun.sh` installs that binary as
`menu.cmd` on a clone of the `mandel.img` turnkey and boots MAME headless with a
periodic-snapshot lua (`scratch/rc759_unzip_snap.lua`).

## Still worth a genuine prompt run (secondary)
This used the turnkey `menu.cmd` autostart (argv overridden in-binary), not a
hand-typed `A> UNZIP …`. The inflate path, far-heap window, CRC and clean `A>`
return are all exercised, so functionally it is proven. A keystroke-typed run
(`B_unzip.mfi` on B:, `natkeyboard:post`) would additionally confirm the normal
command-tail path, but is not required to trust the inflate result.

## Harness/infra added (gated; production unaffected)
- `src/unzip60/unzip.c` — `#ifdef CPM86_AUTORUN` argv-override.
- `build-cpm86.sh` — `${EXTRA_DEFS:-}` passthrough.
- `scripts/rc759_unzip_autorun.sh` (SECS=400 default) + `scratch/rc759_unzip_snap.lua`.
- `build-cpm86-small-diag.sh` — small-model control build (kept for reference).

The `CPM86_NOTES.txt` claim (UNZIP "inflates STORED+DEFLATED … compact memory
model") is now backed by a real-MAME observation, not just emu2.
