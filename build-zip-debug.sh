#!/bin/bash
# Cross-compile Info-ZIP Zip 3.0 for 16-bit CP/M-86 (Intel 8086/80186) with the
# Open Watcom V2 CP/M-86 toolchain (owcc -bcpm86), LARGE memory model.
#
# Companion to build-cpm86.sh (which builds UnZip in SMALL model). Zip needs
# LARGE model for TWO reasons, both verified:
#   1. Zip's pristine source only type-checks under a FAR-DATA model: zip.h
#      prototypes flush_block() as `char far *` but trees.c K&R-defines it as
#      `char *`; those agree only when data pointers are far (E1129 otherwise).
#      The source may NOT be edited (it is the same pristine tree the DOS build
#      reproduces byte-for-byte), so the fix is the model, not a patch.
#   2. Zip's code is ~115 KB -- far past one 64 KB code segment -> needs far
#      code. Large = far code + far data covers both.
#
# ZERO edits to Info-ZIP's generic C sources. Everything CP/M-86 specific is:
#   * a NEW OS layer, src/zip30/cpm86/cpm86.c (mirrors msdos/msdos.c but with
#     BDOS/portable calls; no directory enumeration, far-heap zcalloc, etc.), or
#   * a -D configuration flag below.
#
# Key flags and WHY:
#   -mcmodel=l -zc   LARGE model, per-function *_TEXT so wlink can span >64 KB
#                    code across multiple CP/M-86 code groups (far calls).
#   NO -zc           const-in-code BLOWS the code group past 64 KB and trips
#                    E2052 (clib near relocations cross the boundary). Keep
#                    CONST in DGROUP instead and shrink DGROUP another way:
#   -DSMALL_MEM -DHASH_BITS=12      halves the deflate near buffers (flag_buf etc.) -- the
#   -DLIT_BUFSIZE=0x0400  ...together these bring DGROUP (CONST 38 KB + BSS +
#                    stack) from ~3.3 KB over 64 KB to comfortably under.
#   -DDOS -DMSDOS    CP/M-86 is a DOS-family Watcom target; selects msdos/osdep.h
#                    (which compiles clean under owcc) for the type/macro surface.
#   -DDYN_ALLOC      window/prev/head become far pointers, allocated from the far
#                    heap by cpm86.c's zcalloc()/_fcalloc (OPTION FARHEAP).
#   -DNO_ASM         use the C crc32/longest_match; msdos/osdep.h otherwise
#                    force-defines ASMV and pulls the hand-asm entry points
#                    (_crc32/_longest_match/_match_init) that do not exist here.
#
# STATUS: links to a valid CP/M-86 .CMD (header byte 0x01) and starts under
# emu2. Runtime bring-up (M7) is in progress -- see ZIP_CPM86_PLAN.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OWROOT="${OWROOT:-$(cd "$ROOT/../open-watcom-v2" 2>/dev/null && pwd || true)}"
[ -n "$OWROOT" ] && [ -d "$OWROOT/bld" ] || {
  echo "!! set OWROOT to a built open-watcom-v2 tree (needs bld/ + the CP/M-86 clib)" >&2
  exit 1; }

B="$OWROOT/bld"
LIBDIR="$OWROOT/lib286/cpm86"                    # clibl.lib + cstartlm.obj
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"

[ -f "$LIBDIR/clibl.lib" ] && [ -f "$LIBDIR/cstartlm.obj" ] || {
  echo "!! large-model clib missing under $LIBDIR" >&2
  echo "   build it:  ( cd $OWROOT/contrib/ravn/watcom-cpm86-libc && MODEL=l ./build-lib.sh )" >&2
  exit 1; }

# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

OUT="${OUT:-$ROOT/out-zip-cpm86}"
mkdir -p "$OUT"

INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"
DEFS="-DDOS -DMSDOS -DDYN_ALLOC -DNO_ASM -DSMALL_MEM -DHASH_BITS=12 -DLIT_BUFSIZE=0x0400 -DWSIZE=0x1000 -DCPM86_UPPER_OPTS -DCPM86_STEP_TRACE ${EXTRA_DEFS:-}"
CFLAGS="-bcpm86 -march=i186 -mcmodel=l -zm -zt64 -Os"

