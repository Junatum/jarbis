# Jarbis

**Jarbis — Just A Rather Very Beautiful Intelligent System**

SmartSafeHub용 **OpenWrt 경량 로컬 스마트홈 엔진**입니다. 현재 Tasmota Wi-Fi 전구의 검색·등록·연결·전원·밝기·RGB 색상·색온도 제어를 지원합니다. 이름은 대중문화 속 J.A.R.V.I.S.에서 착안한 비공식 명칭이며 Marvel과 관련이 없습니다.

- **패키지 버전:** `0.1.0-r12` (기능 버전 `0.1.0`, OpenWrt 패키지 revision `11`)
- **라이선스:** `GPL-3.0-or-later` ([LICENSE](LICENSE))
- **플랫폼:** OpenWrt 25.12 기반 SmartSafeHub. 모델별 설치 용량·RAM·MQTT 의존성 검증 필요
- **런타임:** BusyBox ash, UCI, rpcd-ucode, Mosquitto, curl, jsonfilter. Python, Node.js, 상주 AI 서비스는 불필요
- **상태:** 초기 개발 버전. 일반 사용자용 배포 전 실기기 검증이 필요합니다

## 기능과 제한 사항

| 기능 | 상태 |
| --- | --- |
| 독립 `jarbis` 패키지, UCI, 인증된 RPC, 읽기/쓰기 ACL | 구현 |
| 기본 비활성화 및 로컬 인증형 MQTT Broker (기존 설정 보호) | 구현 |
| DHCP/HTTP 및 Tasmota MQTT Discovery 후보 검색 | 구현, 자동 등록하지 않음 |
| 기기 등록·수정·삭제 및 수동 전구 제어 | 구현 |
| 사용자 승인 후 Tasmota MQTT 자동 연결 | 구현, 기기/인증 환경에 따라 실패 가능 |
| 전구의 응답 상태 조회 (`light_state`) | 구현, HTTP 우선/MQTT 대체, 미확인은 미확인으로 표시 |
| 전원·밝기·RGB 색상·색온도 | 구현, 전구 모델별 지원 범위 상이 |
| 예약, Scene, 조건식 자동화, 온디바이스 AI | 미구현 |
| Matter/Zigbee 등 Tasmota 외 프로토콜 | 미구현 |

Jarbis는 SmartSafeHub의 **공유기 웹사이트** 스마트홈 화면과 연동하는 독립 백엔드입니다. 프론트엔드 소스는 `luci-app-smartsafehub`에서 관리하며 이 저장소에는 웹 빌드 결과물을 포함하지 않습니다. Jarbis만 설치해도 별도 LuCI 메뉴가 자동 추가되지는 않습니다. 상세 연동 계약은 [docs/INTEGRATION.md](docs/INTEGRATION.md)를 확인하세요.

## 설치 및 빌드

OpenWrt 소스 트리의 `package/jarbis` 또는 적절한 패키지 피드에 이 저장소를 배치합니다.

```sh
make menuconfig               # Utilities > jarbis 선택
make package/jarbis/compile V=s
```

`Makefile`은 `rpcd-mod-ucode`, `ucode-mod-uci`, `ucode-mod-fs`, `mosquitto-ssl`, `mosquitto-client-ssl`, `curl`, `jsonfilter`를 의존성으로 선언합니다. 관리형 Broker 초기화에는 `mosquitto_passwd` 실행 파일도 필요합니다. `Build/Compile`은 `CONFIG_MOSQUITTO_PASSWD=y`가 아니면 실패합니다. 배포 패키지에 실제 바이너리가 들어 있는지도 릴리스 전에 확인해야 합니다. `curl` 추가로 특히 소형 공유기의 설치 용량 및 의존성을 재검증하세요.

설치 후 Jarbis는 **비활성화** 상태입니다. 앱의 설치·업데이트·복원은 SmartSafeHub Apps 배포 정책에 따라 별도로 승인·검증해야 합니다. 특히 소형 장치에서는 펌웨어 크기, 사용 가능 저장공간과 메모리를 실측해야 합니다.

## 처음 사용하기

> 실제 전구 MQTT 설정을 바꾸는 작업은 같은 신뢰할 수 있는 LAN에서만 수행하고, 기존 MQTT 서버가 연결된 기기는 변경 승인 후 진행하세요.

1. 공유기 웹사이트의 **스마트홈** 메뉴에서 Jarbis를 켭니다. SSH로는 다음과 같이 시작할 수 있습니다.

   ```sh
   uci set jarbis.main.enabled=1
   uci commit jarbis
   /etc/init.d/jarbis start
   ubus call jarbis status '{}'
   ```

