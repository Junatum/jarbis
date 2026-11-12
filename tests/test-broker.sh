#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/secrets" "$TMP/mosquitto"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
case "$1" in
get) [ -f "$STATE/$2" ] || exit 1; cat "$STATE/$2" ;;
set) key="${2%%=*}"; val="${2#*=}"; printf '%s\n' "$val" > "$STATE/$key" ;;
show) [ "${CUSTOM:-0}" = 1 ] && printf '%s\n' 'mosquitto.other=listener' || : ;;
commit) printf '%s\n' "$2" >> "$COMMIT_LOG" ;;
*) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/mosquitto_passwd" <<'MOCK'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = -U ] || exit 1
sed 's/^jarbis:/jarbis:$7$sha512$/' "$2" > "$2.tmp"
mv "$2.tmp" "$2"
MOCK
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
[ "$1" = mosquitto ] && [ "${MOCK_NO_USER:-0}" = 0 ] || exit 1
MOCK
cat > "$TMP/bin/chown" <<'MOCK'
#!/bin/sh
[ "$1" = mosquitto ] && [ "${MOCK_NO_USER:-0}" = 0 ] || exit 1
MOCK
cat > "$TMP/bin/service" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$SERVICE_LOG"
MOCK
chmod 700 "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" STATE="$TMP/state" SERVICE_LOG="$TMP/actions" COMMIT_LOG="$TMP/commits"
export JARBIS_MOSQUITTO_CONF="$TMP/mosquitto/mosquitto.conf"
export JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_MOSQUITTO_INIT="$TMP/bin/service"
export JARBIS_MOSQUITTO_PASSWD_BIN="$TMP/bin/mosquitto_passwd" JARBIS_SECRET_DIR="$TMP/secrets" JARBIS_BROKER_PASS="$TMP/mosquitto/jarbis.passwd" JARBIS_TEST_MODE=1
printf '%s\n' managed > "$STATE/jarbis.broker.mode"
printf '%s\n' 0 > "$STATE/jarbis.broker.managed_ready"
printf '%s\n' 192.168.1.1 > "$STATE/network.lan.ipaddr"
# Read-only preflight: with stock mosquitto.conf and UCI mode 0 it must pass
# without writing credentials or changing the router configuration.
printf '# stock commented sample\n' > "$JARBIS_MOSQUITTO_CONF"
sh "$ROOT/root/usr/libexec/jarbis-broker" diagnose > "$TMP/diagnose" || fail '사전 진단 실패'
grep -q '^PASS: managed broker preflight' "$TMP/diagnose" || fail '진단 성공 응답 누락'
[ ! -e "$TMP/secrets/device-credentials" ] || fail '읽기 전용 진단에서 인증 정보가 생성됨'
[ ! -e "$TMP/commits" ] || fail '읽기 전용 진단에서 UCI가 변경됨'
MOCK_NO_USER=1; export MOCK_NO_USER
if sh "$ROOT/root/usr/libexec/jarbis-broker" diagnose > "$TMP/diagnose" 2> "$TMP/error"; then fail '시스템 계정 누락을 놓침'; fi
grep -q 'mosquitto user missing' "$TMP/error" || fail '시스템 계정 누락 이유 불명확'
unset MOCK_NO_USER
# Static LAN address missing: use only the logical LAN interface address.
cat > "$TMP/bin/ubus" <<'MOCK'
#!/bin/sh
[ "$1" = call ] && [ "$2" = network.interface.lan ] && [ "$3" = status ] || exit 1
printf '{"ipv4-address":[{"address":"192.168.8.1"}]}\n'
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/bin/sh
[ "$1" = -e ] && [ "$2" = '@["ipv4-address"][0].address' ] || exit 1
[ "${MOCK_NO_LAN:-0}" = 1 ] && exit 1
printf '192.168.8.1\n'
MOCK
chmod 700 "$TMP/bin/ubus" "$TMP/bin/jsonfilter"
export JARBIS_UBUS_BIN="$TMP/bin/ubus" JARBIS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
rm -f "$STATE/network.lan.ipaddr"
sh "$ROOT/root/usr/libexec/jarbis-broker" diagnose > "$TMP/diagnose" || fail '동적 LAN 진단 실패'
grep -q 'LAN 192.168.8.1' "$TMP/diagnose" || fail '동적 LAN 주소 사용 누락'
MOCK_NO_LAN=1; export MOCK_NO_LAN
if sh "$ROOT/root/usr/libexec/jarbis-broker" diagnose > "$TMP/diagnose" 2> "$TMP/error"; then fail 'LAN IP 부재 시 성공 처리'; fi
grep -q 'LAN IPv4 unavailable' "$TMP/error" || fail 'LAN IP 실패 원인 누락'
[ ! -e "$TMP/secrets/device-credentials" ] || fail 'LAN IP 검증 실패 시 인증 생성'
unset MOCK_NO_LAN
printf '%s\n' 192.168.1.1/24 > "$STATE/network.lan.ipaddr"
sh "$ROOT/root/usr/libexec/jarbis-broker" diagnose > "$TMP/diagnose" || fail 'CIDR /24 주소 진단 실패'
grep -q 'LAN 192.168.1.1,' "$TMP/diagnose" || fail 'CIDR /24 정규화 실패'
# A failed password hash must not strand credentials and block retry.
cat > "$TMP/bin/badpasswd" <<'MOCK'
#!/bin/sh
exit 1
MOCK
chmod 700 "$TMP/bin/badpasswd"
JARBIS_MOSQUITTO_PASSWD_BIN="$TMP/bin/badpasswd" sh "$ROOT/root/usr/libexec/jarbis-broker" start > "$TMP/out" 2> "$TMP/error" && fail '인증 해시 실패를 허용함'
[ ! -e "$TMP/mosquitto/jarbis.passwd" ] || fail '실패한 암호 파일을 남김'
[ ! -e "$TMP/secrets/device-credentials" ] || fail '실패한 인증 정보를 남김'
[ ! -e "$STATE/jarbis.broker.managed_ready" ] && fail '테스트 준비 상태 삭제됨'
sh "$ROOT/root/usr/libexec/jarbis-broker" start || fail '브로커 최초 설정 실패'
[ "$(cat "$STATE/mosquitto.jarbis_lan.bind_address")" = 192.168.1.1 ] || fail 'LAN 바인딩 오류'
[ "$(cat "$STATE/jarbis.broker.lan_ip")" = 192.168.1.1 ] || fail 'UI용 LAN 주소 보존 실패'
[ "$(cat "$STATE/mosquitto.jarbis_local.bind_address")" = 127.0.0.1 ] || fail 'loopback 바인딩 오류'
[ "$(cat "$STATE/mosquitto.mosquitto.allow_anonymous")" = 0 ] || fail '익명 접속 차단 실패'
[ "$(cat "$STATE/jarbis.broker.managed_ready")" = 1 ] || fail '준비 마커 없음'
[ "$(cat "$TMP/actions")" = "$(printf 'enable\nrestart')" ] || fail '서비스 실행 실패'
[ "$(LC_ALL=C ls -ld "$TMP/secrets/device-credentials" | cut -c 1-10)" = '-rw-------' ] || fail '인증파일 권한 오류'
grep -F 'jarbis:$7$sha512$' "$TMP/mosquitto/jarbis.passwd" >/dev/null || fail '해시 파일 아님'
cp "$TMP/secrets/device-credentials" "$TMP/saved"
sh "$ROOT/root/usr/libexec/jarbis-broker" start || fail '재시작 실패'
[ "$(wc -l < "$TMP/commits")" -eq 2 ] || fail '재시작 시 불필요한 flash commit'
cmp "$TMP/saved" "$TMP/secrets/device-credentials" || fail '재시작이 비밀번호를 변경함'
# Missing managed secrets or modified settings are not silently repaired.
rm -f "$TMP/secrets/mosquitto_sub"
if sh "$ROOT/root/usr/libexec/jarbis-broker" start > "$TMP/out" 2>/dev/null; then fail '분실한 인증 파일을 무시함'; fi
cp "$TMP/secrets/mosquitto_pub" "$TMP/secrets/mosquitto_sub"
printf 'unexpected\n' > "$STATE/mosquitto.mosquitto.password_file"
if sh "$ROOT/root/usr/libexec/jarbis-broker" start > "$TMP/out" 2>/dev/null; then fail '변경된 Mosquitto 설정을 덮어씀'; fi
printf '%s\n' "$JARBIS_BROKER_PASS" > "$STATE/mosquitto.mosquitto.password_file"
# Existing Mosquitto ownership is respected on a first install.
printf '%s\n' 0 > "$STATE/jarbis.broker.managed_ready"
rm -f "$TMP/secrets/device-credentials" "$TMP/secrets/mosquitto_pub" "$TMP/secrets/mosquitto_sub" "$TMP/mosquitto/jarbis.passwd"
CUSTOM=1; export CUSTOM
if sh "$ROOT/root/usr/libexec/jarbis-broker" setup > "$TMP/out" 2>/dev/null; then fail '기존 리스너를 덮어씀'; fi
[ ! -e "$TMP/secrets/device-credentials" ] || fail '기존 리스너에 자격증명을 추가함'
unset CUSTOM
printf 'listener 1883\n' > "$JARBIS_MOSQUITTO_CONF"
if sh "$ROOT/root/usr/libexec/jarbis-broker" setup > "$TMP/out" 2>/dev/null; then fail '기존 파일 기반 Mosquitto 설정을 덮어씀'; fi
printf '# commented sample only\n' > "$JARBIS_MOSQUITTO_CONF"
printf '%s\n' 1 > "$STATE/mosquitto.owrt.use_uci"
if sh "$ROOT/root/usr/libexec/jarbis-broker" setup > "$TMP/out" 2>/dev/null; then fail '기존 UCI 브로커를 덮어씀'; fi
printf 'PASS: 인증된 로컬 브로커 생성·재기동·자격 증명 보존·기존 Mosquitto 설정 보호\n'
