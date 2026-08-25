#!/bin/bash
# build-zip-cpm86-mame.sh -- build a full-DEFLATE ZIP.CMD that FITS and runs on
# a real 384 KB RC759 under Concurrent CP/M-86 3.1 (MAME rc759).  Verified
# 2026-08-25 on real MAME: valid POEM.ZIP, byte-exact round-trip, byte-identical
# to emu2 -m 190.
#
# WHY a separate recipe:
#   The stock large-model Info-ZIP zip reserves ~186 KB at load (CODE 115.6K +
#   DATA 63.8K + EXTRA 6.6K).  The RC759 XIOS 2.3 reports a FIXED 384 KB / 293 KB
#   "bruger lager" regardless of physical RAM (confirmed: a RAM-probe showed
#   0x70000 became real RAM when MAME was set to 512 KB, yet the XIOS banner
#   still said 384 KB -- the XIOS does not size RAM).  The effective per-program
#   TPA behaves like emu2 -m ~190.  With the program eating ~186 KB, deflate's
#   far-heap tables (window+prev+head) cannot be M_ALLOC'd -> "Out of memory".
#
# So this recipe shrinks the footprint until the tables fit, WITHOUT giving up
# the ability to add to / update an existing archive:
#   -DCPM86_SLIM   stubs only the code a floppy-based zip never needs:
#                    * multi-disk SPLIT (ask_for_split_read/write_path)
#                    * -F/-FF archive REPAIR (scanzipf_fixnew)
#                    * the multi-page help()/help_extended() usage text
#                      (~17 KB of DATA-group strings) -> a one-line usage.
#                  KEEPS zipcopy/bfcopy/scanzipf_regnew, so `zip a.zip f2` still
#                  ADDS f2 to an existing a.zip.  Footprint 186.0K -> ~157.8K.
#   WSIZE=0x1000   4 KB window = best ratio (POEM.TXT -> 219 B).  Fits real MAME
#                  (threshold emu2 -m 188 < ~190), verified.  The deflate tables
#                  are a FIXED size independent of input, so this holds for any
#                  input file size.
#
#   To use the FULLY create-only variant instead (no update-existing either, but
#   ~12 KB more headroom for updating very large existing archives), pass
#     EXTRA_DEFS=-DCPM86_CREATE_ONLY  WSIZE=0x800
#   -- CPM86_CREATE_ONLY implies everything CPM86_SLIM cuts, plus the update path.
#
# For extra safety margin (updating a HUGE existing archive whose directory
# fills the near heap before the far tables are allocated), drop to the 2 KB
# window:  WSIZE=0x800 HASH_BITS=11 bash build-zip-cpm86-mame.sh
# (0x800 = 2048 > MIN_LOOKAHEAD 262 -> valid window; do NOT go below 0x200.)
#
# See ZIP_DEFLATE_MAME_SOLVED_2026-08-25.md for the full root-cause writeup.
# A tight fn-128 M_ALLOC OOM now fails cleanly (open-watcom-v2 port/farheap.c)
# instead of carving overlapping memory.
#
# Usage:   bash build-zip-cpm86-mame.sh        (OWROOT auto = ../open-watcom-v2)
#          install out-zip-cpm86/ZIP.CMD onto B:, then:  B:  then  ZIP POEM.ZIP POEM.TXT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec env \
  FARHEAP=0 "WSIZE=${WSIZE:-0x1000}" "HASH_BITS=${HASH_BITS:-12}" \
  EXTRA_DEFS="-DCPM86_SLIM ${EXTRA_DEFS:-}" \
  bash "$ROOT/build-zip-cpm86.sh" "$@"
