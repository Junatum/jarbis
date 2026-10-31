#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
KEEP="$ROOT/root/lib/upgrade/keep.d/jarbis"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -f "$KEEP" ] || fail 'keep.d for sysupgrade is missing'
[ "$(grep -v '^#' "$KEEP" | sed '/^$/d' | wc -l)" -eq 2 ] || fail 'keep.d must declare only user settings and MQTT credentials'
grep -Fxq '/etc/config/jarbis' "$KEEP" || fail 'UCI device settings must be retained'
grep -Fxq '/etc/jarbis/mosquitto_pub' "$KEEP" || fail 'MQTT credentials must be retained'
python3 - "$ROOT/Makefile" <<'PYTEST'
from pathlib import Path
import sys
makefile = Path(sys.argv[1]).read_text()
section = makefile.split('define Package/jarbis/conffiles',1)[1].split('endef',1)[0]
for path in ['/etc/config/jarbis','/etc/jarbis/mosquitto_pub']:
    if path not in section.splitlines():
        raise SystemExit('FAIL: package conffiles must retain ' + path)
PYTEST
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-keep.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/source/etc/config" "$TMP/source/etc/jarbis" "$TMP/restore"
cat > "$TMP/source/etc/config/jarbis" <<'CONFIG'
config core 'main'
    option enabled '1'
config device 'living_room'
    option kind 'light'
    option protocol 'tasmota'
    option topic 'livingroom'
CONFIG
printf '%s\n' '-u light-user' '-P secret-value-keep-private' > "$TMP/source/etc/jarbis/mosquitto_pub"
chmod 600 "$TMP/source/etc/jarbis/mosquitto_pub"
# Simulate OpenWrt archive selection from the actual sysupgrade keep.d rules.
# This fixture does not claim to replace full sysupgrade tests on a router.
while IFS= read -r path; do
    case "$path" in ''|'#'*) continue ;; esac
    [ -f "$TMP/source$path" ] || fail "missing backup fixture $path"
done < "$KEEP"
(
    cd "$TMP/source"
    tar -czf "$TMP/backup.tgz" etc/config/jarbis etc/jarbis/mosquitto_pub
)
tar -xzf "$TMP/backup.tgz" -C "$TMP/restore"
cmp "$TMP/source/etc/config/jarbis" "$TMP/restore/etc/config/jarbis" || fail 'restored devices differ'
cmp "$TMP/source/etc/jarbis/mosquitto_pub" "$TMP/restore/etc/jarbis/mosquitto_pub" || fail 'restored credentials differ'
[ "$(LC_ALL=C ls -l "$TMP/restore/etc/jarbis/mosquitto_pub" | cut -c 1-10)" = '-rw-------' ] || fail 'credential permission changed after restore fixture'
[ ! -e "$ROOT/root/etc/jarbis/mosquitto_pub" ] || fail 'credential must never be bundled in the firmware'
printf 'PASS: sysupgrade keep.d 및 conffiles, 기기·MQTT 설정 보존 모의 백업/복원\n'
