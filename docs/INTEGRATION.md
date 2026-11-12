# SmartSafeHub integration contract

Confirmed against user-provided `luci-app-smartsafehub-develop(20261031-012234).zip`:

- UI: Preact / TypeScript, hash-based routes (`frontend/src/app/routes.ts`)
- RPC: existing LuCI JSON-RPC client (`frontend/src/api/rpc.ts`)
- Backend uses isolated rpcd ucode objects (e.g. `smartsafehub_guest`).
- ACL groups are declared at `root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json`.

**This scaffold intentionally does not modify SmartSafeHub sources or generate frontend bundles.**

Recommended subsequent integration patch (separate release, version bump, changelog, tests):

1. Add `#smart-home` route (`스마트홈` navigation).
2. Add `frontend/src/api/jarbis.ts` typed API adapter, using shared scheduler with low request priority for outside-system calls.
3. Add `SmartHomePage.tsx` with empty/not-installed/disabled states and `light_set` controls.
4. Extend *SmartSafeHub* ACL to grant `jarbis` read/status/list and write/light_set for authenticated sessions, subject to the existing root password checks and login model.
5. Add test/demo fixtures; do not generate or commit new frontend dist files.

Deploying the Jarbis package alone **does not** add a SmartSafeHub UI menu. Avoid installing separate LuCI root-entry hooks or replacing core SmartSafeHub RPC. Preserve `jarbis` RPC independently so package faults do not affect the router admin login.

## SmartSafeHub 웹 통합 (0.1.0-r6)

Jarbis APK 설치 후 공유기 웹사이트의 **스마트홈** 메뉴에서 활성화,
검색, 기기 추가·삭제, 전원/밝기 테스트를 할 수 있습니다.
브라우저는 독립 rpcd 객체 `jarbis`에만 접근하며 관리자 ACL이 필요합니다.

- `status`: `brokerReady`는 MQTT에 인증된 실제 연결 시도의 결과입니다.
- `settings_update {enabled:bool}`: Broker 시작 성공 후에만 활성화합니다.
- `device_add {id,name,topic}`: `/tmp` 검색 캐시에서 발견된 Topic만 등록합니다.
- `device_update {id,name,enabled:bool}`, `device_remove {id}`: 기기 설정을 변경합니다.
- `broker_credentials`: 사용자 요청 시에만 로컬 MQTT 인증 정보를 전달합니다.
  브라우저에서 보관하거나 로그/통계로 전송하지 않아야 합니다.

Tasmota MQTT 연결은 전구 관리 웹 UI에서 사용자가 직접 승인하여 설정해야 합니다.
동일 LAN에서 전구를 발견해도 연결된 상태를 의미하지 않습니다.
기존 Mosquitto 파일 설정이 활성화되어 있으면 Jarbis는 설정을 덮어쓰지 않고
활성화를 거부하며, 이때 외부 Broker 모드를 사용해야 합니다.

새 펌웨어 배포 전 `mosquitto_passwd` 제공 여부와 앱 복원 상태를 확인하세요.