# Zip.exe object set (from msdos/makefile.wat) minus the hand-asm match/crc
# (C versions used via NO_ASM) and minus msdos.c (replaced by cpm86/cpm86.c).
CORE="zip crypt ttyio zipfile zipup util fileio deflate trees globals crc32"

# farheap right-sized: with SMALL_MEM/WSIZE=0x1000/HASH_BITS=12 the deflate far
# tables are window 8K + prev 8K + head 8K = ~24K; the far heap only needs to
# cover those plus a little slack. 0x20000 (128K) was ~4x oversized -- the loader
# must reserve the whole Extra G_MAX, so an oversized farheap directly inflates
# the load-time footprint that trips the CCP/M "For lidt lager" ceiling. Measured
# minimum that still deflates cleanly under emu2 is 0x8000 (0x6000 fails); use
# 0xC000 (48K) for margin -> ~80K less load-time reservation than 0x20000.
: "${FARHEAP:=0xC000}"
FARHEAP_PARAS=$(( FARHEAP / 16 ))

echo "==> compiling Zip for CP/M-86 (large model, farheap=${FARHEAP} = ${FARHEAP_PARAS} paras)"
cd "$ROOT/src/zip30"

# Compile cpm86.c FIRST so its tempname() definition shadows fileio.c's
# broken NO_MKTEMP version (msdos/osdep.h defines NO_MKTEMP which causes
# a buffer overflow: 12-byte malloc + 8-digit sprintf = heap corruption).
# wlink uses the first definition of a public symbol; cpm86.obj must precede
# fileio.obj in the link order for our tempname() to win.
owcc $CFLAGS $DEFS $INC -c cpm86/cpm86.c -o "$OUT/cpm86.obj"
OBJS="file $OUT/cpm86.obj"

for s in $CORE; do
  # shellcheck disable=SC2086
  D=""; case "$s" in deflate|zipup) D="-DDEBUG -DCPM86_ASSERT_ONLY";; esac; owcc $CFLAGS $DEFS $D $INC -c "$s.c" -o "$OUT/$s.obj"
  OBJS="$OBJS file $OUT/$s.obj"
done

# M9 fix: real CCP/M-86's loader (load.sup init_base) writes G_MIN (the
# initialized far-data paragraphs) to DS:0x0C, NOT G_MAX (G_MIN + farheap).
# farheap.c's __cpm86_fh_init() reads DS:0x0C and computes total_paras, so
# on real hardware it sees G_MIN ≈ data_paras and concludes available_paras=0.
# Fix: compile farheap.c with -DCPM86_FARHEAP_PARAS=N so __AllocSeg derives
# total_paras = marker_paras + N (where N = farheap/16), correctly reflecting
# the full G_MAX reservation. This farheap.obj is linked BEFORE clibl.lib so
# it overrides the library's fallback version (which still uses DS:0x0C).
PORTDIR="$OWROOT/contrib/ravn/watcom-cpm86-libc/port"
PORTINC="-I$OWROOT/bld/clib/h -I$OWROOT/bld/clib/heap/h"
# shellcheck disable=SC2086
owcc $CFLAGS $INC $PORTINC -DCPM86_FARHEAP_PARAS=$FARHEAP_PARAS \
  -c "$PORTDIR/farheap.c" -o "$OUT/farheap.obj"
OBJS="$OBJS file $OUT/farheap.obj"

echo "==> linking ZIP.CMD"
WLINK="$B/wl/osxa64/wlink.exe"
# shellcheck disable=SC2086
"$WLINK" format cpm86 op dosseg op start=_cstart_ op farheap=$FARHEAP \
  op map="$OUT/zip.map" \
  name "$OUT/ZIP.CMD" file "$LIBDIR/cstartlm.obj" $OBJS library "$LIBDIR/clibl.lib"

cp "$OUT/ZIP.CMD" "$ROOT/ZIP.CMD"
echo
echo "==> ZIP.CMD built:"
ls -la "$OUT/ZIP.CMD"
echo
echo "   Test under emu2:   emu2 ZIP.CMD ARCHIVE.ZIP FILE.TXT"
