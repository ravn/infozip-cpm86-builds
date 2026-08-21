# Plan — Info-ZIP `zip` 3.0 → CP/M-86 (LARGE model)

Mål: en kørende `ZIP.CMD` for CP/M-86 (RC759), analogt til den eksisterende
`UNZIP.CMD`. Compiler: `owcc -bcpm86`. Model: **large** (`-mcmodel=l`).

## Modelvalg — hvorfor large, ikke medium (revideret 2026-08-21)

Den oprindelige plan sagde *medium* (far code, near data). Det viste sig **forkert**:
`zip.h:834` prototyper `flush_block` som `char far *`, men K&R-definitionen i
`trees.c:1014` er `char *`. I near-data-modeller (small **og medium**) er de to
IKKE ens → `trees.c(1018): E1129`. Samme mismatch findes latent i hele deflate-
datastien (`window` er `far`, men flyder gennem `char *`-parametre i
`flush_block`/`copy_block`/`flush_outbuf`). Kilden må **ikke** editeres — den er den
urørte pristine-kilde DOS-buildet (`build.sh`) reproducerer byte-for-byte.

**Large model løser det med nul edits:** far code + far data gør `char *` == `char far *`,
så prototype og definition matcher. Empirisk bekræftet:

| model | far code | far data | trees.c | zip-kerne |
|-------|:-:|:-:|:-:|:-:|
| small (`s`)   | ✗ | ✗ | **E1129** | — |
| medium (`m`)  | ✓ | ✗ | **E1129** | — |
| compact (`c`) | ✗ | ✓ | ✅ | kode >64 KB → link-fejl |
| **large (`l`)** | ✓ | ✓ | ✅ | **alle 11 objekter rent, nul edits** |

Far code er nødvendig fordi zip's kode ikke er ét segment: linker-map'et lagde
kode over flere 64 KB-frames (frame `0001` ~58 KB + frame `0002` ~52 KB). Compact
(near code) kan derfor ikke linke; large kan.

## Reality-check allerede udført (2026-08-21)

- Alle 11 kerne-objekter oversætter **rent, nul kildeændringer** under
  `owcc -bcpm86 -mcmodel=l`:
  `zip crypt ttyio zipfile zipup util fileio deflate trees globals crc32`
  (`zipup.c` kræver `-DDOS`; **ikke** `-DMMAP` — den trækker Unix `sys/mman.h` ind).
- Prøve-link (mod compact-runtime, kun for at få et map) afslører den præcise
  udefinerede flade: OS-lag + clib-huller + large-runtime-markør `_big_code_`.
- DGROUP = 0x10c22 (68 KB) → **~3 KB over 64 KB**. CONST alene er 38 KB strenge.
  `-zc` (læg konstanter i kodesegmentet, far i large model) flytter dem ud af
  DGROUP → rigelig headroom, uden edits.

Objektsæt (Zip.exe fra `msdos/makefile.wat`): kernen ovenfor **+ `match.c`**
(C-udgaven; leverer `_longest_match`/`_match_init` — droppes IKKE, asm-`match` er
kun en DOS-optimering) + OS-lag (erstatter `msdos.c`).

## Milepæle

### M1 — Modelvalg + large-model compile ✅ (afklaret 2026-08-21)
- [x] Diagnosticér E1129 som near/far type-mismatch (ikke `-zm`-detalje).
- [x] Bekræft large model oversætter hele kernen rent uden kildeændringer.
- [x] Bekræft far code spænder flere frames (>64 KB kode er OK).
- [ ] `-zc` for at holde DGROUP < 64 KB (verificeres ved endeligt link, M6).

### M1b — Large-model clib (`clibl.lib` + `cstartlm.obj`) ✅ (2026-08-21)
build-lib.sh understøttede kun s/m/c. Large = compact's far-data-maskineri
(`__BIG_DATA__` far-heap, `option farheap`) + medium's far-code `-zm`-segmentsplit.
- [x] `MODEL=l` tilføjet til `build-lib.sh` (`-ml -zm`, `crt0lm.asm`, `clibl.lib`,
      `cstartlm.obj`). Byggede rent; staged i `lib286/cpm86/`.
