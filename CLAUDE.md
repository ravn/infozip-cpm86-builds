# CLAUDE.md — infozip-cpm86-builds

Guidance for Claude Code in this repo (Info-ZIP ported to Concurrent CP/M-86,
built with Open Watcom `owcc -bcpm86`). Read this before testing any `.CMD`.

## Truth witness
`emu2-cpm86` (`../emu2-cpm86/emu2`) is a fast **differential oracle**, NOT the
truth witness. Only **MAME (rc759, CCP/M-86)** decides CCP/M-specific behaviour.
If emu2 and MAME disagree, MAME wins.

## Testing a `.CMD` under emu2 — hard rules (each caused a FALSE result once)

1. **Actually exercise the operation — delete outputs first.** Before an
   extract / decrypt / round-trip check, `rm` the target file. Otherwise a tool
   that does *nothing* "passes" against the pre-existing file. (This false
   positive hid that UNZIP wasn't extracting at all.)

2. **Never background emu2 (`&`).** A backgrounded emu2 takes SIGTTIN the moment
   it touches console input. Wrap it in a **foreground** timeout instead — macOS
   has no `timeout(1)`, so use:
   `perl -e 'alarm SECS; exec @ARGV' "$EMU2" -m "$TPA" PROG.CMD args…`

3. **CP/M-86 has NO subdirectories.** Never pass a `../path` to a `.CMD`. Run
   emu2 in ONE flat dir: copy the `.CMD` + inputs in, `cd` there, work there.

4. **CCP/M upper-cases the WHOLE command tail** at base-page level, before the
   program runs (proven with `tools/taildump`; see workspace memory
   `reference_ccpm86_uppercases_command_tail`). Therefore:
   - Lower-case short options fold: `-o`→`-O`, `-v`→`-V`, `-p`→`-P`. **UNZIP
     `-O` is aliased to overwrite** on CP/M-86 (so the folded `-o` works); use
     `unzip -O` for silent overwrite, or extract into an **empty dir** to dodge
     the replace-prompt. Long options got case-insensitive handling in `zip`;
     other short options in `unzip` did NOT — see `CPM86_NOTES.txt` for the
     per-tool option map that ships in the distribution.
   - Command-line passwords fold to upper-case (`zip -Psecret` stores `SECRET`).
     Consistent on encrypt+decrypt, so round-trips work, but case is lost. For a
     case-preserving password use the interactive prompt (raw console).

5. **Console input is not your shell pipe.** Two distinct un-pipeable paths:
   - Raw no-echo `getch()` → BDOS fn 6 → emu2 reads **`/dev/tty`**, not stdin.
     Used by password prompts (`zipcloak`, `zip -e`). A pipe never reaches it →
     busy-hang. **zipcloak is interactive-only → verify under MAME.**
   - `fgets(stdin)` (UNZIP "replace? [y]…" overwrite prompt) returns garbage
     under non-interactive emu2 → "invalid response" loop. Dodge with an empty
     extract dir. (This one *can* be fed a pipe, unlike getch.)

6. **Memory model dictates whether the 32 KB inflate/deflate window fits.**
   `zip` and `unzip` both need a 32 KB window. In the SMALL model it is a near
   `malloc` inside the single 64 KB DGROUP and does not fit → "not enough memory
   to inflate" (this is a 64 KB-segment ceiling, NOT total TPA — more emu2 `-m`
   does not help). Fixes: `zip` = LARGE model + far heap; `unzip` = COMPACT
   model (`-mcmodel=c`, near code like small so its code still fits one 64 KB
   code group, but `__BIG_DATA__` routes `malloc` to the far heap). UNZIP's
   obsolete decompressors (implode/shrink/reduce = explode/unshrink/unreduce)
   are dropped (`-DLZW_CLEAN -DCOPYRIGHT_CLEAN -DNO_IMPLODE`) to keep code under
   64 KB; only store+deflate remain. `funzip` is tiny enough to inflate even in
   the small model.

7. **Rebuild against a consistent clib before diagnosing a "bug".** The scratch
   `open-watcom-v2/contrib/ravn/watcom-cpm86-libc/build-lib/clibcpm.lib` is
   **model-ambiguous** — it holds whatever `MODEL=` ran last. A mismatched-model
   link throws spurious `cannot open …` / `_small_code_ undefined` that mimic
   real bugs. Order: `MODEL=s` clib → small-model consumers (unzip, ziputils,
   funzip); `MODEL=l` clib → `zip` (large). The suite test enforces this order.

## Suite functional test
`tests/test-cpm86-suite.sh` (emu2). PASS the working tools, SKIP the
interactive-only ones (zipcloak) with a MAME pointer, and use STORED archives
where checking the extract path. Run: `bash tests/test-cpm86-suite.sh`.

## Workspace rules that still apply
Root `/Users/ravn/z80/CLAUDE.md` governs: never search outside `/Users/ravn/z80/`;
never write to `~/.claude/`; durable cross-session lessons go in
`/Users/ravn/z80/tasks/memory/` (index `MEMORY.md`); commit locally freely, push
only at merges, `--no-ff`, never open PRs unless told; respond in Danish.
