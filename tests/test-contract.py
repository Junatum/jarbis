#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pure standard library static tests for package/ACL/forward compatibility."""
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class ProjectContracts(unittest.TestCase):
    def test_버전과_현재_릴리스가_일치한다(self):
        mk = (ROOT / "Makefile").read_text()
        self.assertRegex(mk, r"(?m)^PKG_VERSION:=0\.1\.0$")
        self.assertRegex(mk, r"(?m)^PKG_RELEASE:=3$")
        notes = (ROOT / "CHANGELOG.md").read_text()
        self.assertIn("## [0.1.0-r3] - 2026-11-01", notes)
        self.assertIn('\n\n\n## [0.1.0-r2]', notes)
        self.assertNotIn('\n\n\n\n## [0.1.0-r2]', notes)
        self.assertIn("## [0.1.0-r2] - 2026-11-01", notes)
        self.assertIn("## [0.1.0-r1] - 2026-10-31", notes)
        self.assertIn('\n\n\n## [0.1.0-r1]', notes)
        self.assertNotIn('\n\n\n\n## [0.1.0-r1]', notes)
        self.assertIn("version: '0.1.0-r3'", (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text())
        self.assertIn("PKG_LICENSE:=GPL-3.0-or-later", mk)
        self.assertTrue((ROOT / "LICENSE").is_file())

    def test_읽기와_쓰기_ACL은_분리하고_공개하지_않는다(self):
        acl = json.loads((ROOT / "root/usr/share/rpcd/acl.d/jarbis.json").read_text())
        self.assertEqual(acl['jarbis']['read']['ubus']['jarbis'], ['status', 'devices_list'])
        self.assertEqual(acl['jarbis']['write']['ubus']['jarbis'], ['light_set'])
        self.assertNotIn('unauthenticated', json.dumps(acl))

    def test_기본값은_비활성화이며_MQTT_브로커를_자동_노출하지_않는다(self):
        config = (ROOT / 'root/etc/config/jarbis').read_text()
        self.assertRegex(config, r"option enabled '0'")
        mk = (ROOT / 'Makefile').read_text()
        self.assertIn('mosquitto-client-nossl', mk)
        self.assertNotRegex(mk, r"\+mosquitto-(ssl|nossl)(?!-client)")
        self.assertFalse((ROOT / 'root/etc/init.d').exists())
        self.assertFalse((ROOT / 'root/etc/firewall').exists())

    def test_RPC와_파일의_설치_경로가_맞는다(self):
        mk = (ROOT / 'Makefile').read_text()
        paths = [
            'root/etc/config/jarbis',
            'root/usr/libexec/jarbis-control',
            'root/usr/share/rpcd/acl.d/jarbis.json',
            'root/usr/share/rpcd/ucode/jarbis.uc',
            'root/usr/share/rpcd/ucode/jarbis/core.uc',
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())
                self.assertIn('./' + path, mk)
        plugin = (ROOT / paths[3]).read_text()
        self.assertIn('return { jarbis: methods };', plugin)

    def test_비밀과_임의_MQTT_명령이_RPC로_노출되지_않는다(self):
        source = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn("'PUBLISH_FAILED'", source)
        self.assertIn("'INVALID_DEVICE'", source)
        self.assertIn("'INVALID_CAPABILITY'", source)
        self.assertIn("'INVALID_VALUE'", source)
        self.assertNotIn('password:', source)
        cli = (ROOT / 'root/usr/libexec/jarbis-control').read_text()
        self.assertNotIn('eval(', cli)
        self.assertNotRegex(cli, r'(?m)^\s*stat\s')
        self.assertNotRegex(cli, r'(?m)^\s*(find|sort|head|tail)\s+/')

    def test_프론트엔드_빌드_산출물이_없다(self):
        self.assertFalse((ROOT / 'frontend').exists())
        for p in ROOT.rglob('*'):
            self.assertNotIn(p.suffix, {'.wasm', '.apk', '.ipk'})

    def test_모듈은_import로_컴파일한다(self):
        check = (ROOT / 'tests/test-ucode.sh').read_text()
        self.assertIn('compile_entry "$ENTRY"', check)
        self.assertIn('compile_entry "$AGGREGATE"', check)
        self.assertIn('invalid-export.uc', check)
        self.assertNotIn('compile_entry "$MOD/jarbis/core.uc"', check)

    def test_ShellSpec_전체_테스트와_CI가_연결되어_있다(self):
        config = (ROOT / '.shellspec').read_text()
        self.assertIn('--shell sh', config)
        spec = (ROOT / 'spec/contracts_spec.sh').read_text()
        for name in ['test-mqtt.sh', 'test-contract.py', 'test-ucode.sh', 'test-ucode-runner.sh', 'test-suite-integrity.sh', 'test-openwrt-commands.sh']:
            self.assertIn('tests/' + name, spec)
        self.assertFalse((ROOT / 'tests/run.sh').exists())
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertRegex(ci, r'(?m)^\s*run: shellspec\s*$')
        self.assertNotIn('tests/run.sh', ci)
        integrity = (ROOT / 'tests/test-suite-integrity.sh').read_text()
        self.assertIn('tools/check_test_coverage.py', integrity)
        coverage = (ROOT / 'tools/check_test_coverage.py').read_text()
        self.assertIn("'tests/run.sh'", coverage)
        self.assertIn("JARBIS_REQUIRE_UCODE: '1'", ci)
        self.assertIn('SHELLSPEC_VERSION: 0.28.1', ci)

    def test_CI_상단에서_사전_검사를_실행한다(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('name: Verify all tests are included in CI', ci)
        self.assertIn('run: sh tests/test-suite-integrity.sh', ci)
        self.assertIn('name: Verify OpenWrt 25.12 BusyBox compatibility', ci)
        self.assertIn('run: sh tests/test-openwrt-commands.sh', ci)
        self.assertLess(ci.index('name: Verify all tests are included in CI'),
                        ci.index('name: Install ShellSpec'))
        self.assertLess(ci.index('name: Verify OpenWrt 25.12 BusyBox compatibility'),
                        ci.index('name: Install pinned ucode compiler'))
        self.assertTrue((ROOT / 'tools/check_openwrt_commands.py').is_file())
        self.assertTrue((ROOT / 'tools/openwrt-25.12-commands.txt').is_file())


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProjectContracts)
    result = unittest.TextTestRunner(verbosity=2, stream=sys.stdout).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)
    print('PASS: Jarbis 정적 계약 테스트')
