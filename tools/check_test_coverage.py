#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fail before dependencies are installed if any Jarbis test is not run by CI.

ShellSpec automatically discovers *_spec.sh; each test in tests/ must be
registered exactly once by a real `When run command` clause, not a comment.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REGISTRATION = re.compile(
    r'^\s*When\s+run\s+command\s+(?:sh|python3)\s+'
    r'["\']\$SHELLSPEC_PROJECT_ROOT/(tests/[\w./-]+\.(?:sh|py))["\']\s*$'
)
JOB_HEADER = re.compile(r'^  ([A-Za-z][A-Za-z0-9_-]*):\s*$')


class CoverageError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CoverageError(message)


def check_specs(root: Path) -> int:
    require((root / '.shellspec').is_file(), '.shellspec 파일 없음')
    require(not (root / 'tests/run.sh').exists(), '기존 tests/run.sh가 남아 있습니다')
    test_dir = root / 'tests'
    scripts = {p.relative_to(root).as_posix() for p in test_dir.rglob('*')
               if p.is_file() and p.suffix in {'.sh', '.py'}}
    require(bool(scripts), '테스트 파일이 없습니다')
    # Detect new tests that would otherwise be silently skipped by ShellSpec.
    unsupported = [p.relative_to(root).as_posix() for p in test_dir.rglob('*')
                   if p.is_file() and (p.name.startswith(('test-', 'test_')) or
                                       '.test.' in p.name or '.spec.' in p.name)
                   and p.suffix not in {'.sh', '.py'}]
    require(not unsupported, '지원되지 않는 테스트 파일: ' + ', '.join(unsupported))
    specs = sorted((root / 'spec').rglob('*_spec.sh'))
    require(bool(specs), 'ShellSpec 사양 파일이 없습니다')
    other_specs = sorted(p.relative_to(root).as_posix() for p in (root / 'spec').rglob('*.sh')
                         if p not in specs)
    require(not other_specs, 'ShellSpec 자동 검색 대상이 아닌 스크립트: ' + ', '.join(other_specs))

    registrations: Counter[str] = Counter()
    for path in specs:
        for line in path.read_text(encoding='utf-8').splitlines():
            if match := REGISTRATION.fullmatch(line):
                registrations[match.group(1)] += 1
    require(not (scripts - registrations.keys()),
            'ShellSpec 미등록 테스트: ' + ', '.join(sorted(scripts - registrations.keys())))
    require(not (registrations.keys() - scripts),
            '존재하지 않는 ShellSpec 등록: ' + ', '.join(sorted(registrations.keys() - scripts)))
    duplicates = [name for name, count in registrations.items() if count != 1]
    require(not duplicates, 'ShellSpec 중복 등록: ' + ', '.join(sorted(duplicates)))
    return len(scripts)


def check_ci(root: Path) -> None:
    workflow = (root / '.github/workflows/ci.yml').read_text(encoding='utf-8')
    lines = workflow.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if JOB_HEADER.fullmatch(line) and JOB_HEADER.fullmatch(line).group(1) == 'contracts'), None)
    require(start is not None, 'CI contracts 작업 누락')
    end = next((i for i in range(start + 1, len(lines)) if JOB_HEADER.fullmatch(lines[i])), len(lines))
    job = '\n'.join(lines[start:end])
    require(not re.search(r'^    (?:if|continue-on-error):', job, re.MULTILINE),
            'CI contracts 작업은 조건부이거나 실패를 무시하면 안 됩니다')
    steps = re.split(r'(?=^      - name: )', job, flags=re.MULTILINE)
    required = [
        ('Verify all tests are included in CI', 'sh tests/test-suite-integrity.sh'),
        ('Verify OpenWrt 25.12 BusyBox compatibility', 'sh tests/test-openwrt-commands.sh'),
        ('Run tests (ucode required)', 'shellspec'),
    ]
    positions = {}
    for title, command in required:
        matching = [(index, step) for index, step in enumerate(steps)
                    if re.search(r'^      - name: ' + re.escape(title) + r'\s*$', step, re.MULTILINE)]
        require(len(matching) == 1, f'CI 단계 누락/중복: {title}')
        index, step = matching[0]
        require(not re.search(r'^        (?:if|continue-on-error):', step, re.MULTILINE),
                f'조건부 실행 또는 오류 무시: {title}')
        require(bool(re.search(r'^        run: ' + re.escape(command) + r'\s*$', step, re.MULTILINE)),
                f'CI 실행 명령이 다릅니다: {title}')
        positions[title] = index
    require(positions[required[0][0]] < positions[required[1][0]] < positions[required[2][0]],
            'CI 사전 검증은 ShellSpec보다 먼저 실행되어야 합니다')
    for step_name in ('Install ShellSpec', 'Install pinned ucode compiler'):
        indexes = [i for i, step in enumerate(steps) if f'      - name: {step_name}\n' in step]
        require(len(indexes) == 1 and positions[required[1][0]] < indexes[0],
                f'사전 검증은 {step_name}보다 먼저 수행해야 합니다')
    require("JARBIS_REQUIRE_UCODE: '1'" in steps[positions[required[2][0]]],
            'CI 실제 ucode 컴파일이 필수가 아닙니다')
    require('SHELLSPEC_VERSION: 0.28.1' in workflow, 'ShellSpec 버전 고정 누락')
    require('tests/run.sh' not in workflow, '삭제된 tests/run.sh를 CI에서 참조합니다')


