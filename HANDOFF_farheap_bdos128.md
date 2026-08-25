# HANDOFF: CP/M-86 zip far-heap fix (BDOS 128) — 2026-08-25

Status for the next worker (Copilot). Full diagnosis lives in
`tasks/memory/reference_zip_cpm86_needs_large_model.md`; this is the operational
summary + exactly what is done and what remains.

## The bug (root cause, verified)
Info-ZIP `zip`'s deflate **hangs** on real CCP/M-86 (RC759) but works under emu2.
Root cause is NOT the compiler, NOT Info-ZIP, NOT malloc — it is **our libc port**
`open-watcom-v2/contrib/ravn/watcom-cpm86-libc/port/farheap.c`, specifically
`__AllocSeg` (our "sbrk"). The old M9 code trusted the compile-time
`OPTION FARHEAP` reservation (`CPM86_FARHEAP_PARAS`) as the available size, but the
CCP/M loader only *spreads a partial grant* and reports only G_MIN in the base
page (0x0C). So `__AllocSeg` over-committed past the real grant; `_fcalloc`
returned a segment overlapping the live stack; deflate's `prev[]`/`head[]` got
clobbered → hash chain never terminates → infinite loop. Evidence: 640 KB MAME
RAM dump showed `_window` pointing at stack-context bytes; input text absent from
all RAM. (`_fcalloc`/`calloc` zeroing is correct; the pointer/size was wrong.)

Why emu2 hid it: emu2 grants generously and has zero/dead free memory where the
over-commit landed, so the corrupted window survived.

## The fix (B2 — DONE, MAME-verified as far as "no more hang")
The correct memory source on Concurrent CP/M-86 is **BDOS function 128 (M_ALLOC)**,
which RETURNS THE ACTUAL GRANTED SIZE in the MPB — so `__AllocSeg` can never
over-commit. Confirmed in DRI source `scratch/ccpm86-src/kern/memory.mem`
(malloc_entry) + `mpb.def` + `modfunc.def` (`f_malloc=128`), and confirmed WORKING
on real MAME rc759 via probe `watcom-cpm86-libc/test/memtest128.c`.

MPB = `{start,min,max,pdadr,flags}` (5 words, paragraphs). Call `CL=128, DX=&MPB`;
out `BX=0` ok / `0xFFFF` fail; `MPB.start`=granted seg, `MPB.max`=ACTUAL paras.
Free = fn 130.

### Changes made
1. **`port/farheap.c`** — `__AllocSeg` now tries BDOS 128 first
   (`__cpm86_fh_bdos_alloc`), using `mpb.max` as the true size; falls back to the
   old OPTION-FARHEAP carving only if fn 128 is unavailable. MPB is `__near`
   (must live in DGROUP; BDOS reads DS:DX) and passed by offset (large-model safe).
2. **emu2 (`emu2-cpm86/src/`)** — added BDOS **fn 128 (M_ALLOC)** + **130 (M_FREE)**
   in `cpm86.c` (it only had CP/M-86 fns 53-57, which a Concurrent machine does
   NOT expose — that mismatch was itself an emu2 fidelity bug). Also added
   env-gated `CPM86_POISON` (`loader.c mem_poison_free`, `loader.h`, `cpm86.c`)
   for dirty-RAM fidelity (independent improvement; NOT sufficient alone —
   the divergence is layout adjacency, see the memory note).
3. **Verified on MAME**: with the new farheap.c, zip **no longer hangs** — it now
   cleanly reports `zip error: Out of memory (window allocation)` (ZE_MEM) when the
   grant is too small. Hang → honest OOM. This is the correctness win.

## What REMAINS (for Copilot)
The MAME run still OOMs because two things still starve the runtime grant:
1. **`OPTION FARHEAP` still reserves memory the BDOS-128 path no longer uses.**
   That reservation shrinks the free TPA that fn 128 could otherwise grant. NEXT:
   set the wlink `op farheap=` to minimal (e.g. 0x1000, kept only for the fallback
   marker) in `build-zip-cpm86.sh`, so the ~60 KB is freed for runtime M_ALLOC.
   (A first attempt with FARHEAP=0x1000 was built but the MAME re-verify did not
   confirm — the snapshot was stale/old-binary; RE-RUN `scripts/rc759_zip_autorun.sh`
   after confirming out-zip-cpm86/ZIP.CMD is the fresh build.)
2. **zip's image is ~200 KB** on a ~293 KB (effective ~210 KB) machine, leaving
   little for deflate's 24 KB far heap (window 8K + prev 8K + head 8K). Even a
   perfect allocator may OOM. Mitigation (B3): shrink zip's code footprint
   (smaller WSIZE/HASH already in DEFS; consider dropping features / UTIL split).

### Verify loop
- Fast: `emu2` now supports fn 128, so `emu2 out-zip-cpm86/ZIP.CMD` (with POEM.TXT
  in cwd) exercises the BDOS-128 path quickly (currently PASSES = valid archive).
- Truth: `SECS=90 bash scripts/rc759_zip_autorun.sh` then read
  `mame/snap/rc759/0000.png`. GOAL: `adding: poem.txt (deflated NN%)` + POEM.ZIP on
  B:, extractable + `unzip -t` OK. Then run `scripts/rc759_zip_stream_diff.sh` to
  byte-diff the CCP/M deflate stream vs the emu2 reference `/tmp/emu2_deflate.bin`.

## Instrumentation left in the tree (gated, pristine-DOS build unaffected)
- `src/zip30/zipup.c` `-DCPM86_KEEP_BADZIP`: keep archive instead of destroy(tempzip).
- `src/zip30/zip.c` `-DCPM86_AUTORUN`: fixed `zip POEM.ZIP POEM.TXT` for headless autostart.
- `src/zip30/zip.h` `-DCPM86_ASSERT_ONLY`: keep Assert/check_match under DEBUG, drop Trace CONST bloat.
- DEBUG build recipe: `build-zip-debug.sh` (DEBUG only in deflate.c+zipup.c, `-zt64`).
- Build knobs: `EXTRA_DEFS`, `FARHEAP`, `-DLIT_BUFSIZE=0x0200` (DGROUP is at the 64 KB edge — expect E2021 and trim).

## Key files
- `port/farheap.c` (the fix), `test/memtest128.c` (fn128 probe), `test/deflate_fheap_test.c` (unit probe), `build-deflate-fheap-mame.sh`.
- emu2: `emu2-cpm86/src/{cpm86.c,loader.c,loader.h}`.
- Scripts: `scripts/rc759_zip_autorun.sh`, `rc759_zip_stream_diff.sh`, `_zip_decode_diff.py`; luas `scratch/zip_*.lua`.
- Oracle source: `scratch/ccpm86-src/kern/{memory.mem,mpb.def,mem.def}`, `modfunc.def`.
