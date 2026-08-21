#!/bin/bash
# Build the small CP/M-86 ZIP.CMD used for MAME/RC759 smoke tests.
# It writes standard STORE-only ZIP archives and supports CP/M wildcards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OWROOT="${OWROOT:-$(cd "$ROOT/../open-watcom-v2" 2>/dev/null && pwd || true)}"
[ -n "$OWROOT" ] && [ -d "$OWROOT/bld" ] || {
  echo "!! set OWROOT to a built open-watcom-v2 tree" >&2
  exit 1
}

B="$OWROOT/bld"
CLIB="$OWROOT/contrib/ravn/watcom-cpm86-libc"
LIBDIR="${LIBDIR:-$OWROOT/lib286/cpm86}"
ENVSH="$OWROOT/contrib/ravn/cpm86-clib/env.sh"
OUT="${OUT:-$ROOT/out-zip-cpm86}"

[ -f "$LIBDIR/clibs.lib" ] && [ -f "$LIBDIR/cstartcpm.obj" ] || {
  echo "!! small-model clib missing under $LIBDIR" >&2
  echo "   build it:  ( cd $CLIB && ./build-lib.sh )" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$ENVSH" >/dev/null

mkdir -p "$OUT"
INC="-I$B/hdr/dos/h -I$B/clib/h -I$B/clib/intel/h -I$B/watcom/h -I$B/lib_misc/h"
CFLAGS="-bcpm86 -march=i186 -mcmodel=s -Os"

owcc $CFLAGS $INC -c "$ROOT/src/minizip-cpm86/minizip.c" -o "$OUT/minizip.obj"
"$B/wl/osxa64/wlink.exe" format cpm86 op dosseg,nodefaultlibs \
  file "$LIBDIR/cstartcpm.obj" file "$OUT/minizip.obj" library "$LIBDIR/clibs.lib" \
  op map="$OUT/zip.map" name "$OUT/ZIP.CMD"

cp "$OUT/ZIP.CMD" "$ROOT/ZIP.CMD"
ls -la "$OUT/ZIP.CMD"
