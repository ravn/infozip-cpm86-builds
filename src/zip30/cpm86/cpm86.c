/*
  cpm86/cpm86.c -- CP/M-86 OS layer for Info-ZIP Zip 3.0.

  This file REPLACES msdos/msdos.c in the CP/M-86 build (Open Watcom
  owcc -bcpm86, LARGE model). It is a NEW file: it does not touch any pristine
  Info-ZIP source, exactly like the UnZip cpm86 port. The generic Zip core is
  compiled unmodified; only this OS layer differs.

  The build still defines DOS (CP/M-86 is a DOS-family Watcom target), so
  tailor.h pulls in msdos/osdep.h -- which compiles cleanly under owcc and
  supplies the type/macro surface (struct zlist, iztimes, SSTAT=stat_bandaid,
  MATCH=dosmatch, ZE_* codes, ...). We implement the OS entry points the core
  needs with portable C + a few CP/M BDOS (INT 0E0h) calls.

  CP/M-86 realities that shape this layer:
    * No directory enumeration (opendir/readdir) and the CCP does no globbing,
      and BDOS Search First/Next match only '?' in an FCB (never '*'). So
      wild() cannot expand a pattern against the disk -- every argument is
      treated as a literal name (the documented fallback, as in UnZip's cpm86).
    * No sub-directories -> deletedir() is a no-op; procname() never recurses.
    * No reliable file timestamps in the base FCB -> stamp() is a no-op and
      filetime() returns a fixed/degraded time but a CORRECT size (Zip needs
      the size). File size comes from the clib stat() (FILE* layer works).
    * Far heap for the deflate window/prev/head via _fcalloc()/_ffree().
*/

#include "../zip.h"
#include <malloc.h>             /* _fcalloc / _ffree (far heap) */
#include <dos.h>                /* union REGS / struct SREGS / MK_FP */
#include <time.h>

/* Per-port name-conversion constants (each Info-ZIP OS file defines its own,
   as in msdos/msdos.c). CP/M-86 uses '/' internally, no name padding. */
#define PATH_END '/'
#define PAD      0

/* ------------------------------------------------------------------ */
/* Far-heap allocator for the deflate window/prev/head (DYN_ALLOC).   */
/* -ml defines __BIG_DATA__, so the clib far heap (_fcalloc/_ffree,    */
/* reserved by the linker's OPTION FARHEAP) backs these.              */
/* NOTE (M5): a single 2*WSIZE==64K request wraps 16-bit size_t; keep  */
/* WSIZE<=0x4000 (or split) so items*size stays < 64K. Revisit in M5.  */
zvoid far *zcalloc(unsigned int items, unsigned int size)
{
    return (zvoid far *)_fcalloc(items, size);
}

zvoid zcfree(zvoid far *ptr)
{
    _ffree((void __far *)ptr);
}

/* ------------------------------------------------------------------ */
/* stat_bandaid: Zip's stat() shim (SSTAT in msdos/osdep.h). The clib  */
/* ships a working stat(); we just forward to it.                     */
int stat_bandaid(const char *path, struct stat *buf)
{
    return stat((char *)path, buf);
}

/* ------------------------------------------------------------------ */
/* filetime: attributes + size + mtime of a file (see msdos.c).       */
ulg filetime(char *f, ulg *a, zoff_t *n, iztimes *t)
{
    struct stat s;

    if (SSTAT(f, &s) != 0)
        return 0;                       /* nonexistent -> 0 */

    if (a != NULL)
        *a = ((ulg)s.st_mode << 16);    /* high word = unix mode; no DOS bits */
    if (n != NULL)
        *n = ((s.st_mode & S_IFMT) == S_IFREG) ? (zoff_t)s.st_size : (zoff_t)-1L;
    if (t != NULL) {
        t->atime = s.st_atime;
        t->mtime = s.st_mtime;
        t->ctime = s.st_ctime;
    }
    return unix2dostime((time_t *)&s.st_mtime);
}

/* ------------------------------------------------------------------ */
/* Name conversion: external <-> internal (zip) form.                 */
char *ex2in(char *x, int isdir, int *pdosflag)
{
    char *n, *t;

    /* Strip a "d:" drive spec */
    t = (*x && *(x + 1) == ':') ? x + 2 : x;
    /* Strip leading path separators (absolute -> relative) */
    while (*t == '/' || *t == '\\')
        t++;
    while (*t == '.' && (t[1] == '/' || t[1] == '\\'))
        t += 2;

    if ((n = malloc(strlen(t) + 1)) == NULL)
        return NULL;
    strcpy(n, t);

    /* Normalize backslashes to '/' */
    { char *p; for (p = n; *p; p++) if (*p == '\\') *p = '/'; }

    if (!pathput)
        { char *b = last(n, PATH_END); if (b != n) { char *p = n; while ((*p++ = *b++) != 0) ; } }

    if (isdir == 42) return n;          /* size-only probe (as in msdos.c) */

    /* CP/M names are case-insensitive -> store lower-case. Done inline (ASCII)
       to avoid the clib's underscore-named _strlwr symbol. */
    { char *p; for (p = n; *p; p++) if (*p >= 'A' && *p <= 'Z') *p += 32; }
    if (pdosflag)
        *pdosflag = 1;
    return n;
}

