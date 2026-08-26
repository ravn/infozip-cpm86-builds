# DEFERRED: merge cpm86-port -> main (src file-tree vs submodule transition)

**Decision 2026-08-26: leave the port on `cpm86-port`; do NOT merge to `main` yet.**

## The situation
`cpm86-port` holds the entire CP/M-86 port (28 commits ahead of `main`, 0 behind).
`main` is the pristine MS-DOS base. They are NOT a clean superset because `src/`
is stored differently on each branch:

- **`main`:** `src/` is a normal directory of ~420 tracked files (the full
  Info-ZIP Zip/UnZip source lives directly in this repo).
- **`cpm86-port`:** `src` is a **submodule** (gitlink -> `ravn/infozip-cpm86`) plus
  a `.gitmodules`. The source was moved out into its own repo.

So a merge is a **directory <-> submodule transition** for `src/`, not an additive
update. `git checkout main` even aborts on cpm86-port because the submodule's
checked-out files collide with main's tracked `src/*` files.

Merging `cpm86-port -> main` would make `main` **adopt the submodule model**:
delete its ~420 tracked `src/*` files and replace them with the gitlink +
`.gitmodules`. That is a deliberate restructuring of the default branch's storage,
not a routine merge — hence deferred for an explicit decision.

## When we do decide to merge, the clean procedure is
1. `git submodule deinit -f src`   (temporarily empty the `src/` working tree)
2. `git checkout main`
3. `git merge --no-ff cpm86-port`   (resolve `src` to cpm86-port's version = submodule)
4. `git push origin main`

## Current state (fine as-is)
- `cpm86-port` is pushed to origin and is the working/development branch.
- The port is verified: emu2 suite test + real MAME rc759 (compact UnZip inflate,
  large-model deflate ZIP). `main` stays the untouched MS-DOS base.
- No action needed unless/until we want `main` to carry the CP/M-86 port.
