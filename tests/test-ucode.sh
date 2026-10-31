#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/root/usr/share/rpcd/ucode"
[ -f "$MOD/jarbis/core.uc" ] && [ -f "$MOD/jarbis.uc" ] || {
    echo 'FAIL: ucode RPC 소스 누락' >&2; exit 1;
}
if ! command -v ucode >/dev/null 2>&1; then
    if [ "${JARBIS_REQUIRE_UCODE:-0}" = 1 ]; then
        echo 'FAIL: CI에서 ucode 컴파일러는 필수입니다.' >&2
        exit 1
    fi
    echo 'PASS: 로컬 ucode 부재로 정적 구조 검사만 수행했습니다. (CI는 반드시 컴파일)'
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# Host ucode lacks the UCI dynamic module; a minimal stub is enough for compile check.
printf '%s\n' 'export function cursor() { return null; };' > "$TMP/uci.uc"
for src in "$MOD/jarbis/core.uc" "$MOD/jarbis.uc"; do
    target="$TMP/$(basename "$src").ucb"
    if ! ucode -L "$TMP" -L "$MOD" -c -o "$target" "$src" >"$TMP/compiler.log" 2>&1; then
        cat "$TMP/compiler.log" >&2
        echo "FAIL: ucode 컴파일 실패: $src" >&2
        exit 1
    fi
    [ -s "$target" ] || { echo 'FAIL: ucode 출력이 비었습니다.' >&2; exit 1; }
done
printf 'PASS: Jarbis RPC ucode 소스 컴파일\n'
