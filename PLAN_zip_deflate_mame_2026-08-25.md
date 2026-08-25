# PLAN: get full-deflate ZIP.CMD working on real MAME rc759 — 2026-08-25

**Goal:** full-deflate `ZIP.CMD` produces a valid archive on real Concurrent
CP/M-86 (RC759 / MAME). MAME/CCP/M is the authoritative oracle; emu2 is the
differential oracle; host `unzip` / Python `zipfile` are independent archive
oracles.

**Fallback already in hand:** the small-model STORE-only `ZIP.CMD`
(`build-minizip-cpm86.sh`) is verified working on MAME rc759 (user confirmed
2026-08-21). This plan is about reaching *deflate*, with no risk of being left
without a working zip meanwhile.

**Current true blocker:** the deflate divergence
(`ZIP_DEFLATE_DIVERGENCE_2026-08-25.md`, tracking issue
[ravn/infozip-cpm86-builds#5]). The earlier hang/OOM is resolved by the
BDOS-128 farheap fix (`HANDOFF_farheap_bdos128.md`).

---

## Phase 1 — Diagnose the divergence (critical path, #5)
Everything else is blocked on this. Find *why* deflate output differs on
CCP/M vs emu2.

1. **Instrument zlib state.** Build debug `ZIP.CMD` (`build-zip-debug.sh`,
   DEBUG in `deflate.c`+`zipup.c`) and log at each `deflate()` flush:
   `total_in`, `total_out`, `avail_in`, `avail_out` + a CRC/checksum of each
   output buffer.
2. **Run both oracles, frozen repro** (`POEM.TXT`, 3960 B): emu2 (`-m 190`
   for MAME-faithful memory) and MAME rc759 (`scripts/rc759_zip_autorun.sh`,
   cleared NVRAM).
3. **Byte-diff the stream** with `scripts/rc759_zip_stream_diff.sh` /
   `_zip_decode_diff.py` vs `/tmp/emu2_deflate.bin`. Find the FIRST diverging
   byte/block and which deflate phase (literal / match / tree) it is in.

**Decision point** — the first divergence points at one of three roots:
- **(a) Compiler miscompile** (code wrong only on the CCP/M path) →
  bug-analyst pass, file to **ravn/open-watcom-v2-ccpm86**
  (per `feedback_file_bugs_not_fixes` + `feedback_explain_before_filing`).
- **(b) Large-model far-pointer / memory-layout** (deflate's
  `prev[]`/`head[]`/`window` in farheap landing in the wrong segment) → fix
  in `watcom-cpm86-libc/port/farheap.c` or deflate DEFS.
- **(c) zlib buffer state** (e.g. `LIT_BUFSIZE`, `WSIZE`/`HASH` config
  mismatch) → fix in zip's DEFS.

## Phase 2 — Fix the identified root
Depends on Phase 1's decision point. **No fix is selected before the
divergence is isolated** (the divergence doc's own rule). If it turns out to
be a Watcom compiler bug, it is filed as a BUG (not a fix); otherwise fixed
locally in libc/DEFS with a regression guard.

## Phase 3 — Memory headroom (parallel / fallback)
Even with correct deflate, the zip image is ~200 KB on a ~210 KB machine, so
deflate's 24 KB far heap (window 8K + prev 8K + head 8K) is marginal.
- Set `op farheap=` to minimal (fallback marker) in `build-zip-cpm86.sh` to
  free ~60 KB for runtime `M_ALLOC` (started, but the re-verify was stale —
  re-run on a fresh binary).
- If needed: shrink zip's code (smaller `WSIZE`/`HASH`, drop features /
  UTIL split — B3 in the handoff).

## Phase 4 — Verification & regression gate (#3)
- **Success criterion:** `adding: poem.txt (deflated NN%)` + `POEM.ZIP` on B:,
  extractable and passing `unzip -t` AND host `unzip` / Python `zipfile`.
- Wire it into the automated MAME rc759 regression already tracked in
  [ravn/infozip-cpm86-builds#3] so the deflate path cannot regress unnoticed.

---

**Critical path:** Phase 1 → decision point → Phase 2. Phase 3 can run in
parallel. See `HANDOFF_farheap_bdos128.md` for the operational detail behind
Phases 3–4 and `ZIP_DEFLATE_DIVERGENCE_2026-08-25.md` for Phase 1's evidence
baseline.
