#!/usr/bin/python3

"""
Called as
    subvol-prefix.py foo/
Given input
    xx yyy foo/bar
echoes
    bar

Strings whose prefix doesn't match are skipped.
An empty prefix is OK.
"""

from __future__ import annotations

import sys

prefix = sys.argv[1]
for line in sys.stdin:
    try:
        line = line.strip().split()[-1]
    except IndexError:
        continue
    if line.startswith(prefix):
        print(line.removeprefix(prefix))
