#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/auth"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && [ "$2" = get ] || exit 1
case "$3" in
 jarbis.main.enabled|jarbis.discovery.enabled) printf '1\n' ;;
 network.lan.ipaddr) printf '%s\n' "${TEST_LAN:-192.168.1.1}" ;;
 network.lan.netmask) [ "${TEST_MASK:-255.255.255.0}" = missing ] || printf '%s\n' "${TEST_MASK:-255.255.255.0}" ;;
 jarbis.broker.host) printf '127.0.0.1\n' ;;
 jarbis.broker.port) printf '1883\n' ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/bin/sh
args="$*"; out=''; location=0; redirects=1
printf '%s\n' "$args" >> "$HTTP_LOG"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) shift; out="$1" ;;
        --location) location=1 ;;
        --max-redirs) shift; redirects="$1" ;;
    esac
    shift
done
[ "$location" = 1 ] && [ "$redirects" = 0 ] || exit 7
[ "${MOCK_REDIRECT:-0}" != 1 ] || exit 47
case "$args" in
 *192.168.1.172*) printf '%s\n' '{"Status":{"DeviceName":"AiYaTo-RGBCW","Topic":"tasmota_CB0735"},"StatusFWR":{"Version":"16.0.0(release-zbbridge)"},"StatusMQT":{"MqttHost":"192.168.1.1"}}' > "$out" ;;
 *) printf '%s\n' '{"StatusFWR":{"Version":"unknown"}}' > "$out" ;;
esac
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/bin/sh
case "$1" in
-i)
    grep -q 'AiYaTo' "$2" || exit 1
    case "$4" in
        @.StatusFWR.Version) printf '16.0.0(release-zbbridge)\n' ;;
        @.Status.Topic) printf 'tasmota_CB0735\n' ;;
        @.Status.DeviceName) printf 'AiYaTo-RGBCW\n' ;;
    esac ;;
-s)
    case "$2" in
        *aiyato_cb0735*)
            case "$4" in
                @.t) printf 'aiyato_cb0735\n' ;;
                @.ft) printf '%%prefix%%/%%topic%%/\n' ;;
                @.ip) printf '192.168.1.172\n' ;;
                @.mac) printf '40:F5:20:CB:07:35\n' ;;
                @.dn) printf 'AiYaTo\n' ;;
            esac ;;
        *unsafe/topic*)
            case "$4" in
                @.t) printf 'unsafe/topic\n' ;;
                @.ft) printf '%%prefix%%/%%topic%%/\n' ;;
            esac ;;
        *wrongtopic*)
            case "$4" in
                @.t) printf 'wrongtopic\n' ;;
                @.ft) printf 'other/%%topic%%/\n' ;;
            esac ;;
    esac ;;
esac
MOCK
cat > "$TMP/bin/mosquitto_sub" <<'MOCK'
#!/bin/sh
printf '%s\n' 'tasmota/discovery/40F520CB0735/config {"t":"aiyato_cb0735","ft":"%prefix%/%topic%/","ip":"192.168.1.172","mac":"40:F5:20:CB:07:35","dn":"AiYaTo"}'
printf '%s\n' 'tasmota/discovery/ABCD/config {"t":"unsafe/topic","ft":"%prefix%/%topic%/","ip":"10.0.0.2","dn":"Invalid"}'
printf '%s\n' 'tasmota/discovery/EFGH/config {"t":"wrongtopic","ft":"other/%topic%/","ip":"192.168.1.55","dn":"Invalid"}'
MOCK
chmod 700 "$TMP/bin/"*
printf '%s\n' '-u jarbis' '-P test-only' > "$TMP/auth/mosquitto_sub"
chmod 600 "$TMP/auth/mosquitto_sub"
# 18 candidates; bounded to the first 16 valid /24 lease addresses.
for n in 172 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191; do
    printf '0 40:f5:20:cb:07:35 192.168.1.%s host *\n' "$n"
done > "$TMP/leases"
printf '0 aa:bb:cc:dd:ee:ff 10.0.0.4 bad *\n' >> "$TMP/leases"
export HTTP_LOG="$TMP/http-log" JARBIS_TEST_MODE=1 JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_CURL_BIN="$TMP/bin/curl" JARBIS_MQTT_SUB_BIN="$TMP/bin/mosquitto_sub" JARBIS_LEASES="$TMP/leases" JARBIS_DISCOVERY_CACHE="$TMP/cache" JARBIS_MQTT_CONFIG_DIR="$TMP/auth"
PATH="$TMP/bin:$PATH"; export PATH
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail '자동 검색 실패'
[ "$(wc -l < "$TMP/http-log")" -eq 16 ] || fail 'HTTP 요청 수 제한 위반'
# Mocked 302 must not create a false discovery candidate.
MOCK_REDIRECT=1; export MOCK_REDIRECT
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail 'redirect response caused discovery failure'
! grep -F 'http|' "$TMP/cache" >/dev/null || fail 'redirect response accepted as HTTP discovery'
unset MOCK_REDIRECT
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail 'restoring normal discovery after redirect failed'
grep -Fx 'http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo-RGBCW' "$TMP/cache" >/dev/null || fail 'HTTP Tasmota 식별 실패'
grep -Fx 'mqtt|192.168.1.172|40:F5:20:CB:07:35|aiyato_cb0735|AiYaTo' "$TMP/cache" >/dev/null || fail 'MQTT retained discovery 실패'
! grep -F 'wrongtopic' "$TMP/cache" >/dev/null || fail '비표준 FullTopic 허용'
! grep -F 'unsafe/topic' "$TMP/cache" >/dev/null || fail '위험한 topic 허용'
# Real field report: OpenWrt stores a /24 CIDR in ipaddr and omits netmask;
# Tasmota version is 'release-zbbridge', not a string containing 'tasmota'.
TEST_LAN=192.168.1.1/24 TEST_MASK=missing; export TEST_LAN TEST_MASK
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail 'CIDR /24 주소에서 자동 검색 실패'
grep -Fx 'http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo-RGBCW' "$TMP/cache" >/dev/null || fail '실기기 응답 형식을 식별하지 못함'
[ "$(wc -l < "$TMP/http-log")" -eq 16 ] || fail 'CIDR 검색에서 HTTP 개수 제한 위반'
TEST_LAN=192.168.1.1/16
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail '비지원 CIDR에서 안전 검색 실패'
[ ! -s "$TMP/http-log" ] || fail '/16 네트워크에서 자동 HTTP 검색 수행'
TEST_LAN=192.168.1.1 TEST_MASK=missing
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail '마스크 없는 비CIDR 네트워크에서 안전 검색 실패'
[ ! -s "$TMP/http-log" ] || fail '마스크 없는 주소에서 무단 HTTP 검색 수행'
TEST_LAN=192.168.1.1 TEST_MASK=255.255.0.0
: > "$TMP/http-log"
sh "$ROOT/root/usr/libexec/jarbis-discover" scan || fail '비지원 네트워크에서 안전 검색 실패'
[ ! -s "$TMP/http-log" ] || fail '/24 아닌 LAN에서 자동 HTTP 검색 수행'
printf 'PASS: CIDR /24·실제 Tasmota 16 응답·16대 후보 제한·MQTT Discovery 검증\n'
