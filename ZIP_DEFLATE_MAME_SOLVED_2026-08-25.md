# Full-deflate ZIP.CMD works on real 384 KB MAME rc759 — SOLVED 2026-08-25

Closes the investigation tracked in `ZIP_DEFLATE_DIVERGENCE_2026-08-25.md` /
`PLAN_zip_deflate_mame_2026-08-25.md` and ravn/infozip-cpm86-builds#5.

## Result
`ZIP POEM.ZIP POEM.TXT` produces a valid full-DEFLATE archive on real
Concurrent CP/M-86 3.1 (MAME rc759, 384 KB). Verified by three independent
oracles: `unzip -t` OK, byte-exact round-trip to the original, and Python
`zipfile.testzip()`. The archive is **byte-identical** to the one emu2 produces
at `-m 190` — so emu2 is a faithful CCP/M-86 oracle at matched memory.

Build:  `bash build-zip-cpm86-mame.sh`  (see that script for the knobs).

## What the "divergence" actually was
It was **never** a CPU / 80186 / emu2-fidelity problem. Ruled out, with data:
- **CR/LF translation** — no size expansion, stream inflates to correct length.
- **Timestamps** — byte-identical in the local header (offset 10-13).
- **80186 instructions** — a pure `-0` (8086) build corrupts identically to `-1`.
- **Disk I/O** — STORE-mode archives are valid on MAME.
- **M_ALLOC semantics** — match the documented contract (Concurrent CP/M
  Programmer's Reference Guide §6.2.6: grant is between MIN and MAX, never more;
  the earlier "333A/209 KB grant" was an OCR misread of a snapshot).

Root cause = **memory pressure**. The stock large-model zip reserves ~186 KB at
load; the RC759 XIOS 2.3 reports a FIXED 384 KB / 293 KB TPA regardless of
physical RAM (**confirmed: raising MAME RAM to 512 KB does not change the banner
— a RAM-probe showed 0x70000 became real RAM, yet the XIOS still said 384 KB**),
and the effective per-program free memory behaves like emu2 `-m ~190`. With the
program eating ~186 KB, deflate's ~24 KB far-heap tables (window+prev+head)
could not be M_ALLOC'd → "Out of memory", and the far-heap fallback then handed
out **overlapping** memory → bad-CRC archives, then a CPU trap.

## The two fixes
1. **Footprint (this repo).** Two flag levels, both gated so the stock build
   keeps full functionality:
   - `-DCPM86_SLIM` (**the shipped `build-zip-cpm86-mame.sh` default**) stubs
     only what a floppy zip never needs: multi-disk SPLIT
     (`ask_for_split_*`), `-F/-FF` REPAIR (`scanzipf_fixnew`), and the
     multi-page `help()/help_extended()` usage text (~17 KB of DATA-group
     strings) → one-line usage. Load 186.0K → ~157.8K. **KEEPS incremental
     update** (`zipcopy`/`bfcopy`/`scanzipf_regnew`): `zip a.zip f2` still adds
     f2 to an existing a.zip. With `WSIZE=0x1000` (best ratio, POEM.TXT→219 B)
     the threshold is emu2 `-m 188` — verified working on real MAME.
   - `-DCPM86_CREATE_ONLY` additionally drops the update path (create-a-new-
     archive only, overwrites an existing one): load → 163.4K, ~12 KB more
     headroom. Use with `WSIZE=0x800` for a larger safety margin when updating
     a very large existing archive whose directory fills the near heap.
   The deflate far tables are a FIXED size independent of input, so the tight
   `-m 188` margin holds for any input file size.
2. **Correctness (open-watcom-v2 `port/farheap.c`).** A tight fn-128 (M_ALLOC)
   OOM (documented `BX=0FFFFH`) is now recognised as "fn 128 present, just out of
   memory" and returns `_NULLSEG` cleanly, instead of falling through to carve
   the (zero-size, FARHEAP=0) OPTION-FARHEAP reservation and handing out memory
   that overlaps live data/stack. Corruption/crash → honest `ZE_MEM`.

## Fallback if more compression is wanted later
Raising the real TPA needs the PICCOLINE XIOS memory partition regenerated
(GENCCPM) to cover more RAM — a change to the CCP/M system, not just MAME's RAM
map. Not required for the working create-only build above.
