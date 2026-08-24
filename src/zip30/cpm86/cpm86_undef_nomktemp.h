/* Force-included AFTER msdos/osdep.h has run via tailor.h.
 * msdos/osdep.h line 165 defines NO_MKTEMP which causes fileio.c's
 * tempname() to use a buffer-overflowing sprintf path.  Undefine it
 * here so tempname() falls through to mktemp() -- which cpm86.c
 * implements as a thin wrapper around Watcom's tmpnam(). */
#ifdef NO_MKTEMP
# undef NO_MKTEMP
#endif
