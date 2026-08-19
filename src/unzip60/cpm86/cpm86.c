/*
  Copyright (c) 1990-2007 Info-ZIP.  All rights reserved.

  See the accompanying file LICENSE, version 2000-Apr-09 or later
  (the contents of which are also included in unzip.h) for terms of use.
  If, for some reason, all these files are missing, the Info-ZIP license
  also may be found at:  ftp://ftp.info-zip.org/pub/infozip/license.html
*/
/*---------------------------------------------------------------------------

  cpm86.c

  CP/M-86-specific routines for use with Info-ZIP's UnZip 6.0 and later.

  Built under the existing FLEXOS port profile (compile with -DFLEXOS): CP/M-86
  and FlexOS are both Digital Research real-mode 8086 systems, so UnZip's
  generic FLEXOS branches (forward-slash DIR_END, __16BIT__/MED_MEM config in
  flexos/flxcfg.h, dateformat()/USE_EF_UT_TIME hooks) already match CP/M-86.
  This file therefore replaces flexos/flexos.c -- which needs FlexOS-only
  <flexif.h> syscalls (s_open/s_get/s_set, DISKFILE) that CP/M-86 lacks -- with
  an implementation that uses only ANSI C + the CP/M-86 C runtime.  NO generic
  UnZip source is modified; the only "patch" is selecting this OS file instead
  of flexos.c in the build recipe.

  Differences from flexos.c, driven by the CP/M-86 file system (flat, single
  directory per user area, 8.3 uppercase names, no sub-directories, no
  timestamps on plain BDOS):

    do_wild()       - no opendir()/readdir() on CP/M-86: return the literal
                      spec once (single-file behaviour; shell has no globbing).
    mapname()       - reused verbatim from the DOS/FlexOS logic (pure string
                      work + map2fat + checkdir).
    map2fat()       - reused verbatim (pure 8.3 truncation).
    checkdir()      - flat file system: APPEND_DIR discards the directory
                      component (files extract flattened to their basename);
                      no mkdir()/stat().  Buffer bookkeeping preserved.
    mapattr()       - archive bit only.
    close_outfile() - just fclose(); no time-stamp / attribute restore
                      (plain CP/M-86 BDOS exposes neither).
    dateformat(),
    version()       - trivial.

  Contains:  do_wild()
             mapattr()
             mapname()
             map2fat()
             checkdir()
             close_outfile()
             dateformat()
             version()
             _wildarg()

  ---------------------------------------------------------------------------*/


#define UNZIP_INTERNAL
#include "unzip.h"

/* forward decl (compiler dislikes a static forward decl of this) */
extern void map2fat OF((char *pathcomp, char *last_dot));

static int created_dir;        /* used by mapname(), checkdir() */
static int renamed_fullpath;   /* ditto */

/*****************************/
/*  Strings used in cpm86.c  */
/*****************************/

#ifndef SFX
  static ZCONST char Far CantAllocateWildcard[] =
    "warning:  cannot allocate wildcard buffers\n";
#endif
static ZCONST char Far WarnDirTraversSkip[] =
  "warning:  skipped \"../\" path component(s) in %s\n";
static ZCONST char Far Creating[] = "   creating: %s\n";
static ZCONST char Far ConversionFailed[] =
  "mapname:  conversion of %s failed\n";
static ZCONST char Far PathTooLongTrunc[] =
  "checkdir warning:  path too long; truncating\n                   %s\n\
                -> %s\n";


#ifndef SFX

/************************/
/*  Function do_wild()  */
/************************/

char *do_wild(__G__ wildspec)
    __GDEF
    ZCONST char *wildspec;   /* only used first time on a given dir */
{
    static ZCONST char *lastspec;
    static char matchname[FILNAMSIZ];
    static int notfirstcall = FALSE;

    /* CP/M-86 has no directory enumeration (opendir/readdir) and the CCP does
     * no globbing, so a wildcard spec cannot be expanded against the disk.
     * We therefore hand back the spec verbatim on the first call for a given
     * spec and report "no more matches" afterwards -- i.e. treat every
     * argument as a single literal name.  This is the documented fallback
     * behaviour for ports without a readable directory. */
    if (!notfirstcall) {              /* first call:  return spec as-is */
        notfirstcall = TRUE;
        lastspec = wildspec;
        strncpy(matchname, wildspec, FILNAMSIZ);
        matchname[FILNAMSIZ-1] = '\0';
        return matchname;
    }

    if (wildspec != lastspec) {       /* new argument:  restart */
        notfirstcall = TRUE;
        lastspec = wildspec;
        strncpy(matchname, wildspec, FILNAMSIZ);
        matchname[FILNAMSIZ-1] = '\0';
        return matchname;
    }

    notfirstcall = FALSE;             /* reset for the next argument */
    return (char *)NULL;

} /* end function do_wild() */

