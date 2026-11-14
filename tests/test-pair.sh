#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/root/usr/libexec/jarbis-pair"
TMP="$(mktemp -d /tmp/jarbis-pair-tests.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin"
SECRET='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
printf 'username=jarbis\npassword=%s\n' "$SECRET" > "$TMP/credentials"
printf '%s\n' 'http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo-RGBCW' > "$TMP/discovery"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
case "$3" in
    jarbis.main.enabled) echo 1 ;;
    jarbis.broker.mode) echo managed ;;
    jarbis.broker.managed_ready) echo 1 ;;
    jarbis.broker.lan_ip) echo 192.168.1.1 ;;
    jarbis.broker.host) echo 127.0.0.1 ;;
    jarbis.broker.port) echo 1883 ;;
    jarbis.tasmota_CB0735) echo device ;;
    jarbis.tasmota_CB0735.enabled) echo 1 ;;
    jarbis.tasmota_CB0735.protocol) echo tasmota ;;
    jarbis.tasmota_CB0735.topic) echo tasmota_CB0735 ;;
    *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/broker" <<'MOCK'
#!/bin/sh
[ "$1" = check ]
MOCK
cat > "$TMP/bin/fetch" <<'MOCK'
#!/bin/sh
set -eu
form=''; out=''; url=''; redirects=0; location=0; noproxy=0
args="$*"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --data-binary) shift; form="${1#@}" ;;
        --output) shift; out="$1" ;;
        --location) location=1 ;;
        --max-redirs) shift; [ "$1" = 0 ] || exit 9; redirects=1 ;;
        --noproxy) shift; [ "$1" = '*' ] || exit 9; noproxy=1 ;;
        http://*) url="$1" ;;
    esac
    shift
done
[ "$location" = 1 ] && [ "$redirects" = 1 ] && [ "$noproxy" = 1 ] || exit 9
printf '%s\n' "$args" >> "$TEST_DIR/http-argv"
# Mocked 302: curl must fail without following a Location and leaking POST data.
[ "${MOCK_REDIRECT:-0}" != 1 ] || exit 47
[ "$url" = http://192.168.1.172/cm ] || exit 1
[ -s "$form" ] || exit 1
# Never pass secrets to the HTTP client argv / URL.
case "$args $url $out" in *0123456789abcdef*) exit 1 ;; esac
if grep -q 'cmnd=Status%200' "$form"; then
    if [ "${WEB_AUTH_FAIL:-0}" = 1 ]; then
        printf '<html>Login required</html>' > "$out"
    else
        printf '%s\n' '{"Status":{"Topic":"tasmota_CB0735"},"StatusFWR":{"Version":"16.0.0(release-zbbridge)"},"StatusNET":{"Mac":"40:F5:20:CB:07:35"},"StatusMQT":{"MqttHost":"'"${OLD_HOST:-}"'","MqttPort":1883,"MqttUser":"'"${OLD_USER:-DVES_USER}"'"}}' > "$out"
    fi
elif grep -q 'cmnd=Backlog%20' "$form"; then
    # The generated MQTT password must be present ONLY in the private POST body.
    grep -q "MqttPassword%20${SECRET}" "$form" || exit 1
    grep -q 'MqttClient%20jarbis_cb0735' "$form" || exit 1
    grep -q 'FullTopic%20%25prefix%25%2F%25topic%25%2F' "$form" || exit 1
    cp "$form" "$TEST_DIR/sent-body"
    printf '{"Backlog":"Appended"}\n' > "$out"
elif grep -q 'cmnd=Status%206' "$form"; then
    printf '%s\n' '{"StatusMQT":{"MqttHost":"192.168.1.1","MqttUser":"jarbis","MqttClient":"jarbis_cb0735","MqttPort":1883}}' > "$out"
else
    exit 1
fi
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/bin/sh
file=''; expression=''
while [ "$#" -gt 0 ]; do
    case "$1" in -i) shift; file="$1" ;; -e) shift; expression="$1" ;; esac
    shift
done
python3 - "$file" "$expression" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); k=sys.argv[2].removeprefix('@.').split('.')
    for a in k:d=d[a]
    if d is not None: print(d)
