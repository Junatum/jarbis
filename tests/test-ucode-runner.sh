#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify the syntax-test runner's exact entrypoint/module strategy without
# requiring a host-installed OpenWrt ucode compiler.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-compiler-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
cat > "$TMP/ucode" <<'MOCK'
#!/bin/sh
set -eu
output=''
source=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -L) shift 2 ;;
        -c) shift ;;
        *) source="$1"; shift ;;
    esac
done
[ -n "$output" ] && [ -n "$source" ] || exit 1
case "$source" in
    */jarbis.uc)
        grep -Fq "from './jarbis/core.uc';" "$source" || exit 1
        printf 'rpc\n' >> "$MOCK_COMPILER_LOG"
        ;;
    */.jarbis-syntax-all.*.uc)
        grep -Fq "from './jarbis/core.uc';" "$source" || exit 1
        printf 'modules\n' >> "$MOCK_COMPILER_LOG"
        ;;
    */invalid-entry.uc)
        printf 'invalid\n' >> "$MOCK_COMPILER_LOG"
        exit 1
        ;;
    *) exit 1 ;;
esac
printf 'bytecode' > "$output"
MOCK
chmod 700 "$TMP/ucode"
MOCK_COMPILER_LOG="$TMP/compile.log"
export MOCK_COMPILER_LOG
if ! PATH="$TMP:$PATH" JARBIS_REQUIRE_UCODE=1 sh "$ROOT/tests/test-ucode.sh" > "$TMP/stdout" 2> "$TMP/stderr"; then
    cat "$TMP/stderr" >&2
    fail '모의 ucode 컴파일로 테스트 실행기를 검증하지 못했습니다.'
fi
[ ! -s "$TMP/stderr" ] || fail '성공한 컴파일에 오류 메시지가 발생했습니다.'
grep -q '^PASS:' "$TMP/stdout" || fail '성공 메시지가 없습니다.'
[ "$(wc -l < "$MOCK_COMPILER_LOG")" -eq 3 ] || fail '예상하지 못한 컴파일 대상이나 누락이 있습니다.'
grep -qx 'rpc' "$MOCK_COMPILER_LOG" || fail 'RPC 진입점이 컴파일되지 않았습니다.'
grep -qx 'modules' "$MOCK_COMPILER_LOG" || fail '내부 모듈이 컴파일되지 않았습니다.'
grep -qx 'invalid' "$MOCK_COMPILER_LOG" || fail '잘못된 모듈 거부 검사가 누락됐습니다.'
if find "$ROOT/root/usr/share/rpcd/ucode" -maxdepth 1 -type f \
    -name '.jarbis-syntax-all.*.uc' -print | grep -q .; then
    fail '컴파일 검사 임시 파일이 남았습니다.'
fi
printf 'PASS: ucode 컴파일 진입점·모듈·오류 방지 테스트\n'
