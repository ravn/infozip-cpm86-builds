# CCP/M-86 folds the command line to UPPERCASE — MAME-verified 2026-08-25

## Finding
On a real RC759 under Concurrent CP/M-86 3.1 (MAME rc759, PICCOLINE XIOS 2.3),
**the command tail delivered to a transient program is folded to upper-case**,
even though the console *echoes* what you typed in its original case.

This matters for the Info-ZIP zip port: zip has ~13 case-distinct option pairs
(`-d`/`-D`, `-t`/`-T`, `-f`/`-F`, `-l`/`-L`, `-x`/`-X`, `-n`/`-N`, `-s`/`-S`,
`-a`/`-A`, `-c`/`-C`, `-j`/`-J`, `-b`/`-B`, `-o`/`-O`, `-h`/`-H`). Since the tail
arrives upper-cased, a user cannot type the lower-case member of a pair — it
collides with the upper-case one.

## Evidence (MAME, not emu2)
Typed at the `A>` prompt via MAME natkeyboard (lower-case), console echoed
lower-case, but the program received upper-case:

```
A>taildump abcXYZ          <- typed lower-case (echoed lower-case)
RAWTAIL len=7 [ ABCXYZ]    <- base-page 0x80 tail: UPPER-CASED
ARGC=2 argv1=[ABCXYZ]      <- argv: UPPER-CASED
```

So the fold happens in CCP/M's command processing (the P_CLI / F_PARSE path),
*between* console input and base-page tail construction — not in the echo.
Screenshot: `tools/taildump/mame_result_2026-08-25.png`.

## Documentation vs. reality
The Concurrent CP/M Programmer's Reference Guide (Jan 84) §6.2.7:
- `F_PARSE` (used by `P_CLI`) "translates all lowercase letters to uppercase"
  — but the guide documents this only for the **FCB / filename fields**
  (0x5C/0x6C), and does NOT explicitly say the **0x80 command tail** is folded.
- So the guide left the tail's case OPEN. MAME settled it: the tail IS folded.

There is **no BDOS call or structure** that gives a transient program the
pre-fold original command line:
- The original lives in the parent TMP's `CLBUF` (P_CLI input) — not accessible
  to the child.
- The child sees only the base page: 0x80 tail (folded) + FCBs (folded).
- `P_PDADR` (fn 156) → an RSP Command Queue Message has a 129-byte COMMAND TAIL,
  but that is for Resident System Processes, not transient CMD programs.

## Reproduce
`tools/taildump/taildump.c` — reads base-page 0x80 tail + prints argv. Build
small-model (see `open-watcom-v2/contrib/ravn/watcom-cpm86-libc/build-farheap-mame.sh`
recipe: `wcc -bt=dos -0 -ms ...` + `wlink format cpm86 ... clibs.lib`). Install
as e.g. `taildump.cmd` on a disk with NO `menu.cmd` (so the turnkey autostart
`menu imenu` fails to `A>`), boot MAME, `natkeyboard:post("taildump abcXYZ\n")`,
read the console snapshot.

## Implication for zip option handling (sensible scheme)
Case is fundamentally lost, so any scheme must choose which variant a bare letter
means. Recommended:
1. **Short options → map the (folded) upper-case letter to the *common* meaning**
   in the CP/M argv layer (`cpm86/cpm86.c`, the OS layer that may be non-pristine):
   e.g. `-D`→`-d`, `-FF`→`-ff`; digits `-0..-9` unaffected. Covers the options
   people actually use (delete, freshen, update, recurse, exclude, levels).
2. **Rare upper-case variants → case-insensitive long options** (`--dir-entries`,
   `--to-crlf`, …). Word-based, so they don't collide even when the CCP folds them.

(Not yet implemented — this doc records the verified constraint that motivates it.)
