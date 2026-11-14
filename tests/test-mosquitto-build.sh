#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/jarbis-build-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# Exercise the actual OpenWrt Build/Compile recipe without an SDK.
{
    printf 'all:\n'
    awk '/^define Build\/Compile$/{active=1;next} active && /^endef$/{exit} active{print}' "$ROOT/Makefile"
} > "$TMP/guard.mk"
if make -s -f "$TMP/guard.mk" CONFIG_MOSQUITTO_PASSWD=n > "$TMP/out" 2>&1; then
    fail 'mosquitto_passwd 기능이 없는 빌드를 허용함'
fi
grep -q 'CONFIG_MOSQUITTO_PASSWD=y' "$TMP/out" || fail '실패 이유가 명확하지 않음'
if make -s -f "$TMP/guard.mk" CONFIG_MOSQUITTO_PASSWD= > "$TMP/out" 2>&1; then
    fail '설정이 누락된 빌드를 허용함'
fi
make -s -f "$TMP/guard.mk" CONFIG_MOSQUITTO_PASSWD=y || fail '정상 빌드를 거부함'
printf 'PASS: Mosquitto 비밀번호 생성 기능 누락 시 OpenWrt 빌드 차단\n'
