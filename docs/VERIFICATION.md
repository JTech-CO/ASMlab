# ASMlab v0.2.0 검증 보고서

작성일: 2026-09-23. 대상: 이 패키지의 NASM 직접 빌드 Linux x86-64 실행 파일과 독립 런타임 시험 fixture.

## 1. 결과와 범위

**전체 릴리스 검사 71,319개 assertion 통과, 실패 0. 별도 실패 차단 검사 15개 통과, 실패 0.**

| 구성 | 검사 수 | 근거 |
|---|---:|---|
| 기본 release 기존 회귀 | 14,410 | [release-regression.json](../evidence/native/release-regression.json) |
| debug 기존 회귀 | 14,410 | [debug-regression.json](../evidence/native/debug-regression.json) |
| 기존 네이티브 상수·명령·캡처 계약 | 1,254 | [native-contract.json](../evidence/native/native-contract.json) |
| libc primitive 비교 빌드 기존 회귀 | 14,410 | [libc-reference-regression.json](../evidence/runtime/libc-reference-regression.json) |
| 독립 기본 루틴·ABI·입출력·decimal 어댑터 | 26,123 | [runtime-unit.json](../evidence/runtime/runtime-unit.json) |
| 호출 경계·오브젝트·reference 비교 | 712 | [runtime-boundary.json](../evidence/runtime/runtime-boundary.json) |
| **합계** | **71,319** | [release-summary.json](../evidence/release-summary.json) |
| 기존 guard / 추가 runtime guard | 6 / 9 | [기존 6개](../evidence/native/gate-guards.json), [추가 9개](../evidence/runtime/runtime-gate-guards.json) |

Native Gate 30,074 + Runtime Gate 41,245다. 기존 14,410 corpus를 세 개의 빌드에서 반복하며, 자체 루틴 호출마다 ABI assertions도 센다. 전체 수는 서로 독립된 수식·테스트 입력의 개수가 아니다. guard 내부에서 일부 검사를 다시 실행하는 횟수는 합계에 또 더하지 않았다.

빌드 성공, 기능 시험 통과, 무의존 smoke 성공, 전체 L3 완료를 서로 구분한다. **전체 ASMlab은 여전히 Level 2**이고 독립 smoke에는 수식 평가기가 없다.

## 2. 실제 빌드와 출처

세 앱 산출물은 동일한 NASM 수식 코어와 libc I/O 어댑터를 링크한다. 기본 release/debug는 자체 `src/rt/primitives.asm`, 비교 빌드는 개발용 libc primitives를 사용한다. release는 `-Ox`, debug는 `-O0 -g -F dwarf`로 빌드했다. libc는 여전히 콘솔·파일·decimal과 CRT 경로에 존재한다.

독립 smoke는 자체 start/smoke/primitives/integer/fd_io/syscalls 오브젝트를 GNU ld로 연결했다. 테스트용 공유 fixture를 앱에 연결하지 않았으며 smoke에는 가짜 syscall provider가 없다. NASM은 첨부된 서드파티 사전 빌드 2.16.03을 해시 재확인 후 사용했다. [도구 출처](TOOLCHAIN-PROVENANCE.md)

[실제 명령 로그](../evidence/build-test.log) · [실행 환경](../evidence/native/environment.txt) · [기본 release 출처](../bin/asmlab.build.json) · [debug 출처](../bin/asmlab-debug.build.json) · [비교 빌드 출처](../bin/asmlab-libc-reference.build.json) · [foundation 출처](../bin/runtime-foundation.build.json)

모든 빌드 입력·오브젝트·링크 맵·실행 파일 SHA256을 기록한다. 소스 경로가 이동해도 파일 내용과 상대 경로로 검사할 수 있도록 했다. 기록의 원래 도구 절대 경로가 사용자 장치에 있어야 `make verify`가 가능한 것은 아니다. NASM 실행은 재빌드 때 필요하다. 해시/manifest는 디지털 서명이나 공급망 보안 인증이 아니다.

## 3. 기존 수치·관찰 동작 보존

기존 회귀 스크립트 `tests/verify.py`를 유지했다. 수학 함수 비교는 Python 표준 math를 기준으로 하며 MPFR 고정밀 oracle가 아니다. 함수별 정의역과 오차 계약은 [NUMERICS.md](NUMERICS.md)를 따른다.

Native Gate는 기존 50개 64비트 상수 값, 선택한 SSE2 12종의 명령 바이트·실제 캡처 위치·XMM 값·MXCSR와 release/debug의 결과를 확인한다. Runtime boundary 검사에서는 기본 release/debug/개발 reference 사이 639개 JSON 결과 레코드 및 백엔드당 74개 trace frame의 상태를 비교했다. 명령 주소는 서로 다른 링크 배치에 따라 다를 수 있어 정규화하고, 각 실행 파일의 실제 주소 검사는 별도 Native Gate로 유지한다.

v0.1.1 원본과의 보조 비교에서는 결과 레코드 520개와 다섯 수식의 trace 상태가 일치했다. `src/math.asm`/`src/kernels.asm`은 바이트 단위로 동일하다. 이 추가 비교는 원래 ZIP을 사용한 별도 기록으로, 표준 릴리스 합계에는 더하지 않았다. [기준 버전 비교](../evidence/native/baseline-v011-comparison.json)

## 4. 자체 루틴 시험

