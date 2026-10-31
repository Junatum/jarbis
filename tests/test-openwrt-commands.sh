#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT/tools/check_openwrt_commands.py"
POLICY="$ROOT/tools/openwrt-25.12-commands.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Never conceal an unsupported BusyBox applet by adding it to the allowlist.
for applet in od xxd realpath stat wget base64; do
    if grep -Eq "^${applet}$" "$POLICY"; then
        fail "non-default applet unexpectedly allowed: $applet"
    fi
done
for command in ls cut uci mosquitto_pub; do
    grep -Eq "^${command}$" "$POLICY" || fail "missing documented runtime command: $command"
done
python3 "$CHECKER" >/dev/null || fail 'actual shipped scripts failed the OpenWrt 25.12 audit'

mkdir -p "$TMP/root/usr/libexec" "$TMP/root/etc/init.d"
FILE="$TMP/root/usr/libexec/jarbis-fixture"
check_allowed() {
    python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err" || \
        fail "legal command or data was rejected: $(cat "$TMP/err")"
}
check_blocked() {
    label="$1"
    reason="$2"
    if python3 "$CHECKER" --root "$TMP" >"$TMP/out" 2>"$TMP/err"; then
        fail "unsafe router command escaped the audit: $label"
    fi
    grep -F "$reason" "$TMP/err" >/dev/null || \
        fail "wrong failure reason for $label: $(cat "$TMP/err")"
}

cat > "$FILE" <<'EOF'
#!/bin/sh
# od /dev/urandom and xxd must be ignored as comments.
printf '%s\n' 'stat -c %a /etc/jarbis' 'grep -R password /' \
    'while true; do :; done'
cat <<'END_OF_DATA'
find / -type f
xxd /dev/urandom
END_OF_DATA
uci -q get jarbis.main.enabled
mosquitto_pub -h 127.0.0.1 -p 1883 -t cmnd/light/POWER -m ON
ls -ld /etc/jarbis | cut -c 1-10
EOF
check_allowed

cat >> "$FILE" <<'EOF'
od -An -tx1 /dev/urandom
EOF
check_blocked od 'unsupported command: od'

cat > "$FILE" <<'EOF'
#!/bin/sh
value="$(stat -c %a /etc/jarbis)"
EOF
check_blocked stat 'unsupported command: stat'

cat > "$FILE" <<'EOF'
#!/bin/sh
command -v wget >/dev/null 2>&1 || :
EOF
check_blocked wget 'unsupported command: wget'

cat > "$FILE" <<'EOF'
#!/bin/sh
OD_BIN="${JARBIS_OD_BIN:-od}"
"$OD_BIN" -An -tx1 /dev/urandom
EOF
check_blocked 'dynamic applet fallback' 'unsupported command default: OD_BIN=od'

cat > "$FILE" <<'EOF'
#!/bin/sh
if [ -f /dev/null ]; then python3 --version; fi
EOF
check_blocked 'Python on router' 'unsupported command: python3'

cat > "$FILE" <<'EOF'
#!/bin/sh
printf '%s\n' good
EOF
cat > "$TMP/root/etc/init.d/jarbis-fixture" <<'EOF'
#!/bin/sh /etc/rc.common
xxd /dev/urandom
EOF
check_blocked 'init script' 'unsupported command: xxd'
rm "$TMP/root/etc/init.d/jarbis-fixture"

cat > "$TMP/root/usr/libexec/jarbis-bash" <<'EOF'
#!/bin/bash
echo bad
EOF
check_blocked 'unsupported interpreter' 'unsupported interpreter'
rm "$TMP/root/usr/libexec/jarbis-bash"

# Package postinst/prerm are also executed by ash, not just installed files.
cat > "$TMP/Makefile" <<'EOF'
define Package/jarbis/postinst
#!/bin/sh
stat -c %a /etc/jarbis
endef
EOF
check_blocked 'package install hook' 'unsupported command: stat'
rm "$TMP/Makefile"

cat > "$FILE" <<'EOF'
#!/bin/sh
find / -type f
EOF
check_blocked 'unbounded find' 'performance risk:'

cat > "$FILE" <<'EOF'
#!/bin/sh
LC_ALL=C grep -Rn password /etc
EOF
check_blocked 'recursive grep' 'performance risk:'

cat > "$FILE" <<'EOF'
#!/bin/sh
dd if=/dev/urandom bs=1024 of=/tmp/random
EOF
check_blocked 'unbounded random read' 'performance risk:'

cat > "$FILE" <<'EOF'
#!/bin/sh
printf '%s\n' value | xargs -P 0 echo
EOF
check_blocked 'unbounded parallelism' 'performance risk:'

cat > "$FILE" <<'EOF'
#!/bin/sh
while true; do
    echo hot
    :
done
EOF
check_blocked 'hot polling' 'performance risk:'

cat > "$FILE" <<'EOF'
#!/bin/sh
find /etc/config -maxdepth 1 -type f
dd if=/dev/urandom bs=8 count=1 2>/dev/null
while true; do
    echo periodic
    sleep 1
done
EOF
check_allowed

printf 'PASS: OpenWrt 25.12 BusyBox 및 고비용 명령 검사\n'
