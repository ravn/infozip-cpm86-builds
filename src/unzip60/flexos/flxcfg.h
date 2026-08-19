/*
  Copyright (c) 1990-2000 Info-ZIP.  All rights reserved.

  See the accompanying file LICENSE, version 2000-Apr-09 or later
  (the contents of which are also included in unzip.h) for terms of use.
  If, for some reason, all these files are missing, the Info-ZIP license
  also may be found at:  ftp://ftp.info-zip.org/pub/infozip/license.html
*/
/*---------------------------------------------------------------------------
    FlexOS specific configuration section:
  ---------------------------------------------------------------------------*/

#ifndef __flxcfg_h
#define __flxcfg_h

#define __16BIT__
#define MED_MEM
#define EXE_EXTENSION ".286"

#ifndef nearmalloc
#  define nearmalloc malloc
#  define nearfree free
#endif

#define CRTL_CP_IS_OEM

#ifndef __WATCOMC__
/* Legacy FlexOS compilers had no usable far model, so the port historically
 * neutralised the near/far qualifiers.  Open Watcom targeting CP/M-86 DOES
 * have a real `far` keyword and a FAR_DATA segment/Extra group, which we rely
 * on to push UnZip's ~22 KB of `Far` message strings out of the 64 KB DGROUP.
 * Keeping the empty defines here would silently collapse every `Far` string
 * back into DGROUP and re-overflow the small-model data segment. */
#define near
#define far
#endif

#endif /* !__flxcfg_h */