#endif /* !SFX */




/**********************/
/* Function mapattr() */
/**********************/

int mapattr(__G)
    __GDEF
{
    /* set archive bit (file is not backed up): */
    G.pInfo->file_attr = (unsigned)(G.crec.external_file_attributes & 7) | 32;
    return 0;
}




/**********************/
/* Function mapname() */
/**********************/

int mapname(__G__ renamed)
    __GDEF
    int renamed;
/*
 * returns:
 *  MPN_OK          - no problem detected
 *  MPN_INF_TRUNC   - caution (truncated filename)
 *  MPN_INF_SKIP    - info "skip entry" (dir doesn't exist)
 *  MPN_ERR_SKIP    - error -> skip entry
 *  MPN_ERR_TOOLONG - error -> path is too long
 *  MPN_NOMEM       - error (memory allocation failed) -> skip entry
 *  [also MPN_VOL_LABEL, MPN_CREATED_DIR]
 */
{
    char pathcomp[FILNAMSIZ];      /* path-component buffer */
    char *pp, *cp=(char *)NULL;    /* character pointers */
    char *lastsemi=(char *)NULL;   /* pointer to last semi-colon in pathcomp */
    char *last_dot=(char *)NULL;   /* last dot not converted to underscore */
    int dotname = FALSE;           /* path component begins with dot? */
    int killed_ddot = FALSE;       /* is set when skipping "../" pathcomp */
    int error = MPN_OK;
    register unsigned workch;      /* hold the character being tested */


    if (G.pInfo->vollabel)
        return MPN_VOL_LABEL;   /* Cannot set disk volume labels on CP/M-86 */

/*---------------------------------------------------------------------------
    Initialize various pointers and counters and stuff.
  ---------------------------------------------------------------------------*/

    /* can create path as long as not just freshening, or if user told us */
    G.create_dirs = (!uO.fflag || renamed);

    created_dir = FALSE;        /* not yet */
    renamed_fullpath = FALSE;

    if (renamed) {
        cp = G.filename - 1;    /* point to beginning of renamed name... */
        while (*++cp)
            if (*cp == '\\')    /* convert backslashes to forward */
                *cp = '/';
        cp = G.filename;
        /* use temporary rootpath if user gave full pathname */
        if (G.filename[0] == '/') {
            renamed_fullpath = TRUE;
            pathcomp[0] = '/';  /* copy the '/' and terminate */
            pathcomp[1] = '\0';
            ++cp;
        } else if (isalpha((uch)G.filename[0]) && G.filename[1] == ':') {
            renamed_fullpath = TRUE;
            pp = pathcomp;
            *pp++ = *cp++;      /* copy the "d:" (+ '/', possibly) */
            *pp++ = *cp++;
            if (*cp == '/')
                *pp++ = *cp++;  /* otherwise add "./"? */
            *pp = '\0';
        }
    }

    /* pathcomp is ignored unless renamed_fullpath is TRUE: */
    if ((error = checkdir(__G__ pathcomp, INIT)) != 0) /* initialize path buf */
        return error;           /* ...unless no mem or vol label on hard disk */

    *pathcomp = '\0';           /* initialize translation buffer */
    pp = pathcomp;              /* point to translation buffer */
    if (!renamed) {             /* cp already set if renamed */
        if (uO.jflag)           /* junking directories */
            cp = (char *)strrchr(G.filename, '/');
        if (cp == (char *)NULL) /* no '/' or not junking dirs */
            cp = G.filename;    /* point to internal zipfile-member pathname */
        else
            ++cp;               /* point to start of last component of path */
    }

/*---------------------------------------------------------------------------
    Begin main loop through characters in filename.
  ---------------------------------------------------------------------------*/

    while ((workch = (uch)*cp++) != 0) {

        switch (workch) {
            case '/':             /* can assume -j flag not given */
                *pp = '\0';
                map2fat(pathcomp, last_dot);   /* 8.3 truncation (in place) */
                last_dot = (char *)NULL;
                if (strcmp(pathcomp, ".") == 0) {
                    /* don't bother appending "./" to the path */
                    *pathcomp = '\0';
                } else if (!uO.ddotflag && strcmp(pathcomp, "..") == 0) {
                    /* "../" dir traversal detected, skip over it */
                    *pathcomp = '\0';
                    killed_ddot = TRUE;     /* set "show message" flag */
                }
                /* when path component is not empty, append it now */
                if (*pathcomp != '\0' &&
                    ((error = checkdir(__G__ pathcomp, APPEND_DIR))
                     & MPN_MASK) > MPN_INF_TRUNC)
                    return error;
                pp = pathcomp;    /* reset conversion buffer for next piece */
                lastsemi = (char *)NULL; /* leave direct. semi-colons alone */
                break;

            case '.':
                if (pp == pathcomp) {     /* nothing appended yet... */
                    if (*cp == '.' && cp[1] == '/') {   /* "../" */
                        *pp++ = '.';      /* add first dot, unchanged... */
                        ++cp;             /* skip second dot, since it will */
                    } else {              /*  be "added" at end of if-block */
                        *pp++ = '_';      /* FAT doesn't allow null filename */
                        dotname = TRUE;   /*  bodies, so map .exrc -> _.exrc */
                    }                     /*  (extra '_' now, "dot" below) */
                } else if (dotname) {     /* found a second dot, but still */
                    dotname = FALSE;      /*  have extra leading underscore: */
                    *pp = '\0';           /*  remove it by shifting chars */
                    pp = pathcomp + 1;    /*  left one space (e.g., .p1.p2: */
                    while (pp[1]) {       /*  __p1 -> _p1_p2 -> _p1.p2 when */
                        *pp = pp[1];      /*  finished) [opt.:  since first */
                        ++pp;             /*  two chars are same, can start */
                    }                     /*  shifting at second position] */
                }
                last_dot = pp;    /* point at last dot so far... */
                *pp++ = '_';      /* convert dot to underscore for now */
                break;

            /* drive names are not stored in zipfile, so no colons allowed;
             *  no brackets or most other punctuation either */
            case '[':          /* these punctuation characters forbidden */
            case ']':          /*  only on plain FAT file systems */
            case '+':
            case ',':
            case '=':
            case ':':           /* special shell characters of command.com */
            case '\\':          /*  (device and directory limiters, wildcard */
            case '"':           /*  characters, stdin/stdout redirection and */
            case '<':           /*  pipe indicators and the quote sign) are */
            case '>':           /*  never allowed in filenames on (V)FAT */
            case '|':
            case '*':
            case '?':
                *pp++ = '_';
                break;

            case ';':             /* start of VMS version? */
                lastsemi = pp;
                break;

            case ' ':                      /* change spaces to underscores */
                if (uO.sflag)              /*  only if requested */
                    *pp++ = '_';
                else
                    *pp++ = (char)workch;
                break;

            default:
                /* allow ASCII 255 and European characters in filenames: */
                if (isprint(workch) || workch >= 127)
                    *pp++ = (char)workch;

        } /* end switch */
    } /* end while loop */

    /* Show warning when stripping insecure "parent dir" path components */
    if (killed_ddot && QCOND2) {
        Info(slide, 0, ((char *)slide, LoadFarString(WarnDirTraversSkip),
          FnFilter1(G.filename)));
        if (!(error & ~MPN_MASK))
            error = (error & MPN_MASK) | PK_WARN;
    }

/*---------------------------------------------------------------------------
    Report if directory was created (and no file to create:  filename ended
    in '/'), check name to be sure it exists, and combine path and name be-
    fore exiting.
  ---------------------------------------------------------------------------*/

    if (G.filename[strlen(G.filename) - 1] == '/') {
        checkdir(__G__ G.filename, GETPATH);
        if (created_dir) {
            if (QCOND2) {
                Info(slide, 0, ((char *)slide, LoadFarString(Creating),
                  FnFilter1(G.filename)));
            }
            /* set dir time (note trailing '/') */
            return (error & ~MPN_MASK) | MPN_CREATED_DIR;
        }
        /* dir existed already; don't look for data to extract */
        return (error & ~MPN_MASK) | MPN_INF_SKIP;
    }

    *pp = '\0';                   /* done with pathcomp:  terminate it */

    /* if not saving them, remove VMS version numbers (appended ";###") */
    if (!uO.V_flag && lastsemi) {
        pp = lastsemi;            /* semi-colon was omitted:  expect all #'s */
        while (isdigit((uch)(*pp)))
            ++pp;
        if (*pp == '\0')          /* only digits between ';' and end:  nuke */
            *lastsemi = '\0';
    }

    map2fat(pathcomp, last_dot);  /* 8.3 truncation (in place) */

    if (*pathcomp == '\0') {
        Info(slide, 1, ((char *)slide, LoadFarString(ConversionFailed),
          FnFilter1(G.filename)));
        return (error & ~MPN_MASK) | MPN_ERR_SKIP;
    }

    checkdir(__G__ pathcomp, APPEND_NAME);  /* returns 1 if truncated: care? */
    checkdir(__G__ G.filename, GETPATH);

    return error;

} /* end function mapname() */




