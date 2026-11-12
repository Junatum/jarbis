// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
// Independent rpcd object: failures must never break SmartSafeHub login/status.
import { status, devices_list, light_set, discovery_list, discovery_scan } from './jarbis/core.uc';

const methods = {
    status: { call: function(request) { return status(); } },
    devices_list: { call: function(request) { return devices_list(); } },
    discovery_list: { call: function(request) { return discovery_list(); } },
    discovery_scan: { call: function(request) { return discovery_scan(request); } },
    light_set: {
        args: { id: '', capability: '', value: '' },
        call: function(request) { return light_set(request); },
    },
};
return { jarbis: methods };
