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
 *StatusSTS.POWER*) echo ON ;;
 *StatusSTS.Dimmer*) echo 50 ;;
 *StatusSTS.Color*) echo FF80400000 ;;
 *StatusSTS.CT*) echo 250 ;;
 *) exit 1 ;;
esac
MOCK
chmod 700 "$TMP/uci" "$TMP/mosquitto_sub" "$TMP/mosquitto_pub" "$TMP/jsonfilter"
export JARBIS_TEST_MODE=1 JARBIS_UCI_BIN="$TMP/uci" JARBIS_MQTT_PUB_BIN="$TMP/mosquitto_pub" JARBIS_MQTT_SUB_BIN="$TMP/mosquitto_sub" JARBIS_JSONFILTER_BIN="$TMP/jsonfilter"
export JARBIS_MQTT_CONFIG_DIR="$TMP/config" MOCK_SUB_LOG="$TMP/sub.log" MOCK_PUB_LOG="$TMP/pub.log"
mkdir "$JARBIS_MQTT_CONFIG_DIR"
OUTPUT="$(mktemp -d /tmp/jarbis-state-XXXXXX)"
trap 'rm -rf "$TMP" "$OUTPUT"' EXIT HUP INT TERM
sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" || fail '실기기 상태 수신 실패'
[ "$(cat "$OUTPUT/state")" = 'ON|50|FF8040|250' ] || fail 'STATUS11 검증 또는 값 변환 실패'
grep -q 'stat/tasmota_CB0735/STATUS11' "$MOCK_SUB_LOG" || fail '상태 구독 주제 오류'
grep -q -- '-m 11' "$MOCK_PUB_LOG" || fail 'STATUS11 요청 누락'
grep -q -- '-W 3' "$MOCK_SUB_LOG" || fail 'MQTT 구독 시간 제한 누락'
! grep -q -- '-W ' "$MOCK_PUB_LOG" || fail '지원하지 않는 MQTT 게시 옵션 사용'
MOCK_NO_REPLY=1; export MOCK_NO_REPLY
rm -f "$OUTPUT/state"
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '응답이 없는데 상태 수신 성공 처리'; fi
[ ! -e "$OUTPUT/state" ] || fail '실패 상태를 정상 상태로 캐시함'
unset MOCK_NO_REPLY
if sh "$ROOT/root/usr/libexec/jarbis-state" '../../bad' "$OUTPUT" >"$TMP/out" 2>"$TMP/err"; then fail '잘못된 ID 허용'; fi
if sh "$ROOT/root/usr/libexec/jarbis-state" bulb /tmp/foreign >"$TMP/out" 2>"$TMP/err"; then fail '임의 출력 경로 허용'; fi
printf 'PASS: 실제 MQTT 상태 수신·시간 제한·입력·실패 안전성 검증\n'