def check(root: Path) -> int:
    count = check_specs(root)
    check_ci(root)
    return count


def self_test() -> None:
    """Mutation tests prove the same checker used by CI rejects common bypasses."""
    with tempfile.TemporaryDirectory(prefix='jarbis-ci-contract-') as temp:
        root = Path(temp)
        for folder in ('tests', 'spec', '.github/workflows'):
            (root / folder).mkdir(parents=True)
        (root / '.shellspec').write_text('--shell sh\n', encoding='utf-8')
        (root / 'tests/test-example.sh').write_text('#!/bin/sh\n', encoding='utf-8')
        spec = root / 'spec/contracts_spec.sh'
        spec_content = ('Describe "contracts"\n'
                        '  When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-example.sh"\n'
                        'End\n')
        spec.write_text(spec_content, encoding='utf-8')
        ci = root / '.github/workflows/ci.yml'
        ci_text = '''jobs:
  contracts:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Verify all tests are included in CI
        run: sh tests/test-suite-integrity.sh
      - name: Verify OpenWrt 25.12 BusyBox compatibility
        run: sh tests/test-openwrt-commands.sh
      - name: Install ShellSpec
        env:
          SHELLSPEC_VERSION: 0.28.1
      - name: Install pinned ucode compiler
        run: echo install
      - name: Run tests (ucode required)
        env:
          JARBIS_REQUIRE_UCODE: '1'
        run: shellspec
'''
        ci.write_text(ci_text, encoding='utf-8')
        require(check(root) == 1, '기본 계약 fixture 오류')

        def must_fail(fragment: str) -> None:
            try:
                check(root)
            except CoverageError as exc:
                require(fragment in str(exc), f'예상 외 오류: {exc}')
            else:
                raise CoverageError(f'변이 테스트를 감지하지 못함: {fragment}')

        extra = root / 'tests/test-new.sh'
        extra.write_text('#!/bin/sh\n', encoding='utf-8')
        must_fail('미등록')
        extra.unlink()
        spec.write_text(spec_content.replace('End\n',
            '  When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-example.sh"\nEnd\n'), encoding='utf-8')
        must_fail('중복')
        spec.write_text(spec_content.replace('test-example.sh', 'test-missing.sh'), encoding='utf-8')
        must_fail('미등록')
        spec.write_text(spec_content, encoding='utf-8')
        hidden = root / 'spec/hidden.sh'
        hidden.write_text('Describe "hidden"\nEnd\n', encoding='utf-8')
        must_fail('자동 검색 대상')
        hidden.unlink()
        for replacement, fragment in (
            ('run: sh tests/test-suite-integrity.sh', 'CI 실행 명령'),
            ('run: sh tests/test-openwrt-commands.sh', 'CI 실행 명령'),
            ('run: shellspec', 'CI 실행 명령'),
        ):
            ci.write_text(ci_text.replace(replacement, 'run: echo skipped'), encoding='utf-8')
            must_fail(fragment)
        ci.write_text(ci_text.replace(
            '      - name: Verify all tests are included in CI\n',
            '      - name: Verify all tests are included in CI\n        if: false\n'), encoding='utf-8')
        must_fail('조건부')
        ci.write_text(ci_text.replace(
            '      - name: Verify OpenWrt 25.12 BusyBox compatibility\n',
            '      - name: Verify OpenWrt 25.12 BusyBox compatibility\n        continue-on-error: true\n'), encoding='utf-8')
        must_fail('오류 무시')
        ci.write_text(ci_text.replace(
            '      - name: Verify OpenWrt 25.12 BusyBox compatibility\n'
            '        run: sh tests/test-openwrt-commands.sh\n',
            ''), encoding='utf-8')
        must_fail('CI 단계 누락')
        early_steps = (
            '      - name: Verify all tests are included in CI\n'
            '        run: sh tests/test-suite-integrity.sh\n'
            '      - name: Verify OpenWrt 25.12 BusyBox compatibility\n'
            '        run: sh tests/test-openwrt-commands.sh\n'
        )
        swapped_steps = (
            '      - name: Verify OpenWrt 25.12 BusyBox compatibility\n'
            '        run: sh tests/test-openwrt-commands.sh\n'
            '      - name: Verify all tests are included in CI\n'
            '        run: sh tests/test-suite-integrity.sh\n'
        )
        ci.write_text(ci_text.replace(early_steps, swapped_steps), encoding='utf-8')
        must_fail('CI 사전 검증')
        ci.write_text(ci_text, encoding='utf-8')
        require(check(root) == 1, '변이 테스트 이후 복원에 실패')


def main() -> int:
    try:
        count = check(ROOT)
        if '--self-test' in sys.argv[1:]:
            self_test()
    except (CoverageError, OSError) as exc:
        print(f'FAIL: CI test coverage: {exc}', file=sys.stderr)
        return 1
    print(f'PASS: {count} Jarbis tests registered exactly once in ShellSpec and CI')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
