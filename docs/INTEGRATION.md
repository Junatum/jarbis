# SmartSafeHub 연동 가이드

Jarbis는 OpenWrt 패키지의 **독립 rpcd `jarbis` 객체**를 제공합니다. 스마트홈 메뉴와 프론트엔드 코드는 별도 저장소 [`luci-app-smartsafehub`](https://github.com/Junatum/luci-app-smartsafehub)에서 관리합니다. 이 저장소에 프론트엔드 빌드 결과물을 생성하거나 설치하지 않습니다.

## 화면과 패키지 역할

- **스마트홈 메뉴:** 패키지 상태, 활성화, 기기 검색·등록·연결, 전구 제어 및 상태 확인
- **SmartSafeHub Apps:** Jarbis 설치·업데이트·제거·펌웨어 업그레이드 후 복원. 공식 카탈로그 노출 및 펌웨어별 승인 절차는 별도 Hub/Pipeline 작업
- **Jarbis 엔진:** UCI, rpcd, Mosquitto를 이용한 로컬 실행 기능. 설치만으로 새 LuCI 메뉴가 생기지는 않음

### 설치 상태를 안전하게 구분하기

1. **미설치**: 승인된 Apps 설치 상태에서 `jarbis` 패키지가 없음이 확인되었을 때만 설치 안내
2. **설치되었으나 RPC 없음**: `jarbis` ubus 객체 오류는 무조건 미설치로 해석하지 말고 rpcd 등록/ACL/재시작 문제로 분리
3. **설치됨·비활성화**: `status.data.enabled=false`이면 활성화 안내
4. **활성화됨·Broker 미준비**: `status.data.brokerReady=false`이면 진단 안내. 외부 Broker는 `/etc/jarbis/mosquitto_pub` (0600)에 사용자 구성이 있어야 게시 기반 연결 검사를 통과
5. **활성화됨·Broker 준비**: 등록된 기기를 조회하고 필요한 경우 검색·연결 유도

라우팅은 해당 SmartSafeHub 앱의 실제 경로/해시 설정을 기준으로 하며, 실행 경로를 임의 생성하거나 인증되지 않은 외부 URL로 이동시키지 않습니다. 패키지 설치 권한과 Jarbis RPC 권한은 분리하여 관리합니다.

## RPC 권한과 값 처리

- 독립 `jarbis` ACL은 `root/usr/share/rpcd/acl.d/jarbis.json`에 정의돼 있습니다. SmartSafeHub의 로그인/ACL 매핑에서도 필요한 **인증된** 사용자에게만 읽기·쓰기 메서드를 허용해야 합니다.
- `status`, `devices_list`, `discovery_list`, `light_state`는 read, 나머지 작업은 write로 분리합니다. 특히 `broker_credentials`는 **MQTT 자격 증명(`secret`)을 반환하는 민감 API**이므로 일반 통계·상태 자동 폴링에 절대 포함하지 않습니다.
- 브라우저에서 `broker_credentials`를 명시적 사용자 동작으로만 요청하고, 비밀번호는 화면에서 일시적으로만 표시합니다. localStorage, sessionStorage, 캐시, 진단/텔레메트리, 콘솔 로그, 서버 전송에 포함하지 않습니다.
- `device_pair.admin_password`는 사용자가 입력한 Tasmota 웹 관리자 비밀번호입니다. 패키지는 이를 UCI에 저장하지 않으며 LAN HTTP POST 전송에는 TLS가 적용되지 않습니다.
- `light_set`의 `accepted`는 **MQTT 게시 성공**입니다. 물리적인 전구의 상태는 `light_state.observed`와 `source`로 별도 판단하고 `observed:false`를 OFF로 표시하지 않습니다.
- 지원하는 색상은 6자리 RGB 16진수 문자열이고 색온도는 Tasmota CT 153~500 mired입니다. UI 입력 범위에서 검증한 뒤에도 RPC의 서버 측 검증이 최종 기준입니다.

구체적 메서드 명세는 [ARCHITECTURE.md](ARCHITECTURE.md)를 참고하세요.

## 설치·연결 사전 점검

```sh
ubus list jarbis
ubus call jarbis status '{}'
/usr/libexec/jarbis-broker diagnose
```

`diagnose`는 **관리형 Broker** 사전 조건을 읽기 전용으로 검사합니다. 관리형 충돌이 발생해도 기존 Mosquitto 파일/UCI 설정, 인증 파일을 삭제하거나 덮어쓰지 마세요. 기존 Broker 사용자는 `external` 모드로 연결해야 합니다. 외부 Broker의 `brokerReady`는 `mosquitto_pub` QoS 1 게시가 허용된 경우에만 `true`입니다. 외부 Broker 자동 연결(`device_pair`)은 지원하지 않습니다.

설치·업데이트 시 `jarbis-rpcd-reconcile`은 reload로 객체 등록을 확인한 뒤 필요한 경우에 한해 rpcd restart를 시도합니다. 이 작업은 관리 세션에 영향을 줄 수 있으므로 실제 기기 테스트가 필요합니다.

## 0.2.4 출시 검증

SmartSafeHub 스마트홈의 **온습도 센서 측정값·간편 연결·공간별 기기 관리**를 위한 공식 최소 버전은 **Jarbis 0.2.4**입니다. 기존 Tasmota 전구 제어 기능은 유지됩니다. 신규 설치 기본 설정은 비활성화이며, 업그레이드해도 기존 `/etc/config/jarbis`, MQTT 인증 정보와 센서 백업을 변경하지 않습니다.

프로덕션 출시 전에는 지원 공유기에서 다음을 확인하세요.

1. 기존 `0.2.3-r6`에서 `0.2.4-r1` APK로 업데이트합니다. 저장된 기기 목록·공간·MQTT 인증 정보가 유지되어야 합니다. 비밀번호를 로그나 이슈에 첨부하지 마세요.
2. 저장소의 `tools/release-smoke.sh`를 공유기로 복사한 후 `sh /tmp/release-smoke.sh`를 실행합니다. **읽기 전용** 검사로 패키지 RPC 버전과 등록 기기 목록을 확인합니다. 관리형 Broker가 활성화되어 있다면 연결 상태도 확인합니다.
3. Shelly H&T Gen3를 깨워 MQTT 온도·습도·배터리가 갱신되는지, 2시간 절전 이후 다음 보고가 들어오는지 확인합니다. 전구의 켜기·끄기와 밝기·색온도 조절도 직접 테스트합니다.
4. 공유기를 재부팅한 뒤 센서의 저장된 측정값과 전구 등록 정보가 유지되는지 확인합니다. 마지막 센서를 제거한 상태에서는 MQTT 센서 수신기가 실행되지 않아야 합니다.
5. Apps의 **stable** 채널에 현재 펌웨어 아키텍처에 맞는 승인 패키지가 등록되었는지 확인한 뒤 사용자 설치를 진행합니다. 패키지 승인이나 실제 공유기 확인은 이 저장소의 자동 테스트가 대체하지 않습니다.

패키지 설치·검증 과정에서 기존 MQTT 비밀번호를 재발급하거나 이미 등록된 기기를 초기화하지 마세요. 실기기 검증에 실패하면 stable 배포를 보류하세요.

## 펌웨어 및 앱 배포 전 확인

- 각 지원 아키텍처에서 종속 패키지와 `mosquitto_passwd` 제공 여부, 설치 후 저장공간·메모리 사용량 확인
- Apps의 승인 카탈로그/서명된 패키지/펌웨어별 복원 정책을 만족하는지 확인. Jarbis를 별도의 LuCI 앱으로 중복 등록하지 않기
- 신규 설치 비활성화, 기존 UCI/인증 정보 보존, 기존 Mosquitto 충돌 시 비파괴 동작, rpcd ACL 재적용 확인
- WAN으로 1883 포트를 열지 않았는지, 관리자에게만 자격 증명 조회가 허용되는지 점검

## Shelly H&T Gen3 (0.2.3-r3)

**간편 연결** (관리형 MQTT Broker 사용 시):
1. Shelly를 SmartSafeHub Wi-Fi에 연결합니다. Shelly의 HTTP 관리 API는 기본 인증이 없는 상태여야 합니다.
2. 스마트홈에서 기기를 검색한 뒤 `연결 및 추가`를 선택합니다. 기기가 잠들어 있으면 뒷면 버튼을 **짧게** 누르고 다시 시도합니다.
3. 기기가 깨어 있으면 Jarbis가 로컬 HTTP API로 모델과 MAC을 확인한 후 공유기 내장 MQTT 인증 정보를 직접 전달합니다. 비밀번호는 브라우저에 전달하거나 URL/프로세스 인자로 사용하지 않습니다.
4. 연결 전에 가능한 경우 HTTP에서 첫 온습도 측정값을 가져와 센서 카드에 표시합니다. 이후에는 기존 MQTT 수신기에서 최신 보고를 받습니다. 설정 변경 시 Shelly 공식 API의 필요 조건에 따라 자동 재시작합니다.

**안전한 예외 처리**: 기존의 다른 MQTT Broker가 설정되어 있으면 묵시적으로 덮어쓰지 않고 다시 확인받습니다. 절전 중에는 임의로 연결/재부팅하지 않고 버튼을 짧게 누르도록 안내합니다. HTTP 관리자 인증이 설정된 Shelly는 자동 연결 대상에서 제외하고 수동 연결을 유지합니다. DHCP 검색 후보는 사용자 승인을 받아야 하며, HTTP 연결 시 기기 모델·ID·MAC을 다시 확인합니다. 관리형 Broker가 아닌 경우에도 수동 연결을 사용합니다.

**수동 연결**은 고급 설정에 남아 있습니다. Shelly 관리 화면에서 MQTT 서버(공유기 LAN IP:1883), 사용자 이름/비밀번호, RPC status notifications를 입력하면 됩니다. 기본 MQTT topic prefix `shellyhtg3-<12자리 MAC>`을 사용합니다. HTTP가 닿지 않는 절전 기기도 DHCP 후보로 표시되지만, 자동 연결은 깨어 있는 상태에서만 가능합니다.

`source=http`은 최초 측정값을 직접 수신한 경우, `source=mqtt`는 기기의 MQTT 보고를 의미합니다. 최신 값을 정기적으로 강제 조회하지 않으며 배터리 절전을 유지합니다. 재부팅용 플래시 백업은 센서별 최대 6시간마다 갱신합니다.

보안: 로컬 승인된 센서 토픽만 캐시되고, 수신 페이로드 최대 4 KiB, 인증 정보는 RPC/로그에 노출되지 않습니다.
MQTT Broker는 기존 LAN 바인딩·인증 정책을 유지하고 Shelly Cloud는 필수 요구사항이 아닙니다.
참고: https://shelly-api-docs.shelly.cloud/gen2/Devices/Gen3/ShellyHTG3/

## 공간별 기기 관리 (0.2.3-r5)

`status.features.rooms=true`가 있을 때 SmartSafeHub 0.2.34-r6 이상에서 공간 선택을 제공합니다.

- `devices_list`는 각 기기에 `room`을 반환합니다. 기존 기기처럼 공간 설정이 없는 경우 `unassigned`가 기본값입니다.
- `device_room_set {"id":"<등록된 ID>","room":"living"}`는 인증된 사용자의 **쓰기 RPC**입니다. `living`, `bedroom`, `study`, `kitchen`, `other`, `unassigned`만 허용합니다.
- 변경은 `/etc/config/jarbis`의 개별 device 섹션에 기록되고, 브라우저 비밀 저장소나 MQTT 설정을 건드리지 않습니다.
- 센서·전구 수가 많아도 프론트엔드는 순환·분산 상태 조회를 수행하므로 기기 6대 초과가 누락되지 않습니다.
