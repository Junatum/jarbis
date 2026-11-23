#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/backup" "$TMP/auth"
chmod 700 "$TMP/backup"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
case "$1" in
    get) [ -f "$STATE/$2" ] || exit 1; cat "$STATE/$2" ;;
    set) printf '%s\n' "${2#*=}" > "$STATE/${2%%=*}" ;;
    delete) rm -f "$STATE/$2" "$STATE/$2."* ;;
    commit) : ;;
    show)
        for file in "$STATE"/jarbis.*; do
            [ -f "$file" ] || continue
            name="${file##*/}"
            printf '%s=%s\n' "$name" "$(cat "$file")"
        done ;;
    *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/usr/bin/env python3
import json, sys, re
try:
    argv=sys.argv
    if argv[1]=='-i':
        data=json.load(open(argv[2],encoding='utf-8'))
        expr=argv[4]
    else: raise Exception('unsupported')
    cur=data
    for part in re.findall(r'\["([^"]+)"\]|\.?([A-Za-z_][A-Za-z_0-9]*)',expr[1:]):
        key=part[0] or part[1]
        cur=cur[key]
    if cur is None: raise Exception('null')
    print(cur)
except Exception:
    sys.exit(1)
MOCK
cat > "$TMP/bin/init" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$INIT_LOG"
MOCK
chmod 700 "$TMP/bin/"*
export STATE="$TMP/state" INIT_LOG="$TMP/init.log"
export JARBIS_TEST_MODE=1 JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export JARBIS_SENSOR_TMP_DIR="$TMP/cache" JARBIS_SENSOR_BACKUP_DIR="$TMP/backup"
export JARBIS_MANAGE_LOCK="$TMP/manage.lock" JARBIS_DISCOVERY_CACHE="$TMP/discovery"
export JARBIS_INIT_BIN="$TMP/bin/init"
PATH="$TMP/bin:$PATH"; export PATH
printf '1\n' > "$STATE/jarbis.main.enabled"
cat > "$TMP/discovery" <<'DISCOVERY'
shelly-http|192.168.1.20|aa:bb:cc:dd:ee:ff|shellyhtg3-aabbccddeeff|Shelly H&T Gen3
http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo
DISCOVERY
MANAGE="$ROOT/root/usr/libexec/jarbis-manage"
CACHE="$ROOT/root/usr/libexec/jarbis-shelly-cache"
[ -x "$MANAGE" ] && [ -x "$CACHE" ] || fail 'new helper not executable'
if sh "$MANAGE" device-add fake 'Fake' 'shellyhtg3-001122334455' shelly_htg3 >/dev/null 2>&1; then fail 'unapproved sensor registered'; fi
if sh "$MANAGE" device-add bad 'Bad' 'tasmota_CB0735' shelly_htg3 >/dev/null 2>&1; then fail 'Tasmota record registered as Shelly'; fi
if sh "$MANAGE" device-add bad 'Bad' 'shellyhtg3-aabbccddeeff' other >/dev/null 2>&1; then fail 'invalid protocol accepted'; fi
sh "$MANAGE" device-add living 'Shelly H&T Gen3' 'shellyhtg3-aabbccddeeff' shelly_htg3 || fail 'Shelly register failed'
[ "$(cat "$STATE/jarbis.living.kind")" = sensor ] || fail 'sensor kind not stored'
[ "$(cat "$STATE/jarbis.living.name")" = 'Shelly H&T Gen3' ] || fail 'Shelly name with ampersand not stored'
[ "$(cat "$STATE/jarbis.living.protocol")" = shelly_htg3 ] || fail 'sensor protocol not stored'
grep -Fx reload "$INIT_LOG" >/dev/null || fail 'reader config not reloaded on registration'
if sh "$MANAGE" device-add same 'Duplicate' 'shellyhtg3-aabbccddeeff' shelly_htg3 >/dev/null 2>&1; then fail 'duplicate accepted'; fi
sh "$MANAGE" device-add bulb 'Bulb' 'tasmota_CB0735' || fail 'Tasmota regression'
[ "$(cat "$STATE/jarbis.bulb.kind")" = light ] || fail 'Tasmota light changed kind'
[ "$(cat "$STATE/jarbis.bulb.protocol")" = tasmota ] || fail 'Tasmota protocol changed'
# Actual Shelly Gen3 NotifyFullStatus envelope; no data from other broker topics.
payload='{"src":"shellyhtg3-aabbccddeeff","dst":"shellyhtg3-aabbccddeeff/events","method":"NotifyFullStatus","params":{"temperature:0":{"id":0,"tC":23.4},"humidity:0":{"id":0,"rh":51.2},"devicepower:0":{"battery":{"percent":85}}}}'
printf '%s' "$payload" | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/events/rpc' || fail 'FullStatus not accepted'
line="$(cat "$TMP/cache/living")"
case "$line" in '23.4|51.2|85|'*) ;; *) fail "wrong full status: $line" ;; esac
[ -f "$TMP/backup/living" ] || fail 'no persistent backup'
backup_before="$(cat "$TMP/backup/living")"
# A mismatched src must not overwrite a registered sensor.
spoof='{"src":"shellyhtg3-001122334455","method":"NotifyFullStatus","params":{"temperature:0":{"tC":77}}}'
if printf '%s' "$spoof" | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/events/rpc' >/dev/null 2>&1; then fail 'mismatched source accepted'; fi
[ "$(cat "$TMP/cache/living")" = "$line" ] || fail 'spoof changed cache'
# Generic component status updates are optional. Partial updates retain others.
printf '%s' '{"id":0,"tC":25.6}' | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/temperature:0' || fail 'temperature status failed'
case "$(cat "$TMP/cache/living")" in '25.6|51.2|85|'*) ;; *) fail 'partial report destroyed preserved fields' ;; esac
[ "$(cat "$TMP/backup/living")" = "$backup_before" ] || fail 'flash cache written too frequently'
# Invalid values, oversized payloads and unregistered topics are rejected.
if printf '%s' '{"id":0,"rh":110}' | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/humidity:0' >/dev/null 2>&1; then fail 'out-of-range accepted'; fi
if printf '%s' '{"id":0,"tC":-999}' | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/temperature:0' >/dev/null 2>&1; then fail 'invalid negative accepted'; fi
if printf '%s' '{"id":0,"rh":25}' | sh "$CACHE" ingest 'shellyhtg3-001122334455/status/humidity:0' >/dev/null 2>&1; then fail 'unknown topic accepted'; fi
if printf '%05000d' 0 | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/temperature:0' >/dev/null 2>&1; then fail 'oversize accepted'; fi
rm -f "$TMP/cache/living"
printf '%s' '{"id":0,"rh":53.1}' | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/humidity:0' || fail 'backup merge failed'
case "$(cat "$TMP/cache/living")" in '23.4|53.1|85|'*) ;; *) fail 'reboot fallback did not restore fields' ;; esac
# MQTT subscriber must ignore retained messages and use fixed topic patterns.
cat > "$TMP/bin/mosquitto_sub" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" > "$SUB_ARGS"
printf '%s\n' 'shellyhtg3-aabbccddeeff/events/rpc {"src":"shellyhtg3-aabbccddeeff","method":"NotifyStatus","params":{"temperature:0":{"tC":21.1}}}'
MOCK
chmod 700 "$TMP/bin/mosquitto_sub"
printf '%s\n' '127.0.0.1' > "$STATE/jarbis.broker.host"
printf '%s\n' '1883' > "$STATE/jarbis.broker.port"
printf '%s\n' '-u jarbis' > "$TMP/auth/mosquitto_sub"
chmod 600 "$TMP/auth/mosquitto_sub"
export SUB_ARGS="$TMP/sub.args" JARBIS_MQTT_CONFIG_DIR="$TMP/auth"
export JARBIS_MQTT_SUB_BIN="$TMP/bin/mosquitto_sub" JARBIS_SHELLY_CACHE_BIN="$CACHE"
sh "$ROOT/root/usr/libexec/jarbis-shelly-listen" || fail 'MQTT listener failed'
grep -F -- '-R' "$TMP/sub.args" >/dev/null || fail 'retained MQTT messages are not excluded'
grep -F -- '+/events/rpc' "$TMP/sub.args" >/dev/null || fail 'default Shelly RPC topic not subscribed'
case "$(cat "$TMP/cache/living")" in '21.1|53.1|85|'*) ;; *) fail 'listener did not dispatch real Shelly report' ;; esac
# Removed devices must stop receiving (even while old cached data exists).
sh "$MANAGE" device-remove living || fail 'cannot remove sensor'
[ ! -e "$TMP/cache/living" ] && [ ! -e "$TMP/backup/living" ] || fail 'removed sensor cache remains'
if printf '%s' '{"id":0,"tC":21}' | sh "$CACHE" ingest 'shellyhtg3-aabbccddeeff/status/temperature:0' >/dev/null 2>&1; then fail 'removed sensor still updated'; fi
# DHCP discovery identifies only the expected awake Shelly Gen3 model + MAC.
cat > "$TMP/bin/curl" <<'MOCK'
#!/bin/sh
out=''; url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) shift; out="$1" ;;
        --max-redirs) shift; [ "$1" = 0 ] || exit 1 ;;
        http://*) url="$1" ;;
    esac
    shift
