#!/bin/bash
# Assemble release assets: one combined archive containing every program,
# plus both pristine upstream source trees and a checksum file.
#
#   ./package.sh [version]       version defaults to r1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VER="${1:-r1}"

[ -n "$(ls out/*.exe 2>/dev/null)" ] || { echo "!! no binaries in ./out; run ./build.sh" >&2; exit 1; }

rm -rf dist
mkdir -p dist/stage

echo "==> staging combined distribution"
cp out/*.exe dist/stage/
# The Info-ZIP license must accompany binary redistributions (condition 2).
cp src/unzip60/LICENSE dist/stage/LICENSE.TXT
# Upstream plain-text manuals, useful on the target machine itself.
cp src/zip30/zip.txt src/zip30/zipcloak.txt src/zip30/zipnote.txt \
   src/zip30/zipsplit.txt dist/stage/
cp src/unzip60/unzip.txt src/unzip60/funzip.txt src/unzip60/unzipsfx.txt dist/stage/

# DOS-facing readme, CRLF line endings so EDIT and TYPE render it correctly.
python3 gen-readme.py "$VER" > dist/stage/README.tmp
python3 -c "
open('dist/stage/README.TXT','w',newline='\r\n').write(open('dist/stage/README.tmp').read())
"
rm -f dist/stage/README.tmp

# CP/M-86 platform notes (option-letter case folding etc.), CRLF so TYPE/EDIT
# render it correctly on the target machine.
python3 -c "
open('dist/stage/CPM86_NOTES.TXT','w',newline='\r\n').write(open('CPM86_NOTES.txt').read())
"

echo "==> creating archives"
( cd dist/stage && zip -9 -q "../infozip-dos16-$VER.zip" ./* )
rm -rf dist/stage

# Pristine upstream sources, mirrored for preservation.
( cd src && zip -9 -qr ../dist/zip30-source.zip   zip30 )
( cd src && zip -9 -qr ../dist/unzip60-source.zip unzip60 )

echo "==> checksums"
( cd dist && shasum -a 256 ./*.zip | sed 's| \./| |' > SHA256SUMS )

ls -la dist/
echo
cat dist/SHA256SUMS
