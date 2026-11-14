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

## 펌웨어 및 앱 배포 전 확인

- 각 지원 아키텍처에서 종속 패키지와 `mosquitto_passwd` 제공 여부, 설치 후 저장공간·메모리 사용량 확인
- Apps의 승인 카탈로그/서명된 패키지/펌웨어별 복원 정책을 만족하는지 확인. Jarbis를 별도의 LuCI 앱으로 중복 등록하지 않기
- 신규 설치 비활성화, 기존 UCI/인증 정보 보존, 기존 Mosquitto 충돌 시 비파괴 동작, rpcd ACL 재적용 확인
- WAN으로 1883 포트를 열지 않았는지, 관리자에게만 자격 증명 조회가 허용되는지 점검
