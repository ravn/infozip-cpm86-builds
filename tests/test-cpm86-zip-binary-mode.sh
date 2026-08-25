#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build-zip-cpm86.sh"
TAILOR="$ROOT/src/zip30/tailor.h"

# ZIP output is compressed binary data.  Text-mode writes can expand a
# compressed LF to CR/LF on CCP/M, producing "s=318, actual=319".
grep -q -- '#    define FOPW "wb"' "$TAILOR"
