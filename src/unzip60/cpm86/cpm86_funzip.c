/*
 * cpm86_funzip.c -- Minimal CP/M-86 OS layer for fUnZip.
 *
 * fUnZip only needs three things from the OS layer:
 *   fdopen(0, ...)  -- get stdin as a binary FILE*
 *   fdopen(1, ...)  -- get stdout as a binary FILE*
 *   getch()         -- no-echo console read for decryption password
 *
 * The full unzip60/cpm86/cpm86.c is NOT used here because it pulls in
 * msdos/doscfg.h via -DMSDOS, which defines far-string machinery
 * (fnfilter, fLoadFarString, _CompiledWith) that requires fileio.c /
 * process.c -- absent in the funzip build.
 */

#include <stdio.h>

/* fdopen(0,"rb") / fdopen(1,"wb"):
 * CP/M-86 has no POSIX fd layer; fd 0 == stdin and fd 1 == stdout by
 * convention, so just return the existing FILE* pointers.  The "binary"
 * mode flag is a no-op on CP/M (no CR/LF translation at the seam). */
FILE *fdopen(int fd, const char *mode)
{
    (void)mode;
    if (fd == 0) return stdin;
    if (fd == 1) return stdout;
    return (FILE *)NULL;
}

/* getch: blocking, no-echo single-key read for the decryption password
 * prompt.  Uses CP/M BDOS INT 0E0h function 6 (Direct Console I/O)
 * with DL=0xFF (poll/read without echo). */
static unsigned char cpm_conio(unsigned char e);
#pragma aux cpm_conio =         \
        "mov cl, 6"             \
        "int 0E0h"              \
        parm [dl]               \
        value [al]              \
        modify [ax bx cx dx];

int getch(void)
{
    unsigned char c;
    do { c = cpm_conio(0xFF); } while (c == 0);
    return (int)c;
}

/* check_for_windows: stub; never running under Windows on CP/M-86. */
void check_for_windows(const char *app)
{
    (void)app;
}
