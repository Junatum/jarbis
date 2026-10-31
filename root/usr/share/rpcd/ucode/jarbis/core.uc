// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import { cursor } from 'uci';

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
            version: '0.1.0-r1',
            enabled: cfg.get('jarbis', 'main', 'enabled') == '1',
            mqttConfigured: !!cfg.get('jarbis', 'broker', 'host'),
            features: { lightControl: true, discovery: false, automation: false, ai: false },
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
            result.push({
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

export function light_set(request) {
    const id = request?.id;
    const capability = request?.capability;
    const value = request?.value;
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
        if (system(['/usr/libexec/jarbis-control', 'light-set', id, capability, value], 5000) != 0)
            return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.');
    }
    catch (e) { return failure('PUBLISH_FAILED', '기기 명령을 전송하지 못했습니다.'); }
    return success({ accepted: true, id: id, capability: capability, value: value });
};