/**********************/
/* Function map2fat() */
/**********************/

static void map2fat(pathcomp, last_dot)
    char *pathcomp, *last_dot;
{
    char *pEnd = pathcomp + strlen(pathcomp);

/*---------------------------------------------------------------------------
    Case 1:  filename has no dot, so figure out if we should add one.  Note
    that the algorithm does not try to get too fancy:  if there are no dots
    already, the name either gets truncated at 8 characters or the last un-
    derscore is converted to a dot (only if more characters are saved that
    way).  In no case is a dot inserted between existing characters.
  ---------------------------------------------------------------------------*/

    if (last_dot == (char *)NULL) {   /* no dots:  check for underscores... */
        char *plu = strrchr(pathcomp, '_');   /* pointer to last underscore */

        if (plu == (char *)NULL) {  /* no dots, no underscores:  truncate at */
            if (pEnd > pathcomp+8)  /* 8 chars (could insert '.' and keep 11) */
                *(pEnd = pathcomp+8) = '\0';
        } else if (MIN(plu - pathcomp, 8) + MIN(pEnd - plu - 1, 3) > 8) {
            last_dot = plu;       /* be lazy:  drop through to next if-block */
        } else if ((pEnd - pathcomp) > 8)    /* more fits into just basename */
            pathcomp[8] = '\0';    /* than if convert last underscore to dot */
        /* else whole thing fits into 8 chars or less:  no change */
    }

/*---------------------------------------------------------------------------
    Case 2:  filename has dot in it, so truncate first half at 8 chars (shift
    extension if necessary) and second half at three.
  ---------------------------------------------------------------------------*/

    if (last_dot != (char *)NULL) {   /* one dot (or two, in the case of */
        *last_dot = '.';              /*  "..") is OK:  put it back in */

        if ((last_dot - pathcomp) > 8) {
            char *p=last_dot, *q=pathcomp+8;
            int i;

            for (i = 0;  (i < 4) && *p;  ++i)  /* too many chars in basename: */
                *q++ = *p++;                   /*  shift extension left and */
            *q = '\0';                         /*  truncate/terminate it */
        } else if ((pEnd - last_dot) > 4)
            last_dot[4] = '\0';                /* too many chars in extension */
        /* else filename is fine as is:  no change */
    }
} /* end function map2fat() */




