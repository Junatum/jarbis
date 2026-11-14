# Jarbis 아키텍처 및 RPC v1

현재 기준: `0.1.0-r12`. 이 문서는 구현된 기능만 설명하며 Scene/규칙 엔진/AI는 설계 계획입니다.

```text
SmartSafeHub 공유기 웹사이트 (인증된 LuCI 세션)
                 │ ubus / rpcd ACL
                 ▼
     jarbis.uc → jarbis/core.uc (API v1)
                 │
     ┌───────────┼───────────────────┐
     ▼           ▼                   ▼
  조회/상태   등록/설정/승인       Broker 관리
  UCI/캐시    jarbis-manage          jarbis-broker
  │           jarbis-pair            │
  │           │                      ▼
  │       Tasmota HTTP POST    Mosquitto (procd)
  ▼           │                      │
  jarbis-state / jarbis-discover     │
  (HTTP 우선, MQTT 대체)             │
  │                                  │
  └────── jarbis-control ── mosquitto_pub ── Tasmota 전구
```

- **기본 비활성화:** 사용자가 활성화할 때만 관리형 Broker를 준비합니다. Jarbis 자체의 상주 폴링 데몬은 없습니다.
- **Broker:** 기존 Mosquitto의 커스텀 설정을 덮어쓰지 않습니다. 관리형은 127.0.0.1과 LAN IP의 인증형 1883/TCP 리스너를 사용하고 방화벽/WAN 설정은 변경하지 않습니다. 외부 Broker 모드는 기존 Broker를 사용하며, `brokerReady`는 제공된 0600 client config로 QoS 1 게시를 확인합니다. 외부 Broker에 새 설정을 작성하지 않습니다.
- **Discovery:** DHCP 리스의 `/24` LAN 후보 HTTP 최대 16대, MQTT retained 후보 수집을 제한된 시간/크기로 수행합니다. 결과는 `/tmp/jarbis-discovery.records`에만 저장합니다. 검색은 등록이나 접근 권한 부여가 아닙니다.
- **Device:** UCI의 `config device`로 승인 등록된 `kind=light`, `protocol=tasmota` 기기만 제어 가능합니다. 표준 Tasmota FullTopic `%prefix%/%topic%/`을 가정합니다.
- **상태:** `jarbis-state`는 등록 기기를 검증한 뒤 확인된 HTTP 후보를 먼저 조회하고 실패 시 MQTT 응답을 시도합니다. 유효한 기기 응답이 없으면 `observed:false`로 반환합니다.
- **연결:** `device_pair`는 승인한 등록 기기의 이전 설정을 확인하고, MQTT 자격 증명을 제한된 임시 파일과 LAN HTTP 요청 본문으로 전달합니다. 이전 Broker 변경은 별도 승인해야 합니다.

## API v1

모든 메서드의 응답은 성공 시 `{ "ok": true, "data": ..., "error": null }`, 실패 시 `{ "ok": false, "data": null, "error": { "code": "...", "message": "..." } }`입니다.

| 메서드 | ACL | 요청 | 주요 응답/의미 |
| --- | --- | --- | --- |
| `status` | read | `{}` | `version`, `apiVersion`, `enabled`, `mqttConfigured`, `brokerMode`, `brokerHost`, `brokerPort`, `brokerReady`, `features` |
| `devices_list` | read | `{}` | 등록된 기기 목록 (`id`, `name`, `kind`, `protocol`, `topic`, `enabled`, `capabilities`) |
| `discovery_list` | read | `{}` | 마지막 발견 후보 목록 (승인 전 제어 불가) |
| `light_state` | read | `{ "id": "..." }` | `observed`, `power`, `brightness`, `color`, `colorTemperature`, `source`, 실패 시 `reason` |
| `discovery_scan` | write | `{}` | 제한된 수동 검색 후 후보 목록 |
| `settings_update` | write | `{ "enabled": true }` | 기능 활성화 결과 |
| `device_add` | write | `{ "id": "...", "name": "...", "topic": "..." }` | 발견된 Topic의 기기 추가 |
| `device_update` | write | `{ "id": "...", "name": "...", "enabled": true }` | 기기 수정 |
| `device_remove` | write | `{ "id": "..." }` | 등록 기기 제거 |
| `device_pair` | write | `{ "id": "...", "admin_password": "", "replace_existing": false }` | `configured`, `mqttConfirmed`; 요청/응답에 MQTT 비밀번호가 나타나지 않음 |
| `light_set` | write | `{ "id": "...", "capability": "power", "value": "ON" }` | `accepted:true`는 게시 성공이지 전구 상태 확인이 아님 |
| `broker_credentials` | write | `{}` | `host`, `port`, `username`, **`secret`**. 명시적 관리자 요청으로만 호출해야 함 |

`light_set` capability는 `power` (`ON`/`OFF`), `brightness` (0~100), `color` (`RRGGBB`), `color_temperature` (153~500 mired)를 지원합니다. 물리적인 전구가 해당 기능을 지원하는지는 별도 검증해야 합니다. 문자열 제어 인자 및 등록된 Device ID/Topic은 RPC와 실행 스크립트에서 각각 검사합니다.

## 패키징 및 복구

- `Makefile`의 `postinst`는 실제 공유기에서만 `jarbis-rpcd-reconcile`을 실행합니다. rpcd reload 후 객체가 보이지 않을 때에만 제한적으로 restart합니다.
- `Package/jarbis/conffiles`와 `/lib/upgrade/keep.d/jarbis`는 UCI 및 MQTT 인증 정보를 보존합니다. **보존 파일에는 실제 비밀번호가 있으므로 백업을 보호해야 합니다.**
- ShellSpec, Python 계약 검사, 모의 UCI/파일 시스템의 ucode RPC 테스트는 CI에서 실행됩니다. 실제 Mosquitto 또는 전구가 동작한다는 보장은 아닙니다.

## 설계 단계 (미구현)

`Device → Capability → Observed State → Event → Rule/Scene → Policy/Authorization → Action Executor → Adapter`로 확장할 수 있습니다. 추후 온디바이스 AI가 도입되어도 기존 인증·기기 검증·제어 경로를 우회하지 않아야 합니다. Matter 등 추가 프로토콜은 아직 지원하지 않습니다.
