# 보안 설계와 현재 한계

Jarbis `0.1.0-r12` 보안 경계를 설명합니다. 취약점 신고는 [루트 SECURITY.md](../SECURITY.md)에 있는 **비공개 신고 절차**를 사용하세요.

## 기본 정책

- **기본 비활성화:** 사용자 활성화 전에는 관리형 Broker를 초기화하지 않습니다. WAN 방화벽/포트포워딩 규칙을 추가하지 않습니다.
- **기존 설정 보호:** 기존 Mosquitto listener/bridge, `use_uci` 또는 사용자 파일 설정을 덮어쓰지 않습니다. 충돌 시 거부하고 외부 Broker 모드를 안내합니다.
- **인증된 로컬 MQTT:** 관리형 Broker는 루프백과 공유기의 LAN IPv4에 1883/TCP 리스너를 만들고 `allow_anonymous=0`을 적용합니다. LAN 주소가 잘못되면 시작하지 않습니다.
- **RPC ACL 분리:** read (`status`, `devices_list`, `discovery_list`, `light_state`)와 write (`light_set`, `discovery_scan`, 설정/기기 관리, 연결, `broker_credentials`)를 분리합니다. **Jarbis 패키지 ACL 정의만으로 관리자 인증이 보장되는 것은 아니며**, SmartSafeHub 세션 권한 부여를 별도로 검사해야 합니다.
- **좁은 명령 경계:** CLI는 등록된 기기/Topic과 허용된 기능/값을 재검증합니다. 임의 MQTT publish, 셸 인자, 임의 IP 스캔은 노출하지 않습니다.
- **확인 가능한 상태만 표시:** MQTT publish 성공은 물리적인 전구 동작을 뜻하지 않습니다. 직접 확인되지 않은 상태는 `observed:false`입니다.

## 비밀번호·개인 정보

- 인증 정보는 최초 관리형 Broker 구성 시 무작위 생성되며, `/etc/jarbis/` 및 `/etc/mosquitto/jarbis.passwd`에 제한된 권한으로 저장됩니다. 커맨드라인에 `-P` 비밀번호를 노출하지 않고 별도 client config를 사용합니다.
- `status`, `devices_list`, `discovery_list`, `device_pair`는 MQTT 비밀번호를 반환하지 않습니다. **예외: `broker_credentials`는 호출자에게 `jarbis` write ACL이 있으면 `secret`을 응답에 포함**합니다. RPC 내부의 별도 관리자 재인증은 없으므로 관리자에게만 권한을 부여하고, UI에서는 명시적 요청 때만 호출해야 합니다. 이 메서드는 민감한 write 권한이며, 호출·응답 로그, 브라우저 저장소, 진단 데이터 및 원격 수집에서 제외해야 합니다.
- Tasmota HTTP 요청은 프록시와 리다이렉트를 금지하고 정해진 LAN IPv4만 사용합니다. 자동 연결의 웹 관리자 비밀번호는 인증된 호출에서 제한된 루트 전용 `/tmp` 임시 파일로 전달되며, 기기 설정 요청에는 암호화되지 않은 HTTP POST가 사용됩니다. 저장/로깅하지 말아야 하며 신뢰할 수 있는 LAN에서만 실행하세요.
- 발견 정보는 `/tmp/jarbis-discovery.records`에서만 관리되며 검색 후보에 등록/제어 권한을 부여하지 않습니다. HTTP 검색은 DHCP 리스 기반 `/24` LAN 최대 **16대**, 짧은 타임아웃과 크기 제한을 사용합니다. MQTT retained 검색도 최대 2초/32KiB로 제한합니다.
- `conffiles`, `keep.d`에 MQTT 인증 정보가 포함됩니다. **sysupgrade/설정 백업은 비밀번호가 포함된 민감 파일**이므로 암호화된 저장소에 보관하고 공개 저장소/이슈에 첨부하지 마세요.

## 알려진 한계와 배포 조건

1. 관리형 Broker의 1883/TCP 연결은 **TLS가 없는 평문 MQTT**입니다. WAN, 게스트망, 공유 LAN에서의 노출을 피하고 신뢰된 IoT 네트워크로 제한해야 합니다.
2. 전구들이 하나의 MQTT 계정을 공유하며, 기기별 토픽 ACL/자격 증명 분리는 아직 구현되지 않았습니다. 이를 완료하기 전에는 강한 멀티테넌트 분리를 보장할 수 없습니다.
3. Tasmota HTTP 발견/자동 연결 역시 TLS가 아니므로 장치가 공유 네트워크에 있거나 중간자 공격 위험이 있는 환경에 사용하면 안 됩니다.
4. 관리형 Broker의 포트가 실제 WAN/비신뢰 인터페이스에서 접근되지 않는지는 **공유기 네트워크 구성별로** 검증해야 합니다. 로컬 리스너 생성/방화벽 미변경만으로 노출 위험이 자동 해소되지는 않습니다.
5. CI의 모의 RPC/셸 테스트는 실제 공유기 권한·Mosquitto 패키지 빌드·전구 모델의 동작을 대체하지 않습니다.

## 최소 배포 점검

- 실제 관리자/일반 사용자/비로그인 상태로 각각 `broker_credentials`, `settings_update`, `device_pair` 권한 확인
- 1883/TCP가 WAN·비신뢰 VLAN에서 차단되었는지 실기기 네트워크에서 검증
- 기존 Mosquitto 구성 충돌 시 자동 변경이 없고, 펌웨어 업그레이드 이후 credential 파일의 권한과 내용이 보존되는지 검증
- 로그·원격 진단·브라우저 개발자 도구에 비밀번호가 자동 기록되지 않는지 확인