- [x] `crt0lm.asm` = crt0mm's far-code-startup (`_big_code_`, far-kald/`retf`).
      Far-data ligger i clib-modulerne, ikke crt0 — MEN argv krævede rettelse:
      i far-data-model er `char **argv` en far pointer (offset i BX, segment i CX)
      og hvert `argv[i]` en **4-byte far `char *`**. crt0mm's near 2-byte-argvtab
      gav tom `argv[0]`; crt0lm bygger nu far-pointer-slots med runtime-DS-segment.
- [x] Verificeret på emu2: `printf` (stdio/`__CommonInit`), `malloc/free`
      (far-heap), fuld argv (`CLIBHELL FOO BAR` → argc=3, argv[0..2]=ZIP/FOO/BAR).
- [~] `run-all-models.sh` udvidet med `l`; kører (validerer s/m/c/l samlet).
- Note: samme near-argvtab-fejl er **latent i `crt0cm` (compact)** — argv[0] blev
  aldrig testet der; afklares af den udvidede harness.

### M2 — clib-rutiner zip refererer (delmængde af COMPLETE_CLIB_TODO bunke A)
Tilføj til `build-lib.sh` modullisten:
- [ ] `strstr`
- [ ] `strncat`
- [ ] `rand`, `srand`
- [ ] (evt. `asctime` — verificér om zip's tid-output kræver den)

### M3 — OS-specifikke stubs (zip's brug; COMPLETE_CLIB_TODO bunke B)
Leveres i zip's `cpm86/cpm86.c`:
- [ ] `lstat`/`stat`/`stat_bandaid` — **funktionelt nødvendig**: zip stat'er input
      (størrelse, mtime, attributter) → FCB/BDOS-søgning (BDOS 17/18)
- [ ] `getch` — konsol (adgangskode-prompt via ttyio) → BDOS 6
- [ ] `getpid` — konstant (bruges kun til temp-navne/seed)
- [ ] `intdosx` — hvis kernen kalder den direkte; ellers erstat via osdep.h
- [ ] `system`, `spawnlp` — dokumenterede fejl-stubs (ingen CP/M-mening)

### M4 — OS-lag `cpm86/cpm86.c` + `cpm86/osdep.h` + `cpm86/zipup.h`
Mirror unzip's 628-linjers `cpm86.c`. Linker-krævede symboler:
- [ ] `wild()` — globbing/directory-scan (BDOS søg-først/næste 17/18)
- [ ] `procname()` · `filetime()` · `stamp()` · `ex2in()` / `in2ex()`
- [ ] `deletedir()` (CP/M har ingen kataloger → stub) · `set_extra_field()` (minimér)
- [ ] `GetFileMode()` · `version_local()` · `check_for_windows()` (stub)
- [ ] `zcalloc()` / `zcfree()` — **far**-allokering af deflate-tabeller (se M5)
- [ ] `cpm86/zipup.h` — `ftype`/`zstdin`/`fbad` + rå læse-makroer
- [ ] `cpm86/osdep.h` — target-defines (DRI-tilpasset `msdos/osdep.h`)

### M5 — Far-allokering af deflate-tabeller + DGROUP-diæt
- [ ] `DYN_ALLOC`: `window`/`prev`/`head` bliver `far *` via `zcalloc` (far heap).
- [ ] `-zc` holder CONST-strenge ude af DGROUP; verificér DGROUP < 64 KB i map'et.
- [ ] Vinduesstørrelse: `NO_DEFLATE64`, `WSIZE=0x8000` (32 KB) som unzip.

### M6 — `build-zip-cpm86.sh`
- [ ] Nyt script (spejl af `build-cpm86.sh`): `-mcmodel=l -zc`, defines, OS-lag +
      `match.c`, link `format cpm86 … cstartlm.obj … clibl.lib`, emit `ZIP.CMD`.

### M7 — Test
- [ ] emu2 (kan nu fixups): `zip A.ZIP FILE.TXT` → verificér med host `unzip -t`
- [ ] MAME rc759: endelig HW-kontrol
- [ ] Round-trip: zip pakker → UNZIP.CMD udpakker → byte-identisk med original

## Åbne risici
- **Large-model clib er uprøvet på CP/M-86** — M1b er den reelle nye risiko;
  ingen `clibl`/`cstartlm` findes endnu. Alt andet er velforstået.
- Large model + zip's dybe deflate-kaldekæde vs. stak (unzip krævede 2 KB stak).
- CP/M-86-filsystem har ingen kataloger/symlinks/rige tidsstempler → `wild`,
  `stamp`, `filetime` skal degradere pænt.
