# Help text stubbed under -DCPM86_SLIM

To make full-DEFLATE ZIP.CMD fit in the RC759's ~190 KB effective TPA (see
`ZIP_DEFLATE_MAME_SOLVED_2026-08-25.md`), the `-DCPM86_SLIM` build replaces two
help functions in `src/zip30/zip.c` with a single one-line usage message. This
frees ~17 KB of DATA-group strings — enough to keep the incremental-update code
AND run the full 4 KB deflate window.

## What is stubbed (both gated `#if defined(CPM86_SLIM) || defined(CPM86_CREATE_ONLY)`)

| Function | Reached by | Lines of text removed | What it was |
|----------|-----------|----------------------:|-------------|
| `help()`          | `zip -h`, or bad options | **56** | Standard usage screen: the one-screen option summary (`-f -u -d -r -0..-9 -q -v -c -z -F -T -X …`), including the Mac/VMS/Tandem `#ifdef` variants. |
| `help_extended()` | `zip -h2`                | **325** (~340 code lines) | The multi-page manual-style extended help: "Extended Help for Zip", examples (`zip z file.txt`), mode descriptions, per-option explanations. |

Total: **381 text strings ≈ 17 KB** of DATA group.

## Replaced by
```c
printf("Zip (CP/M-86). Usage: zip [-0..-9 -d -f -u -m -j] archive.zip file...\n");
```

## What is NOT affected
Only the *help text* is removed. The option parser in `main()` is untouched, so
every option still works — `-0..-9`, `-d`, `-f`, `-u`, `-m`, `-j`, `-r`, `-x`/`-i`,
`-l`, `-q`, `-v`, etc. `zip -h` / `zip -h2` just print the one-line usage instead
of the full help/manual screens.

This matches the CP/M idiom of shipping help in a separate `.HLP` file (as the
turnkey disk's own `HELP.HLP` does) rather than embedding it in the executable.

The stock (non-SLIM, non-CREATE_ONLY) build keeps the full help unchanged.