/***********************/
/* Function checkdir() */
/***********************/

int checkdir(__G__ pathcomp, flag)
    __GDEF
    char *pathcomp;
    int flag;
/*
 * returns:
 *  MPN_OK          - no problem detected
 *  MPN_INF_TRUNC   - (on APPEND_NAME) truncated filename
 *  MPN_INF_SKIP    - path doesn't exist, not allowed to create
 *  MPN_ERR_SKIP    - path doesn't exist, tried to create and failed; or path
 *                    exists and is not a directory, but is supposed to be
 *  MPN_ERR_TOOLONG - path is too long
 *  MPN_NOMEM       - can't allocate memory for filename buffers
 *
 * CP/M-86 note:  the file system is flat -- no sub-directories.  We therefore
 * DISCARD directory components (APPEND_DIR is a no-op that just resets the
 * buffer) so every member extracts under its bare 8.3 name in the current
 * user area.  Only the final filename (APPEND_NAME) is retained.
 */
{
    static char *buildpath;   /* full path (so far) to extracted file */
    static char *end;         /* pointer to end of buildpath ('\0') */

#   define FN_MASK   7
#   define FUNCTION  (flag & FN_MASK)


/*---------------------------------------------------------------------------
    APPEND_DIR:  on a flat file system there are no directories to create or
    descend, so simply drop the component and keep the buffer empty for the
    filename that follows.
  ---------------------------------------------------------------------------*/

    if (FUNCTION == APPEND_DIR) {
        Trace((stderr, "discarding dir segment [%s]\n", FnFilter1(pathcomp)));
        end = buildpath;      /* forget any accumulated directory prefix */
        *end = '\0';
        return MPN_OK;
    } /* end if (FUNCTION == APPEND_DIR) */

/*---------------------------------------------------------------------------
    GETPATH:  copy full path to the string pointed at by pathcomp, and free
    buildpath.
  ---------------------------------------------------------------------------*/

    if (FUNCTION == GETPATH) {
        strcpy(pathcomp, buildpath);
        Trace((stderr, "getting and freeing path [%s]\n",
          FnFilter1(pathcomp)));
        free(buildpath);
        buildpath = end = (char *)NULL;
        return MPN_OK;
    }

/*---------------------------------------------------------------------------
    APPEND_NAME:  assume the path component is the filename; append it and
    return without checking for existence.
  ---------------------------------------------------------------------------*/

    if (FUNCTION == APPEND_NAME) {
        Trace((stderr, "appending filename [%s]\n", FnFilter1(pathcomp)));
        while ((*end = *pathcomp++) != '\0') {
            ++end;
            if ((end-buildpath) >= FILNAMSIZ) {
                *--end = '\0';
                Info(slide, 1, ((char *)slide, LoadFarString(PathTooLongTrunc),
                  FnFilter1(G.filename), FnFilter2(buildpath)));
                return MPN_INF_TRUNC;   /* filename truncated */
            }
        }
        Trace((stderr, "buildpath now = [%s]\n", FnFilter1(buildpath)));
        return MPN_OK;
    }

/*---------------------------------------------------------------------------
    INIT:  allocate and initialize buffer space for the file currently being
    extracted.
  ---------------------------------------------------------------------------*/

    if (FUNCTION == INIT) {
        Trace((stderr, "initializing buildpath to "));
        if ((buildpath = (char *)malloc(strlen(G.filename)+3)) ==
            (char *)NULL)
            return MPN_NOMEM;
        if (renamed_fullpath) {   /* pathcomp = valid data */
            end = buildpath;
            while ((*end = *pathcomp++) != '\0')
                ++end;
        } else {
            *buildpath = '\0';
            end = buildpath;
        }
        Trace((stderr, "[%s]\n", FnFilter1(buildpath)));
        return MPN_OK;
    }

/*---------------------------------------------------------------------------
    ROOT:  no extract-to directory support on a flat CP/M-86 file system;
    accept and ignore.
  ---------------------------------------------------------------------------*/

#if (!defined(SFX) || defined(SFX_EXDIR))
    if (FUNCTION == ROOT) {
        return MPN_OK;
    }
#endif /* !SFX || SFX_EXDIR */

/*---------------------------------------------------------------------------
    END:  nothing persistent to free (buildpath is freed per file at GETPATH).
  ---------------------------------------------------------------------------*/

    if (FUNCTION == END) {
        return MPN_OK;
    }

    return MPN_INVALID; /* should never reach */

} /* end function checkdir() */




