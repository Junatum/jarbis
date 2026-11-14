#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/jarbis-state-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $1" >&2; exit 1; }
cat > "$TMP/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && [ "$2" = get ] || exit 1
case "$3" in
 jarbis.main.enabled) echo 1 ;;
 jarbis.bulb) echo device ;;
 jarbis.bulb.enabled) echo 1 ;;
 jarbis.bulb.kind) echo light ;;
 jarbis.bulb.protocol) echo tasmota ;;
 jarbis.bulb.topic) echo tasmota_CB0735 ;;
 jarbis.broker.host) echo 127.0.0.1 ;;
 jarbis.broker.port) echo 1883 ;;
 jarbis.broker.lan_ip) [ "${MOCK_BAD_LAN:-0}" = 1 ] && echo 172.16.0.1 || echo 192.168.1.1 ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/mosquitto_sub" <<'MOCK'
#!/bin/sh
if [ "$1" = --help ]; then printf '%s\n' ' -W timeout'; exit 0; fi
printf '%s\n' "$*" > "$MOCK_SUB_LOG"
[ "${MOCK_NO_REPLY:-0}" != 1 ] || exit 1
printf '%s\n' '{"StatusSTS":{"POWER":"ON","Dimmer":50,"Color":"FF80400000","CT":250}}'
MOCK
cat > "$TMP/mosquitto_pub" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" > "$MOCK_PUB_LOG"
MOCK
cat > "$TMP/jsonfilter" <<'MOCK'
#!/bin/sh
case "$*" in
 *Status.Topic*) [ "${MOCK_TOPIC_MISMATCH:-0}" = 1 ] && echo wrong_device || echo tasmota_CB0735 ;;
 *StatusSTS.POWER1*) [ "${MOCK_POWER1:-0}" = 1 ] && echo ON || exit 1 ;;
 *StatusSTS.POWER*) [ "${MOCK_POWER1:-0}" = 1 ] || echo ON ;;
 *StatusSTS.Dimmer*) echo 50 ;;
 *StatusSTS.Color*) echo FF80400000 ;;
 *StatusSTS.CT*) echo 250 ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/fetch" <<'MOCK'
#!/bin/sh
[ "${MOCK_HTTP_FAILED:-0}" != 1 ] || exit 1
have_location=0; maxredirs=1; dest=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) shift; dest="$1" ;;
    --location) have_location=1 ;;
    --max-redirs) shift; maxredirs="$1" ;;
  esac
  shift
