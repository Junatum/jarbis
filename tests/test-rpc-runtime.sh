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
            if (section == 'broker' && option == 'mode') return 'managed';
            if (section == 'discovery' && option == 'enabled') return '1';
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
# Mock the optional native fs module from OpenWrt in this isolated host test.
# The injected reader tests discovery parsing; this null stub covers the
# actual cache-missing fallback without reading any host filesystem state.
cat > "$TMP/fs.uc" <<'STUB'
export function readfile(path, limit) { return null; };
export function mkdtemp(template) { return null; };
export function open(path, mode, perm) { return null; };
export function unlink(path) { return true; };
export function rmdir(path) { return true; };
STUB
cat > "$RUNNER" <<'UCRUN'
import { status, devices_list, light_set, light_state, discovery_list, discovery_scan, settings_update, device_add, device_update, device_remove, broker_credentials, device_pair } from './jarbis/core.uc';
import { set_unavailable } from 'uci';
let published = null;
const mock_publish = function(argv, timeout) {
    published = { argv: argv, timeout: timeout };
    return 0;
};
let pair_cleanup = [];
let invalid_state_executed = false;
const result = {
    status: status(function() { return 0; }),
    enabled: settings_update({ args: { enabled: true } }, function(argv) { return argv[1] == 'enabled' && argv[2] == '1' ? 0 : 1; }),
    invalidEnabled: settings_update({ args: { enabled: 'true' } }, function() { return 0; }),
    brokerLanError: settings_update({ args: { enabled: true } }, function() { return 1; }, function() { return 'LAN_UNAVAILABLE\n'; }),
    brokerUserError: settings_update({ args: { enabled: true } }, function() { return 1; }, function() { return 'MOSQUITTO_USER_MISSING\n'; }),
    add: device_add({ args: { id: 'tasmota_aiyato', name: 'AiYaTo Bulb', topic: 'aiyato_cb0735' } }, function(argv) { return argv[1] == 'device-add' ? 0 : 1; }),
    invalidAdd: device_add({ args: { id: '../../broken', name: 'bad', topic: 'home' } }, function() { return 0; }),
    update: device_update({ args: { id: 'living_room', name: 'Lamp', enabled: true } }, function(argv) { return argv[1] == 'device-update' ? 0 : 1; }),
    remove: device_remove({ args: { id: 'living_room' } }, function(argv) { return argv[1] == 'device-remove' ? 0 : 1; }),
    credsUnavailable: broker_credentials(function() { return null; }),
    pairInvalid: device_pair({ args: { id: '../../unsafe' } }),
    pairSuccess: device_pair({ args: { id: 'living_room', admin_password: 'admin&test', replace_existing: true } },
      function(argv, timeout) {
        if (argv[0] != '/usr/libexec/jarbis-pair' || timeout != 23000 || length(argv) != 2) return 1;
        return 0;
      }, {
        mkdtemp: function(template) { return '/tmp/jarbis-pair-ABC123'; },
        open: function(path, mode, perm) {
            if (mode != 'wx' || perm != 0o600) return null;
            return { write: function(data) { return length(data); }, close: function() { return true; } };
        },
        readfile: function(path, limit) { return 'CONNECTED\n'; },
        unlink: function(path) { return true; }, rmdir: function(path) { return true; },
      }),
    pairFailureCleanup: device_pair({ args: { id: 'living_room', admin_password: 'private' } },
      function(argv) { return 1; }, {
        mkdtemp: function() { return '/tmp/jarbis-pair-MOCK22'; },
        open: function() { return { write: function(data) { return length(data); }, close: function() { return true; } }; },
        readfile: function(path) { return 'BROKER_UNAVAILABLE\n'; },
        unlink: function(path) { push(pair_cleanup, path); return true; },
        rmdir: function(path) { push(pair_cleanup, path); return true; },
      }),
    pairCleanup: pair_cleanup,
    devices: devices_list(),
    discoveredMissing: discovery_list(),
    discovered: discovery_list(function(path, limit) {
        return 'http|192.168.1.172|40:f5:20:cb:07:35|aiyato_cb0735|AiYaTo\n' +
               'mqtt|192.168.1.172|40:f5:20:cb:07:35|aiyato_cb0735|AiYaTo\n' +
               'mqtt|192.168.1.23|aa:bb:cc:dd:ee:ff|bad/topic|NotSafe\n';
    }),
    scan: discovery_scan({}, function(argv, timeout) {
        if (timeout != 25000 || argv[0] != '/usr/libexec/jarbis-discover' || argv[1] != 'scan') return 1;
        return 0;
    }, function(path, limit) { return 'mqtt|192.168.1.172|40:f5:20:cb:07:35|aiyato_cb0735|AiYaTo\n'; }),
    scanFailed: discovery_scan({}, function(argv, timeout) { return 1; }),
    on: light_set({ args: { id: 'living_room', capability: 'power', value: 'ON' } }, mock_publish),
    publish: published,
    brightness: light_set({ args: { id: 'living_room', capability: 'brightness', value: '90' } }, mock_publish),
    color: light_set({ args: { id: 'living_room', capability: 'color', value: 'FF8800' } }, mock_publish),
    temperature: light_set({ args: { id: 'living_room', capability: 'color_temperature', value: '300' } }, mock_publish),
    badColor: light_set({ args: { id: 'living_room', capability: 'color', value: '#FF0000' } }, mock_publish),
    badCT: light_set({ args: { id: 'living_room', capability: 'color_temperature', value: '999' } }, mock_publish),
    stateInvalidId: light_state({ args: { id: '../../escape' } }, function() {
        invalid_state_executed = true;
        return 0;
    }),
    stateMissingId: light_state({ args: {} }, function() {
        invalid_state_executed = true;
        return 0;
    }),
    state: light_state({ args: { id: 'living_room' } }, function(argv, timeout) {
        return argv[0] == '/usr/libexec/jarbis-state' && timeout == 9500 ? 0 : 1;
    }, {
        mkdtemp: function() { return '/tmp/jarbis-state-MOCK12'; },
        readfile: function() { return 'ON|55|FF8800|250\n'; },
        unlink: function() { return true; }, rmdir: function() { return true; },
    }),
    stateMissing: light_state({ args: { id: 'living_room' } }, function() { return 1; }, {
        mkdtemp: function() { return '/tmp/jarbis-state-MOCK12'; },
        readfile: function() { return null; },
        unlink: function() { return true; }, rmdir: function() { return true; },
    }),
    stateInvalidExecutorCalled: invalid_state_executed,
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
def success_data(name):
    response = r.get(name)
    require(isinstance(response, dict), f'{name} RPC 응답 누락 또는 잘못된 형식: {response!r}')
    require(response.get('ok') is True,
            f'{name} RPC 실패: {response.get("error")!r}')
    data = response.get('data')
    require(isinstance(data, dict), f'{name} RPC 성공 응답의 data 누락')
    return data

def expect_error(name, code):
    response = r.get(name)
    require(isinstance(response, dict), f'{name} RPC 응답 누락 또는 잘못된 형식: {response!r}')
    require(response.get('ok') is False, f'{name} RPC 오류가 반환되지 않음')
    error = response.get('error')
    require(isinstance(error, dict) and error.get('code') == code,
            f'{name} RPC 오류 코드: {error!r} (예상: {code})')

status_data = success_data('status')
require(status_data.get('enabled') is True, 'UCI enabled 조회')
require(status_data.get('features', {}).get('ai') is False, 'AI 비활성 상태')
require(status_data.get('features', {}).get('discovery') is True, '발견 지원')
require(status_data.get('brokerMode') == 'managed', 'Broker 모드')
devices_data = success_data('devices')
devices = devices_data.get('devices')
require(isinstance(devices, list) and len(devices) == 2, 'UCI 기기 목록 개수')
require(devices[0].get('id') == 'living_room', 'UCI 기기 ID')
require(devices[0].get('capabilities') == ['power', 'brightness', 'color', 'color_temperature'], '지원 capability')
require('must-not-leak' not in json.dumps(r), 'UCI 비밀값 노출')
require(len(success_data('discoveredMissing')['devices']) == 0, '캐시 파일이 없는 경우 빈 목록 반환')
require(len(success_data('discovered')['devices']) == 1, '중복 및 위험 기기 검색 결과 필터링')
require(len(success_data('scan')['devices']) == 1, '검색 RPC 실행 및 결과 수신')
require(success_data('on').get('accepted') is True, 'request.args 기반 전원 제어')
success_data('brightness')
success_data('color')
success_data('temperature')
require(success_data('state').get('power') == 'ON', '기기 실제 전원 조회')
require(success_data('state').get('brightness') == 55, '기기 실제 밝기 조회')
require(success_data('stateMissing').get('observed') is False, '응답 없는 기기는 상태 확인 불가')
expect_error('stateInvalidId', 'INVALID_DEVICE')
expect_error('stateMissingId', 'INVALID_DEVICE')
require(r.get('stateInvalidExecutorCalled') is False, '잘못된 기기 ID에서 상태 조회 실행 금지')
expect_error('badColor', 'INVALID_VALUE')
expect_error('badCT', 'INVALID_VALUE')
require(success_data('pairSuccess').get('mqttConfirmed') is True, 'Tasmota 자동 연결 RPC 확인')
expect_error('pairInvalid', 'INVALID_DEVICE')
expect_error('pairFailureCleanup', 'BROKER_UNAVAILABLE')
require(len(r.get('pairCleanup', [])) == 6, '실패 시 모든 임시 인증 파일과 디렉터리 정리')
require(not any('private' in str(path) for path in r['pairCleanup']), '임시 경로에 비밀번호 누출 없음')
for field in ('enabled','add','update','remove'): success_data(field)
expect_error('invalidEnabled', 'INVALID_VALUE')
for key, token in [('brokerLanError', 'LAN_UNAVAILABLE'), ('brokerUserError', 'MOSQUITTO_USER_MISSING')]:
    expect_error(key, 'SETTINGS_FAILED')
    require(token in r[key]['error']['message'], f'{key}에 진단 코드 누락')
expect_error('invalidAdd', 'INVALID_DEVICE')
expect_error('credsUnavailable', 'BROKER_UNAVAILABLE')
published = r.get('publish')
require(isinstance(published, dict), '실제 MQTT 발행 호출 누락')
require(published.get('argv') == ['/usr/libexec/jarbis-control', 'light-set', 'living_room', 'power', 'ON'], '실제 발행 인수')
require(published.get('timeout') == 5000, '발행 시간 제한')
expect_error('unavailableStatus', 'CONFIG_UNAVAILABLE')
expect_error('unavailableDevices', 'CONFIG_UNAVAILABLE')
for field, error in [('topLevelOnly','INVALID_DEVICE'), ('invalidDevice','INVALID_DEVICE'),
                     ('invalidCapability','INVALID_CAPABILITY'), ('invalidValue','INVALID_VALUE'),
                     ('noArgs','INVALID_DEVICE'), ('publishFailed','PUBLISH_FAILED'), ('scanFailed','DISCOVERY_FAILED')]:
    expect_error(field, error)
PYTEST
printf 'PASS: 실제 ucode RPC 요청 인자·UCI 기기 조회·MQTT 호출 결과 검증\n'
