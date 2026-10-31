# Jarbis

**Jarbis — Just A Rather Very Beautiful Intelligent System**

SmartSafeHub의 경량 로컬 홈 자동화 엔진입니다. *Iron Man*의 J.A.R.V.I.S.를 패러디한 이름으로, Marvel 공식 제품과 관련이 없습니다. 영문 풀이는 사용자 프로젝트의 원래 표현을 그대로 유지합니다.

- **버전:** 0.1.0-r4 (RPC 런타임 안정화 및 설치·설정 보존 검증 추가)
- **라이선스:** GPL-3.0-or-later
- **대상:** OpenWrt 25.12 / SmartSafeHub (기본 기능에 대한 하드웨어별 실기 검증 필요)
- **런타임:** BusyBox ash, UCI, rpcd-ucode, mosquitto_pub. Python/Node.js/AI 런타임 및 상주 데몬 불필요.

## 현재 구현

- 독립 `jarbis` OpenWrt 패키지, UCI 설정, 인증된 ubus API, 세분화된 ACL
- 등록한 Tasmota 전구의 전원(`POWER`)과 밝기(`Dimmer`) MQTT 명령 송신
- 전용 MQTT 클라이언트 설정 파일을 이용한 인증 정보 분리 (명령행에 비밀번호 노출하지 않음)
- 패키지 설치 시 기능 **기본 비활성화**, 브로커 자동 생성/외부 포트 개방 없음
- ShellSpec 0.28.1 기반 셸 계약 테스트, Python 정적 계약 검사, OpenWrt 25.12 BusyBox 명령 감사, ucode 컴파일 및 실제 RPC 런타임 CI
- 설치·업데이트 후 누락된 `jarbis` RPC 객체에 대해 제한적 재확인 및 복구; `keep.d`로 UCI/MQTT 자격 증명 보존

**미구현:** 자동 탐색, 상태 수신/동기화, 예약·조건식 자동화, 장면(Scene), AI, SmartSafeHub 프론트엔드 UI. 현재 `light_set`의 `accepted: true`는 **브로커 게시 성공**만 의미하며, 실제 전구 동작 확인은 아닙니다.

## OpenWrt 패키지 빌드

이 저장소를 OpenWrt 빌드 트리의 `package/jarbis` 또는 자체 피드에 넣습니다.

```sh
make menuconfig                 # Utilities > jarbis 선택
make package/jarbis/compile V=s
```

`jarbis`는 MQTT *클라이언트*만 설치합니다. 기존 보안 설정된 MQTT 브로커를 사용하거나, 별도로 Mosquitto 브로커를 설치·설정해야 합니다.

## 최소 설정

1. 신뢰할 수 있는 MQTT 브로커를 준비합니다. 전구는 같은 브로커로 연결하고 Tasmota의 MQTT Topic을 확인합니다.
2. `/etc/config/jarbis`에서 `jarbis.broker.host`, `jarbis.broker.port`를 설정하고 `config device`를 등록합니다.
3. 브로커에 인증이 필요하면 `/etc/jarbis/mosquitto_pub`에 `-u USERNAME`, `-P PASSWORD`를 각 줄에 지정합니다. 루트만 읽을 수 있도록 `chmod 600 /etc/jarbis/mosquitto_pub`을 적용합니다. 예: `mkdir -p /etc/jarbis && chmod 700 /etc/jarbis`.
4. `uci set jarbis.main.enabled=1 && uci commit jarbis`로 활성화합니다.
5. 관리자 로그인 상태의 ubus RPC로 기기 목록을 조회하고 명령을 전송합니다.

```sh
# 예: /etc/config/jarbis에 'living_room' 장치 등록 후
ubus call jarbis status '{}'
ubus call jarbis devices_list '{}'
ubus call jarbis light_set '{"id":"living_room","capability":"power","value":"ON"}'
ubus call jarbis light_set '{"id":"living_room","capability":"brightness","value":"50"}'
```

자세한 범위와 API 계약은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/INTEGRATION.md](docs/INTEGRATION.md), [docs/SECURITY.md](docs/SECURITY.md)를 참조하세요.

## 테스트

ShellSpec 0.28.1을 설치한 환경에서 실행합니다. (`luci-app-smartsafehub`와 동일한 버전)

```sh
shellspec                       # 모든 테스트 실행 (단일 진입점)
```

CI는 ShellSpec 및 ucode 설치에 앞서 `Verify all tests are included in CI`와 `Verify OpenWrt 25.12 BusyBox compatibility`를 먼저 실행합니다.
별도의 모의 ucode 컴파일러로 ucode 문법 테스트 자체도 검증합니다. 별도의 전체 테스트 실행 스크립트는 사용하지 않습니다. ShellSpec 또는 Python 3가 없으면 전체 테스트가 실패하며, 누락된 테스트 스크립트가 있으면 실행 전에 실패합니다.
로컬에 `ucode`가 없으면 셸·JSON·정적 계약 테스트만 실행합니다. CI에서는 `JARBIS_REQUIRE_UCODE=1`로 실제 ucode 컴파일과 UCI 모의 환경에서의 RPC 함수 실행을 필수로 검사합니다.

새 회귀 테스트는 `tests/test-rpc-runtime.sh`, `tests/test-package-contract.sh`, `tests/test-rpcd-reconcile.sh`, `tests/test-backup-restore.sh`, `tests/test-changelog-spacing.sh`이며 모두 ShellSpec에 직접 등록되어 있습니다. `test-backup-restore.sh`는 `keep.d`에 기록된 경로를 이용한 백업·복원 **모의 테스트**로, 실제 공유기 sysupgrade 검증을 대체하지는 않습니다.

설치·업데이트 시 rpcd는 정상 reload를 우선 사용하며, `jarbis` ubus 객체가 누락된 경우에만 최후 수단으로 **한 번** restart합니다. 재시도 횟수는 제한하며 복구 실패 시 패키지 설치 스크립트가 실패를 알립니다. 이 동작은 공유기의 관리자 연결에 영향을 줄 수 있으므로 실제 기기에서 검증해야 합니다.

## 개발 원칙

Jarbis의 기기 타입/Capability → 상태 이벤트 → 규칙 엔진 → Action Executor는 내부 계약으로 분리합니다. 향후 `jarbis-ai` 모듈도 동일한 검증된 Action Executor를 사용해야 합니다. SafeShield 및 SmartSafeHub의 핵심 네트워크/로그인 RPC에는 Jarbis 코드를 추가하지 않습니다.