done
[ "$have_location" = 1 ] && [ "$maxredirs" = 0 ] || exit 7
[ "${MOCK_REDIRECT:-0}" != 1 ] || exit 47
printf '%s\n' '{"Status":{"Topic":"tasmota_CB0735"},"StatusSTS":{"POWER":"ON","Dimmer":50,"Color":"FF80400000","CT":250}}' > "$dest"
MOCK
chmod 700 "$TMP/uci" "$TMP/mosquitto_sub" "$TMP/mosquitto_pub" "$TMP/jsonfilter" "$TMP/fetch"
export JARBIS_TEST_MODE=1 JARBIS_UCI_BIN="$TMP/uci" JARBIS_MQTT_PUB_BIN="$TMP/mosquitto_pub" JARBIS_MQTT_SUB_BIN="$TMP/mosquitto_sub" JARBIS_JSONFILTER_BIN="$TMP/jsonfilter" JARBIS_CURL_BIN="$TMP/fetch"
export JARBIS_MQTT_CONFIG_DIR="$TMP/config" MOCK_SUB_LOG="$TMP/sub.log" MOCK_PUB_LOG="$TMP/pub.log"
mkdir "$JARBIS_MQTT_CONFIG_DIR"
export JARBIS_DISCOVERY_CACHE="$TMP/discovery.records" JARBIS_LEASE_FILE="$TMP/dhcp.leases"
printf '%s\n' '0 40:f5:20:cb:07:35 192.168.1.172 tasmota-CB0735-1845 *' > "$JARBIS_LEASE_FILE"
OUTPUT="$(mktemp -d /tmp/jarbis-state-XXXXXX)"
trap 'rm -rf "$TMP" "$OUTPUT"' EXIT HUP INT TERM
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail '실기기 상태 수신 실패'
[ "$(cat "$OUTPUT/state")" = 'ON|50|FF8040|250' ] || fail 'STATUS11 검증 또는 값 변환 실패'
[ "$(cat "$OUTPUT/source")" = mqtt ] || fail 'MQTT 응답 출처 누락'
grep -q 'stat/tasmota_CB0735/STATUS11' "$MOCK_SUB_LOG" || fail '상태 구독 주제 오류'
grep -q -- '-m 11' "$MOCK_PUB_LOG" || fail 'STATUS11 요청 누락'
grep -q -- '-W 3' "$MOCK_SUB_LOG" || fail 'MQTT 구독 시간 제한 누락'
! grep -q -- '-W ' "$MOCK_PUB_LOG" || fail '지원하지 않는 MQTT 게시 옵션 사용'
MOCK_NO_REPLY=1; export MOCK_NO_REPLY
rm -f "$OUTPUT/state" "$OUTPUT/source"
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '응답이 없는데 상태 수신 성공 처리'; fi
[ ! -e "$OUTPUT/state" ] || fail '실패 상태를 정상 상태로 캐시함'
# Live Tasmota fallback: no MQTT reply, but the registered topic matches
# a fresh read-only HTTP Status 0 response from the /24 LAN DHCP lease.
cat > "$JARBIS_DISCOVERY_CACHE" <<'RECORD'
http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo-RGBCW
RECORD
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail 'MQTT 오류 후 LAN HTTP 상태 조회 실패'
[ "$(cat "$OUTPUT/state")" = 'ON|50|FF8040|250' ] || fail 'HTTP 응답 상태 파싱 실패'
[ "$(cat "$OUTPUT/source")" = http ] || fail 'HTTP 응답 출처 누락'
# A verified HTTP bulb is checked first, without waiting for MQTT timeouts.
: > "$MOCK_SUB_LOG"
: > "$MOCK_PUB_LOG"
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail 'HTTP 우선 조회 실패'
[ ! -s "$MOCK_SUB_LOG" ] && [ ! -s "$MOCK_PUB_LOG" ] || fail 'HTTP 성공 후 불필요한 MQTT 요청 발생'
# A device-supplied redirect must be rejected, never parsed as another bulb.
MOCK_REDIRECT=1; export MOCK_REDIRECT
MOCK_NO_REPLY=1; export MOCK_NO_REPLY
rm -f "$OUTPUT/state" "$OUTPUT/source"
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then
    fail 'redirect was accepted as a bulb state'
fi
[ "$(cat "$OUTPUT/reason")" = HTTP_FETCH_FAILED ] || fail 'redirect error state missing'
unset MOCK_REDIRECT
MOCK_POWER1=1; export MOCK_POWER1
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail 'POWER1 상태 파싱 실패'
[ "$(cat "$OUTPUT/state")" = 'ON|50|FF8040|250' ] || fail 'POWER1 상태 검증 실패'
unset MOCK_POWER1
rm -f "$OUTPUT/state" "$OUTPUT/source"
MOCK_TOPIC_MISMATCH=1; export MOCK_TOPIC_MISMATCH
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '다른 Topic 장치의 상태를 허용함'; fi
[ ! -e "$OUTPUT/state" ] || fail '다른 Topic의 상태가 저장됨'
unset MOCK_TOPIC_MISMATCH
MOCK_BAD_LAN=1; export MOCK_BAD_LAN
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '다른 LAN의 상태를 허용함'; fi
unset MOCK_BAD_LAN
MOCK_HTTP_FAILED=1; export MOCK_HTTP_FAILED
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail 'HTTP 연결 실패를 성공 처리함'; fi
[ "$(cat "$OUTPUT/reason")" = HTTP_FETCH_FAILED ] || fail 'HTTP 실패 진단 코드 누락'
# An unreachable HTTP API does not prevent a valid MQTT STATUS11 response.
unset MOCK_NO_REPLY
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail 'HTTP 실패 후 MQTT 대체 조회 실패'
[ "$(cat "$OUTPUT/source")" = mqtt ] || fail 'MQTT 대체 응답 출처 누락'
MOCK_NO_REPLY=1; export MOCK_NO_REPLY
unset MOCK_HTTP_FAILED
unset MOCK_NO_REPLY
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb '../../bad'  "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '잘못된 ID 허용'; fi
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb /tmp/foreign >"$TMP/out" 2>"$TMP/err"; then fail '임의 출력 경로 허용'; fi
printf 'PASS: 실제 MQTT 및 검증된 HTTP 상태 수신·LAN 격리·시간 제한·실패 안전성 검증\n'
