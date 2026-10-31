#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/jarbis-rpcd-reconcile"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -x "$HELPER" ] || fail 'reconcile helper missing'
grep -Fq '/bin/sh /usr/libexec/jarbis-rpcd-reconcile' "$ROOT/Makefile" || fail 'postinst hook not connected'
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jarbis-reconcile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/rpcd" <<'MOCK'
#!/bin/sh
set -eu
file="$JARBIS_TEST_STATE"
case "$1" in
    reload)
        printf 'reload\n' >> "$JARBIS_TEST_LOG"
        case "$JARBIS_TEST_SCENARIO" in
            healthy) printf 'ready\n' > "$file" ;;
            reload-fails) exit 1 ;;
            *) printf 'missing\n' > "$file" ;;
        esac ;;
    restart)
        printf 'restart\n' >> "$JARBIS_TEST_LOG"
        case "$JARBIS_TEST_SCENARIO" in
            unrecoverable) printf 'missing\n' > "$file" ;;
            *) printf 'ready\n' > "$file" ;;
        esac ;;
    *) exit 2 ;;
esac
MOCK
cat > "$TMP/ubus" <<'MOCK'
#!/bin/sh
[ "$1" = list ] && [ "$2" = jarbis ] || exit 2
[ "$(cat "$JARBIS_TEST_STATE")" = ready ] || exit 1
printf 'jarbis\n'
MOCK
cat > "$TMP/sleep" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$JARBIS_TEST_SLEEPS"
MOCK
chmod +x "$TMP/rpcd" "$TMP/ubus" "$TMP/sleep"
export JARBIS_RPCD_INIT="$TMP/rpcd"
export JARBIS_UBUS_BIN="$TMP/ubus"
export JARBIS_SLEEP_BIN="$TMP/sleep"
export JARBIS_RPCD_PROBE_ATTEMPTS=2
export JARBIS_RPCD_PROBE_DELAY_S=0
export JARBIS_TEST_STATE="$TMP/state"
export JARBIS_TEST_LOG="$TMP/log"
export JARBIS_TEST_SLEEPS="$TMP/sleeps"
reset() { : > "$JARBIS_TEST_LOG"; : > "$JARBIS_TEST_SLEEPS"; printf 'ready\n' > "$JARBIS_TEST_STATE"; }
reset
export JARBIS_TEST_SCENARIO=healthy
sh "$HELPER" || fail 'normal reload fails'
[ "$(cat "$JARBIS_TEST_LOG")" = reload ] || fail 'healthy path must avoid restart'
reset
export JARBIS_TEST_SCENARIO=missing-after-reload
sh "$HELPER" || fail 'missing RPC object must be recovered'
[ "$(cat "$JARBIS_TEST_LOG")" = "$(printf 'reload\nrestart')" ] || fail 'fallback must restart exactly once'
[ "$(wc -l < "$JARBIS_TEST_SLEEPS")" -eq 1 ] || fail 'missing object must be re-probed'
reset
export JARBIS_TEST_SCENARIO=reload-fails
sh "$HELPER" || fail 'failed reload must trigger restart'
[ "$(cat "$JARBIS_TEST_LOG")" = "$(printf 'reload\nrestart')" ] || fail 'reload failure fallback'
reset
export JARBIS_TEST_SCENARIO=unrecoverable
if sh "$HELPER" > "$TMP/stdout" 2> "$TMP/stderr"; then fail 'unrecoverable error must not be hidden'; fi
[ "$(cat "$JARBIS_TEST_LOG")" = "$(printf 'reload\nrestart')" ] || fail 'restarts must be bounded'
grep -Fq 'rpcd object missing' "$TMP/stderr" || fail 'unrecoverable error must be visible'
# Guard against unbounded user-provided attempts.
reset
export JARBIS_RPCD_PROBE_ATTEMPTS=999
if sh "$HELPER" > "$TMP/stdout" 2> "$TMP/stderr"; then fail 'unrecoverable error with untrusted attempts'; fi
[ "$(wc -l < "$JARBIS_TEST_SLEEPS")" -le 4 ] || fail 'retry count must be bounded'
printf 'PASS: rpcd reload, missing object recovery, one restart and bounded failure\n'
