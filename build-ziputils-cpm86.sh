#!/bin/bash
# build-ziputils-cpm86.sh -- Cross-compile Info-ZIP Zip 3.0 UTIL programs for
# CP/M-86 (Intel 8086/80186, small memory model, Open Watcom owcc -bcpm86).
#
# Builds three utilities from the same zip30 source tree as ZIP.CMD:
#
#   ZIPNOTE.CMD   Read/write comments in ZIP archives (stdin/stdout).
#                 Usage: ZIPNOTE ARCHIVE.ZIP            (print comments)
#                        ZIPNOTE -w ARCHIVE.ZIP < notes.txt (write comments)
#
#   ZIPSPLIT.CMD  Split one ZIP archive into multiple volumes.
#                 Usage: ZIPSPLIT -n <maxbytes> ARCHIVE.ZIP
#                 Output: 000001.zip, 000002.zip, ... + zipsplit.idx
#
#   ZIPCLOAK.CMD  Encrypt/decrypt entries in an existing ZIP archive.
#                 Usage: ZIPCLOAK ARCHIVE.ZIP           (encrypt, prompts for password)
#                        ZIPCLOAK -d ARCHIVE.ZIP        (decrypt)
#
# UTIL-mode architecture (-DUTIL):
#   - NO deflate, NO trees, NO DYN_ALLOC, NO far heap, NO WSIZE buffers.
#   - Shared UTIL core: zipfile, fileio, util, globals (compiled once with -DUTIL).
#   - Each utility adds only its own .obj (zipnote.c already #defines UTIL).
#   - zipcloak adds: crc32 (CRC_TABLE_ONLY via zip.h), crypt (-DUTIL entry point),
#     ttyio (getp() no-echo password via BDOS getch()).
#   - All three fit in small model (~14-25 KB each; no farheap needed).
#   - cpm86/cpm86.c is compiled with -DUTIL: suppresses zcalloc/zcfree (which
#     reference _fcalloc/_ffree, absent in clibs.lib small model).
#
# ZERO edits to Info-ZIP's generic C sources. All CP/M-86 specifics are in
# cpm86/cpm86.c (the OS layer, same file as ZIP.CMD but compiled -DUTIL).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OWROOT="${OWROOT:-$(cd "$ROOT/../open-watcom-v2" 2>/dev/null && pwd || true)}"
[ -n "$OWROOT" ] && [ -d "$OWROOT/bld" ] || {
  echo "!! set OWROOT to a built open-watcom-v2 tree" >&2
  exit 1; }

B="$OWROOT/bld"
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"
CLIB="$OWROOT/contrib/ravn/watcom-cpm86-libc"

# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

# cstartcpm.obj (defines _small_code_) from the staged lib286/cpm86/ dir;
# clibcpm.lib from contrib build-lib/ (avoids wlink's auto-import of
# "clibs.lib" by name which fails even with a full path).
LIBDIR="$OWROOT/lib286/cpm86"

[ -f "$LIBDIR/cstartcpm.obj" ] || {
  echo "!! cstartcpm.obj missing under $LIBDIR" >&2; exit 1; }
[ -f "$CLIB/build-lib/clibcpm.lib" ] || {
  echo "!! clibcpm.lib missing under $CLIB/build-lib" >&2
  echo "   build it: ( cd $CLIB && ./build-lib.sh )" >&2; exit 1; }

OUT="${OUT:-$ROOT/out-ziputils-cpm86}"
mkdir -p "$OUT"

INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"

# -DUTIL: suppresses deflate machinery, DYN_ALLOC, far-heap zcalloc.
# Zip utility .c files already #define UTIL themselves, so -DUTIL is redundant
# but harmless for those; it IS needed for the shared core files.
CFLAGS="-bcpm86 -march=i186 -mcmodel=s -Os"
DEFS="-DUTIL"

WLINK="$B/wl/osxa64/wlink.exe"

echo "==> compiling shared UTIL core (small model, -DUTIL)"
cd "$ROOT/src/zip30"

# Shared core -- compiled once with -DUTIL, linked into all three utilities.
CORE_SRCS="zipfile fileio util globals"
OBJS_CORE=""
for s in $CORE_SRCS; do
  # shellcheck disable=SC2086
  owcc $CFLAGS $DEFS $INC -c "$s.c" -o "$OUT/${s}_u.obj"
  OBJS_CORE="$OBJS_CORE file $OUT/${s}_u.obj"
