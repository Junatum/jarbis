# Jarbis

**Jarbis — Just A Rather Very Beautiful Intelligent System**

SmartSafeHub의 경량 로컬 홈 자동화 엔진입니다. *Iron Man*의 J.A.R.V.I.S.를 패러디한 이름으로, Marvel 공식 제품과 관련이 없습니다. 영문 풀이는 사용자 프로젝트의 원래 표현을 그대로 유지합니다.

- **버전:** 0.1.0-r6 (MQTT Broker 관리 및 스마트홈 웹 연동 RPC)
- **라이선스:** GPL-3.0-or-later
- **대상:** OpenWrt 25.12 / SmartSafeHub (기본 기능에 대한 하드웨어별 실기 검증 필요)
- **런타임:** BusyBox ash, UCI, rpcd-ucode, Mosquitto Broker/Client, uclient-fetch, jsonfilter. Python/Node.js/AI 런타임 불필요. MQTT Broker는 procd로 관리됩니다.

## 현재 구현

- 독립 `jarbis` OpenWrt 패키지, UCI 설정, 인증된 ubus API, 세분화된 ACL
- 등록한 Tasmota 전구의 전원(`POWER`)과 밝기(`Dimmer`) MQTT 명령 송신
- 전용 MQTT 클라이언트 설정 파일을 이용한 인증 정보 분리 (명령행에 비밀번호 노출하지 않음)
- 새 설치 시 기능 **기본 비활성화**. 기능 활성화 후 Jarbis 서비스 시작 시 전용 인증 MQTT Broker를 구성하며 WAN 포트/방화벽 규칙은 열지 않음
- ShellSpec 0.28.1 기반 셸 계약 테스트, Python 정적 계약 검사, OpenWrt 25.12 BusyBox 명령 감사, ucode 컴파일 및 실제 RPC 런타임 CI
- 설치·업데이트 후 누락된 `jarbis` RPC 객체에 대해 제한적 재확인 및 복구; `keep.d`로 UCI/MQTT 자격 증명 보존

**미구현:** 검색 결과 자동 등록, 전구 MQTT 자동 설정, 상태 수신/동기화, 예약·조건식 자동화, 장면(Scene), AI, SmartSafeHub 프론트엔드 UI. 현재 `light_set`의 `accepted: true`는 **브로커 게시 성공**만 의미하며, 실제 전구 동작 확인은 아닙니다.

## OpenWrt 패키지 빌드

이 저장소를 OpenWrt 빌드 트리의 `package/jarbis` 또는 자체 피드에 넣습니다.

```sh
make menuconfig                 # Utilities > jarbis 선택
make package/jarbis/compile V=s
```

`jarbis` 신규 설치는 `mosquitto-ssl`, `mosquitto-client-ssl`을 함께 의존성으로 설치합니다. OpenWrt 25.12 빌드 구성에 `CONFIG_MOSQUITTO_PASSWD=y`가 필요합니다. 기존에 Mosquitto 리스너/브리지가 있거나 `use_uci=1`인 환경은 관리형 초기화를 거부하므로 `jarbis.broker.mode=external`로 전환해 기존 Broker를 사용하세요. GL-MT300N-V2 같은 소형 공유기에서는 펌웨어 용량과 메모리 측정이 필요합니다.

## 실기기 초기 테스트 (신규 설치)

1. `uci set jarbis.main.enabled=1 && uci commit jarbis`로 기능을 켭니다. 이미 기기를 등록한 공유기에서는 기존 UCI를 덮어쓰지 않습니다. `0.1.0-r4`에서 업그레이드한 경우 `option mode`가 없으면 기존 외부 브로커로 계속 운영되므로, 관리형을 사용하고 싶다면 `uci set jarbis.broker.mode=managed && uci commit jarbis`를 명시적으로 실행하세요.
2. `/etc/init.d/jarbis start`를 실행합니다. 이때 **최초 한 번만** 랜덤 비밀번호를 생성하고 `mosquitto_passwd -U`로 해시합니다. 기존 Mosquitto 리스너/설정이 있다면 실패하고 설정을 변경하지 않습니다. `status`는 준비 여부만 확인할 수 있습니다: `/usr/libexec/jarbis-broker status`.
3. 기기의 MQTT 설정에서 Host를 **공유기 LAN IP**, Port `1883`, Username `jarbis`로 설정합니다. 인증 정보는 공유기 SSH에서 `cat /etc/jarbis/device-credentials`로 *관리자만* 확인하세요. 이 파일과 관련 파일은 공유기 루트 전용(0600)이며 웹 API에는 노출되지 않습니다. **자동 검색은 인증·설정 변경을 하지 않습니다.** 전구의 MQTT 설정은 이 단계에서 수동 입력합니다.
4. 공유기에서 아래 읽기 전용 검색을 실행합니다. HTTP 검색은 DHCP 임대 목록에 기록된 `/24` LAN 기기 **최대 16대**를 대상으로 합니다. `ipaddr=192.168.1.1/24` 형식도 인식하며 일반 HTTP 요청은 1초, Tasmota 이름으로 확인된 일부 후보는 최대 2초 타임아웃과 4KiB 응답 제한이 있습니다. Tasmota HTTP 응답의 `Status.Topic`과 `StatusFWR.Version`을 사용하며 버전 문자열에 `tasmota`라는 단어가 없는 제조사 빌드도 인식합니다. MQTT 검색은 `tasmota/discovery/+/config`의 retained 메시지를 2초, 최대 32KiB까지만 수집합니다. 브로커와 HTTP를 함께 사용해 후보를 모읍니다.

