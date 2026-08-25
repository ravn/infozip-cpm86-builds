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

### Latest verification (2026-08-25)

With `FARHEAP=0` and a fresh build, real MAME now reaches and completes the
deflate phase; it no longer reports the earlier `window allocation` failure or
hang. The run then fails while writing the temporary archive (`zipcopy`), because
the turnkey A: image has insufficient directory/data space for both the 200 KB
`ZIP.CMD` and the temporary output. The autorun script now clears persisted
rc759 NVRAM and removes additional optional A: files before installing ZIP.

### BDOS-128 contract deep-check (2026-08-25, DONE)

The BDOS interface was re-verified independently of ZIP with a strengthened
`test/memtest128.c`:
- variable requests with **min<max** (`min={1,4,16,64}`, `max={4,16,64,1024}`)
- validation of `BX`, `start`, and returned `max` (`min <= max <= requested`)
- full write/read sweep of each granted block

On real MAME rc759 this reports `pass=4 fail=0`. A full RAM dump is then
validated by `test/verify_memtest128_dump.py`, which confirms all expected
byte-pattern blocks are present. Conclusion: BDOS 128/130 contract and segment
addressing behave correctly; current ZIP failure is no longer a plausible
BDOS-grant/corruption interface bug.

## Key files
- `port/farheap.c` (the fix), `test/memtest128.c` (fn128 probe), `test/deflate_fheap_test.c` (unit probe), `build-deflate-fheap-mame.sh`.
- `test/verify_memtest128_dump.py` (independent RAM-dump oracle for variable memtest128 patterns).
- emu2: `emu2-cpm86/src/{cpm86.c,loader.c,loader.h}`.
- Scripts: `scripts/rc759_zip_autorun.sh`, `rc759_zip_stream_diff.sh`, `_zip_decode_diff.py`; luas `scratch/zip_*.lua`.
- `build-farheap-mame.sh` accepts `TEST_SRC=...` so the same MAME+dump harness can run both `farheap_smalltest.c` and `memtest128.c`.
- Oracle source: `scratch/ccpm86-src/kern/{memory.mem,mpb.def,mem.def}`, `modfunc.def`.

### emu2 catches MAME's exact ZIP OOM message (2026-08-25)

Root-caused and fixed why emu2 never reproduced MAME's OOM: emu2's underlying MCB
free-memory pool was sized ONCE at startup (`dos.c` `init_dos()`, `mcb_init(0x80,
0xA000)`, ~640 KB) independent of the `CPM86_TPA_KB` cap that only applied to the
`.CMD` loader's LOAD-TIME group grant. A running program's RUNTIME BDOS-128 calls
(farheap.c's `_fmalloc`) could therefore always draw "free" memory from the
oversized pool, so zip's deflate window/hash allocations never failed under emu2
regardless of the configured TPA.

**Fix** (`emu2-cpm86` commit `fe9dfb9`): `init_dos()` now peeks the program file
via `cpm86_detect()` BEFORE calling `mcb_init()`, and if it's CP/M-86, sizes the
WHOLE arena to `CPM86_TPA_KB` — load-time AND runtime allocations now share one
correctly-sized pool. New `cpm86_get_tpa_kb()` is the single source of truth
(precedence: `-m <kb>` CLI option > `CPM86_TPA_KB` env var > built-in default,
210 KB). `cpm86.c`'s group-allocation logic was also reworked to use the same
"ask max, fall back to actual available if it covers the minimum" pattern the
BDOS-128 handler already used, spreading extra/stack surplus from the grant's
TRUE size (matching `load.sup`'s real "spread after the combined allocation
returns" semantics).

**Calibration**: at `-m 190` (or `CPM86_TPA_KB=190`), emu2 reproduces MAME's
CURRENT exact failure, `zip error: Out of memory (window allocation)`, byte-for-
byte the same message as a fresh real-MAME run (confirmed via
`scripts/rc759_zip_autorun.sh` with cleared NVRAM). At the built-in default (210),
emu2 fails at the SLIGHTLY later `hash table allocation` request instead (deflate
allocates `window` first, then the larger combined `prev+head` "hash table"), i.e.
the stock default still leaves emu2 with marginally more headroom than the real
machine; use `-m 190` for a byte-exact MAME OOM reproduction. `memtest128` and
`farheap_smalltest` regressions were re-verified (PASS) on both MAME and emu2
after this fix (see `build-farheap-mame.sh`'s `TEST_SRC` fix, same commit series).