| 분류 | 다룬 경계 |
|---|---|
| 메모리 | 겹침 양방향·자기 복사·길이 0·정렬되지 않은 span·앞뒤 canary |
| 문자열 | NUL 위치·최대 길이·unsigned byte 비교·읽기 상한 |
| 정수 포매터 | 부호 없는 최대값·INT64_MIN·16자리 hex·모든 시험 용량·실패 시 무변경 |
| 정수 파서 | 정확 범위·overflow·부호·빈 입력·잘못된 문자·부분 파싱 거부 |
| ABI | RBX/RBP/R12–R15, DF, MXCSR 보존과 함수 반환 |
| 실제 I/O | 파일·바이너리 파이프·NUL·무개행 EOF·openat 네 번째 인수·PTY ioctl |
| 실패 주입 | partial write, EINTR, EAGAIN, 진행 없음, read 오류, flush 일부 실패·sticky error |
| 보호 페이지 | PROT_NONE 경계에 배치한 12개 별도 프로세스 검사 |
| smoke | 옵션·정수·echo/cat·파일 오류·닫힌 fd·/dev/full·SIGPIPE |

독립 시험 26,123개 중 17,079개는 호출별 ABI assertion이다. ABI 보존은 실제 NASM 호출을 probe가 감싸서 검사한다. fault provider가 Python callback으로 진입하는 경로에서는 Python 내부의 MXCSR 보존을 요구하지 않고 GPR/DF 등을 분리해서 검사한다. 실제 own-native 경로의 MXCSR 검사는 유지한다.

보호 페이지와 가짜 syscall은 시험 호스트에서만 설정한다. 실제 앱·smoke에 Python·C 시험 함수를 넣지 않았다. 공유 fixture는 ctypes로 검사할 수 있게 만든 도구이며 앱의 동적 플러그인이 아니다.

## 5. decimal 시험의 정확한 의미

현재 어댑터의 `strtod`를 독립 정확 유리수/정수 반올림 기준과 407개 표본에서 비교했다. 원시 binary64 bits와 end-pointer를 각각 확인한 814개 assertion이며, oracle 자체의 고정 기대 비트 7개 sanity check를 추가했다. 어댑터 수준의 긴 표본은 현재 앱의 토큰 길이를 확장하지 않는다.

이 시험은 v0.2.0에서 **자체 float64 문자열 변환을 구현했다는 뜻이 아니다.** 전체 숫자 입력은 여전히 libc 어댑터를 사용한다. 정확한 유리수에서 nearest-even으로 반올림하는 시험 기준은 Python 개발 코드이고, 실제 수학 계산 경로에 들어가지 않는다.

## 6. 의존성과 실패 차단

기본 앱 오브젝트는 15개의 `rt_*` 심볼만 미해결 참조한다. own primitive 오브젝트에는 외부 참조가 없다. 기본 앱 ELF에 libc 메모리·문자열 entrypoint가 나타나면 실패하도록 검사한다. libc I/O globals/functions와 CRT는 허용된 경계에 남아 있다.

smoke에는 PT_INTERP, DT_NEEDED, 미해결 심볼과 CRT 입력이 없고 GNU_STACK은 실행 불가다. 독립 primitive/fault fixture도 libc를 필요로 하지 않으나 decimal-adapter fixture만 의도적으로 libc를 링크한다. [실제 오브젝트·smoke 감사](../evidence/runtime/module-audit.txt)

새 guard는 변조된 smoke/공유 fixture/오브젝트, 달라진 내부 소스, 누락된 입력 inventory, 잘못된 모듈 그룹, 누락된 reference 출처를 거부한다. NASM을 찾지 못한 foundation 빌드는 이전 실행 파일·fixture·sidecar를 남기지 않음을 확인했다. 기본 6개와 추가 9개가 모두 통과했다. [guard 실행 로그](../evidence/guard-tests.log)

이것은 악의적인 공격자가 모든 소스·검증기·메타데이터를 함께 바꾸는 경우에 대한 인증이 아니다. 해시를 포함한 일반 무결성·오래된 산출물 혼용 방지 검사다.

## 7. 재현

```sh
# 제공된 바이너리, object, link map과 소스로 확인; NASM 재빌드 없음
make verify
make test-guards

# 새 네이티브 빌드부터 확인
make clean
make -j2 test
make test-guards
```

Ubuntu 계열에서 NASM/gcc/make/binutils/python3가 필요하다. Python 최소 3.10이다. `make verify`에는 Python/binutils와 동봉된 선택 build 오브젝트·맵이 필요하다. `make clean`으로 이를 제거했다면 `make test`로 다시 만든다.

## 8. 미검증 및 미구현

실행 검증은 Linux x86-64 컨테이너 한 환경이다. 설정한 Ubuntu 22.04/24.04 원격 CI를 실행한 것이 아니며 WSL 장비·Windows native·ARM64·Pi·다중 사용자 서버 검증은 없다. 전체 수치 정의역의 올바른 반올림 증명, 전수 메모리 안전, 퍼징 완전성, 보안 인증, 성능 우위도 주장하지 않는다.

자체 binary64 입출력, 전체 앱 fd 통합, 전체 앱의 CRT/libc 제거, 동적 allocator/Value, reentrant API, 그래프/웹/ARM 코드는 후속 개발이다. [현재 경계](LEVEL3-CONTRACT.md)

`evidence/baseline-0.1.1/`와 `baseline-0.1.0/`는 과거 산출물 기록이다. 현재 테스트 성공으로 혼용하지 않는다.