```sh
ubus call jarbis status '{}'
ubus call jarbis discovery_scan '{}'
ubus call jarbis discovery_list '{}'
```

검색한 기기는 **후보 목록**일 뿐입니다. `devices_list`나 `light_set`로 바로 접근할 수 없으며, 사용자 승인 후 `config device`를 따로 등록해야 합니다. 이미 연결된 기기라도 Tasmota 웹 비밀번호가 필요하면 HTTP 검색은 그 기기를 건너뜁니다. DHCP 리스가 없거나 `/24`가 아닌 LAN에서는 HTTP 검색을 생략하고 MQTT 검색만 합니다. 표준 Tasmota FullTopic `%prefix%/%topic%/`만 지원합니다. 실행 후 결과 캐시는 `/tmp/jarbis-discovery.records`이며 재부팅 시 사라집니다.

```sh
# AiYaTo를 승인하여 수동 등록하는 예시 (검색만으로 추가되지 않음)
uci set jarbis.aiyato_cb0735=device
uci set jarbis.aiyato_cb0735.enabled=1
uci set jarbis.aiyato_cb0735.name='AiYaTo'
uci set jarbis.aiyato_cb0735.kind=light
uci set jarbis.aiyato_cb0735.protocol=tasmota
uci set jarbis.aiyato_cb0735.topic=aiyato_cb0735
uci commit jarbis
ubus call jarbis light_set '{"id":"aiyato_cb0735","capability":"power","value":"ON"}'
```

Broker와 클라이언트는 LAN에서 암호화되지 않은 MQTT(1883)을 사용하므로 **신뢰할 수 있는 LAN에서만** 사용하세요. 기존 MQTT 환경을 쓰려면 `uci set jarbis.broker.mode=external` 후 host/port 및 `/etc/jarbis/mosquitto_pub`·`mosquitto_sub`을 개별 설정합니다. **브로커는 자동 설치·초기화 대상이지만, 전구 연결/등록은 아직 사용자 확인 단계**입니다.

## 테스트

ShellSpec 0.28.1을 설치한 환경에서 실행합니다. (`luci-app-smartsafehub`와 동일한 버전)

```sh
shellspec                       # 모든 테스트 실행 (단일 진입점)
```

CI는 ShellSpec 및 ucode 설치에 앞서 `Verify all tests are included in CI`와 `Verify OpenWrt 25.12 BusyBox compatibility`를 먼저 실행합니다.
별도의 모의 ucode 컴파일러로 ucode 문법 테스트 자체도 검증합니다. 별도의 전체 테스트 실행 스크립트는 사용하지 않습니다. ShellSpec 또는 Python 3가 없으면 전체 테스트가 실패하며, 누락된 테스트 스크립트가 있으면 실행 전에 실패합니다.
로컬에 `ucode`가 없으면 셸·JSON·정적 계약 테스트만 실행합니다. CI에서는 `JARBIS_REQUIRE_UCODE=1`로 실제 ucode 컴파일과 UCI 모의 환경에서의 RPC 함수 실행을 필수로 검사합니다.

새 회귀 테스트는 `tests/test-broker.sh`, `tests/test-discovery.sh`, `tests/test-rpc-runtime.sh`, `tests/test-package-contract.sh`, `tests/test-rpcd-reconcile.sh`, `tests/test-backup-restore.sh`, `tests/test-changelog-spacing.sh`이며 모두 ShellSpec에 직접 등록되어 있습니다. `test-backup-restore.sh`는 `keep.d`에 기록된 경로를 이용한 백업·복원 **모의 테스트**로, 실제 공유기 sysupgrade 검증을 대체하지는 않습니다.

설치·업데이트 시 rpcd는 정상 reload를 우선 사용하며, `jarbis` ubus 객체가 누락된 경우에만 최후 수단으로 **한 번** restart합니다. 재시도 횟수는 제한하며 복구 실패 시 패키지 설치 스크립트가 실패를 알립니다. 이 동작은 공유기의 관리자 연결에 영향을 줄 수 있으므로 실제 기기에서 검증해야 합니다.

## 개발 원칙

Jarbis의 기기 타입/Capability → 상태 이벤트 → 규칙 엔진 → Action Executor는 내부 계약으로 분리합니다. 향후 `jarbis-ai` 모듈도 동일한 검증된 Action Executor를 사용해야 합니다. SafeShield 및 SmartSafeHub의 핵심 네트워크/로그인 RPC에는 Jarbis 코드를 추가하지 않습니다.
