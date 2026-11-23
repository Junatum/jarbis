#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run the real init start_service and management scripts with isolated mocks.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-life.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/cache" "$TMP/backup"
chmod 700 "$TMP/cache" "$TMP/backup"
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
   printf '%s=%s\n' "${file##*/}" "$(cat "$file")"
  done ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/broker" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$BROKER_LOG"
case "$1" in check|start|stop) : ;; *) exit 1 ;; esac
MOCK
cat > "$TMP/bin/init" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$1" >> "$INIT_LOG"
[ "$1" = reload ] || exit 1
[ "${RELOAD_FAIL:-0}" = 0 ] || exit 1
# Mimic procd's replacement of declared instances (do not run services).
procd_open_instance() { printf 'shelly\n' > "$INSTANCE_FILE"; }
procd_set_param() { :; }
procd_close_instance() { :; }
: > "$INSTANCE_FILE"
. "$JARBIS_INIT_SOURCE"
start_service
MOCK
chmod 700 "$TMP/bin/"*
export STATE="$TMP/state" BROKER_LOG="$TMP/broker.log" INIT_LOG="$TMP/init.log"
export INSTANCE_FILE="$TMP/instances" JARBIS_INIT_SOURCE="$ROOT/root/etc/init.d/jarbis"
export JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_BROKER_BIN="$TMP/bin/broker"
export JARBIS_INIT_BIN="$TMP/bin/init" JARBIS_MANAGE_LOCK="$TMP/manage.lock"
export JARBIS_DISCOVERY_CACHE="$TMP/discovery" JARBIS_TEST_MODE=1
export JARBIS_SENSOR_TMP_DIR="$TMP/cache" JARBIS_SENSOR_BACKUP_DIR="$TMP/backup"
PATH="$TMP/bin:$PATH"; export PATH
printf '1\n' > "$STATE/jarbis.main.enabled"
printf 'managed\n' > "$STATE/jarbis.broker.mode"
cat > "$TMP/discovery" <<'DISC'
shelly-dhcp|192.168.1.209|08:3a:f2:d1:32:9c|shellyhtg3-083af2d1329c|Shelly H&T Gen3
shelly-http|192.168.1.210|aa:bb:cc:dd:ee:ff|shellyhtg3-aabbccddeeff|Shelly H&T Gen3
http|192.168.1.172|40:f5:20:cb:07:35|tasmota_CB0735|AiYaTo
DISC
MANAGE="$ROOT/root/usr/libexec/jarbis-manage"
# The zero-sensor case must not declare a subscriber.
sh "$TMP/bin/init" reload || fail 'initial broker-only reload failed'
[ ! -s "$INSTANCE_FILE" ] || fail 'subscriber started with zero sensors'
sh "$MANAGE" device-add bulb AiYaTo tasmota_CB0735 || fail 'light registration failed'
[ ! -s "$INSTANCE_FILE" ] || fail 'light-only subscription started'
sh "$MANAGE" device-add first 'Shelly H&T Gen3' shellyhtg3-083af2d1329c shelly_htg3 || fail 'first sensor registration'
[ "$(cat "$INSTANCE_FILE")" = shelly ] || fail 'reader missing with one active sensor'
sh "$MANAGE" device-add second 'Shelly H&T Gen3' shellyhtg3-aabbccddeeff shelly_htg3 || fail 'second sensor registration'
[ "$(cat "$INSTANCE_FILE")" = shelly ] || fail 'two sensors spawned extra reader'
for id in first second; do
 printf '24|55|100|1795405327|mqtt\n' > "$TMP/cache/$id"
 printf '24|55|100|1795405327|mqtt\n' > "$TMP/backup/$id"
done
sh "$MANAGE" device-update first 'Shelly H&T Gen3' 0 || fail 'first sensor disable failed'
[ "$(cat "$INSTANCE_FILE")" = shelly ] || fail 'remaining sensor lost reader'
[ -f "$TMP/cache/first" ] || fail 'disable should preserve sensor reading'
sh "$MANAGE" device-update second 'Shelly H&T Gen3' 0 || fail 'second disable failed'
[ ! -s "$INSTANCE_FILE" ] || fail 'last disabled sensor still has reader'
sh "$MANAGE" device-update first 'Shelly H&T Gen3' 1 || fail 'sensor re-enable failed'
[ "$(cat "$INSTANCE_FILE")" = shelly ] || fail 'reader not recreated on re-enable'
sh "$MANAGE" device-remove first || fail 'sensor removal failed'
[ ! -s "$INSTANCE_FILE" ] || fail 'reader remains when no active sensor'
[ ! -e "$TMP/cache/first" ] && [ ! -e "$TMP/backup/first" ] || fail 'deleted sensor cache remains'
[ -f "$TMP/cache/second" ] && [ -f "$TMP/backup/second" ] || fail 'other sensor cache removed'
sh "$MANAGE" device-update second 'Shelly H&T Gen3' 1 || fail 'last remaining sensor activation failed'
[ "$(cat "$INSTANCE_FILE")" = shelly ] || fail 'last sensor activation missing reader'
# A held writer lock must delay deletion, with no stale report after removal.
mkdir "$TMP/cache/.second.lock"
sh "$MANAGE" device-remove second > "$TMP/remove.log" 2>&1 &
remove_pid=$!
sleep 0.2
[ -f "$STATE/jarbis.second" ] || fail 'removed sensor despite an in-flight writer'
rmdir "$TMP/cache/.second.lock"
wait "$remove_pid" || fail 'locked sensor remove failed'
[ ! -e "$TMP/cache/second" ] && [ ! -e "$TMP/backup/second" ] || fail 'removed cache was recreated'
[ ! -s "$INSTANCE_FILE" ] || fail 'reader not stopped after last deletion'
[ -f "$STATE/jarbis.bulb" ] || fail 'Tasmota device changed'
! grep -Fx stop "$BROKER_LOG" >/dev/null || fail 'reload stopped shared broker'
! grep -Fx start "$BROKER_LOG" >/dev/null || fail 'reload restarted working broker'
# Failed reloads must not silently commit device additions or enabled changes.
export RELOAD_FAIL=1
if sh "$MANAGE" device-add failed 'Shelly H&T Gen3' shellyhtg3-083af2d1329c shelly_htg3 > /dev/null 2>&1; then fail 'reload failure was hidden during add'; fi
[ ! -e "$STATE/jarbis.failed" ] || fail 'failed registration did not roll back'
unset RELOAD_FAIL
sh "$MANAGE" device-add recovered 'Shelly H&T Gen3' shellyhtg3-083af2d1329c shelly_htg3 || fail 'add after failed reload'
export RELOAD_FAIL=1
if sh "$MANAGE" device-update recovered 'Shelly H&T Gen3' 0 > /dev/null 2>&1; then fail 'reload failure was hidden during update'; fi
[ "$(cat "$STATE/jarbis.recovered.enabled")" = 1 ] || fail 'failed update was not rolled back'
printf 'PASS: procd lifecycle, zero-sensor footprint, no broker disruption, cache lock/cleanup, rollback\n'
