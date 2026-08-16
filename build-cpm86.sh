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
# KNOWN LIMITATION (memory ceiling, honestly characterized):
#   STORED entries extract with byte-correct content AND passing CRC.
#   DEFLATE entries fail with "not enough memory to inflate": the 32 KB window +
#   inflate's huft tables + UnZip's ~22 KB of Far message strings + globals +
#   stack exceed the single 64 KB small-model DGROUP by a few KB. Fitting
#   deflate would require moving the message strings to a far segment (compact
#   model -- against the small-model/near-clib design) or stripping messages
#   (a generic-source edit -- against this port's zero-edit rule). Left as-is.
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
LIBDIR="$CLIB/build-lib"                 # holds clibcpm.lib + crt0.obj
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"

[ -f "$LIBDIR/clibcpm.lib" ] && [ -f "$LIBDIR/crt0.obj" ] || {
  echo "!! clibcpm.lib / crt0.obj missing under $LIBDIR" >&2
  echo "   build them first:  ( cd $CLIB && ./build-lib.sh )" >&2
  exit 1; }

# owcc/wcc/wlink on PATH (env.sh symlinks a -bcpm86 owcc into a temp bindir).
# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

OUT="${OUT:-$ROOT/out-cpm86}"
mkdir -p "$OUT"

INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"
DEFS="-DFLEXOS -DMALLOC_WORK -DDYNALLOC_CRCTAB -DNO_ZIPINFO -DNO_DEFLATE64 \
-DSMALL_MEM -DINBUFSIZ=512 \
-Dzfmalloc=malloc -Dzffree=free -Dzfstrcpy=strcpy -Dzfstrcmp=strcmp"
CFLAGS="-bcpm86 -march=i186 -mcmodel=s -Os"

# UnZip core objects for a NO_ZIPINFO build, plus the CP/M-86 OS layer.
CORE="unzip crc32 crypt envargs explode extract fileio globals inflate \
list match process ttyio ubz2err unreduce unshrink apihelp"

echo "==> compiling UnZip for CP/M-86 (small model)"
cd "$ROOT/src/unzip60"
OBJS=""
for s in $CORE; do
  # shellcheck disable=SC2086
  owcc $CFLAGS $DEFS $INC -c "$s.c" -o "$OUT/$s.obj"
  OBJS="$OBJS file $OUT/$s.obj"
done
# shellcheck disable=SC2086
owcc $CFLAGS $DEFS $INC -c cpm86/cpm86.c -o "$OUT/cpm86.obj"
OBJS="$OBJS file $OUT/cpm86.obj"

echo "==> linking UNZIP.CMD"
WLINK="$B/wl/osxa64/wlink.exe"
# shellcheck disable=SC2086
"$WLINK" format cpm86 op dosseg,nodefaultlibs \
  file "$LIBDIR/crt0.obj" $OBJS library "$LIBDIR/clibcpm.lib" \
  name "$OUT/UNZIP.CMD"

cp "$OUT/UNZIP.CMD" "$ROOT/UNZIP.CMD"
echo
echo "==> UNZIP.CMD built:"
ls -la "$OUT/UNZIP.CMD"
echo
echo "   Test under emu2:   emu2 UNZIP.CMD ARCHIVE.ZIP        (STORED entries)"
echo "   NOTE: emu2/CCP upper-cases the command tail, so lower-case option"
echo "         letters (e.g. -l) arrive as -L; test the default extract action."
