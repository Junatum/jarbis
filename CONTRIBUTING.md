# Jarbis 기여 가이드

오류 제보와 코드 개선을 환영합니다. Jarbis는 Flash/RAM이 제한된 OpenWrt 장치에서 실행되므로 일반 Linux에서 동작하는 것만으로는 충분하지 않습니다.

## 작업 방식

1. 공개 릴리스 기준은 `main`, 개발 및 검증 작업은 `develop`을 사용합니다. 변경 사항은 대상 브랜치로 Pull Request를 보냅니다.
2. 민감한 정보(공유기 백업, MQTT 비밀번호, 개인 네트워크 정보, 실기기 토큰)는 이슈·PR·테스트 fixture·커밋에 올리지 마세요.
3. 실제 환경에서 재현한 문제는 사용 모델, OpenWrt 버전, 패키지 revision, 예상 결과/실제 결과, **비밀정보를 제거한** 최소 로그로 정리합니다.
4. OpenWrt 25.12 BusyBox ash 호환성과 상주 프로세스/디스크 쓰기 부담을 고려해 구현합니다. ShellSpec 테스트명에는 한국어로 검증 의도를 작성합니다.
5. 버전 업데이트 시 `Makefile`의 `PKG_RELEASE`, `core.uc`의 `status.version`, `CHANGELOG.md` 최상단 릴리스와 README 표기를 일치시킵니다. CHANGELOG 블록 사이의 공백 두 줄을 유지합니다.

## 기본 테스트

```sh
sh tests/test-suite-integrity.sh
sh tests/test-openwrt-commands.sh
python3 tests/test-contract.py
shellspec
```

- 새 `tests/test-*.sh` 또는 `tests/test-*.py`는 `spec/contracts_spec.sh`에서 **정확히 한 번** 호출합니다. 누락/중복은 CI 검사에서 실패합니다.
- CI의 `JARBIS_REQUIRE_UCODE=1`은 실제 ucode 문법 컴파일과 모의 UCI RPC 실행을 강제합니다.
- 실행 환경에서 ShellSpec/ucode가 없는 경우 전체 테스트 통과를 주장하지 마세요.
- 변경된 기능의 실패 시나리오(권한 거부·타임아웃·서비스 오류·설정 충돌·백업 보존)를 테스트합니다.

## 라이선스·보안

기여된 코드는 기존 파일의 SPDX `GPL-3.0-or-later` 표기를 유지하고, 외부 소스/리소스를 추가하는 경우 라이선스 호환성, 저작권, 원 출처 및 필요한 고지·전문을 `LICENSES/`에 보관하세요. Mosquitto 같은 런타임 의존성의 소스는 이 저장소에 번들하지 않습니다.

RPC에서 사용자 입력을 실행 스크립트로 전달하는 경우 항상 인자 목록으로 전달하고, UCI 기기 소유권과 Topic·기능·값을 이중 검증합니다. 신규 권한은 `jarbis.json`, 테스트, 보안 문서를 함께 수정해야 합니다. **비밀번호가 필요한 새 RPC는 원칙적으로 만들지 마세요.** 취약점은 [SECURITY.md](SECURITY.md)를 통해 비공개로 신고해 주세요.
