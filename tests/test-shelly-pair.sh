#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/cache" "$TMP/backup"
chmod 700 "$TMP/cache" "$TMP/backup"
cat > "$TMP/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" = -q ] && shift
case "$1" in
    get) [ -f "$STATE/$2" ] || exit 1; cat "$STATE/$2" ;;
    show) printf 'jarbis.sensor=device\n';;
    *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/jsonfilter" <<'MOCK'
#!/usr/bin/env python3
import json, sys, re
try:
    data=json.load(open(sys.argv[2]))
    expr=sys.argv[4]
    current=data
    for a,b in re.findall(r'\["([^"]+)"\]|\.?([A-Za-z_][A-Za-z_0-9]*)',expr[1:]):
        current=current[a or b]
    if current is None: raise ValueError()
    if isinstance(current,bool): print('true' if current else 'false')
    else: print(current)
except Exception: sys.exit(1)
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env python3
import os, sys, json
args=sys.argv[1:]
assert '--max-redirs' in args and args[args.index('--max-redirs')+1]=='0'
assert "--noproxy" in args and args[args.index('--noproxy')+1]=='*'
assert '--proto' in args and args[args.index('--proto')+1]=='=http'
out=args[args.index('--output')+1]
req=args[args.index('--data-binary')+1]
assert req.startswith('@')
uri=args[-1]
assert uri=='http://192.168.1.209/rpc'
data=json.load(open(req[1:]))
method=data['method']
with open(os.environ['MOCK_LOG'],'a') as f: f.write(method+'\n')
if os.getenv('MOCK_ASLEEP')=='1': sys.exit(7)
if method=='Shelly.GetDeviceInfo':
    result={'id':'shellyhtg3-083af2d1329c', 'mac':'083AF2D1329C', 'model':'S3SN-0U12A','gen':3,'app':'HTG3','auth_en':False}
    if os.getenv('MOCK_MISMATCH')=='1': result['mac']='111111111111'
    if os.getenv('MOCK_AUTH')=='1': result['auth_en']=True
elif method=='Shelly.GetStatus':
    result={'sys':{'mac':'083AF2D1329C'},'temperature:0':{'id':0,'tC':24.8},
            'humidity:0':{'id':0,'rh':52.1},'devicepower:0':{'id':0,'battery':{'percent':100}}}
elif method=='MQTT.GetConfig':
    server='192.168.1.1:1883' if os.getenv('MOCK_ALREADY')=='1' else ('10.0.0.9:1883' if os.getenv('MOCK_CONFLICT')=='1' else None)
    result={'enable': server is not None,'server':server,'user':'jarbis' if os.getenv('MOCK_ALREADY')=='1' else None,
            'topic_prefix':'shellyhtg3-083af2d1329c','rpc_ntf':True,'ssl_ca':None}
elif method=='MQTT.GetStatus': result={'connected': True}
elif method=='MQTT.SetConfig':
    c=data['params']['config']
    assert c['pass']==os.environ['EXPECTED_SECRET']
    assert c['server']=='192.168.1.1:1883'
    assert c['user']=='jarbis' and c['rpc_ntf'] is True
    result={'restart_required':True}
