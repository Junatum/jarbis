#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
sh "$ROOT/tests/test-mqtt.sh"
python3 "$ROOT/tests/test-contract.py"
sh "$ROOT/tests/test-ucode.sh"
printf 'PASS: 모든 Jarbis 테스트가 통과했습니다.\n'
