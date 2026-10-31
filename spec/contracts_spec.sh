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

  It '새 테스트가 누락되지 않고 CI에서 실행되는지 검증한다'
    When run command sh "$SHELLSPEC_PROJECT_ROOT/tests/test-suite-integrity.sh"
    The status should be success
    The output should start with 'PASS:'
    The error should be blank
  End
End
