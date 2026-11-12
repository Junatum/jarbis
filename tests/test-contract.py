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
        import re
        mk = (ROOT / 'Makefile').read_text()
        version = re.search(r'(?m)^PKG_VERSION:=(\S+)$', mk)
        revision = re.search(r'(?m)^PKG_RELEASE:=(\d+)$', mk)
        self.assertIsNotNone(version)
        self.assertIsNotNone(revision)
        release = f'{version.group(1)}-r{revision.group(1)}'
        notes = (ROOT / 'CHANGELOG.md').read_text()
        self.assertRegex(notes, r'(?m)^## \[' + re.escape(release) + r'\] - \d{4}-\d{2}-\d{2}$')
        self.assertIn(f"version: '{release}'", (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text())
        self.assertIn('PKG_LICENSE:=GPL-3.0-or-later', mk)
        self.assertIn('./root/usr/libexec/jarbis-manage', mk)
        self.assertTrue((ROOT / 'LICENSE').is_file())

    def test_읽기와_쓰기_ACL은_분리하고_공개하지_않는다(self):
        acl = json.loads((ROOT / "root/usr/share/rpcd/acl.d/jarbis.json").read_text())
        self.assertEqual(acl['jarbis']['read']['ubus']['jarbis'], ['status', 'devices_list', 'light_state', 'discovery_list'])
        self.assertEqual(acl['jarbis']['write']['ubus']['jarbis'], ['light_set', 'discovery_scan', 'settings_update', 'device_add', 'device_update', 'device_remove', 'device_pair', 'broker_credentials'])
        self.assertNotIn('unauthenticated', json.dumps(acl))

    def test_기본값은_비활성화이며_인증된_관리형_MQTT를_선택한다(self):
        config = (ROOT / 'root/etc/config/jarbis').read_text()
        self.assertRegex(config, r"option enabled '0'")
        mk = (ROOT / 'Makefile').read_text()
        self.assertIn('mosquitto-client-ssl', mk)
        self.assertIn('+mosquitto-ssl', mk)
        self.assertIn("option mode 'managed'", config)
        self.assertIn("option enabled '1'", config)
        self.assertTrue((ROOT / 'root/etc/init.d/jarbis').is_file())
        self.assertFalse((ROOT / 'root/etc/firewall').exists())

    def test_RPC와_파일의_설치_경로가_맞는다(self):
        mk = (ROOT / 'Makefile').read_text()
        paths = [
            'root/etc/config/jarbis',
            'root/usr/libexec/jarbis-control',
            'root/usr/libexec/jarbis-state',
            'root/usr/share/rpcd/acl.d/jarbis.json',
            'root/usr/share/rpcd/ucode/jarbis.uc',
            'root/usr/share/rpcd/ucode/jarbis/core.uc',
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).is_file())
                self.assertIn('./' + path, mk)
        plugin = (ROOT / 'root/usr/share/rpcd/ucode/jarbis.uc').read_text()
        self.assertIn('return { jarbis: methods };', plugin)

    def test_비밀과_임의_MQTT_명령이_RPC로_노출되지_않는다(self):
        source = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn("'PUBLISH_FAILED'", source)
        self.assertIn("'INVALID_DEVICE'", source)
        self.assertIn("'INVALID_CAPABILITY'", source)
        self.assertIn("'INVALID_VALUE'", source)
        self.assertNotIn('password:', source)
        # ucode arrays use push(array, item), not JavaScript's array.push(item).
        # A syntax-only compiler check does not catch this runtime error.
        self.assertNotRegex(source, r'\.\s*push\s*\(')
        self.assertIn('push(result, {', source)
        cli = (ROOT / 'root/usr/libexec/jarbis-control').read_text()
        self.assertNotIn('eval(', cli)
        self.assertNotRegex(cli, r'(?m)^\s*stat\s')
        self.assertNotRegex(cli, r'(?m)^\s*(find|sort|head|tail)\s+/')

    def test_브로커_사전_점검과_안전한_오류_전달(self):
        broker = (ROOT / 'root/usr/libexec/jarbis-broker').read_text()
        manager = (ROOT / 'root/usr/libexec/jarbis-manage').read_text()
        rpc = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn('diagnose', broker)
        self.assertIn('network.interface.lan', broker)
        self.assertIn('valid_lan_ipv4', broker)
        self.assertIn('broker_error_code()', manager)
        self.assertIn('JARBIS_MANAGE_ERROR_FILE', manager)
        self.assertIn('LAN_UNAVAILABLE', rpc)
        self.assertIn('BROKER_CONFIG_CONFLICT', rpc)
        self.assertNotIn('cat "$BROKER_PASS"', manager)

    def test_Tasmota_실기기_CIDR와_표준_Status_Topic을_검색한다(self):
        discover = (ROOT / 'root/usr/libexec/jarbis-discover').read_text()
        broker = (ROOT / 'root/usr/libexec/jarbis-broker').read_text()
        rpc = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn('*/24)', discover)
        self.assertIn("'@.Status.Topic'", discover)
        self.assertNotIn("'@.StatusMQT.Topic'", discover)
        self.assertNotIn('*tasmota*|*Tasmota*', discover)
        self.assertIn('*/24) lan="${lan%/24}"', broker)
        self.assertIn("cfg.get('jarbis', 'broker', 'lan_ip') ?? cfg.get('network', 'lan', 'ipaddr')", rpc)

    def test_MQTT_브로커_확인은_지원되는_Publisher_옵션을_사용한다(self):
        broker = (ROOT / 'root/usr/libexec/jarbis-broker').read_text()
        self.assertIn('MQTT_PUB_BIN', broker)
        self.assertIn('"$MQTT_PUB_BIN" -h "$host" -p "$port" -q 1', broker)
        self.assertNotRegex(broker, r'(?m)^\s*mosquitto_pub\s+.*\s-W\s')
        self.assertIn("fail 'MQTT connection failed'", broker)

    def test_등록된_전구의_로컬_상태_조회는_안전한_조회만_사용한다(self):
        helper = (ROOT / 'root/usr/libexec/jarbis-state').read_text()
        core = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn('parse_status "$output/http" http', helper)
        self.assertIn("'@.Status.Topic'", helper)
        self.assertIn('"$reported_topic" = "$topic"', helper)
        self.assertIn('valid_ip "$lan" && valid_ip "$ip"', helper)
        self.assertIn('"http://$target/cm?cmnd=Status%200"', helper)
        self.assertIn('"$FETCH_BIN" -q -Y off -T 2', helper)
        self.assertNotIn('password=', helper)
        self.assertIn("source: source == 'mqtt' || source == 'http'", core)

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

    def test_호스트_ucode_테스트는_파일시스템_모듈을_격리한다(self):
        mk = (ROOT / 'Makefile').read_text()
        self.assertIn('+ucode-mod-fs', mk)
        for script in ['test-ucode.sh', 'test-rpc-runtime.sh']:
            with self.subTest(script=script):
                source = (ROOT / 'tests' / script).read_text()
                self.assertIn('cat > "$TMP/fs.uc"', source)
                self.assertIn('export function readfile(path, limit)', source)
                self.assertIn('-L "$TMP"', source)


    def test_ShellSpec_전체_테스트와_CI가_연결되어_있다(self):
        config = (ROOT / '.shellspec').read_text()
        self.assertIn('--shell sh', config)
        spec = (ROOT / 'spec/contracts_spec.sh').read_text()
        for name in ['test-mqtt.sh', 'test-contract.py', 'test-ucode.sh', 'test-ucode-runner.sh', 'test-suite-integrity.sh', 'test-openwrt-commands.sh', 'test-rpc-runtime.sh', 'test-package-contract.sh', 'test-rpcd-reconcile.sh', 'test-backup-restore.sh', 'test-changelog-spacing.sh', 'test-broker.sh', 'test-discovery.sh', 'test-manage.sh', 'test-pair.sh']:
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


    def test_Tasmota_자동_연결은_승인과_인증정보_보호를_적용한다(self):
        mk = (ROOT / 'Makefile').read_text()
        cli = (ROOT / 'root/usr/libexec/jarbis-pair').read_text()
        rpc = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        self.assertIn('PKG_RELEASE:=9', mk)
        self.assertIn('./root/usr/libexec/jarbis-pair', mk)
        self.assertIn('export function device_pair(', rpc)
        self.assertIn("mkdtemp('/tmp/jarbis-pair-XXXXXX')", rpc)
        self.assertIn("'wx', 0o600", rpc)
        self.assertIn('device_pair', (ROOT / 'root/usr/share/rpcd/ucode/jarbis.uc').read_text())
        self.assertIn('--post-file=', cli)
        self.assertIn('BROKER_CONFLICT', cli)
        self.assertIn('WEB_AUTH_REQUIRED', cli)
        self.assertNotIn('eval ', cli)
        self.assertNotIn('--post-data=', cli)
        self.assertIn('tests/test-pair.sh', (ROOT / 'spec/contracts_spec.sh').read_text())

    def test_ucode_지원하지_않는_finally_구문을_금지하고_인증파일_정리를_보장한다(self):
        import re
        core = (ROOT / 'root/usr/share/rpcd/ucode/jarbis/core.uc').read_text()
        runner = (ROOT / 'tests/test-rpc-runtime.sh').read_text()
        checker = (ROOT / 'tests/test-ucode.sh').read_text()
        self.assertIsNone(re.search(r'\bfinally\s*\{', core))
        self.assertIn('pair_in_directory(', core)
        self.assertIn('io.unlink(path +', core)
        self.assertIn('io.rmdir(path)', core)
        self.assertIn('pairFailureCleanup', runner)
        self.assertIn('ucode는 finally 구문을 지원하지 않습니다.', checker)

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
