#!/usr/bin/env python3
"""SmartSafeHub Apps 공개 배포 및 안전한 제거 계약."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
mk = (root / "Makefile").read_text()
core = (root / "root/usr/share/rpcd/ucode/jarbis/core.uc").read_text()
broker = (root / "root/usr/libexec/jarbis-broker").read_text()
init = (root / "root/etc/init.d/jarbis").read_text()
version = re.search(r"(?m)^PKG_VERSION:=(\S+)$", mk).group(1)
release = re.search(r"(?m)^PKG_RELEASE:=(\d+)$", mk).group(1)
assert "version: '" + version + "-r" + release + "'" in core
assert "PKG_LICENSE:=GPL-3.0-or-later" in mk
assert "JARBIS_MOSQUITTO_INIT" in broker
assert '"$action" = stop' in broker
assert "broker ownership cannot be proven" in broker
assert "shared Mosquitto listener/bridge found" in broker
assert '"$INIT" disable' in broker
assert '"$BROKER_BIN" stop' in init and "has_active_sensor" in init
assert "/etc/init.d/jarbis stop || exit 1" in mk
assert 'rm -f "$BROKER_PASS"' not in broker[broker.index('if [ "$action" = stop ]'):broker.index('if [ "$mode" = external ]')]
print("PASS: Jarbis Apps 버전·라이선스·공유 MQTT Broker 안전 제거 계약")
