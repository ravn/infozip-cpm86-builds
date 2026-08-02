#!/bin/bash
# Automated smoke test: run the freshly built 16-bit binaries under DOSBox-X
# headless, round-tripping a zip archive and verifying integrity.
# Usage: ./test-dos.sh [cputype]     (default: 8086)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CPUTYPE="${1:-8086}"
T="$ROOT/dostest"

rm -rf "$T"
mkdir -p "$T"
cp "$ROOT"/out/*.exe "$T"/

# Test payload: some text, plus a binary file to exercise the deflate path.
printf 'Hello from a 16-bit DOS build of Info-ZIP.\r\n%.0s' {1..40} > "$T/README.TXT"
head -c 20000 /dev/urandom > "$T/RANDOM.BIN"
cp "$ROOT/out/ZipNote.exe" "$T/PAYLOAD.DAT"

# Each command redirects separately so DOSBox flushes the file as it goes;
# a single redirect around the whole batch only lands at exit.
cat > "$T/TEST.BAT" <<'BAT'
@echo off
echo === zip -9 === >> TESTLOG.TXT
zip -9 TEST.ZIP README.TXT RANDOM.BIN PAYLOAD.DAT >> TESTLOG.TXT
echo === unzip -l === >> TESTLOG.TXT
unzip -l TEST.ZIP >> TESTLOG.TXT
echo === unzip -t === >> TESTLOG.TXT
unzip -t TEST.ZIP >> TESTLOG.TXT
echo === extract to OUT === >> TESTLOG.TXT
unzip -o -d OUT TEST.ZIP >> TESTLOG.TXT
rem ZIPSPLIT and ZIPNOTE are deliberately not exercised here: they prompt for
rem confirmation, and Info-ZIP reads those prompts straight from the DOS
rem console rather than from stdin, so redirected input cannot answer them and
rem the session would block forever. Test them by hand if you need to.
echo === funzip === >> TESTLOG.TXT
zip -9 ONE.ZIP README.TXT >> TESTLOG.TXT
funzip ONE.ZIP > FUNZ.OUT
echo === DONE === >> TESTLOG.TXT
BAT

cat > "$T/dosbox.conf" <<CONF
[sdl]
output=surface
autolock=false
[dosbox]
machine=svga_s3
memsize=16
# Never pop a GUI "are you sure you want to quit?" dialog -- this harness is
# headless and may be terminated by a watchdog.
quit warning=false
[cpu]
core=normal
cputype=$CPUTYPE
cycles=max
[autoexec]
mount c $T
c:
call TEST.BAT
exit
CONF

echo "==> running DOSBox-X (cputype=$CPUTYPE) headless"
# Watchdog: if the DOS session wedges (e.g. on an interactive prompt), kill it
# outright with SIGKILL. A plain TERM makes DOSBox-X raise a GUI quit dialog.
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  dosbox-x -conf "$T/dosbox.conf" -nolog -fastlaunch >/dev/null 2>&1 &
DOSPID=$!
( sleep "${TIMEOUT:-300}"; kill -9 "$DOSPID" 2>/dev/null ) &
WATCHDOG=$!
wait "$DOSPID" 2>/dev/null || true
kill "$WATCHDOG" 2>/dev/null || true

echo "==> DOS session output:"
if [ -f "$T/TESTLOG.TXT" ]; then
  tr -d '\r' < "$T/TESTLOG.TXT"
else
  echo "!! no TESTLOG.TXT produced"
  exit 1
fi

echo
echo "==> verifying extracted files match originals (on the host)"
fail=0
for f in README.TXT RANDOM.BIN PAYLOAD.DAT; do
  if cmp -s "$T/$f" "$T/OUT/$f"; then
    echo "  OK   $f"
  else
    echo "  FAIL $f"
    fail=1
  fi
done

if cmp -s "$T/README.TXT" "$T/FUNZ.OUT"; then
  echo "  OK   funzip stdout stream"
else
  echo "  FAIL funzip stdout stream"
  fail=1
fi

echo
echo "==> host unzip cross-check of the DOS-produced archive"
unzip -t "$T/TEST.ZIP" | tail -3 || fail=1

exit $fail
