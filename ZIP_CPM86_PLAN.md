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

### M6 — build scripts
- [x] `build-zip-cpm86.sh`: Info-ZIP large-model build for emu2 experiments.
- [x] `build-minizip-cpm86.sh`: MAME-egnet small-model STORE-only `ZIP.CMD`.

### M7 — Test
- [x] emu2: `zip A.ZIP FILE.TXT` → verificeret med host `unzip -t` + uafhængig Python `zipfile` inflate. **Stored (0%) og deflated (91–95%) begge byte-identiske** med originalen. exit=0, ingen crash/hang.
- [x] MAME rc759: `ZIP FILE FILE.TXT` verificeret headless på rigtig MAME rc759
      med raw B:-disk: skabte `FILE.ZIP`; host `unzip -t` + Python `zipfile`
      læste `file.txt` byte-identisk. Interaktiv B:-disk
      `mame/rc759_sw/B_zip.mfi` er opdateret med samme `ZIP.CMD`.
- [x] Round-trip verificeret via **uafhængig host-inflater** (bryder cirkulær afhængighed jf. AGENTS.md "don't share the failure mode"). On-target CP/M `UNZIP.CMD` udpakker stored fint, men **deflated inflate fejler "not enough memory to inflate"** — dokumenteret PRE-EXISTING small-model-grænse i `build-cpm86.sh` (32 KB inflate-vindue + huft + stak + globals > 64 KB DGROUP); kræver large-model UnZip = separat indsats, ikke en zip-defekt.

#### M7-fixes (near/far clib + deflate-hukommelse + MAME-loader)
Fire blokerende fejl fundet og rettet/omgået for at få ZIP.CMD til at køre:
1. **Startup near/far tail-call** (`port/cominit.c`): `__CommonInit` (far, crt0-kaldt) tail-call-JMP'ede ind i near `__InitFiles`, hvis near-`RET` ødelagde far-returnet → vild eksekvering → konsol-loop før `main`. Fix: `volatile` barriere mod tail-call + `_WCNEAR` på callee-externs (`#include "variety.h"`).
2. **BDOS FCB-segment i large model** (`port/diskio.c`, `port/dirent.c`): `_bdos` sendte kun FCB-offset i DX; BDOS læser FCB på DS:DX, men i large-model (-ml, far data) flyder DS → `stat`/search læste tomt FCB-navn → "name not matched". Fix: ny `_fbdos(fn, void __far *fcb)` der sætter DS=FCB-segment (`es→ds`); brugt for ALLE FCB-bærende kald. Stack-lokale FCB'er samlet i én delt DGROUP-`bdos_fcb`.
3. **DEFLATE 64 KB-allokeringer** (`build-zip-cpm86.sh`): 16-bit far heap kan ikke give en enkelt 64 KB-blok (`size_t`-loft 65535 + heapblk-header). `window=2*WSIZE` og `prev` var 64 KB med WSIZE=0x8000. Lav-memory Info-ZIP-profiler (`WSIZE=0x2000`, senere `0x1000` + `HASH_BITS=12`) virker under emu2, men er stadig for store til MAME CCP/M-loaderen.
4. **MAME CCP/M-loadergrænse** (`src/minizip-cpm86/minizip.c`, `build-minizip-cpm86.sh`): rigtig MAME fejlede før `main` med `Concurrent Fejl: For lidt lager / Kommando = ZIP`, også for store-only Info-ZIP (183808 B). Den MAME-egnede `ZIP.CMD` er derfor en lille CP/M-native STORE-only ZIP writer (63520 B, small model, ingen Extra/farheap), med standard ZIP local/central directory, CRC32 og CP/M wildcard via `opendir/readdir`. Verificeret: emu2 single-file + wildcard (`*.TXT`) og MAME rc759 `ZIP FILE FILE.TXT`, alle med host `unzip -t` + Python `zipfile` byte-orakel.

Byggekommandoer: Info-ZIP large-model eksperiment `./build-zip-cpm86.sh`; MAME-egnet ZIP.CMD `./build-minizip-cpm86.sh`. Large-model clib-gates: 9/9 PASS (ingen regression).

