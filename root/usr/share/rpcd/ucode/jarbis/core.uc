// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import { cursor } from 'uci';
import { readfile, mkdtemp, open, unlink, rmdir } from 'fs';

export function success(data) {
    return { ok: true, data: data, error: null };
};
export function failure(code, message) {
    return { ok: false, data: null, error: { code: code, message: message } };
};

function config_cursor() {
    try { return cursor(); }
    catch (e) { return null; }
};

export function status(checker) {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', 'Jarbis 설정을 읽지 못했습니다.');
    try {
        let connected = false;
        if (cfg.get('jarbis', 'main', 'enabled') == '1') {
            try {
                connected = (type(checker) == 'function' ? checker() : system(['/usr/libexec/jarbis-broker', 'check'], 3500)) == 0;
            } catch (e) { connected = false; }
        }
        return success({
            apiVersion: 1,
            version: '0.2.1-r1',
            enabled: cfg.get('jarbis', 'main', 'enabled') == '1',
            mqttConfigured: !!cfg.get('jarbis', 'broker', 'host'),
            brokerMode: cfg.get('jarbis', 'broker', 'mode') ?? 'external',
            brokerHost: cfg.get('jarbis', 'broker', 'mode') == 'managed' ? (cfg.get('jarbis', 'broker', 'lan_ip') ?? cfg.get('network', 'lan', 'ipaddr') ?? '') : (cfg.get('jarbis', 'broker', 'host') ?? ''),
            brokerPort: cfg.get('jarbis', 'broker', 'port') ?? '1883',
            brokerReady: connected,
            features: { lightControl: true, discovery: true, mqttDiscovery: true, automation: false, ai: false },
        });
    }
    catch (e) { return failure('CONFIG_UNAVAILABLE', 'Jarbis 설정을 읽지 못했습니다.'); }
};

export function devices_list() {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', '기기 목록을 읽지 못했습니다.');
    const result = [];
    try {
        cfg.foreach('jarbis', 'device', function(dev) {
            // Never return MQTT credentials or arbitrary UCI values to the browser.
            const id = dev['.name'];
            if (type(id) != 'string') return;
            push(result, {
                id: id,
                name: dev.name ?? id,
                kind: dev.kind ?? '',
                protocol: dev.protocol ?? '',
                topic: dev.topic ?? '',
                enabled: dev.enabled == '1',
                capabilities: dev.kind == 'light' && dev.protocol == 'tasmota'
                    ? ['power', 'brightness', 'color', 'color_temperature'] : [],
            });
        });
        return success({ devices: result });
    }
    catch (e) { return failure('CONFIG_UNAVAILABLE', '기기 목록을 읽지 못했습니다.'); }
};

// rpcd method parameters are wrapped in request.args, not request itself.
// Optional publisher is internal test injection; rpcd never supplies it.
function publish_light_command(id, capability, value, publisher) {
    const command = ['/usr/libexec/jarbis-control', 'light-set', id, capability, value];
    // The test publisher exists only as an internal test seam, never a ubus argument.
    if (type(publisher) == 'function') return publisher(command, 5000);
    return system(command, 5000);
};

