#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
text = (root / 'CHANGELOG.md').read_text(encoding='utf-8')
lines = text.splitlines()
versions = [(i, m.group(1)) for i, line in enumerate(lines)
            if (m := re.fullmatch(r'## \[([^]]+)\] - \d{4}-\d{2}-\d{2}', line))]
if len(versions) < 2:
    raise SystemExit('FAIL: CHANGELOG must include at least two releases')
for i, _ in versions[1:]:
    prev = i-1
    while prev >= 0 and not lines[prev].strip():
        if lines[prev]:
            raise SystemExit('FAIL: whitespace-only release gap')
        prev -= 1
    if i-prev-1 != 2:
        raise SystemExit(f'FAIL: release at line {i+1} needs exactly two blank lines')
mk = (root/'Makefile').read_text()
version = re.search(r'^PKG_VERSION:=(\S+)$', mk, re.M)
revision = re.search(r'^PKG_RELEASE:=(\d+)$', mk, re.M)
if not version or not revision or versions[0][1] != version.group(1) + '-r' + revision.group(1):
    raise SystemExit('FAIL: latest release must match Makefile')
if len({v for _,v in versions}) != len(versions):
    raise SystemExit('FAIL: duplicate release version')
print(f'PASS: {len(versions)} 릴리스 버전 및 공백 2줄 형식 확인')
PYTEST