done
[ -z "${HTTP_LOG:-}" ] || printf '%s\n' "$url" >> "$HTTP_LOG"
case "$url" in
    http://192.168.1.20/rpc/Shelly.GetDeviceInfo)
        printf '%s\n' '{"id":"shellyhtg3-aabbccddeeff","app":"HTG3","model":"S3SN-0U12A","gen":3}' > "$out" ;;
    http://192.168.1.21/rpc/Shelly.GetDeviceInfo)
        printf '%s\n' '{"id":"shellyhtg3-001122334455","app":"HTG3","model":"wrong-model","gen":3}' > "$out" ;;
    *) exit 1 ;;
esac
MOCK
chmod 700 "$TMP/bin/curl"
printf '%s\n' '0 aa:bb:cc:dd:ee:ff 192.168.1.20 ShellyHTG3-AABBCCDDEEFF *' > "$TMP/leases"
printf '%s\n' '0 00:11:22:33:44:55 192.168.1.21 ShellyHTG3-001122334455 *' >> "$TMP/leases"
printf '%s\n' '1' > "$STATE/jarbis.discovery.enabled"
printf '%s\n' '192.168.1.1' > "$STATE/network.lan.ipaddr"
printf '%s\n' '255.255.255.0' > "$STATE/network.lan.netmask"
export JARBIS_LEASES="$TMP/leases" JARBIS_CURL_BIN="$TMP/bin/curl"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail 'Shelly discovery failed'
grep -Fx 'shelly-http|192.168.1.20|aa:bb:cc:dd:ee:ff|shellyhtg3-aabbccddeeff|Shelly H&T Gen3' "$TMP/discovery" >/dev/null || fail 'valid Shelly identity not discovered'
! grep -F '192.168.1.21' "$TMP/discovery" >/dev/null || fail 'wrong Shelly model accepted'
# Real field case: Shelly is asleep and its lease appears after 16 others.
# Matching hostname and MAC is sufficient for a provisional candidate only.
: > "$TMP/leases"
for n in 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37; do
    printf '0 40:f5:20:cb:07:35 192.168.1.%s ordinary-%s *\n' "$n" "$n" >> "$TMP/leases"
