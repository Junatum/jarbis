#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ ! -e "$ROOT/tests/run.sh" ] || fail 'tests/run.sh must remain removed'
[ -x "$ROOT/root/usr/libexec/jarbis-manage" ] || fail 'manage executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-broker" ] || fail 'broker executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-pair" ] && [ -x "$ROOT/root/usr/libexec/jarbis-shelly-pair" ] || fail 'pair executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-discover" ] || fail 'discover executable missing'
[ -x "$ROOT/root/etc/init.d/jarbis" ] || fail 'init executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-state" ] || fail 'jarbis-state executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-control" ] || fail 'jarbis-control executable missing'
[ -x "$ROOT/root/usr/libexec/jarbis-rpcd-reconcile" ] || fail 'rpcd reconcile helper executable missing'
[ -f "$ROOT/root/usr/share/rpcd/ucode/jarbis.uc" ] || fail 'rpcd entrypoint missing'
[ -f "$ROOT/root/usr/share/rpcd/ucode/jarbis/core.uc" ] || fail 'rpcd module missing'
[ -f "$ROOT/root/usr/share/rpcd/acl.d/jarbis.json" ] || fail 'ACL missing'
[ -f "$ROOT/root/lib/upgrade/keep.d/jarbis" ] || fail 'keep.d missing'
[ -f "$ROOT/root/etc/config/jarbis" ] || fail 'default UCI config missing'
sh -n "$ROOT/root/usr/libexec/jarbis-shelly-listen" "$ROOT/root/usr/libexec/jarbis-shelly-cache" "$ROOT/root/usr/libexec/jarbis-state" "$ROOT/root/usr/libexec/jarbis-control" "$ROOT/root/usr/libexec/jarbis-broker" "$ROOT/root/usr/libexec/jarbis-manage" "$ROOT/root/usr/libexec/jarbis-discover" "$ROOT/root/usr/libexec/jarbis-pair" "$ROOT/root/usr/libexec/jarbis-shelly-pair" "$ROOT/root/etc/init.d/jarbis" "$ROOT/root/usr/libexec/jarbis-rpcd-reconcile" || fail 'invalid router shell syntax'
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import json, re, sys
root = Path(sys.argv[1])
mk = (root / 'Makefile').read_text()
paths = {
  'root/etc/config/jarbis': 'INSTALL_CONF',
  'root/usr/libexec/jarbis-control': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-state': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-broker': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-manage': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-discover': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-pair': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-shelly-listen': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-shelly-cache': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-shelly-pair': 'INSTALL_BIN',
  'root/etc/init.d/jarbis': 'INSTALL_BIN',
  'root/usr/libexec/jarbis-rpcd-reconcile': 'INSTALL_BIN',
  'root/usr/share/rpcd/ucode/jarbis.uc': 'INSTALL_DATA',
  'root/usr/share/rpcd/ucode/jarbis/core.uc': 'INSTALL_DATA',
  'root/usr/share/rpcd/acl.d/jarbis.json': 'INSTALL_DATA',
  'root/lib/upgrade/keep.d/jarbis': 'INSTALL_DATA',
}
def require(ok, msg):
    if not ok: raise SystemExit('FAIL: ' + msg)
for path, command in paths.items():
    require((root / path).is_file(), path + ' missing')
    require(re.search(r'(?m)^\s*\$\(' + command + r'\)\s+\./' + re.escape(path) + r'\s+', mk), path + ' install action')
require('IPKG_INSTROOT' in mk and '/bin/sh /usr/libexec/jarbis-rpcd-reconcile' in mk, 'postinst runtime reconcilation')
require('DEPENDS:=+rpcd-mod-ucode +ucode-mod-uci +ucode-mod-fs +mosquitto-client-ssl +mosquitto-ssl +curl +jsonfilter' in mk, 'declared runtime dependencies')
require('PKG_LICENSE:=GPL-3.0-or-later' in mk, 'license')
acl = json.loads((root / 'root/usr/share/rpcd/acl.d/jarbis.json').read_text())
source = (root / 'root/usr/share/rpcd/ucode/jarbis.uc').read_text()
actual = set(re.findall(r'^    ([a-z_]+):\s*\{', source, flags=re.M))
read = set(acl['jarbis']['read']['ubus']['jarbis'])
write = set(acl['jarbis']['write']['ubus']['jarbis'])
require(actual == (read | write), 'RPC methods must match ACL grants exactly')
require(not (read & write), 'read/write ACL must not overlap')
require(read == {'status','devices_list','discovery_list','light_state','sensor_state'} and write == {'light_set','discovery_scan','settings_update','device_add','device_update','device_remove','broker_credentials','device_pair'}, 'unexpected RPC method privilege')
require('unauthenticated' not in json.dumps(acl), 'ACL must not grant anonymous access')
PYTEST
printf 'PASS: 패키지 설치 대상·실행 권한·RPC ACL·의존성 및 기본 보안 계약\n'
