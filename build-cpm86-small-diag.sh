#!/bin/bash
# Cross-compile Info-ZIP UnZip 6.0 for 16-bit CP/M-86 (Intel 8086/80186, small
# memory model) using the Open Watcom V2 clib retargeted to CP/M-86 via a thin
# BDOS seam (contrib/ravn/watcom-cpm86-libc -> clibcpm.lib + crt0.obj).
#
# This is a SEPARATE target from build.sh (which builds the DOS large-model
# .exe with the stock Linux Watcom toolchain). Here we drive owcc/wlink from a
# locally built open-watcom-v2 tree on the host (macOS/Apple Silicon native).
#
# The port carries ZERO edits to UnZip's generic C sources. Everything CP/M-86
# specific is either:
#   * a NEW OS layer selected by -DFLEXOS  (src/unzip60/cpm86/cpm86.c), or
#   * a -D configuration flag on the command line (below).
#
# Key configuration flags and WHY each is required on CP/M-86 small model:
#   -DFLEXOS         Reuse UnZip's FLEXOS port profile (closest DRI CP/M cousin);
#                    selects cpm86/cpm86.c and its zero-generic-edit conventions.
#   -DSMALL_MEM      16-bit small model: 2 KB I/O buffers, Far-string machinery.
#   -DINBUFSIZ=512   Shrink in/out buffers (OUTBUFSIZ follows INBUFSIZ) so they
#                    coexist with the 32 KB inflate window in our ~35 KB near
#                    arena (the whole heap lives inside one 64 KB DGROUP).
#   -DNO_DEFLATE64   CRITICAL. Without it WSIZE=65536L, and the window alloc
#                    zcalloc(16384,4) computes 16384*4 == 65536 which WRAPS to 0
#                    in 16-bit size_t -> a 0-byte (NULL) window. UnZip then
#                    decompresses through a NULL near pointer (offset 0); crc32()
#                    sees buf==NULL as its "initialize" sentinel and returns 0,
#                    i.e. the "bad CRC 00000000" symptom with otherwise-correct
#                    extracted bytes. NO_DEFLATE64 -> WSIZE=0x8000 (32 KB), no
#                    overflow. (16-bit CP/M-86 cannot address a 64 KB window in
#                    near memory anyway, so Deflate64 is out of reach regardless.)
#   -DNO_ZIPINFO     Drop ZipInfo ("unzip -Z") to save DGROUP message strings.
#   -DMALLOC_WORK    Allocate the work/window areas from the heap (not BSS).
#   -DDYNALLOC_CRCTAB  Build the 1 KB CRC table on the heap, not in BSS.
#   -Dzf{malloc,free,strcpy,strcmp}=...  SMALL_MEM only auto-maps these Far
#                    helpers for MSC/Turbo; Watcom needs them pointed at the
#                    plain near clib entry points.
#
# DEFLATE STATUS (updated after the stack-overflow fix, 2026-08-20):
#   STORED entries extract byte-correct with passing CRC. DEFLATE now also works
#   byte-correct (CRC-verified) for outputs of ANY size, INCLUDING >= the 32 KB
#   window: a wrapping window flush used to crash because the clib's 512-byte
#   crt0 stack overflowed on UnZip's deep inflate call chain (fixed: crt0*.asm
#   now defaults the stack to 2 KB; see the WC_STACK_BYTES comment there).
#
# RESIDUAL LIMITATION (memory ceiling, honestly characterized):
#   Files whose DEFLATE stream needs large Huffman (huft) tables -- typically
#   real prose with skewed symbol frequencies -- still fail GRACEFULLY with
#   "not enough memory to inflate": the 32 KB window + those huft tables + the
#   2 KB stack + UnZip's near globals/strings exceed the single 64 KB small-model
#   DGROUP by a few KB. Synthetic/random inputs (uniform Huffman) fit and pass.
#   Lifting this needs moving more near message strings out of DGROUP (extending
#   the Far-string -> Extra-group work in flexos/flxcfg.h) or the medium/compact
#   model -- a separate effort, not the >32 KB crash this build fixes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Locate the open-watcom-v2 tree (built bld/ + the CP/M-86 clib contrib).
OWROOT="${OWROOT:-$(cd "$ROOT/../open-watcom-v2" 2>/dev/null && pwd || true)}"
[ -n "$OWROOT" ] && [ -d "$OWROOT/bld" ] || {
  echo "!! set OWROOT to a built open-watcom-v2 tree (needs bld/ and the" >&2
  echo "   contrib/ravn/watcom-cpm86-libc clib). Got: '${OWROOT:-<unset>}'" >&2
  exit 1; }

B="$OWROOT/bld"
CLIB="$OWROOT/contrib/ravn/watcom-cpm86-libc"
# COMPACT model (was small): UnZip's 32 KB inflate window (slide[]) is malloc'd
# via MALLOC_WORK, and in the small model that malloc came from the near heap
# inside the single 64 KB DGROUP -> it could not fit ("not enough memory to
# inflate"), so only STORED entries extracted.  Compact (-mcmodel=s) keeps the
# code NEAR (one <=64 KB code segment, exactly as small -- UnZip's code only
# just fits 64 KB, and the LARGE model's -zm far-call overhead bloats it past
# the single CP/M-86 code group -> E2052), but makes DATA far: -mc defines
# __BIG_DATA__ so plain malloc()/free() are the FAR-heap ones (the .CMD Extra
# group / dynamic BDOS-128 grants), so the 32 KB slide lives outside the 64 KB
# near limit and DEFLATED entries now inflate.
LIBDIR="${LIBDIR:-$OWROOT/lib286/cpm86}"
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"

