#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/root/usr/share/rpcd/ucode"
ENTRY="$MOD/jarbis.uc"
[ -f "$ENTRY" ] && [ -f "$MOD/jarbis/core.uc" ] || {
    echo 'FAIL: ucode RPC 소스 누락' >&2
    exit 1
}
if ! command -v ucode >/dev/null 2>&1; then
    if [ "${JARBIS_REQUIRE_UCODE:-0}" = 1 ]; then
        echo 'FAIL: CI에서 ucode 컴파일러는 필수입니다.' >&2
        exit 1
    fi
    echo 'PASS: 로컬 ucode 부재로 정적 구조 검사만 수행했습니다. (CI는 반드시 컴파일)'
    exit 0
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-ucode.XXXXXX")"
# A ucode module may contain exports but cannot be compiled as an entrypoint.
# Place the synthetic importing entrypoint beside the actual rpcd sources so
# relative imports resolve exactly as they do on the router.
AGGREGATE="$MOD/.jarbis-syntax-all.$$.uc"
trap 'rm -rf "$TMP"; rm -f "$AGGREGATE"' EXIT HUP INT TERM
cat > "$TMP/uci.uc" <<'STUB'
export function cursor() { return null; };
STUB
# The CI compiler is built without optional OpenWrt runtime plugins. Its
# module import graph still has to resolve, so mock the fs *module* (as we do
# for uci) without skipping syntax compilation of the real Jarbis sources.
# On the router, ucode-mod-fs supplies the real native implementation.
cat > "$TMP/fs.uc" <<'STUB'
export function readfile(path, limit) { return null; };
export function mkdtemp(template) { return null; };
export function open(path, mode, perm) { return null; };
export function unlink(path) { return true; };
export function rmdir(path) { return true; };
STUB

compile_entry() {
    source_file="$1"
    output_file="$2"
    if ! ucode -L "$TMP" -L "$MOD" -c -o "$output_file" "$source_file" >"$TMP/compiler.log" 2>&1; then
        cat "$TMP/compiler.log" >&2
        printf 'FAIL: ucode 컴파일 실패: %s\n' "$source_file" >&2
        exit 1
    fi
    [ -s "$output_file" ] || {
        echo 'FAIL: ucode 컴파일 출력이 비었습니다.' >&2
        exit 1
    }
}

# Compile the executable RPC plugin. Its static imports compile core.uc as a
# module (unlike `ucode -c core.uc`, which caused the reported CI error).
compile_entry "$ENTRY" "$TMP/rpc.ucb"

# Also compile every nested module through imports, even if an RPC entrypoint
# stops importing one in the future. Do not silently miss dormant modules.
: > "$AGGREGATE"
find "$MOD" -mindepth 2 -type f -name '*.uc' -print | LC_ALL=C sort |
while IFS= read -r module; do
    module_index="${module_index:-0}"
    module_index=$((module_index + 1))
    relative="${module#"$MOD"/}"
    printf "import * as jarbis_syntax_%s from './%s';\n" "$module_index" "$relative"
done > "$AGGREGATE"
printf 'return true;\n' >> "$AGGREGATE"
if ! grep -q '^import ' "$AGGREGATE"; then
    echo 'FAIL: ucode 내부 모듈이 없습니다.' >&2
    exit 1
fi
compile_entry "$AGGREGATE" "$TMP/all-modules.ucb"

# Ensure the installed compiler really rejects malformed exported modules.
cat > "$TMP/invalid-export.uc" <<'INVALID'
export function broken_export() {
    return true;
}
INVALID
cat > "$TMP/invalid-entry.uc" <<'INVALID_ENTRY'
import { broken_export } from './invalid-export.uc';
return broken_export();
INVALID_ENTRY
if ucode -L "$TMP" -c -o "$TMP/invalid.ucb" "$TMP/invalid-entry.uc" >/dev/null 2>&1; then
    echo 'FAIL: ucode 컴파일러가 잘못된 export 구문을 허용했습니다.' >&2
    exit 1
fi
printf 'PASS: Jarbis RPC 진입점 및 모든 ucode 모듈의 컴파일 검사\n'
