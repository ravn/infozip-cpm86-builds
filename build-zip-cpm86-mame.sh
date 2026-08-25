#!/bin/bash
# build-zip-cpm86-mame.sh -- build a full-DEFLATE ZIP.CMD that FITS and runs on
# a real 384 KB RC759 under Concurrent CP/M-86 3.1 (MAME rc759), verified
# 2026-08-25 (byte-identical archive on MAME and on emu2 -m 190).
#
# WHY a separate recipe:
#   The stock large-model Info-ZIP zip reserves ~186 KB at load (CODE 115.6K +
#   DATA 63.8K + EXTRA 6.6K).  The RC759 XIOS 2.3 reports a FIXED 384 KB / 293 KB
#   "bruger lager" regardless of physical RAM (confirmed: raising MAME RAM to
#   512 KB does NOT change the banner -- the XIOS does not size RAM), and the
#   effective per-program TPA behaves like emu2 -m ~190.  With the program eating
#   ~186 KB there is < ~5 KB left, so deflate's ~24 KB far-heap tables
#   (window+prev+head) cannot be M_ALLOC'd -> "Out of memory".
#
# So this build shrinks the footprint until the tables fit:
#   -DCPM86_CREATE_ONLY  stubs the update/copy/repair + split paths that a
#                        create-a-new-archive tool never uses (zipcopy, bfcopy,
#                        scanzipf_fixnew, scanzipf_regnew, ask_for_split_*):
#                        load 186.0K -> 163.4K.
#                        TRADE-OFF: cannot add to / update an existing archive
#                        (running zip on an existing .ZIP OVERWRITES it) and no
#                        -F/-FF repair.  Creating a fresh archive from N files in
#                        one command still works.
#   WSIZE=0x800          2 KB sliding window -> ~12 KB far tables instead of
#                        ~24 KB.  Slightly worse ratio, still standard DEFLATE.
#                        (0x800 = 2048 > MIN_LOOKAHEAD 262, so the window is
#                        valid; do NOT go below 0x200.)
#   FARHEAP=0            far heap comes from CCP/M's fn-128 (M_ALLOC), the real
#                        source of free memory on RC759.  (See farheap.c: a tight
#                        fn-128 OOM now returns cleanly instead of carving
#                        overlapping memory.)
#
# Result: threshold drops to emu2 -m 182 (< MAME's ~190) -> deflate succeeds on
# real MAME.  333-byte POEM.ZIP, valid unzip -t / python zipfile, exact
# round-trip, byte-identical MAME vs emu2 -m 190.
#
# Usage:   bash build-zip-cpm86-mame.sh        (OWROOT auto = ../open-watcom-v2)
#          then install out-zip-cpm86/ZIP.CMD onto the B: disk and run:
#            B:  then  ZIP POEM.ZIP POEM.TXT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec env \
  FARHEAP=0 WSIZE=0x800 HASH_BITS=11 \
  EXTRA_DEFS="-DCPM86_CREATE_ONLY ${EXTRA_DEFS:-}" \
  bash "$ROOT/build-zip-cpm86.sh" "$@"
