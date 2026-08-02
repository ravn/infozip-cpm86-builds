#!/bin/bash
# Cross-compile Info-ZIP Zip 3.0 and UnZip 6.0 for 16-bit real-mode MS-DOS
# (8086, large memory model) using Open Watcom V2.
#
# The Watcom binaries we use are Linux x86_64. On such a host we run them
# directly; anywhere else (e.g. macOS/Apple Silicon) we run them in an
# amd64 Linux container. Either way the emitted DOS executables are identical.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

[ -d watcom/binl64 ] || { echo "!! toolchain missing; run ./setup-toolchain.sh first" >&2; exit 1; }

echo "==> preparing pristine build tree"
rm -rf build out
mkdir -p build out
cp -R src/zip30 src/unzip60 build/

echo "==> patching makefiles for a POSIX host"
python3 patch-makefile.py build/zip30/msdos/makefile.wat
python3 patch-makefile.py build/unzip60/msdos/makefile.wat

# The compile steps themselves, run either natively or inside a container.
COMPILE='
set -euo pipefail
export WATCOM=$PWD/watcom
export PATH=$WATCOM/binl64:$PATH
export INCLUDE=$WATCOM/h
export EDPATH=$WATCOM/eddat

echo "--- Zip 3.0 ---"
( cd build/zip30   && wmake -f msdos/makefile.wat all )
echo "--- UnZip 6.0 ---"
( cd build/unzip60 && wmake -f msdos/makefile.wat all )

cp build/zip30/*.exe build/unzip60/*.exe out/
'

if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
  echo "==> building natively (linux/x86_64)"
  bash -c "$COMPILE"
else
  echo "==> building in an amd64 container ($(uname -s)/$(uname -m) host)"
  command -v docker >/dev/null || { echo "!! docker required on non-Linux hosts" >&2; exit 1; }
  docker run --rm -i --platform linux/amd64 \
    -v "$ROOT":/w -w /w debian:bookworm-slim bash -c "$COMPILE"
fi

chmod 644 out/*.exe
echo
echo "==> binaries in $ROOT/out"
ls -la out/