export function light_set(request, publisher) {
    const args = request?.args ?? {};
    const id = args.id;
    const capability = args.capability;
    const value = args.value;
    if (type(id) != 'string' || match(id, /^[A-Za-z_][A-Za-z0-9_]{0,47}$/) == null)
        return failure('INVALID_DEVICE', '기기 ID가 올바르지 않습니다.');
    if (capability != 'power' && capability != 'brightness' &&
        capability != 'color' && capability != 'color_temperature')
        return failure('INVALID_CAPABILITY', '지원하지 않는 기기 기능입니다.');
    if (type(value) != 'string')
        return failure('INVALID_VALUE', '제어 값이 올바르지 않습니다.');
    if (capability == 'power' && value != 'ON' && value != 'OFF')
        return failure('INVALID_VALUE', '전원 값은 ON 또는 OFF여야 합니다.');
    if (capability == 'brightness' && match(value, /^(100|[1-9]?[0-9])$/) == null)
        return failure('INVALID_VALUE', '밝기는 0부터 100 사이여야 합니다.');
    if (capability == 'color' && match(value, /^[0-9A-Fa-f]{6}$/) == null)
        return failure('INVALID_VALUE', '색상은 6자리 RGB 코드여야 합니다.');
    if (capability == 'color_temperature' &&
        (match(value, /^[0-9]{3}$/) == null || int(value) < 153 || int(value) > 500))
        return failure('INVALID_VALUE', '색온도는 153부터 500 mired 사이여야 합니다.');

    try {
        // No shell invocation, no interpolation. The CLI independently verifies UCI
        // device membership, enabled flag, allowed capability and MQTT topic.
        if (publish_light_command(id, capability, value, publisher) != 0)
            return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.');
    }
    catch (e) { return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.'); }
    return success({ accepted: true, id: id, capability: capability, value: value });
};

// ucode resolves functions by declaration order; declare shared ID validation
// before light_state() so RPC calls cannot reference an undeclared symbol.
function device_id(id) {
    return type(id) == 'string' && match(id, /^[A-Za-z_][A-Za-z0-9_]{0,47}$/) != null;
};

// A bounded MQTT STATUS11 query returns a fresh report from the Tasmota
// device. MQTT publication alone is never treated as a physical state change.
export function light_state(request, executor, fsops) {
    const id = request?.args?.id;
    if (!device_id(id)) return failure('INVALID_DEVICE', '기기 ID가 올바르지 않습니다.');
    const io = fsops ?? { mkdtemp: mkdtemp, readfile: readfile,
                          unlink: unlink, rmdir: rmdir };
    let path = null;
    let raw = null;
    let source = null;
    let reason = null;
    try {
        path = io.mkdtemp('/tmp/jarbis-state-XXXXXX');
        if (path) {
            const command = ['/usr/libexec/jarbis-state', id, path];
            const rc = type(executor) == 'function' ? executor(command, 9500) : system(command, 9500);
            if (rc == 0) {
                raw = trim(io.readfile(path + '/state', 128) ?? '');
                source = trim(io.readfile(path + '/source', 16) ?? '');
            } else {
                reason = trim(io.readfile(path + '/reason', 32) ?? '');
            }
        }
    } catch (e) { raw = null; }
    if (path) {
        for (let name in ['reply', 'http', 'state', 'source', 'reason']) {
            try { io.unlink(path + '/' + name); } catch (e) { /* best effort */ }
        }
        try { io.rmdir(path); } catch (e) { /* best effort */ }
    }
    const fields = split(raw ?? '', '|');
    if (length(fields) != 4 || (fields[0] != 'ON' && fields[0] != 'OFF'))
        return success({ id: id, observed: false, power: null,
                         brightness: null, color: null, colorTemperature: null, source: null,
                         reason: match(reason ?? '', /^HTTP_(NO_CANDIDATE|CLIENT_MISSING|FETCH_FAILED|INVALID_STATE)$/) != null
                             ? reason : 'STATE_TIMEOUT_OR_UNAVAILABLE' });
    const d = fields[1], c = fields[2], ct = fields[3];
    return success({
        id: id, observed: true, source: source == 'mqtt' || source == 'http' ? source : null, power: fields[0],
        brightness: match(d, /^(100|[1-9]?[0-9])$/) != null ? int(d) : null,
        color: match(c, /^[0-9A-F]{6}$/) != null ? '#' + c : null,
        colorTemperature: match(ct, /^[0-9]{3}$/) != null && int(ct) >= 153 && int(ct) <= 500 ? int(ct) : null,
    });
};

// The cache contains only validated, non-secret candidate fields. It is not a
// registry and never grants control of a discovered device.
export function discovery_list(reader) {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', '검색 설정을 읽지 못했습니다.');
    let entries = [];
    let seen = {};
    let registered = {};
    try {
        cfg.foreach('jarbis', 'device', function(dev) {
            if (type(dev.topic) == 'string' && dev.protocol == 'tasmota')
                registered[dev.topic] = true;
        });
        const raw = (type(reader) == 'function'
            ? reader('/tmp/jarbis-discovery.records', 8192)
            : readfile('/tmp/jarbis-discovery.records', 8192)) ?? '';
        for (let line in split(raw, '\n')) {
            const fields = split(line, '|');
            if (length(fields) != 5) continue;
            const source = fields[0], ip = fields[1], mac = fields[2];
            const topic = fields[3], name = fields[4];
            if (source != 'http' && source != 'mqtt') continue;
            if (topic && match(topic, /^[A-Za-z0-9_-]{1,96}$/) == null) continue;
            if (ip && match(ip, /^[0-9.]{7,15}$/) == null) continue;
            if (mac && match(mac, /^[a-fA-F0-9:]{12,17}$/) == null) continue;
            if (match(name, /^[A-Za-z0-9 _-]{1,48}$/) == null) continue;
            let key = ip || mac || topic;
            if (!key || seen[key]) continue;
            seen[key] = true;
            push(entries, { protocol: 'tasmota', source: source, ip: ip,
                            mac: mac, topic: topic, name: name, registered: !!registered[topic] });
            if (length(entries) >= 32) break;
        }
        return success({ devices: entries });
    }
    catch (e) { return failure('DISCOVERY_UNAVAILABLE', '검색 결과를 읽지 못했습니다.'); }
};

export function discovery_scan(request, scanner, reader) {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', '검색 설정을 읽지 못했습니다.');
    try {
        if (cfg.get('jarbis', 'main', 'enabled') != '1' ||
            cfg.get('jarbis', 'discovery', 'enabled') != '1')
            return failure('DISCOVERY_DISABLED', '기기 검색이 비활성화되어 있습니다.');
        const cmd = ['/usr/libexec/jarbis-discover', 'scan'];
        const rc = type(scanner) == 'function' ? scanner(cmd, 25000) : system(cmd, 25000);
        if (rc != 0) return failure('DISCOVERY_FAILED', '기기 검색을 완료하지 못했습니다.');
        return discovery_list(reader);
    }
    catch (e) { return failure('DISCOVERY_FAILED', '기기 검색을 완료하지 못했습니다.'); }
};

// All mutations use a narrow privileged CLI. Never accept a UCI path, raw MQTT
// command, arbitrary destination or shell fragment from an ubus caller.
function managed_command(args, executor) {
    const command = ['/usr/libexec/jarbis-manage'];
    for (let part in args) push(command, part);
    try {
        return (type(executor) == 'function' ? executor(command, 10000) : system(command, 10000)) == 0;
    }
    catch (e) { return false; }
};
function device_name(name) {
    return type(name) == 'string' && match(name, /^[A-Za-z0-9 _-]{1,48}$/) != null;
};
function device_topic(topic) {
    return type(topic) == 'string' && match(topic, /^[A-Za-z0-9_-]{1,96}$/) != null;
};

// Error codes are written by the privileged helper, never arbitrary stderr.
// Display only fixed user-facing messages; no MQTT secret or configuration dump.
function activation_error(reader) {
    let code = '';
    try {
        code = (type(reader) == 'function' ? reader('/tmp/jarbis-manage.error', 64)
            : readfile('/tmp/jarbis-manage.error', 64)) ?? '';
    } catch (e) { return 'Jarbis 설정을 변경하지 못했습니다. MQTT 서비스 설정을 확인해 주세요.'; }
    const messages = {
        LAN_UNAVAILABLE: 'LAN_UNAVAILABLE: 공유기 LAN IPv4 주소를 찾지 못했습니다. network.lan 설정을 확인해 주세요.',
        MOSQUITTO_USER_MISSING: 'MOSQUITTO_USER_MISSING: Mosquitto 시스템 계정이 없습니다. 설치된 패키지를 확인해 주세요.',
        PASSWORD_TOOL_MISSING: 'PASSWORD_TOOL_MISSING: mosquitto_passwd 실행 파일이 없습니다.',
        BROKER_CONFIG_CONFLICT: 'BROKER_CONFIG_CONFLICT: 기존 MQTT 설정을 보호하기 위해 시작을 중단했습니다. 외부 Broker 모드를 확인해 주세요.',
        BROKER_CREDENTIALS_CONFLICT: 'BROKER_CREDENTIALS_CONFLICT: 이전 MQTT 인증 파일이 남아 있습니다. 파일을 삭제하지 말고 상태를 확인해 주세요.',
        BROKER_CREDENTIALS_FAILED: 'BROKER_CREDENTIALS_FAILED: MQTT 인증 정보를 생성하지 못했습니다.',
        BROKER_SERVICE_FAILED: 'BROKER_SERVICE_FAILED: Mosquitto 서비스가 시작되지 않았습니다. logread를 확인해 주세요.',
        BROKER_START_FAILED: 'BROKER_START_FAILED: MQTT Broker 초기화에 실패했습니다. jarbis-broker diagnose 결과를 확인해 주세요.',
    };
    const key = trim(code);
    return messages[key] ?? 'Jarbis 설정을 변경하지 못했습니다. MQTT 서비스 설정을 확인해 주세요.';
};

export function settings_update(request, executor, errorReader) {
    const enabled = request?.args?.enabled;
    if (type(enabled) != 'bool') return failure('INVALID_VALUE', '활성화 값이 올바르지 않습니다.');
    if (!managed_command(['enabled', enabled ? '1' : '0'], executor))
        return failure('SETTINGS_FAILED', activation_error(errorReader));
    return success({ enabled: enabled });
};

export function device_add(request, executor) {
    const args = request?.args ?? {};
    if (!device_id(args.id) || !device_name(args.name) || !device_topic(args.topic))
        return failure('INVALID_DEVICE', '기기 이름, ID 또는 MQTT Topic을 확인해 주세요.');
    if (!managed_command(['device-add', args.id, args.name, args.topic], executor))
        return failure('DEVICE_ADD_FAILED', '발견한 기기를 등록하지 못했습니다. 다시 검색해 주세요.');
    return success({ id: args.id, added: true });
};

export function device_update(request, executor) {
    const args = request?.args ?? {};
    if (!device_id(args.id) || !device_name(args.name) || type(args.enabled) != 'bool')
        return failure('INVALID_DEVICE', '수정할 기기 정보를 확인해 주세요.');
    if (!managed_command(['device-update', args.id, args.name, args.enabled ? '1' : '0'], executor))
        return failure('DEVICE_UPDATE_FAILED', '기기 설정을 변경하지 못했습니다.');
    return success({ id: args.id, updated: true });
};

export function device_remove(request, executor) {
    const id = request?.args?.id;
    if (!device_id(id)) return failure('INVALID_DEVICE', '기기 ID가 올바르지 않습니다.');
    if (!managed_command(['device-remove', id], executor))
        return failure('DEVICE_REMOVE_FAILED', '기기를 삭제하지 못했습니다.');
    return success({ id: id, removed: true });
};

// Explicit opt-in secret display; excluded from status/devices/discovery.
// UI must never log or persist this response. Only used for local pairing.
export function broker_credentials(reader) {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', '설정을 읽지 못했습니다.');
    if (cfg.get('jarbis', 'broker', 'mode') != 'managed' ||
        cfg.get('jarbis', 'broker', 'managed_ready') != '1')
        return failure('BROKER_UNAVAILABLE', '관리형 MQTT Broker가 준비되지 않았습니다.');
    try {
        const content = type(reader) == 'function' ? reader('/etc/jarbis/device-credentials', 512)
            : readfile('/etc/jarbis/device-credentials', 512);
        const fields = split(content ?? '', '\n');
        if (fields[0] != 'username=jarbis' || match(fields[1] ?? '', /^password=[a-f0-9]{64}$/) == null)
            return failure('BROKER_UNAVAILABLE', 'MQTT 인증 정보를 읽지 못했습니다.');
        return success({ host: cfg.get('jarbis', 'broker', 'lan_ip') ?? cfg.get('network', 'lan', 'ipaddr') ?? '', port: '1883',
                         username: 'jarbis', secret: substr(fields[1], 9) });
    }
    catch (e) { return failure('BROKER_UNAVAILABLE', 'MQTT 인증 정보를 읽지 못했습니다.'); }
};


// Approved pairing only. The secret stays in a root-private temporary request
// file and is never exposed in command arguments or ubus responses.
// ucode supports try/catch but not JavaScript's finally statement: keep the
// actual pairing call separate so every return path reaches the cleanup below.
function pair_in_directory(io, path, id, password, replace, executor) {
    const handle = io.open(path + '/request', 'wx', 0o600);
    if (!handle) return failure('PAIR_UNAVAILABLE', '연결 요청 파일을 만들지 못했습니다.');
    const payload = id + '\n' + password + '\n' + (replace ? '1' : '0') + '\n';
    const written = handle.write(payload);
    const closed = handle.close();
    if (written != length(payload) || !closed)
        return failure('PAIR_UNAVAILABLE', '연결 요청을 안전하게 저장하지 못했습니다.');
    const command = ['/usr/libexec/jarbis-pair', path];
    const rc = type(executor) == 'function' ? executor(command, 23000) : system(command, 23000);
    const result = trim(io.readfile(path + '/result', 64) ?? '');
    if (rc == 0 && (result == 'CONNECTED' || result == 'CONFIGURED'))
        return success({ id: id, configured: true, mqttConfirmed: result == 'CONNECTED' });
    const messages = {
        WEB_AUTH_REQUIRED: '전구 관리자 인증이 필요합니다. 비밀번호를 입력해 주세요.',
        BROKER_CONFLICT: '전구가 다른 MQTT Broker에 설정되어 있습니다. 기존 연결 변경을 승인해야 합니다.',
        DEVICE_NOT_FOUND: 'HTTP로 발견된 전구가 없습니다. 다시 검색해 주세요.',
        DEVICE_MISMATCH: '전구의 Topic 또는 응답이 검색 기록과 일치하지 않습니다.',
        BROKER_UNAVAILABLE: '내장 MQTT Broker가 준비되지 않았습니다.',
        CONNECTION_PENDING: '전구 설정 후 연결 확인이 완료되지 않았습니다. 잠시 후 다시 확인해 주세요.',
        HTTP_UNAVAILABLE: '전구 관리 API에 접근하지 못했습니다.',
        HTTP_CONFIG_FAILED: '전구에 MQTT 설정을 전달하지 못했습니다.',
        UNSAFE_TARGET: '다른 네트워크로의 연결 요청을 차단했습니다.',
        INVALID_PASSWORD: '관리자 비밀번호 형식이 올바르지 않습니다.',
        INVALID_DEVICE: '등록된 Tasmota 전구가 아닙니다.',
        DISABLED: 'Jarbis가 비활성화되어 있습니다.',
    };
    return failure(result || 'PAIR_FAILED', messages[result] ?? '자동 연결이 완료되지 않았습니다. 전구 상태를 확인해 주세요.');
};

export function device_pair(request, executor, fsops) {
    const args = request?.args ?? {};
    const id = args.id;
    const password = args.admin_password ?? '';
    const replace = args.replace_existing ?? false;
    if (!device_id(id)) return failure('INVALID_DEVICE', '기기 ID가 올바르지 않습니다.');
    if (type(replace) != 'bool' || type(password) != 'string' || length(password) > 64 ||
        match(password, /^[\x20-\x7e]*$/) == null)
        return failure('INVALID_VALUE', '기기 관리자 비밀번호 형식을 확인해 주세요.');

    const io = fsops ?? { mkdtemp: mkdtemp, open: open, readfile: readfile,
                          unlink: unlink, rmdir: rmdir };
    let path = null;
    let response = null;
    try {
        path = io.mkdtemp('/tmp/jarbis-pair-XXXXXX');
        response = path
            ? pair_in_directory(io, path, id, password, replace, executor)
            : failure('PAIR_UNAVAILABLE', '안전한 임시 작업 공간을 만들지 못했습니다.');
    }
    catch (e) {
        response = failure('PAIR_FAILED', '전구 자동 연결 요청을 완료하지 못했습니다.');
    }
    // Deliberately outside try/catch: ucode has no `finally` keyword. The
    // pairing helper may return early or throw, but cleanup always runs.
    if (path) {
        for (let file in ['request', 'form', 'response', 'lwt', 'result']) {
            try { io.unlink(path + '/' + file); } catch (e) { /* ignore cleanup failures */ }
        }
        try { io.rmdir(path); } catch (e) { /* best effort */ }
    }
    return response;
};
