// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import { cursor } from 'uci';
import { readfile } from 'fs';

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

export function status() {
    const cfg = config_cursor();
    if (!cfg) return failure('CONFIG_UNAVAILABLE', 'Jarbis 설정을 읽지 못했습니다.');
    try {
        return success({
            apiVersion: 1,
            version: '0.1.0-r5',
            enabled: cfg.get('jarbis', 'main', 'enabled') == '1',
            mqttConfigured: !!cfg.get('jarbis', 'broker', 'host'),
            brokerMode: cfg.get('jarbis', 'broker', 'mode') ?? 'external',
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
                enabled: dev.enabled == '1',
                capabilities: dev.kind == 'light' && dev.protocol == 'tasmota'
                    ? ['power', 'brightness'] : [],
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
    if (capability != 'power' && capability != 'brightness')
        return failure('INVALID_CAPABILITY', '지원하지 않는 기기 기능입니다.');
    if (type(value) != 'string')
        return failure('INVALID_VALUE', '제어 값이 올바르지 않습니다.');
    if (capability == 'power' && value != 'ON' && value != 'OFF')
        return failure('INVALID_VALUE', '전원 값은 ON 또는 OFF여야 합니다.');
    if (capability == 'brightness' && match(value, /^(100|[1-9]?[0-9])$/) == null)
        return failure('INVALID_VALUE', '밝기는 0부터 100 사이여야 합니다.');

    try {
        // No shell invocation, no interpolation. The CLI independently verifies UCI
        // device membership, enabled flag, allowed capability and MQTT topic.
        if (publish_light_command(id, capability, value, publisher) != 0)
            return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.');
    }
    catch (e) { return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.'); }
    return success({ accepted: true, id: id, capability: capability, value: value });
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
