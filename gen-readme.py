#!/usr/bin/env python3
"""Emit the DOS-facing README.TXT shipped inside the binary release archive.

Usage: gen-readme.py <version>
"""
import sys

VERSION = sys.argv[1]

print(f"""Info-ZIP Zip 3.0 / UnZip 6.0 -- 16-bit MS-DOS binaries
Unofficial community build {VERSION}

!! IMPORTANT ------------------------------------------------------------
!! This is an UNOFFICIAL, community-produced build. It is NOT an Info-ZIP
!! release and is NOT endorsed by or supported by Info-ZIP. Do not report
!! problems with these binaries to Info-ZIP or the Zip-Bugs address.
!! The C sources were compiled UNMODIFIED from the official Zip 3.0 and
!! UnZip 6.0 releases; only the Watcom makefiles were edited, to let them
!! run on a modern POSIX build host. See the project page for the exact
!! diff.
!! ---------------------------------------------------------------------

CONTENTS

  From UnZip 6.0:
    UNZIP.EXE      list, test and extract .zip archives
    UNZIPSFX.EXE   stub for building self-extracting archives
    FUNZIP.EXE     filter: extract the first member to standard output

  From Zip 3.0:
    ZIP.EXE        create and update .zip archives
    ZIPCLOAK.EXE   encrypt / decrypt entries in an archive
    ZIPNOTE.EXE    read and write archive comments
    ZIPSPLIT.EXE   split an archive across several disks

  *.TXT            upstream manuals for each program
  LICENSE.TXT      the Info-ZIP license (please read)

REQUIREMENTS

  Any 8086/8088 or later CPU -- these are pure real-mode MZ executables
  built with the 8086 instruction set only. No DOS extender, no DPMI and
  no 386 instructions are used. MS-DOS 3.0 or later is recommended.
  ZIP.EXE is the largest program and wants roughly 200 KB of free
  conventional memory; UNZIP.EXE somewhat less.

INSTALLING

  Copy the .EXE files to a directory on your DOS PATH, for example
  C:\\DOS or C:\\UTIL.

  Info-ZIP warns that the TZ environment variable is not set, because DOS
  has no timezone concept. To silence it, add a line such as
  SET TZ=EST5EDT to your AUTOEXEC.BAT.

LICENSE

  Copyright (c) 1990-2009 Info-ZIP. All rights reserved. Distributed
  under the Info-ZIP license; the full text is in LICENSE.TXT and must
  accompany any redistribution of these binaries.""")