elif method=='Shelly.Reboot': result={}
else: sys.exit(1)
with open(out,'w') as f: json.dump(result,f)
MOCK
cat > "$TMP/bin/broker" <<'MOCK'
#!/bin/sh
[ "$1" = check ]
MOCK
chmod 700 "$TMP/bin/"*
export STATE="$TMP/state" MOCK_LOG="$TMP/methods"
export JARBIS_TEST_MODE=1 JARBIS_UCI_BIN="$TMP/bin/uci" JARBIS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export JARBIS_CURL_BIN="$TMP/bin/curl" JARBIS_BROKER_BIN="$TMP/bin/broker"
export JARBIS_DISCOVERY_CACHE="$TMP/discovery" JARBIS_DEVICE_CREDENTIALS="$TMP/creds"
export JARBIS_SHELLY_CACHE_BIN="$ROOT/root/usr/libexec/jarbis-shelly-cache"
export JARBIS_SENSOR_TMP_DIR="$TMP/cache" JARBIS_SENSOR_BACKUP_DIR="$TMP/backup"
PATH="$TMP/bin:$PATH"; export PATH
printf '%s\n' 1 > "$STATE/jarbis.main.enabled"
printf '%s\n' managed > "$STATE/jarbis.broker.mode"
printf '%s\n' 1 > "$STATE/jarbis.broker.managed_ready"
printf '%s\n' '192.168.1.1' > "$STATE/jarbis.broker.lan_ip"
printf '%s\n' 1883 > "$STATE/jarbis.broker.port"
printf '%s\n' device > "$STATE/jarbis.sensor"
printf '%s\n' 1 > "$STATE/jarbis.sensor.enabled"
printf '%s\n' shelly_htg3 > "$STATE/jarbis.sensor.protocol"
printf '%s\n' sensor > "$STATE/jarbis.sensor.kind"
printf '%s\n' 'shellyhtg3-083af2d1329c' > "$STATE/jarbis.sensor.topic"
printf '%s\n' 'shelly-dhcp|192.168.1.209|08:3a:f2:d1:32:9c|shellyhtg3-083af2d1329c|Shelly H&T Gen3' > "$TMP/discovery"
EXPECTED_SECRET="$(printf '%064d' 0)"; export EXPECTED_SECRET
printf 'username=jarbis\npassword=%s\n' "$EXPECTED_SECRET" > "$TMP/creds"
PAIR="$ROOT/root/usr/libexec/jarbis-shelly-pair"
[ -x "$PAIR" ] || fail 'missing package helper'
run() {
    work="$(mktemp -d /tmp/jarbis-pair-XXXXXX)"
    chmod 700 "$work"
    printf 'sensor\n\n%s\n' "${1:-0}" > "$work/request"
    : > "$MOCK_LOG"
    if sh "$PAIR" "$work"; then success=1; else success=0; fi
    result="$(cat "$work/result" 2>/dev/null || :)"
    rm -rf "$work"
}
run 0
[ "$success" = 1 ] && [ "$result" = OBSERVED ] || fail 'first awake pairing should yield an observed reading'
case "$(cat "$TMP/cache/sensor")" in '24.8|52.1|100|'*'|http') ;; *) fail 'first report not persisted from verified HTTP' ;; esac
[ "$(grep -cx MQTT.SetConfig "$MOCK_LOG")" = 1 ] || fail 'device not configured'
[ "$(grep -cx Shelly.Reboot "$MOCK_LOG")" = 1 ] || fail 'new MQTT config not activated'
[ "$(grep -c "$EXPECTED_SECRET" "$MOCK_LOG" || :)" = 0 ] || fail 'secret leaked into method log'
MOCK_ALREADY=1; export MOCK_ALREADY
run 0
[ "$success" = 1 ] && [ "$result" = OBSERVED ] || fail 'already configured sensor failed'
! grep -Eq 'MQTT.SetConfig|Shelly.Reboot' "$MOCK_LOG" || fail 'unnecessary sensor reconfiguration'
unset MOCK_ALREADY
# Once a validated MQTT report has arrived, re-pairing while the sensor
# sleeps must be a no-op. An HTTP snapshot alone is not MQTT evidence.
MOCK_ASLEEP=1; export MOCK_ASLEEP
now="$(date +%s)"
printf '24.3|54|100|%s|mqtt\n' "$now" > "$TMP/cache/sensor"
run 0
[ "$success" = 1 ] && [ "$result" = OBSERVED ] || fail 'recent MQTT sensor treated as sleeping error'
[ ! -s "$MOCK_LOG" ] || fail 'already reporting sensor was unnecessarily contacted over HTTP'
# Old MQTT reports and HTTP-only first readings cannot bypass pairing.
printf '24.3|54|100|%s|mqtt\n' "$((now - 10801))" > "$TMP/cache/sensor"
run 0
[ "$success" = 0 ] && [ "$result" = WAKE_REQUIRED ] || fail 'old MQTT report treated as current connection'
printf '24.3|54|100|%s|http\n' "$now" > "$TMP/cache/sensor"
run 0
[ "$success" = 0 ] && [ "$result" = WAKE_REQUIRED ] || fail 'HTTP seed wrongly trusted as MQTT connection'
# An explicit broker replacement must not silently reuse the cached report.
printf '24.3|54|100|%s|mqtt\n' "$now" > "$TMP/cache/sensor"
run 1
[ "$success" = 0 ] && [ "$result" = WAKE_REQUIRED ] || fail 'approved override bypassed HTTP reconfiguration'
# With no active MQTT report the sensor still needs a wakeup.
rm -f "$TMP/cache/sensor"
run 0
[ "$success" = 0 ] && [ "$result" = WAKE_REQUIRED ] || fail 'sleep did not provide a clear retry reason'
! grep -q 'MQTT.SetConfig' "$MOCK_LOG" || fail 'sleeping device was modified'
unset MOCK_ASLEEP
MOCK_CONFLICT=1; export MOCK_CONFLICT
run 0
[ "$success" = 0 ] && [ "$result" = BROKER_CONFLICT ] || fail 'third-party MQTT config overwritten without consent'
! grep -q MQTT.SetConfig "$MOCK_LOG" || fail 'third-party broker modified'
run 1
[ "$success" = 1 ] && [ "$result" = OBSERVED ] || fail 'approved replacement failed'
unset MOCK_CONFLICT
MOCK_MISMATCH=1; export MOCK_MISMATCH
run 0
[ "$success" = 0 ] && [ "$result" = DEVICE_MISMATCH ] || fail 'wrong MAC not blocked'
! grep -q MQTT.SetConfig "$MOCK_LOG" || fail 'mismatched device configured'
unset MOCK_MISMATCH
MOCK_AUTH=1; export MOCK_AUTH
run 0
[ "$success" = 0 ] && [ "$result" = WEB_AUTH_REQUIRED ] || fail 'admin auth was not respected'
unset MOCK_AUTH
printf '%s\n' external > "$STATE/jarbis.broker.mode"
run 0
[ "$success" = 0 ] && [ "$result" = BROKER_UNAVAILABLE ] || fail 'external broker was modified'
# Compromised callers cannot select a different working directory.
if sh "$PAIR" "$TMP" >/dev/null 2>&1; then fail 'unsafe request path accepted'; fi
printf '%s\n' 'PASS: Shelly 간편 연결·기기 식별·최초 측정값·절전·기존 MQTT 보호·비밀번호 비노출'
