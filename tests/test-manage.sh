#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/state" "$TMP/bin"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
case "$1" in
    get) [ -f "$STATE/$2" ] || exit 1; cat "$STATE/$2" ;;
    set)
        key="${2%%=*}"; val="${2#*=}"
        printf '%s\n' "$val" > "$STATE/$key"
        ;;
    delete) rm -f "$STATE/$2" "$STATE/$2."* ;;
    show)
        for file in "$STATE"/jarbis.*; do
            [ -f "$file" ] || continue
            name="${file##*/}"
            printf '%s=%s\n' "$name" "$(cat "$file")"
        done
        ;;
    commit) printf '%s\n' "$2" >> "$COMMITS" ;;
    *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/broker" <<'MOCK'
#!/bin/sh
[ "$1" = start ] || exit 1
[ "${BROKER_FAIL:-0}" = 0 ] || exit 1
printf '%s\n' start >> "$ACTIONS"
MOCK
chmod +x "$TMP/bin/"*
export STATE="$TMP/state" COMMITS="$TMP/commits" ACTIONS="$TMP/actions"
export JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_BROKER_BIN="$TMP/bin/broker"
export JARBIS_DISCOVERY_CACHE="$TMP/discovery" JARBIS_MANAGE_LOCK="$TMP/lock"
CLI="$ROOT/root/usr/libexec/jarbis-manage"
printf 'managed\n' > "$STATE/jarbis.broker.mode"
printf '0\n' > "$STATE/jarbis.main.enabled"
BROKER_FAIL=1; export BROKER_FAIL
if sh "$CLI" enabled 1 > /dev/null 2>&1; then fail 'Broker 오류인데 활성화됨'; fi
[ "$(cat "$STATE/jarbis.main.enabled")" = 0 ] || fail '실패 시 enabled 변경됨'
BROKER_FAIL=0; export BROKER_FAIL
sh "$CLI" enabled 1 || fail '활성화 실패'
[ "$(cat "$STATE/jarbis.main.enabled")" = 1 ] || fail '활성화 상태 누락'
[ "$(cat "$ACTIONS")" = start ] || fail 'Broker 시작 누락'
sh "$CLI" enabled 0 || fail '비활성화 실패'
[ "$(cat "$STATE/jarbis.main.enabled")" = 0 ] || fail '비활성화 상태 누락'
[ "$(cat "$ACTIONS")" = start ] || fail '공유 Broker를 중지함'
sh "$CLI" enabled 1 || fail '재활성화 실패'
cat > "$TMP/discovery" <<'CACHE'
http|192.168.1.172|40:f5:20:cb:07:35|aiyato_cb0735|AiYaTo
CACHE
if sh "$CLI" device-add evil 'Bad device' 'other_topic' >/dev/null 2>&1; then fail '검색하지 않은 Topic 등록'; fi
if sh "$CLI" device-add '../../evil' 'Bad' 'aiyato_cb0735' >/dev/null 2>&1; then fail '위험 ID 등록'; fi
if sh "$CLI" device-add bulb 'Bad|Name' 'aiyato_cb0735' >/dev/null 2>&1; then fail '위험 이름 등록'; fi
sh "$CLI" device-add bulb 'AiYaTo Bulb' 'aiyato_cb0735' || fail '기기 등록 실패'
[ "$(cat "$STATE/jarbis.bulb.topic")" = aiyato_cb0735 ] || fail 'Topic 설정 누락'
if sh "$CLI" device-add bulb2 'Another Bulb' 'aiyato_cb0735' >/dev/null 2>&1; then fail '중복 Topic 허용'; fi
sh "$CLI" device-update bulb 'Kitchen Bulb' 0 || fail '기기 비활성화 실패'
[ "$(cat "$STATE/jarbis.bulb.enabled")" = 0 ] || fail '기기 비활성화 누락'
if sh "$CLI" device-update bulb 'Broken' bogus >/dev/null 2>&1; then fail '잘못된 enabled 허용'; fi
sh "$CLI" device-remove bulb || fail '기기 삭제 실패'
[ ! -e "$STATE/jarbis.bulb" ] || fail '기기 삭제 후 UCI 섹션 잔존'
[ ! -d "$TMP/lock" ] || fail '관리 락 미해제'
printf 'PASS: Broker 시작 실패 보호, 승인된 MQTT Topic 등록, 중복·입력 검증 및 삭제\n'
