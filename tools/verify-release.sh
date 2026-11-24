#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Non-destructive smoke check on an OpenWrt router after a Jarbis upgrade.
# Prints no MQTT credentials, registered device names, or sensor measurements.
set -eu
EXPECTED='0.2.4-r1'
UBUS_BIN="${JARBIS_UBUS_BIN:-ubus}"
UCI_BIN="${JARBIS_UCI_BIN:-uci}"
JSON_BIN="${JARBIS_JSONFILTER_BIN:-jsonfilter}"
fail() { printf 'FAIL: Jarbis 0.2.4 release check: %s\n' "$1" >&2; exit 1; }
value() { printf '%s\n' "$1" | "$JSON_BIN" -e "$2" 2>/dev/null || :; }

# These calls only read Jarbis's public, authenticated status and device RPC.
status="$("$UBUS_BIN" call jarbis status '{}' 2>/dev/null)" || fail 'jarbis RPC unavailable (check rpcd)'
[ "$(value "$status" '@.ok')" = true ] || fail 'status RPC returned an error'
version="$(value "$status" '@.data.version')"
[ "$version" = "$EXPECTED" ] || fail "running RPC version is ${version:-unknown}, expected $EXPECTED"
for capability in shellyHtg3 shellyQuickPair rooms; do
    [ "$(value "$status" "@.data.features.$capability")" = true ] ||
        fail "required 0.2.4 feature $capability is unavailable"
done

list="$("$UBUS_BIN" call jarbis devices_list '{}' 2>/dev/null)" || fail 'devices_list RPC unavailable'
[ "$(value "$list" '@.ok')" = true ] || fail 'devices_list RPC returned an error'

enabled="$(value "$status" '@.data.enabled')"
ready="$(value "$status" '@.data.brokerReady')"
mode="$(value "$status" '@.data.brokerMode')"
if [ "$enabled" = true ] && [ "$ready" != true ]; then
    fail 'Jarbis is enabled but the MQTT broker is not ready'
fi

# Do not poll any sensor while the feature is disabled or no active sensor
# exists. An unread measurement is normal for a newly added sleeping device.
sensors=0
if [ "$enabled" = true ]; then
    for id in $("$UCI_BIN" -q show jarbis 2>/dev/null |
        sed -n 's/^jarbis\.\([A-Za-z_][A-Za-z0-9_]*\)=device$/\1/p'); do
        [ "$("$UCI_BIN" -q get "jarbis.$id.enabled" 2>/dev/null || :)" = 1 ] || continue
        [ "$("$UCI_BIN" -q get "jarbis.$id.kind" 2>/dev/null || :)" = sensor ] || continue
        [ "$("$UCI_BIN" -q get "jarbis.$id.protocol" 2>/dev/null || :)" = shelly_htg3 ] || continue
        sensors=$((sensors + 1))
        # ID was read from validated UCI section name, not an MQTT topic.
        result="$("$UBUS_BIN" call jarbis sensor_state "{\"id\":\"$id\"}" 2>/dev/null)" || fail 'sensor_state RPC unavailable'
        [ "$(value "$result" '@.ok')" = true ] || fail 'registered sensor_state RPC returned an error'
    done
fi
printf 'PASS: Jarbis %s RPC, devices_list, broker %s/%s, active sensors %s (read-only)\n' \
    "$version" "${mode:-unknown}" "${ready:-unknown}" "$sensors"