2. 관리형 Broker는 처음 시작할 때 인증 정보를 생성합니다. 기존 Mosquitto 리스너/브리지 또는 설정이 있다면 덮어쓰지 않고 실패합니다. 이 경우 기존 Broker를 별도로 설정한 뒤 `jarbis.broker.mode=external`을 사용하세요. **진단 중 기존 Mosquitto 설정이나 비밀번호 파일을 삭제하지 마세요.**
3. 공유기 웹사이트에서 **기기 검색 → 기기 추가 → 전구 연결 설정** 순서로 진행합니다. 발견된 후보는 자동 등록되지 않습니다. 자동 연결은 등록된 Tasmota 전구, 확인된 HTTP 후보, 사용자의 승인을 요구합니다.
4. 필요할 때만 상태를 새로 조회하고 전원을 제어합니다.

   ```sh
   ubus call jarbis devices_list '{}'
   ubus call jarbis discovery_scan '{}'
   ubus call jarbis discovery_list '{}'
   ubus call jarbis light_set '{"id":"living_room","capability":"power","value":"ON"}'
   ubus call jarbis light_state '{"id":"living_room"}'
   ```

   위 `living_room`은 **이미 등록된 기기 ID를 가정한 예시**입니다. 실제 ID는 `devices_list`를 확인하세요. `light_set`의 `accepted: true`는 브로커로 명령을 게시했다는 뜻으로, 실제 전구 동작 성공을 보장하지 않습니다. `light_state`의 `observed: false`도 오프라인 확정이 아니라 현재 상태 미확인을 의미합니다.

5. 문제를 해결할 때는 먼저 다음 읽기 전용 명령으로 관리형 MQTT Broker의 사전 조건을 확인합니다.

   ```sh
   /usr/libexec/jarbis-broker diagnose
   ```

### MQTT 인증 정보와 통신 주의사항

- 로컬 MQTT는 기본적으로 **1883/TCP, 암호화되지 않은 평문**입니다. 신뢰할 수 있는 내부망에서만 사용하고 WAN으로 포트 포워딩하지 마세요.
- 관리형 Broker는 익명 접속을 차단하지만 현재 **전구들이 하나의 MQTT 계정을 공유**합니다. 기기별 계정·토픽 ACL은 아직 구현되지 않았습니다.
- 비밀번호 파일 `/etc/jarbis/device-credentials`, `/etc/jarbis/mosquitto_pub`, `/etc/jarbis/mosquitto_sub`, `/etc/mosquitto/jarbis.passwd`는 민감 정보입니다. 공유기 백업에도 포함될 수 있습니다.
- `broker_credentials` RPC는 **`jarbis` write ACL을 부여받은 세션에 MQTT 비밀번호(`secret`)를 반환**하며 RPC 내부에 별도 관리자 재인증은 없습니다. SmartSafeHub에서 관리자에게만 해당 권한을 부여해야 합니다. 일반 `status`, `devices_list`, `discovery_list`, `device_pair` 응답에는 비밀번호를 포함하지 않습니다. UI는 사용자 동작 없이 자동 호출하지 말고, 응답을 저장·캐시·로깅·원격 전송하지 않아야 합니다.
- 전구 검색·상태 조회·자동 연결은 HTTP 3xx 리다이렉트를 거부합니다(`curl --location --max-redirs 0`). 자동 연결(`device_pair`)의 관리자 비밀번호는 로컬 임시 파일 및 LAN HTTP POST 본문으로 전달됩니다. HTTP는 암호화되지 않으므로 격리되지 않은 네트워크에서 사용하지 마세요.

보안 모델과 제한 사항은 [docs/SECURITY.md](docs/SECURITY.md), 취약점 비공개 신고 방법은 [SECURITY.md](SECURITY.md)를 참고하세요.

## 테스트

CI는 ShellSpec `0.28.1`, Python 3 및 고정된 ucode 컴파일러를 사용합니다. 신규 테스트는 반드시 `spec/contracts_spec.sh`에 등록해야 합니다.

```sh
sh tests/test-suite-integrity.sh  # 새 테스트가 CI에서 누락되는지 검사
sh tests/test-openwrt-commands.sh # OpenWrt 25.12 BusyBox 명령 검사
python3 tests/test-contract.py    # 정적 패키지 및 공개 준비 계약 검사
shellspec                         # 전체 테스트 (ShellSpec 설치 필요)
```

CI에서는 `JARBIS_REQUIRE_UCODE=1`로 ucode 컴파일 및 RPC 런타임 테스트를 필수 실행합니다. CI 테스트는 실제 Tasmota/Mosquitto와 펌웨어 업그레이드 테스트를 대체하지 않습니다.

## 프로젝트 문서

- [아키텍처 및 RPC 계약](docs/ARCHITECTURE.md)
- [SmartSafeHub 통합](docs/INTEGRATION.md)
- [보안 설계와 제한](docs/SECURITY.md)
- [비공개 취약점 신고](SECURITY.md)
- [기여 및 개발 가이드](CONTRIBUTING.md)
- [변경 내역](CHANGELOG.md)

코드 및 문서의 변경은 GPL-3.0-or-later 조건으로 배포합니다. 외부 서비스·도구의 라이선스는 각 상위 프로젝트의 배포 조건을 따르며, 타사 소스나 자산을 이 저장소에 추가할 때는 해당 라이선스 전문·출처를 함께 보관해야 합니다.
