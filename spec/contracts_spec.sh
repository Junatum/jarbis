# SPDX-License-Identifier: GPL-3.0-or-later

Describe 'Jarbis ShellSpec 계약 테스트'
  It 'Tasmota 전구 명령의 검증과 MQTT 자격 증명 보호를 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-mqtt.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '전구 MQTT STATUS11 상태 수신과 실패 시 안전한 처리를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-state.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Jarbis 공식 Apps 출시와 공유 MQTT Broker 제거 안전성을 검증한다'
    When run command python3 "$SHELLSPEC_PROJECT_ROOT/tests/test-apps-release.py"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '패키지·RPC·ACL·버전 및 보안 계약을 확인한다'
    When run command python3 "$SHELLSPEC_PROJECT_ROOT/tests/test-contract.py"
    The status should be success
    The output should include 'OK'
    The error should be blank
  End

  It 'RPC 진입점과 내부 ucode 모듈의 컴파일을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-ucode.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'ucode 모듈 컴파일러 테스트 실행기 자체를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-ucode-runner.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'OpenWrt 25.12 BusyBox 기본 명령 및 경량 성능 정책을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-openwrt-commands.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '새 테스트가 누락되지 않고 CI에서 실행되는지 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-suite-integrity.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End
  It '실제 ucode RPC 함수의 UCI 읽기와 제어 인자를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rpc-runtime.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Shelly 센서 간편 연결과 최초 측정값 및 기존 MQTT 보호를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-shelly-pair.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '패키지 설치 경로와 ACL 및 권한 계약을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-package-contract.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '패키지 설치 이후 누락된 RPC 객체를 제한적으로 복구한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-rpcd-reconcile.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '센서 등록 변경에 따른 MQTT 수신기와 캐시 생명주기를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-shelly-lifecycle.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '0.2.4 정식 버전의 읽기 전용 공유기 점검을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-release-check.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '0.2.3-r6에서 0.2.4-r1로 업그레이드할 때 설정과 수신기를 보존한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-upgrade.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '기기 및 MQTT 인증 설정을 업그레이드 시 보존한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-backup-restore.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'CHANGELOG 릴리스 간격과 버전 표기를 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-changelog-spacing.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End
  It 'HTTP 리다이렉트로 자격 증명이 다른 주소로 전송되지 않는지 확인한다'
    When run command python3 "$SHELLSPEC_PROJECT_ROOT/tests/test-http-redirect.py"
    The status should be success
    The output should include 'PASS:'
    The error should be blank
  End

  It 'Mosquitto 비밀번호 도구의 빌드 설정을 실제 Make 레시피로 검사한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-mosquitto-build.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '관리형 MQTT 브로커 자동 설정과 기존 설정 보호를 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-broker.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It '승인된 장치 등록과 설정 변경을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-manage.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Tasmota 자동 연결과 자격 증명 보호 및 관리자 승인 절차를 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-pair.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'Shelly H&T Gen3 기기 검색 및 MQTT 측정값 수신을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-shelly.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End

  It 'DHCP 및 Tasmota MQTT 자동 검색과 탐색 제한을 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-discovery.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End
End
