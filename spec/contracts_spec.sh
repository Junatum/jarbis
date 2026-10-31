# SPDX-License-Identifier: GPL-3.0-or-later

Describe 'Jarbis ShellSpec 계약 테스트'
  It 'Tasmota 전구 명령의 검증과 MQTT 자격 증명 보호를 확인한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-mqtt.sh"
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
End
