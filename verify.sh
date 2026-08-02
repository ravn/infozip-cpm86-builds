#!/bin/bash
# Assert that every built executable is a genuine 16-bit real-mode DOS image:
# an MZ header with no PE/NE/LE/LX extended header hiding behind it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

python3 - <<'PY'
import glob, os, struct, sys

files = sorted(glob.glob('out/*.exe'))
if not files:
    sys.exit('!! no binaries in ./out')

bad = 0
for path in files:
    data = open(path, 'rb').read()
    magic = data[:2]
    (_, _, _, relocs, _, minalloc, *_rest) = struct.unpack('<7H', data[:14])
    cs, ip = struct.unpack('<H', data[22:24])[0], struct.unpack('<H', data[20:22])[0]

    # A DOS stub for a PE/NE/LE binary points at an extended header via 0x3c.
    ext = b''
    if len(data) > 0x40:
        off = struct.unpack('<I', data[0x3c:0x40])[0]
        if 0 < off < len(data) - 2:
            ext = data[off:off + 2]

    ok = magic == b'MZ' and ext not in (b'PE', b'NE', b'LE', b'LX')
    bad += not ok
    print(f"{os.path.basename(path):<14} {len(data):>7} bytes  relocs={relocs:<5} "
          f"CS:IP={cs:04x}:{ip:04x}  {'OK real-mode MZ' if ok else 'FAIL not real-mode'}")

sys.exit(bad and f'!! {bad} file(s) are not real-mode DOS executables')
PY
