# CP/M-86 ZIP deflate divergence

**Date:** 2026-08-25  
**Status:** Open; cause not yet proven

## Question

Why does the large-model CP/M-86 build of Info-ZIP `ZIP.CMD` fail under real
Concurrent CP/M-86 3.1 in RC759 MAME, while the same program succeeds under
emu2?

CCP/M/MAME is the authoritative runtime oracle. emu2 is a differential
debugging oracle. Host `unzip` and Python `zipfile` remain independent archive
oracles.

## Frozen repro

Input: `scratch/rc759-unzip-demo/POEM.TXT` (3960 bytes)  
Command: `ZIP POEM2.ZIP POEM.TXT`  
Binary: large-model `infozip-cpm86-builds` build  
Disk: fresh `B_zip.mfi`, rebuilt for each MAME run

The failure is after compression has completed:

```text
s=350, actual=349
zip error: Internal logic error (incorrect compressed size)
```

## Experiments and results

### Binary output mode

`FOPW` and `FOPW_TMP` were forced to `"wb"`. This did not make the CCP/M
failure disappear. Therefore text-mode LF-to-CRLF expansion is not a
sufficient explanation.

### Input-read trace

Both runtimes reported the same first read and EOF:

```text
zread: 3960 bytes
zread: 0 bytes
```

Sampled input bytes at offsets 0, 1000, 2000, 3000, and 3959 matched. This
does not prove every internal state byte is identical, but it rules out the
simple hypothesis that CCP/M reads a different file length or different
obvious input contents.

### Output trace

With deflate enabled, emu2 produced a 333-byte archive and completed. CCP/M
reached the compressed-size check with a different deflate/output result and
failed with the mismatch above.

### STORE-only control

The same binary was rebuilt with `CPM86_STORE_ONLY`:

- emu2: archive completed (`stored 0%`)
- CCP/M/MAME: archive completed (`stored 0%`)

This is the strongest current isolation result. The common input and ordinary
FILE*/BDOS output path work in STORE mode. The unresolved divergence is
confined to the deflate/zlib path or to large-model runtime state exercised
only by deflate.

## Current conclusion

This is a real CCP/M-vs-emu2 behavioral divergence, but the root cause is
**not yet identified**. The evidence does not justify claiming a Watcom
`fwrite`, CP/M binary/text mode, or generic BDOS write bug. It also does not
yet distinguish among:

- a zlib/deflate algorithm or buffer-state difference,
- a large-model far-pointer or memory-layout problem exercised by deflate,
- compiler-generated code that is incorrect only on the CCP/M execution path,
- or another runtime interaction inside the deflate implementation.

No fix should be selected until zlib state or deflate output is compared
directly. The existing binary-mode shell test is only a source-definition
guard; it is not proof that the runtime problem is fixed.

## Next evidence

The next useful measurements are zlib `total_out`, `avail_in`, `avail_out`,
and checksums or byte samples of each deflate output buffer, captured under
both runtimes. A minimal STORE-vs-deflate matrix should remain available as a
control while those measurements are added.