done
# CP/M-86 OS layer (compiled with -DUTIL: suppresses zcalloc/zcfree).
# shellcheck disable=SC2086
owcc $CFLAGS $DEFS $INC -c cpm86/cpm86.c -o "$OUT/cpm86_u.obj"
OBJS_CORE="$OBJS_CORE file $OUT/cpm86_u.obj"

# wlink pattern mirrors build-cpm86.sh (unzip, proven): op nodefaultlibs
# suppresses auto-import of "clibs.lib" by name; clibcpm.lib is the contrib
# C runtime that works without naming conflicts; cstartcpm.obj defines
# _small_code_ for small-model C objects.
WLINK_FLAGS="format cpm86 op dosseg,nodefaultlibs"
CLIB_LIB="$LIBDIR/clibs.lib"
CRT0="$LIBDIR/cstartcpm.obj"

# --------------------------------------------------------------------------
echo "==> ZIPNOTE.CMD"
# shellcheck disable=SC2086
owcc $CFLAGS $INC -c zipnote.c -o "$OUT/zipnote.obj"
# shellcheck disable=SC2086
"$WLINK" $WLINK_FLAGS \
  op map="$OUT/zipnote.map" name "$OUT/ZIPNOTE.CMD" \
  file "$CRT0" file "$OUT/zipnote.obj" $OBJS_CORE \
  library "$CLIB_LIB"

# --------------------------------------------------------------------------
echo "==> ZIPSPLIT.CMD"
# shellcheck disable=SC2086
owcc $CFLAGS $INC -c zipsplit.c -o "$OUT/zipsplit.obj"
# shellcheck disable=SC2086
"$WLINK" $WLINK_FLAGS \
  op map="$OUT/zipsplit.map" name "$OUT/ZIPSPLIT.CMD" \
  file "$CRT0" file "$OUT/zipsplit.obj" $OBJS_CORE \
  library "$CLIB_LIB"

# --------------------------------------------------------------------------
echo "==> ZIPCLOAK.CMD"
# zipcloak needs: crc32 (CRC_TABLE_ONLY via -DUTIL in zip.h), crypt (-DUTIL
# enables the zipcloak() entry point), ttyio (getp() password prompt via getch).
# shellcheck disable=SC2086
owcc $CFLAGS $DEFS $INC -c zipcloak.c -o "$OUT/zipcloak.obj"
owcc $CFLAGS $DEFS $INC -c crc32.c    -o "$OUT/crc32_u.obj"
owcc $CFLAGS $DEFS $INC -c crypt.c    -o "$OUT/crypt_u.obj"
owcc $CFLAGS $DEFS $INC -c ttyio.c    -o "$OUT/ttyio_u.obj"
# shellcheck disable=SC2086
"$WLINK" $WLINK_FLAGS \
  op map="$OUT/zipcloak.map" name "$OUT/ZIPCLOAK.CMD" \
  file "$CRT0" \
  file "$OUT/zipcloak.obj" file "$OUT/crc32_u.obj" \
  file "$OUT/crypt_u.obj"  file "$OUT/ttyio_u.obj" \
  $OBJS_CORE library "$CLIB_LIB"

# --------------------------------------------------------------------------
cp "$OUT/ZIPNOTE.CMD"  "$ROOT/ZIPNOTE.CMD"
cp "$OUT/ZIPSPLIT.CMD" "$ROOT/ZIPSPLIT.CMD"
cp "$OUT/ZIPCLOAK.CMD" "$ROOT/ZIPCLOAK.CMD"

echo
echo "==> built:"
ls -la "$OUT/ZIPNOTE.CMD" "$OUT/ZIPSPLIT.CMD" "$OUT/ZIPCLOAK.CMD"
echo
echo "   Test under emu2:"
echo "   emu2 ZIPNOTE.CMD POEM.ZIP                       (print archive comment)"
echo "   emu2 ZIPSPLIT.CMD -n 5000 BIG.ZIP               (split into volumes)"
echo "   emu2 ZIPCLOAK.CMD -d ENCRYPTED.ZIP              (decrypt, prompts password)"
