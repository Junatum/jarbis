#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
cat > "$TMP/uci" <<'MOCK'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = 'get' ] || exit 1
case "$3" in
    jarbis.main.enabled) printf '%s\n' "${MOCK_ENABLED:-1}" ;;
    jarbis.living_room) printf 'device\n' ;;
    jarbis.living_room.enabled) printf '1\n' ;;
    jarbis.living_room.kind) printf 'light\n' ;;
    jarbis.living_room.protocol) printf 'tasmota\n' ;;
    jarbis.living_room.topic) printf '%s\n' "${MOCK_TOPIC:-livingroom}" ;;
    jarbis.broker.host) printf '%s\n' "${MOCK_HOST:-127.0.0.1}" ;;
    jarbis.broker.port) printf '%s\n' "${MOCK_PORT:-1883}" ;;
    *) exit 1 ;;
esac
MOCK
cat > "$TMP/mosquitto_pub" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" > "$MOCK_PUBLISH_LOG"
MOCK
chmod 700 "$TMP/uci" "$TMP/mosquitto_pub"
export MOCK_PUBLISH_LOG="$TMP/published"
export JARBIS_UCI_BIN="$TMP/uci" JARBIS_MQTT_PUB_BIN="$TMP/mosquitto_pub"
export JARBIS_MQTT_CONFIG_DIR="$TMP/mqttconfig" JARBIS_TEST_MODE=1
mkdir -p "$JARBIS_MQTT_CONFIG_DIR"

control="$ROOT/root/usr/libexec/jarbis-control"
sh -n "$control" || fail '셸 문법 오류'
sh "$control" light-set living_room power ON || fail '켜기 명령 실패'
grep -F -- '-t cmnd/livingroom/POWER -m ON' "$MOCK_PUBLISH_LOG" >/dev/null || fail '전원 토픽 오류'
sh "$control" light-set living_room brightness 50 || fail '밝기 명령 실패'
grep -F -- '-t cmnd/livingroom/Dimmer -m 50' "$MOCK_PUBLISH_LOG" >/dev/null || fail '밝기 토픽 오류'

must_reject() {
    rm -f "$MOCK_PUBLISH_LOG"
    if sh "$control" "$@" >"$TMP/stdout" 2>"$TMP/stderr"; then
        fail "잘못된 입력을 허용했습니다: $*"
    fi
    [ ! -e "$MOCK_PUBLISH_LOG" ] || fail '실패한 명령이 MQTT 게시까지 실행되었습니다'
}

# 기능/권한/입력 방어 계약
must_reject light-set missing power ON
must_reject light-set 'living_room;reboot' power ON
must_reject light-set living_room power TOGGLE
must_reject light-set living_room brightness 101
must_reject light-set living_room brightness 050
must_reject light-set living_room brightness -1
must_reject light-set living_room brightness '1;touch /tmp/pwned'
must_reject light-set living_room color red
must_reject execute living_room power ON
MOCK_ENABLED=0; export MOCK_ENABLED
must_reject light-set living_room power ON
unset MOCK_ENABLED
MOCK_TOPIC='foo/../../bad'; export MOCK_TOPIC
must_reject light-set living_room power ON
unset MOCK_TOPIC
MOCK_PORT=99999; export MOCK_PORT
must_reject light-set living_room power ON
unset MOCK_PORT
MOCK_HOST='-malicious'; export MOCK_HOST
must_reject light-set living_room power ON
unset MOCK_HOST

# 인증 파일은 root만 읽을 수 있어야 하고 명령 인자로 노출되면 안 됩니다.
printf '%s\n' '-u myuser' '-P secret' > "$JARBIS_MQTT_CONFIG_DIR/mosquitto_pub"
chmod 644 "$JARBIS_MQTT_CONFIG_DIR/mosquitto_pub"
must_reject light-set living_room power ON
chmod 600 "$JARBIS_MQTT_CONFIG_DIR/mosquitto_pub"
sh "$control" light-set living_room power OFF || fail '안전한 MQTT 인증 파일을 사용하지 못했습니다'
! grep -F 'secret' "$MOCK_PUBLISH_LOG" >/dev/null || fail '명령 인자에 비밀번호가 노출되었습니다'

printf 'PASS: Tasmota 명령, 주제 및 인증·입력 검증 테스트\n'
