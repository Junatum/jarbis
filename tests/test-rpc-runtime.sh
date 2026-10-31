#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/root/usr/share/rpcd/ucode"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
if ! command -v ucode >/dev/null 2>&1; then
    [ "${JARBIS_REQUIRE_UCODE:-0}" != 1 ] || fail 'ucode runtime is required in CI'
    printf 'PASS: ucode 미설치 로컬 환경에서는 실제 RPC 실행을 생략합니다. CI에서는 필수입니다.\n'
    exit 0
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-rpc.XXXXXX")"
RUNNER="$MOD/.jarbis-rpc-runtime.$$.uc"
trap 'rm -rf "$TMP"; rm -f "$RUNNER"' EXIT HUP INT TERM
# Mock OpenWrt 25.12 UCI module; execute the real core, not a source-string check.
cat > "$TMP/uci.uc" <<'STUB'
let unavailable = false;
export function set_unavailable(value) { unavailable = value; };
export function cursor() {
    if (unavailable) return null;
    return {
        get: function(config, section, option) {
            if (config != 'jarbis') return null;
            if (section == 'main' && option == 'enabled') return '1';
            if (section == 'broker' && option == 'host') return '127.0.0.1';
            return null;
        },
        foreach: function(config, kind, callback) {
            if (config == 'jarbis' && kind == 'device') {
                callback({ '.name': 'living_room', name: '거실 전구', kind: 'light', protocol: 'tasmota', enabled: '1', password: 'must-not-leak' });
                callback({ '.name': 'disabled', name: '꺼진 기기', kind: 'light', protocol: 'tasmota', enabled: '0' });
            }
        },
    };
};
STUB
cat > "$RUNNER" <<'UCRUN'
import { status, devices_list, light_set } from './jarbis/core.uc';
import { set_unavailable } from 'uci';
let published = null;
const mock_publish = function(argv, timeout) {
    published = { argv: argv, timeout: timeout };
    return 0;
};
const result = {
    status: status(),
    devices: devices_list(),
    on: light_set({ args: { id: 'living_room', capability: 'power', value: 'ON' } }, mock_publish),
    publish: published,
    brightness: light_set({ args: { id: 'living_room', capability: 'brightness', value: '90' } }, mock_publish),
    topLevelOnly: light_set({ id: 'living_room', capability: 'power', value: 'ON' }, mock_publish),
    invalidDevice: light_set({ args: { id: '../../x', capability: 'power', value: 'ON' } }, mock_publish),
    invalidCapability: light_set({ args: { id: 'living_room', capability: 'raw', value: 'ON' } }, mock_publish),
    invalidValue: light_set({ args: { id: 'living_room', capability: 'brightness', value: '101' } }, mock_publish),
    noArgs: light_set({}, mock_publish),
    publishFailed: light_set({ args: { id: 'living_room', capability: 'power', value: 'OFF' } }, function(argv, timeout) { return 1; }),
};
set_unavailable(true);
result.unavailableStatus = status();
result.unavailableDevices = devices_list();
printf('%J\n', result);
UCRUN
if ! ucode -L "$TMP" -L "$MOD" "$RUNNER" > "$TMP/output.json" 2> "$TMP/error.log"; then
    cat "$TMP/error.log" >&2
    fail '실제 ucode RPC 모듈 실행 실패'
fi
[ ! -s "$TMP/error.log" ] || { cat "$TMP/error.log" >&2; fail 'ucode가 stderr를 기록했습니다'; }
python3 - "$TMP/output.json" <<'PYTEST'
import json
import pathlib
import sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
def require(cond, msg):
    if not cond: raise SystemExit('FAIL: ' + msg)
require(r['status']['ok'] and r['status']['data']['enabled'] is True, 'UCI enabled 조회')
require(r['status']['data']['features']['ai'] is False, 'AI 비활성 상태')
devices = r['devices']['data']['devices']
require(len(devices) == 2 and devices[0]['id'] == 'living_room', 'UCI 기기 목록')
require(devices[0]['capabilities'] == ['power', 'brightness'], '지원 capability')
require('must-not-leak' not in json.dumps(r), 'UCI 비밀값 노출')
require(r['on']['ok'] and r['on']['data']['accepted'], 'request.args 기반 전원 제어')
require(r['brightness']['ok'], '밝기 제어')
require(r['publish']['argv'] == ['/usr/libexec/jarbis-control', 'light-set', 'living_room', 'power', 'ON'], '실제 발행 인수')
require(r['publish']['timeout'] == 5000, '발행 시간 제한')
require(r['unavailableStatus']['error']['code'] == 'CONFIG_UNAVAILABLE', 'UCI 생성 실패 status')
require(r['unavailableDevices']['error']['code'] == 'CONFIG_UNAVAILABLE', 'UCI 생성 실패 devices')
for field, error in [('topLevelOnly','INVALID_DEVICE'), ('invalidDevice','INVALID_DEVICE'),
                     ('invalidCapability','INVALID_CAPABILITY'), ('invalidValue','INVALID_VALUE'),
                     ('noArgs','INVALID_DEVICE'), ('publishFailed','PUBLISH_FAILED')]:
    require(not r[field]['ok'] and r[field]['error']['code'] == error, field + ' 오류 코드')
PYTEST
printf 'PASS: 실제 ucode RPC 요청 인자·UCI 기기 조회·MQTT 호출 결과 검증\n'