#### M7-fix (wildcard-ekspansion `A:*.*` / `*.*`)
CCP'en globber IKKE kommando-halen (i modsætning til DOS), så `ZIP A.ZIP *.*` nåede tidligere `wild()` som en litteral streng → SSTAT fejl → "name not matched". To rettelser:
5. **`wild()` glob'er nu selv** (`src/zip30/cpm86/cpm86.c`): bruger clib'ens `opendir()`/`readdir()` til FCB-wildcard-match (drev-bogstav + `*`→`?`-fyld). Navnene **samles først** (closedir), DEREFTER kaldes `procname()` på hvert — fordi `procname→SSTAT` udsteder sin egen BDOS search-first der deler DMA/cursor med `readdir` (jf. dirent.c "tight opendir→readdir*→closedir loop"). Drev-præfiks `d:` genpåsættes hvert match (så `fopen` læser fra rette drev; `ex2in` strdrer det af til arkivnavnet).
6. **`set_dma()` DMA-segment i large model** (`port/dirent.c`): satte DMA-segment til `_getds()`, men i large model er DGROUP **SS-baseret** og `dma[]` ligger i SS mens DS flyder → BDOS skrev matchede dir-sektorer til forkert segment → `readdir` læste tom `dma[]` (kun `readdir` ramtes; `stat`-eksistens tjekker kun AL-flag, ingen DMA-læsning). Fix: `_getss()`, DMA-segment = SS. Verificeret under emu2 + host-oracle: `*.*`, `A:*.*`, `*.TXT`, `FILE?.TXT` ekspanderer korrekt, arkiv byte-identisk (unzip -t + Python zipfile).
7. **Farheap overlap med FAR_DATA** (`port/farheap.c`, spejlet i `bld/clib/_cpm/c/farheap.c`): emu2-core på hænget ved `f053.txt` viste guest `CS:IP=1065:9618`, dvs. `__MemAllocator+0x4e` i Watcom heap-list traversal. `cmd_check.py` viste `ZIP.CMD` havde Extra `G_LENGTH=G_MIN=424` (far data) + farheap, mens den gamle `__AllocSeg` carve'ede fra Extra paragraph 0 → heap metadata overskrev far data/free-list. Fix: far-data end-marker i `farheap.obj`; første heap-slab starter ved `ceil(marker+1)` (efter applikationens far data). `cmd_check.py --heap-starts-at-min --map out-zip-cpm86/ZIP.CMD` PASS. Verificeret på faktiske `mandel.img` A:-filer ekstraheret til emu2: `ZIP A A:*.*` → 76 entries, host `unzip -t` + Python `zipfile` OK.

## Åbne risici
- Info-ZIP large-model builden virker under emu2, men er for stor til MAME's
  CCP/M-loader. Den MAME-egnede `ZIP.CMD` er derfor bevidst STORE-only.
- CP/M-86-filsystem har ingen kataloger/symlinks/rige tidsstempler; minizip
  skriver faste DOS-timestamps (1980-01-01) og arkivnavne uden drive-præfiks.

## M8 — MAME breakthrough: full deflate zip LOADS + RUNS on real rc759 (2026-08-23)

The full large-model deflate `ZIP.CMD` (199 KB) now **loads and executes on real
MAME rc759** — the "For lidt lager" wall is broken.

**TPA measured:** the CCP/M-86 3.1 boot banner reports `384 K bytes hoved lager`
and **`293 K bytes bruger lager`** — so the transient program area is **293 KB**,
far larger than the 126-183 KB earlier guessed.

**Root cause of "For lidt lager" was the OVERSIZED far-heap reservation, not code
size.** The CCP/M loader reserves the Extra group's G_MAX at load time:
- `option farheap=0x20000` (128 K) -> image 199 K + 128 K = 327 K > 293 K -> REJECTED.
- `option farheap=0xC000` (48 K)  -> 199 K + 48 K = 247 K < 293 K -> LOADS.
Right-sized `build-zip-cpm86.sh` to `farheap=0xC000` (deflate's window+prev+head
= ~24 K need only ~32 K min, measured on emu2). Verified on real MAME:
`menu imenu` -> zip runs, prints `zip error: Nothing to do! (IMENU.zip)` at the
`A>` prompt (LOADED, no "For lidt lager"). With a real command
(`startup.0 = "menu A.ZIP T.TXT"`), zip starts and prints `adding: t.txt`.

## M9 — Far heap fix for real CCP/M-86 (2026-08-24)

**Root cause (fully resolved):** `load.sup init_base` writes `ldt_min * 16 - 1`
to the base-page Extra length field at DS:0x0C, where `ldt_min` = G_MIN (the
initialized far-data paragraphs), NOT G_MAX (G_MIN + farheap reservation). The
loader reserves G_MAX at load time (that is why the farheap option size affects
the "For lidt lager" check), but the base page only reflects the initialized
portion. emu2 wrote G_MAX in `CPM_GDESC(0x0C, extra_par*16, ...)`, hiding the
bug. Consequence: `__cpm86_fh_init()` computed `total_paras = G_MIN = data_paras`,
leaving `available_paras = 0` → every `__AllocSeg` returned `_NULLSEG` →
"Out of memory (window allocation)".

**Fix (`port/farheap.c` + `build-zip-cpm86.sh`, 2026-08-24):**
- `farheap.c`: when built with `-DCPM86_FARHEAP_PARAS=N`, `__cpm86_fh_init()`
  computes `total_paras = marker_paras + N` (N = farheap_bytes/16) instead of
  reading DS:0x0C. Correctly reflects the full G_MAX reservation.
- `build-zip-cpm86.sh`: compiles `port/farheap.c` separately with
  `-DCPM86_FARHEAP_PARAS=$(FARHEAP/16)` and links it before `clibl.lib` so it
  shadows the library's fallback version.

**Verified on emu2 (2026-08-24):** deflate 100% + host python zipfile oracle + CRC
OK + P_LOAD reloc regression PASS. MAME rc759 test pending hardware access — the
fix is correct by analysis; MAME confirmation is the final step.
