// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
// Independent rpcd object: failures must never break SmartSafeHub login/status.
import { status, devices_list, light_set, light_state, sensor_state, discovery_list, discovery_scan, settings_update, device_add, device_update, device_room_set, device_remove, broker_credentials, device_pair } from './jarbis/core.uc';

const methods = {
    status: { call: function(request) { return status(); } },
    devices_list: { call: function(request) { return devices_list(); } },
    discovery_list: { call: function(request) { return discovery_list(); } },
    discovery_scan: { call: function(request) { return discovery_scan(request); } },
    settings_update: { args: { enabled: false }, call: function(request) { return settings_update(request); } },
    device_add: { args: { id: '', name: '', topic: '', protocol: '', kind: '' }, call: function(request) { return device_add(request); } },
    device_update: { args: { id: '', name: '', enabled: false }, call: function(request) { return device_update(request); } },
    device_room_set: { args: { id: '', room: '' }, call: function(request) { return device_room_set(request); } },
    device_remove: { args: { id: '' }, call: function(request) { return device_remove(request); } },
    broker_credentials: { call: function(request) { return broker_credentials(); } },
    device_pair: { args: { id: '', admin_password: '', replace_existing: false },
        call: function(request) { return device_pair(request); } },
    light_state: { args: { id: '' }, call: function(request) { return light_state(request); } },
    sensor_state: { args: { id: '' }, call: function(request) { return sensor_state(request); } },
    light_set: {
        args: { id: '', capability: '', value: '' },
        call: function(request) { return light_set(request); },
    },
};
return { jarbis: methods };
