#!/usr/bin/env python3
"""Convert DOS path separators in Info-ZIP's makefile.wat so wmake can run
on a Linux host while still cross-compiling for 16-bit DOS."""
import re
import sys

path = sys.argv[1]
text = open(path, encoding="latin-1").read()

# "O = $(OBDIR)\   # comment here so backslash won't continue the line"
text = re.sub(r"^(O\s*=\s*\$\(OBDIR\))\\", r"\1/", text, flags=re.M)

# Platform subdirectory references: msdos\foo.c -> msdos/foo.c
text = re.sub(r"\b(msdos|win32|amiga)\\", r"\1/", text)

# clean targets use the DOS 'del' command; wmake shells out to /bin/sh here.
text = re.sub(r"^\tdel ", "\trm -f ", text, flags=re.M)

open(path, "w", encoding="latin-1").write(text)
print(f"patched {path}")