/****************************/
/* Function close_outfile() */
/****************************/

void close_outfile(__G)
    __GDEF
 /*
  * CP/M-86 VERSION
  *
  * Plain CP/M-86 BDOS exposes neither file time stamps nor a permission
  * model beyond the (rarely honoured) read-only / system attribute bits, and
  * the C runtime provides no portable setftime()/chmod() seam here, so this
  * simply closes the file.  Restoring archive time/attributes is optional in
  * UnZip; omitting it is correct behaviour, just less faithful.
  */
{
    fclose(G.outfile);
} /* end function close_outfile() */


#ifndef SFX

/*************************/
/* Function dateformat() */
/*************************/

int dateformat()
{
    return DF_DMY;   /* default for systems without locale info */
}

/************************/
/*  Function version()  */
/************************/

void version(__G)
    __GDEF
{
    int len;

    len = sprintf((char *)slide, LoadFarString(CompiledWith),
            "Open Watcom C/C++",
            "",
            "CP/M-86",
            " (16-bit, small)",

#ifdef __DATE__
      " on ", __DATE__
#else
      "", ""
#endif
    );

    (*G.message)((zvoid *)&G, slide, (ulg)len, 0);
}

#endif /* !SFX */

/************************/
/*  Function _wildarg() */
/************************/

/* This prevents the PORTLIB startup code from performing argument globbing */

_wildarg() {}

/**************************/
/*  Function check_for_windows()  */
/**************************/

/* The DOS Watcom headers pulled in via -I.../hdr/dos/h define MSDOS, so
   unzip.c compiles the "#if defined(MSDOS)" error-path call
   check_for_windows("UnZip"). That helper lives in msdos/msdos.c (a generic
   source we do NOT compile) and only warns a Windows user that the DOS build
   crashed; on CP/M-86 there is no Windows, so provide a no-op here rather than
   pull the whole DOS msdos.c. */

void check_for_windows(app)
    ZCONST char *app;
{
    (void)app;
}