done
printf '0 08:3a:f2:d1:32:9c 192.168.1.209 shellyhtg3-083af2d1329c 01:08:3a:f2:d1:32:9c\n' >> "$TMP/leases"
# A claimed Shelly hostname not matching its MAC must never be offered.
printf '0 00:11:22:33:44:55 192.168.1.210 shellyhtg3-999999999999 *\n' >> "$TMP/leases"
export HTTP_LOG="$TMP/http-log"
: > "$HTTP_LOG"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail 'asleep Shelly discovery failed'
grep -Fx 'shelly-dhcp|192.168.1.209|08:3a:f2:d1:32:9c|shellyhtg3-083af2d1329c|Shelly H&T Gen3' "$TMP/discovery" >/dev/null || fail 'asleep Shelly after 16 leases not discovered'
! grep -F '192.168.1.210' "$TMP/discovery" >/dev/null || fail 'hostname-MAC mismatch shown as Shelly'
[ "$(wc -l < "$HTTP_LOG")" -le 16 ] || fail 'Shelly priority exceeded discovery HTTP budget'
sh "$MANAGE" device-add sleeping 'Shelly H&T Gen3' 'shellyhtg3-083af2d1329c' shelly_htg3 || fail 'approved DHCP-only Shelly was not registered'
[ "$(cat "$STATE/jarbis.sleeping.protocol")" = shelly_htg3 ] || fail 'sleeping Shelly registration did not persist'
printf 'PASS: Shelly 승인 등록·전체/부분 MQTT 보고·수치/소스 검증·절전 캐시·복원·Tasmota 호환\n'
