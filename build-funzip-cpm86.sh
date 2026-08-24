#!/bin/bash
# build-funzip-cpm86.sh -- Cross-compile Info-ZIP fUnZip for 16-bit CP/M-86
# (Intel 8086/80186, small model, Open Watcom owcc -bcpm86).
#
# funzip: filter unzip -- reads a ZIP or gzip stream from stdin, decompresses
# the first entry, and writes the result to stdout.  CP/M-86 usage:
#
#   FUNZIP.CMD ARCHIVE.ZIP > OUTPUT.TXT     (decompress first entry to file)
#   FUNZIP.CMD < ARCHIVE.ZIP > OUTPUT.TXT   (stdin redirect, same effect)
#
# stdin/stdout redirection works via __CommonRedirect_ in crt0sm.asm:
# "FUNZIP.CMD POEM.ZIP > POEM.TXT" opens POEM.ZIP for reading on fd 0 and
# POEM.TXT for writing on fd 1 before main() runs.  On real CCP/M-86 the
# user must type the redirect operators literally on the command line.
#
# ZERO edits to generic UnZip sources.  All CP/M-86 specifics are in
# cpm86/cpm86.c (reused from the main UNZIP.CMD build, unchanged).
#
# Memory model: small (same as UNZIP.CMD).  The 32 KB inflate window is
# heap-allocated (MALLOC_WORK) so it does not consume BSS in the 64 KB
# DGROUP.  funzip's code and data together are well under 64 KB.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OWROOT="${OWROOT:-$(cd "$ROOT/../open-watcom-v2" 2>/dev/null && pwd || true)}"
[ -n "$OWROOT" ] && [ -d "$OWROOT/bld" ] || {
  echo "!! set OWROOT to a built open-watcom-v2 tree" >&2; exit 1; }

B="$OWROOT/bld"
CLIB="$OWROOT/contrib/ravn/watcom-cpm86-libc"
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"

# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

LIBDIR="${LIBDIR:-$CLIB/build-lib}"     # clibcpm.lib + crt0.obj (proven pattern)

[ -f "$LIBDIR/clibcpm.lib" ] && [ -f "$LIBDIR/crt0.obj" ] || {
  echo "!! clibcpm.lib / crt0.obj missing under $LIBDIR" >&2
  echo "   build them: ( cd $CLIB && ./build-lib.sh )" >&2; exit 1; }

OUT="${OUT:-$ROOT/out-funzip-cpm86}"
mkdir -p "$OUT"

INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"

# -DFUNZIP:       compile as the filter variant (no extract/list/test logic)
# -DMSDOS -DDOS:  DOS-family target; selects msdos/osdep.h type/macro surface
#                 (does NOT use -DFLEXOS: that activates MED_MEM far-string
#                 machinery that requires fileio.c/process.c absent in funzip)
# -DNO_DEFLATE64: keep WSIZE=32KB so window alloc fits 16-bit size_t
# -DMALLOC_WORK:  heap-allocate inflate window (keeps it out of 64KB DGROUP)
# -DDYNALLOC_CRCTAB: CRC table on heap, not in BSS
# -DSMALL_MEM:    2KB I/O buffers (less DGROUP pressure)
# -DINBUFSIZ=512: shrink input buffer
DEFS="-DFUNZIP -DMSDOS -DDOS -DNO_DEFLATE64 -DMALLOC_WORK -DDYNALLOC_CRCTAB \
-DSMALL_MEM -DINBUFSIZ=512 \
-Dzfmalloc=malloc -Dzffree=free"
CFLAGS="-bcpm86 -march=i186 -mcmodel=s -Os"

echo "==> compiling fUnZip for CP/M-86 (small model)"
cd "$ROOT/src/unzip60"

SRCS="funzip inflate crc32 crypt globals ttyio"
OBJS=""
for s in $SRCS; do
  # shellcheck disable=SC2086
  owcc $CFLAGS $DEFS $INC -c "$s.c" -o "$OUT/${s}f.obj"
  OBJS="$OBJS file $OUT/${s}f.obj"
done
# Minimal CP/M-86 OS layer for funzip: provides fdopen(0/1) and getch().
# We do NOT compile the full unzip cpm86.c here because -DMSDOS pulls in
# msdos/doscfg.h which enables far-string machinery (fnfilter, fLoadFarString,
# _CompiledWith) that requires fileio.c/process.c -- absent in funzip.
# shellcheck disable=SC2086
owcc $CFLAGS $INC -c cpm86/cpm86_funzip.c -o "$OUT/cpm86f.obj"
OBJS="$OBJS file $OUT/cpm86f.obj"

# After env.sh, set LIBDIR + use same proven linker pattern as UTIL utilities:
# cstartcpm.obj (defines _small_code_) + op nodefaultlibs + clibs.lib.
LIBDIR="$OWROOT/lib286/cpm86"

echo "==> linking FUNZIP.CMD"
WLINK="$B/wl/osxa64/wlink.exe"
# shellcheck disable=SC2086
"$WLINK" format cpm86 op dosseg,nodefaultlibs \
  file "$LIBDIR/cstartcpm.obj" $OBJS library "$LIBDIR/clibs.lib" \
  name "$OUT/FUNZIP.CMD"

cp "$OUT/FUNZIP.CMD" "$ROOT/FUNZIP.CMD"
echo
echo "==> FUNZIP.CMD built:"
ls -la "$OUT/FUNZIP.CMD"
echo
echo "   Test under emu2:"
echo "   emu2 FUNZIP.CMD POEM.ZIP > /tmp/poem_out.txt && diff /tmp/poem_out.txt scratch/rc759-unzip-demo/poem.txt"