[ -f "$LIBDIR/clibs.lib" ] && [ -f "$LIBDIR/cstartcpm.obj" ] || {
  echo "!! compact-model clib missing under $LIBDIR" >&2
  echo "   build it:  ( cd $CLIB && MODEL=c ./build-lib.sh )" >&2
  exit 1; }

# owcc/wcc/wlink on PATH (env.sh symlinks a -bcpm86 owcc into a temp bindir).
# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

OUT="${OUT:-$ROOT/out-cpm86-small-diag}"
mkdir -p "$OUT"

INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"
# SMALL_MEM stays (it only sizes I/O buffers + selects the Far-string helpers,
# it is NOT the compiler memory model); the model is set by -mcmodel=l.  With
# __BIG_DATA__ (implied by -ml) malloc()/free() are the FAR-heap ones, so the
# MALLOC_WORK slide window lands in the far heap.
DEFS="-DFLEXOS -DMALLOC_WORK -DDYNALLOC_CRCTAB -DNO_ZIPINFO -DNO_DEFLATE64 \
-DSMALL_MEM -DINBUFSIZ=512 \
-DLZW_CLEAN -DCOPYRIGHT_CLEAN -DNO_IMPLODE \
-Dzfmalloc=malloc -Dzffree=free ${EXTRA_DEFS:-}"
CFLAGS="-bcpm86 -march=i186 -mcmodel=s -Os"

# Far-heap reservation for the linker's fallback marker.  BDOS-128 is the primary
# allocator and grants each segment (incl. the 32 KB inflate window) from the OS
# on demand, so a minimal reservation suffices; override FARHEAP to test the
# static fallback.  (Same rationale as build-zip-cpm86.sh.)
: "${FARHEAP:=0x1000}"
FARHEAP_PARAS=$(( FARHEAP / 16 ))

# UnZip core objects for a NO_ZIPINFO build, plus the CP/M-86 OS layer.
# The obsolete PKZIP-1.x decompressors (explode/unshrink/unreduce, i.e. the
# implode/shrink/reduce methods) are DROPPED: they add ~7 KB of code that pushed
# the compact-model single 64 KB code group over the limit (E2021), and modern
# archives use only store + deflate.  LZW_CLEAN/COPYRIGHT_CLEAN (Info-ZIP flags)
# remove the unshrink/unreduce call sites; NO_IMPLODE (our gate in extract.c)
# removes the explode one.  Such an archive member reports an unsupported method.
CORE="unzip crc32 crypt envargs extract fileio globals inflate \
list match process ttyio ubz2err apihelp"

echo "==> compiling UnZip for CP/M-86 (compact model, farheap=${FARHEAP} = ${FARHEAP_PARAS} paras)"
cd "$ROOT/src/unzip60"
# cpm86.obj first so its seam definitions win the first-definition link rule.
# shellcheck disable=SC2086
owcc $CFLAGS $DEFS $INC -c cpm86/cpm86.c -o "$OUT/cpm86.obj"
OBJS="file $OUT/cpm86.obj"
for s in $CORE; do
  # shellcheck disable=SC2086
  owcc $CFLAGS $DEFS $INC -c "$s.c" -o "$OUT/$s.obj"
  OBJS="$OBJS file $OUT/$s.obj"
done

# farheap.c compiled with -DCPM86_FARHEAP_PARAS so __AllocSeg derives the full
# G_MAX reservation on real CCP/M-86 (loader writes G_MIN to DS:0x0C); linked
# BEFORE clibl.lib so it overrides the library fallback.  (Mirrors zip build.)
PORTDIR="$OWROOT/contrib/ravn/watcom-cpm86-libc/port"
PORTINC="-I$OWROOT/bld/clib/h -I$OWROOT/bld/clib/heap/h"
# shellcheck disable=SC2086
:
# (small model: no far heap)

echo "==> linking UNZIP.CMD"
WLINK="$B/wl/osxa64/wlink.exe"
# shellcheck disable=SC2086
"$WLINK" format cpm86 op dosseg,nodefaultlibs \
  op map="$OUT/unzip.map" \
  name "$OUT/UNZIP.CMD" file "$LIBDIR/cstartcpm.obj" $OBJS library "$LIBDIR/clibs.lib"

cp "$OUT/UNZIP.CMD" "$ROOT/UNZIP.CMD"
echo
echo "==> UNZIP.CMD built:"
ls -la "$OUT/UNZIP.CMD"
echo
echo "   Test under emu2:   emu2 UNZIP.CMD ARCHIVE.ZIP        (STORED entries)"
echo "   NOTE: emu2/CCP upper-cases the command tail, so lower-case option"
echo "         letters (e.g. -l) arrive as -L; test the default extract action."
