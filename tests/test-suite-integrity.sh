#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
# This checker and its mutation tests also run before dependencies are installed.
exec python3 "$ROOT/tools/check_test_coverage.py" --self-test