except Exception: pass
PY
MOCK
cat > "$TMP/bin/mosquitto_sub" <<'MOCK'
#!/bin/sh
for arg do
    if [ "$arg" = -W ] && [ "${SUB_NO_WAIT:-0}" = 1 ]; then exit 2; fi
done
printf 'Online\n'
MOCK
chmod +x "$TMP/bin/"*
export JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_BROKER_BIN="$TMP/bin/broker"
export JARBIS_CURL_BIN="$TMP/bin/fetch" JARBIS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export JARBIS_MQTT_SUB_BIN="$TMP/bin/mosquitto_sub"
export JARBIS_DEVICE_CREDENTIALS="$TMP/credentials" JARBIS_DISCOVERY_CACHE="$TMP/discovery"
printf "%s\n" "-u jarbis" > "$TMP/mosquitto_sub"
export JARBIS_SUB_CONFIG="$TMP/mosquitto_sub"
export TEST_DIR="$TMP" SECRET
make_request() {
    CASE_DIR="$(mktemp -d /tmp/jarbis-pair-XXXXXX)"
    printf '%s\n%s\n%s\n' "$1" "${2:-}" "${3:-0}" > "$CASE_DIR/request"
    chmod 600 "$CASE_DIR/request"
}
cleanup_request() { rm -rf "$CASE_DIR"; }
make_request tasmota_CB0735 '' 0
"$TARGET" "$CASE_DIR" || fail 'Tasmota 자동 연결 실패'
[ "$(cat "$CASE_DIR/result")" = CONNECTED ] || fail 'MQTT LWT 연결 검증'
[ -s "$TMP/sent-body" ] || fail 'HTTP POST body not sent'
! grep -F '0123456789abcdef' "$CASE_DIR/result" >/dev/null || fail 'secret in output'
cleanup_request
# Reject a device attempting to redirect the POST (including broker secret).
export MOCK_REDIRECT=1
make_request tasmota_CB0735 '' 0
if "$TARGET" "$CASE_DIR"; then fail 'HTTP 302 redirect accepted'; fi
[ "$(cat "$CASE_DIR/result")" = HTTP_UNAVAILABLE ] || fail 'redirect failure code'
cleanup_request
unset MOCK_REDIRECT
! grep -F "$SECRET" "$TMP/http-argv" >/dev/null || fail 'credential appeared in curl argv'
# If mosquitto_sub lacks -W, do not hang; preserve HTTP-configured status.
export SUB_NO_WAIT=1
make_request tasmota_CB0735 '' 0
"$TARGET" "$CASE_DIR" || fail 'unsupported MQTT -W must not block pairing'
[ "$(cat "$CASE_DIR/result")" = CONFIGURED ] || fail 'unsupported MQTT -W must not claim confirmation'
cleanup_request
unset SUB_NO_WAIT
# Foreign broker changes require explicit user consent.
make_request tasmota_CB0735 '' 0
export OLD_HOST=10.10.10.10
if "$TARGET" "$CASE_DIR"; then fail 'existing broker override not blocked'; fi
[ "$(cat "$CASE_DIR/result")" = BROKER_CONFLICT ] || fail 'broker conflict code'
cleanup_request
make_request tasmota_CB0735 '' 1
"$TARGET" "$CASE_DIR" || fail 'user-approved broker change failed'
cleanup_request
unset OLD_HOST
# Login HTML must be distinguished from a different device / topic.
make_request tasmota_CB0735 '' 0
export WEB_AUTH_FAIL=1
if "$TARGET" "$CASE_DIR"; then fail 'protected Tasmota accepted'; fi
[ "$(cat "$CASE_DIR/result")" = WEB_AUTH_REQUIRED ] || fail 'missing admin-auth signal'
cleanup_request
unset WEB_AUTH_FAIL
# Reject unregistered device IDs; no arbitrary LAN HTTP requests.
make_request ../../evil '' 1
if "$TARGET" "$CASE_DIR"; then fail 'invalid ID accepted'; fi
[ "$(cat "$CASE_DIR/result")" = INVALID_DEVICE ] || fail 'wrong invalid-ID code'
cleanup_request
# Known supported router command audit remains part of CI.
printf 'PASS: Tasmota 등록 승인·안전한 POST·MQTT 확인·기존 Broker 보호·인증 오류 테스트\n'
