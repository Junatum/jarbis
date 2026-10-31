#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[ -f "$ROOT/.shellspec" ] || fail '.shellspec 설정이 없습니다.'
[ -f "$ROOT/spec/contracts_spec.sh" ] || fail 'ShellSpec 계약 파일이 없습니다.'
[ -f "$ROOT/.github/workflows/ci.yml" ] || fail 'CI 설정이 없습니다.'
[ ! -e "$ROOT/tests/run.sh" ] || fail '이전 실행 스크립트 tests/run.sh가 남아 있습니다.'

# Every test file is deliberately registered in ShellSpec rather than silently
# being left out of CI when a new test is added.
for test_file in "$ROOT"/tests/test-*.sh "$ROOT"/tests/test-*.py; do
    [ -f "$test_file" ] || continue
    test_name="$(basename "$test_file")"
    grep -Fq "tests/$test_name" "$ROOT/spec/contracts_spec.sh" ||         fail "ShellSpec에서 누락된 테스트: $test_name"
done
# Keep the direct ShellSpec command and mandatory compiler flag tied to CI.
grep -Eq '^[[:space:]]*run:[[:space:]]*shellspec[[:space:]]*$' "$ROOT/.github/workflows/ci.yml" || fail 'CI는 shellspec을 직접 실행해야 합니다.'
if grep -Fq 'tests/run.sh' "$ROOT/.github/workflows/ci.yml"; then
    fail 'CI가 삭제된 테스트 실행 스크립트를 참조합니다.'
fi
grep -Fq 'JARBIS_REQUIRE_UCODE:' "$ROOT/.github/workflows/ci.yml" || fail 'CI ucode 필수 설정이 없습니다.'
grep -Fq 'SHELLSPEC_VERSION: 0.28.1' "$ROOT/.github/workflows/ci.yml" || fail 'CI ShellSpec 버전 고정이 없습니다.'
printf 'PASS: 모든 Jarbis 테스트가 ShellSpec 및 CI에 등록되어 있습니다.\n'
