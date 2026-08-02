#!/bin/bash
# Fetch the Open Watcom V2 toolchain used to cross-compile for 16-bit DOS.
#
# The official Linux installer is a self-extracting ELF binary. Rather than
# execute it (it dies with SIGFPE under Rosetta on Apple Silicon, and running
# a downloaded installer is undesirable anyway), we note that its payload is
# an ordinary ZIP archive appended to the ELF and simply extract that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

URL="https://github.com/open-watcom/open-watcom-v2/releases/download/Current-build/open-watcom-2_0-c-linux-x64"
INSTALLER="ow-c-linux-x64"

if [ -d watcom/binl64 ]; then
  echo "==> toolchain already present in ./watcom (delete it to re-fetch)"
  exit 0
fi

if [ ! -f "$INSTALLER" ]; then
  echo "==> downloading Open Watcom V2 (~128 MB)"
  curl -fsSL -o "$INSTALLER" "$URL"
fi

echo "==> extracting payload"
mkdir -p watcom
python3 - "$INSTALLER" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall('watcom')
    print(f"   {len(z.namelist())} entries extracted")
PY

chmod -R u+rwX watcom
chmod +x watcom/binl64/* 2>/dev/null || true

echo "==> toolchain ready in ./watcom"
