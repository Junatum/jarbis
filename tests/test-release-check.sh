#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Smoke-check test uses private mocks; never contacts a live router.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-release.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ubus" <<'MOCK'
#!/bin/sh
[ "$1" = call ] && [ "$2" = jarbis ] || exit 1
printf '%s\n' "$3" >> "$JARBIS_TEST_LOG"
case "$3" in
 status)
  printf '{"ok":true,"data":{"version":"%s","enabled":%s,"brokerReady":%s,"brokerMode":"managed","features":{"shellyHtg3":true,"shellyQuickPair":%s,"rooms":true}}}\n' \
    "${JARBIS_MOCK_VERSION:-0.2.4-r1}" "${JARBIS_MOCK_ENABLED:-true}" "${JARBIS_MOCK_READY:-true}" "${JARBIS_MOCK_CAPABILITY:-true}" ;;
 devices_list) printf '%s\n' '{"ok":true,"data":{"devices":[]}}' ;;
 sensor_state) printf '%s\n' '{"ok":true,"data":{"observed":false}}' ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
case "$1" in
 show) [ "$2" = jarbis ] || exit 1
  if [ "${JARBIS_MOCK_SENSOR:-0}" = 1 ]; then printf 'jarbis.living=device\n'; fi ;;
 get)
  case "$2" in
   jarbis.living.enabled) printf '1\n' ;;
   jarbis.living.kind) printf 'sensor\n' ;;
   jarbis.living.protocol) printf 'shelly_htg3\n' ;;
   *) exit 1 ;;
  esac ;;
 *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/usr/bin/env python3
import json, sys
try:
    assert sys.argv[1] == '-e'
    value = json.load(sys.stdin)
    for key in sys.argv[2].removeprefix('@.').split('.'):
        value = value[key]
    print(str(value).lower() if isinstance(value, bool) else value)
except Exception:
    sys.exit(1)
MOCK
chmod +x "$TMP/bin/"*
export JARBIS_UBUS_BIN="$TMP/bin/ubus"
export JARBIS_UCI_BIN="$TMP/bin/uci"
export JARBIS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export JARBIS_TEST_LOG="$TMP/log"
CHECK="$ROOT/tools/verify-release.sh"
[ -x "$CHECK" ] || fail 'release verifier not executable'
: > "$JARBIS_TEST_LOG"
sh "$CHECK" > "$TMP/out" || fail 'zero-sensor release verification failed'
grep -Fq 'active sensors 0' "$TMP/out" || fail 'empty sensor result missing'
! grep -Fq sensor_state "$JARBIS_TEST_LOG" || fail 'sensor state queried without a sensor'
: > "$JARBIS_TEST_LOG"
export JARBIS_MOCK_SENSOR=1
sh "$CHECK" > "$TMP/out" || fail 'registered sensor release verification failed'
grep -Fq 'active sensors 1' "$TMP/out" || fail 'registered sensor count missing'
[ "$(grep -cx sensor_state "$JARBIS_TEST_LOG")" -eq 1 ] || fail 'sensor_state should only be called once'
: > "$JARBIS_TEST_LOG"
export JARBIS_MOCK_ENABLED=false
sh "$CHECK" > "$TMP/out" || fail 'disabled service release verification failed'
! grep -Fq sensor_state "$JARBIS_TEST_LOG" || fail 'disabled service queried sensors'
export JARBIS_MOCK_ENABLED=true
export JARBIS_MOCK_READY=false
if sh "$CHECK" > "$TMP/out" 2> "$TMP/err"; then fail 'unavailable broker was accepted'; fi
grep -Fq 'broker is not ready' "$TMP/err" || fail 'broker failure reason missing'
export JARBIS_MOCK_READY=true
export JARBIS_MOCK_CAPABILITY=false
if sh "$CHECK" > "$TMP/out" 2> "$TMP/err"; then fail 'missing 0.2.4 capability was accepted'; fi
grep -Fq 'shellyQuickPair is unavailable' "$TMP/err" || fail 'capability failure reason missing'
export JARBIS_MOCK_CAPABILITY=true
export JARBIS_MOCK_VERSION=0.2.3-r6
if sh "$CHECK" > "$TMP/out" 2> "$TMP/err"; then fail 'outdated version was accepted'; fi
grep -Fq 'expected 0.2.4-r1' "$TMP/err" || fail 'version mismatch error missing'
! grep -Eiq 'password|secret|credential' "$TMP/out" "$TMP/err" || fail 'secret-related text leaked into output'
printf 'PASS: 0.2.4 release smoke, zero/active sensor, disabled and broker/version failure checks\n'
