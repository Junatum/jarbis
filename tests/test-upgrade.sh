#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Execute the actual Makefile postinst recipe with private mock paths. This is
# an upgrade fixture, not a substitute for a real APK upgrade on OpenWrt.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-upgrade.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/etc/config" "$TMP/etc/jarbis/sensor-cache" "$TMP/etc/mosquitto"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
[ "$1" = get ] && [ "$2" = jarbis.main.enabled ] || exit 1
cat "$JARBIS_MOCK_ENABLED"
MOCK
cat > "$TMP/bin/init" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$JARBIS_ACTIONS"
if [ "$1" = reload ]; then
 [ "${JARBIS_MOCK_FAIL_RELOAD:-0}" = 0 ] || exit 1
 printf 'r6\n' > "$JARBIS_LISTENER_RELEASE"
fi
MOCK
cat > "$TMP/rpcd-init" <<'MOCK'
#!/bin/sh
[ "$1" = -x ] || :
MOCK
cat > "$TMP/rpcd-reconcile" <<'MOCK'
#!/bin/sh
printf 'reconcile\n' >> "$JARBIS_ACTIONS"
MOCK
chmod +x "$TMP/bin/"* "$TMP/rpcd-init" "$TMP/rpcd-reconcile"
# Extract the executable script from the real package definition, replacing
# only path destinations. The conffiles stay under the temporary fixture.
python3 - "$ROOT/Makefile" "$TMP/postinst" "$TMP/bin/init" "$TMP/rpcd-init" "$TMP/rpcd-reconcile" <<'PYTEST'
from pathlib import Path
import sys
mk = Path(sys.argv[1]).read_text()
body = mk.split('define Package/jarbis/postinst\n', 1)[1].split('\nendef', 1)[0]
body = body.replace('$${', '${')
body = body.replace('/etc/init.d/jarbis', sys.argv[3])
body = body.replace('/etc/init.d/rpcd', sys.argv[4])
body = body.replace('/usr/libexec/jarbis-rpcd-reconcile', sys.argv[5])
Path(sys.argv[2]).write_text(body + '\n')
PYTEST
# Keep existing Tasmota/Shelly registrations, room, broker and auth files.
cat > "$TMP/etc/config/jarbis" <<'CONFIG'
config core 'main'
 option enabled '1'
config broker 'broker'
 option mode 'managed'
config device 'bulb'
 option kind 'light'
 option protocol 'tasmota'
config device 'shelly'
 option kind 'sensor'
 option protocol 'shelly_htg3'
 option room 'living'
CONFIG
printf '%s\n' 'password=randomly-generated-private-token' > "$TMP/etc/jarbis/device-credentials"
printf '%s\n' '-u jarbis' '-P another-private-token' > "$TMP/etc/jarbis/mosquitto_pub"
cp "$TMP/etc/jarbis/mosquitto_pub" "$TMP/etc/jarbis/mosquitto_sub"
printf '%s\n' 'jarbis:$7$hashed' > "$TMP/etc/mosquitto/jarbis.passwd"
printf '24.3|54|100|1795405327|mqtt\n' > "$TMP/etc/jarbis/sensor-cache/shelly"
chmod 600 "$TMP/etc/jarbis/device-credentials" "$TMP/etc/jarbis/mosquitto_pub" "$TMP/etc/jarbis/mosquitto_sub" "$TMP/etc/mosquitto/jarbis.passwd"
(
 cd "$TMP/etc"
 find . -type f -print | LC_ALL=C sort | xargs sha256sum > "$TMP/before.sha"
)
export JARBIS_MOCK_ENABLED="$TMP/enabled" JARBIS_ACTIONS="$TMP/actions"
export JARBIS_LISTENER_RELEASE="$TMP/active-release"
printf '1\n' > "$JARBIS_MOCK_ENABLED"
printf 'r5\n' > "$JARBIS_LISTENER_RELEASE"
PATH="$TMP/bin:$PATH"; export PATH
IPKG_INSTROOT=''; export IPKG_INSTROOT
sh "$TMP/postinst" || fail 'upgrade postinst failed'
grep -Fxq 'reload' "$JARBIS_ACTIONS" || fail 'running instance did not reload'
grep -Fxq 'reconcile' "$JARBIS_ACTIONS" || fail 'rpcd object not reconciled'
[ "$(cat "$JARBIS_LISTENER_RELEASE")" = r6 ] || fail 'new listener code not applied'
! grep -Fxq stop "$JARBIS_ACTIONS" || fail 'unnecessary full stop during upgrade'
(
 cd "$TMP/etc"
 find . -type f -print | LC_ALL=C sort | xargs sha256sum > "$TMP/after.sha"
)
cmp -s "$TMP/before.sha" "$TMP/after.sha" || fail 'existing registrations, cache or credentials changed'
: > "$JARBIS_ACTIONS"
printf '0\n' > "$JARBIS_MOCK_ENABLED"
sh "$TMP/postinst" || fail 'disabled package upgrade failed'
! grep -Fxq reload "$JARBIS_ACTIONS" || fail 'disabled service unexpectedly started'
: > "$JARBIS_ACTIONS"
IPKG_INSTROOT="$TMP/staged"; export IPKG_INSTROOT
sh "$TMP/postinst" || fail 'image-build package install failed'
[ ! -s "$JARBIS_ACTIONS" ] || fail 'staged package executed live service calls'
IPKG_INSTROOT=''; export IPKG_INSTROOT
printf '1\n' > "$JARBIS_MOCK_ENABLED"
export JARBIS_MOCK_FAIL_RELOAD=1
if sh "$TMP/postinst" > "$TMP/out" 2>&1; then fail 'failed reload was hidden by postinst'; fi
printf 'PASS: upgrade reload, config and MQTT secret preservation, disabled/staged safety, failure propagation\n'