char *in2ex(char *n)
{
    char *x;

    if ((x = malloc(strlen(n) + 1 + PAD)) == NULL)
        return NULL;
    strcpy(x, n);
    return x;
}

/* ------------------------------------------------------------------ */
/* procname: process one command-line name (add file, or match names  */
/* already in the archive). No wildcard expansion / recursion on CP/M. */
int procname(char *n, int caseflag)
{
    struct stat s;

    if (n == NULL)
        return ZE_OK;
    if (strcmp(n, "-") == 0)            /* stdin */
        return newname(n, 0, caseflag);
    if (*n == '\0')
        return ZE_MISS;

    if (SSTAT(n, &s)) {
        /* Not an existing file: treat as a match expression against the names
           already in the archive (delete/freshen). */
        struct zlist far *z;
        char *p;
        int m = 1;

        p = ex2in(n, 0, (int *)NULL);
        if (p == NULL)
            return ZE_MEM;
        for (z = zfiles; z != NULL; z = z->nxt) {
            if (MATCH(p, z->iname, caseflag)) {
                z->mark = pcount ? filter(z->zname, caseflag) : 1;
                if (z->mark) z->dosflag = 1;
                m = 0;
            }
        }
        free((zvoid *)p);
        return m ? ZE_MISS : ZE_OK;
    }

    /* Live, existing file (CP/M-86 has no directories). */
    return newname(n, 0, caseflag);
}

/* wild: no OS-level globbing on CP/M-86 -> literal name (UnZip precedent). */
int wild(char *w)
{
    return procname(w, 0);
}

/* ------------------------------------------------------------------ */
/* Timestamp / directory / extra-field: degrade gracefully.           */
void stamp(char *f, ulg d)
{
    (void)f; (void)d;                   /* CP/M-86 cannot set file times */
}

int deletedir(char *d)
{
    (void)d;                            /* no sub-directories on CP/M-86 */
    return 0;
}

int set_extra_field(struct zlist far *z, iztimes *z_utim)
{
    (void)z; (void)z_utim;              /* no UT timestamp extra field */
    return ZE_OK;
}

/* ------------------------------------------------------------------ */
/* Windows check: never running under Windows on CP/M-86.             */
void check_for_windows(char *app)
{
    (void)app;
}

/* version_local: the "Compiled with ..." banner line.                */
void version_local(void)
{
    char buf[80];

#if defined(__WATCOMC__)
    sprintf(buf, "Open Watcom C %d.%d", __WATCOMC__ / 100, (__WATCOMC__ % 100) / 10);
#else
    strcpy(buf, "an unknown compiler");
#endif
    printf("Compiled with %s for CP/M-86 (Intel 8086/80186, large model).\n\n",
           buf);
}

/* ------------------------------------------------------------------ */
/* CP/M BDOS console helper (INT 0E0h, function 6 direct console I/O). */
static unsigned char cpm_conio(unsigned char e);
#pragma aux cpm_conio =         \
        "mov cl, 6"             \
        "int 0E0h"              \
        parm [dl]               \
        value [al]              \
        modify [ax bx cx dx];

/* getch: blocking, no-echo single-key read (used by ttyio password prompt). */
int getch(void)
{
    unsigned char c;
    do { c = cpm_conio(0xFF); } while (c == 0);
    return (int)c;
}

/* ------------------------------------------------------------------ */
/* init_upper()'s MSDOS16 path calls intdosx() for INT21/AX=3800h (get  */
/* country info) to obtain a case-mapping function for chars >=128. CP/M */
/* has no such call; supply an identity mapper so extended chars pass    */
/* through unchanged. casemap is the FIRST field of the country buffer   */
/* at seg->ds:in->x.dx.                                                   */
static int __far cpm_identmap(int c) { return c; }

int intdosx(const union REGS *in, union REGS *out, struct SREGS *seg)
{
    void (__far * __far *casemap)(void);
    casemap = (void (__far * __far *)(void))MK_FP(seg->ds, in->x.dx);
    *casemap = (void (__far *)(void))cpm_identmap;
    if (out != in) *out = *in;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Process/OS stubs with no CP/M-86 meaning.                          */
int getpid(void)          { return 1; }                 /* crypt seed only */
int system(const char *s) { (void)s; return -1; }       /* no shell */

/* spawnlp: used only by Zip's "-T" self-test (spawns UnZip). Not available
   on CP/M-86; report failure so the test path degrades to "cannot verify". */
int spawnlp(int mode, const char *path, const char *a0, ...)
{
    (void)mode; (void)path; (void)a0;
    return -1;
}

/* fdopen: the POSIX fd layer is a no-op on classic CP/M (FILE* is the real
   path). Zip only uses this for the mkstemp()+fdopen() temp-archive pattern;
   returning NULL forces callers into their error path. Resolving the temp
   archive without an fd layer is tracked for M7. */
FILE *fdopen(int fd, const char *mode)
{
    (void)fd; (void)mode;
    return (FILE *)NULL;
}
