# ASMlab v0.2.0 - Runtime Foundation

**구현 상태: 완료 / 전체 ASMlab은 여전히 Level 2.**

v0.1.1의 수식·행렬·수학·추적 기능을 유지하면서 외부 런타임을 교체할 수 있는 호출 경계와 자체 기본 루틴을 만들었다. 별도 `runtime-smoke`는 libc/CRT 없이 실행되지만, 이것을 전체 ASMlab의 Level 3 완료로 취급하지 않는다.

[README](../README-KR.md) · [ABI 명세](RUNTIME-ABI.md) · [검증 보고서](VERIFICATION.md) · [변경 이력](../CHANGELOG.md)

## 1. 무엇이 실제로 연결되었는가

| 구분 | 이번 구현 | 전체 ASMlab 연결 여부 |
|---|---|---|
| 메모리·문자열 | memcpy/memmove/memset/memcmp/strlen/strnlen/strcmp의 자체 NASM 루틴 | 기본 release/debug에서 사용하는 호출에 연결 |
| 콘솔·파일 | `rt_*` API와 libc 호환 어댑터, opaque stream handle | 연결. libc 의존성은 어댑터 안에 유지 |
| float64 문자열 변환 | `rt_decimal_from_cstr` 경계와 독립 비교 시험 | 연결. 실제 변환은 여전히 strtod |
| 정수·16진수 변환 | 자체 uint64/int64 파싱과 용량 제한 포매터 | 독립 시험·smoke에서 사용 |
| syscall·fd 입출력 | read/write/openat/close/ioctl/exit와 오류 처리 | 독립 시험·smoke에서 사용 |
| Reader/Writer | 4KiB 버퍼, EOF·오류 구분, 부분 쓰기·flush 처리 | 독립 시험·smoke에서 사용 |
| 프로그램 시작 | 자체 `_start`와 인수 전달·종료 | smoke에만 사용. 전체 앱은 CRT/main 유지 |
| 비교 백엔드 | libc primitive adapter | 개발용 별도 실행 파일에만 연결 |

**자체 기본 루틴을 시험만 한 것이 아니다.** 전체 앱에서 기존에 사용하던 메모리·문자열 호출은 자체 구현으로 교체했다. 반대로 별도 fd Reader/Writer를 이미 전체 앱에 적용했다고 주장하지 않는다.

## 2. 구조

```text
전체 ASMlab (Level 2)
  parser / evaluator / workspace / kernels / view / main
                |
             rt_* API
                +-- src/rt/primitives.asm: 자체 메모리·문자열
                +-- src/rt/adapters/libc_io.asm
                       콘솔 / 파일 / strtod / libc globals

개발용 비교 빌드
  동일 앱 + 동일 libc_io 어댑터
          + dev/runtime/libc_primitives.asm

독립 Runtime Foundation (전체 앱이 아님)
  자체 _start -> smoke main -> 정수 변환 / Reader / Writer
                        -> 자체 primitives -> Linux syscall
```

`FILE*`와 libc의 `stdin` 주소는 `libc_io.asm` 안에서만 처리한다. 코어는 반환받은 핸들을 역참조하지 않는다. 전환 어댑터에는 stdin 한 개와 열린 스크립트 한 개의 슬롯이 있으며, 멀티스레드·서버 세션 API로 사용할 수 없다.

`rt_console_printf`는 형식 문자열과 가변 인수를 그대로 전달하는 **임시 호환 경계**다. 이를 자체 printf나 완성된 typed float writer로 설명하지 않는다. v0.3.0에서 소수 변환과 출력 계층을 교체하기 위한 명시적인 잔여 작업이다.

## 3. 저장소와 오브젝트 경계

- `include/abi.inc`: 호출 매크로와 공통 ABI.
- `include/layout.inc`: AST/Value/trace 등 기존 크기·오프셋.
- `include/rt/api.inc`: 앱용 런타임 선언.
- `include/rt/foundation.inc`: 독립 fd 버퍼 구조와 상태 상수.
- `src/core_storage.asm`: 기존 상수와 BSS 저장소를 한 번만 정의.

수학·언어 코어는 기존 단일 번역 단위를 유지했다. 전체 소스 모두를 한꺼번에 다중 오브젝트로 전환하지 않고, 실제 교체할 런타임부터 분리했다. 릴리스별 코어 오브젝트의 미해결 참조는 `rt_*`만 허용하고, libc 참조는 어댑터 오브젝트에서 확인한다.

## 4. 오류와 소유권

기본 루틴은 유효한 메모리와 길이를 받는 내부 API다. 임의 주소를 안전하게 검증하는 보호 계층은 아니다. n=0에서 접근하지 않는 루틴과 NUL 종결이 필요한 루틴을 ABI 문서에 구분했다.

정수 포매터는 NUL을 포함한 용량이 부족하면 -ENOSPC를 반환하며 목적 버퍼를 변경하지 않는다. 정수 파서는 전체 입력 범위를 소비하거나 실패하고, overflow와 문법 오류를 반환한다. 이 문법은 독립 루틴용이며 기존 float64 수식 언어의 숫자 문법을 대체하지 않는다.

fd 쓰기는 부분 쓰기 이후 정확한 오프셋부터 이어가고 EINTR만 재시도한다. EAGAIN은 반환하며, 0바이트 진행은 오류로 처리한다. close는 EINTR에 무조건 재시도하지 않는다. Reader는 EOF와 errno=-1을 다른 상태로 반환한다.

Writer의 '수락한 입력 바이트'와 'fd로 실제 쓴 바이트'를 구분했다. flush가 일부만 성공한 뒤 실패하면 쓴 앞부분은 제거하고 남은 부분과 오류를 보존한다. 이후 호출이 같은 내용을 중복 출력하지 않게 한다. 버퍼 재초기화는 보류된 출력을 버리는 명시적인 동작이다.

## 5. 독립 실행 예제

```sh
make foundation
./bin/asmlab-runtime-smoke --version
./bin/asmlab-runtime-smoke --i64 -9223372036854775808
./bin/asmlab-runtime-smoke --u64 18446744073709551615
./bin/asmlab-runtime-smoke --hex64 18446744073709551615
printf 'hello\n' | ./bin/asmlab-runtime-smoke --echo
./bin/asmlab-runtime-smoke --cat examples/walkthrough.asmlab
```

`--hex64`의 입력은 십진수 uint64이며 출력만 16자리 16진수다. `--echo`와 `--cat`은 NUL을 포함한 바이트를 그대로 전달한다. 최종 개행을 임의 추가하지 않는다. 잘못된 옵션·입력과 일반 I/O 실패는 종료 코드 2다. 닫힌 파이프의 SIGPIPE는 기본 신호 정책을 유지한다.

이 도구에는 수식 계산 기능이 없다. 기존 계산은 `bin/asmlab`로 실행한다.

## 6. 시험 구성

```sh
# 전체: release/debug + libc 비교 + 독립 foundation
make -j2 test
make test-guards

# 런타임에 집중한 재빌드/시험
make -j2 runtime-test

# 동봉 바이너리·오브젝트·맵·소스 해시를 검사한 뒤 실행
make verify
```

독립 fixture는 테스트에서만 Python/ctypes로 호출한다. 보호 페이지 설치·입출력 실패 주입도 시험 인프라다. 실제 배포 앱에 Python이나 테스트 syscall provider를 연결하지 않는다.

시험은 겹침 복사, 정렬되지 않은 메모리, 길이 0, NUL·높은 바이트, 용량 끝 경계, signed/unsigned 한계, ABI 보존, 실제 fd·PTY, 부분 쓰기·EINTR·flush 오류, 보호 페이지 경계와 종료 상태를 다룬다. 정확한 입력 유리수 기반의 독립 기준으로 현재 strtod 어댑터를 비교하지만, 자체 binary64 decimal 알고리즘이나 MPFR 기반 수학 함수 인증을 구현한 것은 아니다.

무결성 검증은 소스뿐 아니라 오브젝트와 링크 맵도 확인한다. 따라서 검증 ZIP은 `build/`의 필요한 `.o`와 `.map`을 함께 보관한다. `make clean` 이후에는 `make test`로 이를 다시 생성해야 `make verify`가 가능하다. 빌드 해시와 체크섬은 디지털 서명이 아니다.

## 7. 이번에 의도적으로 남긴 범위

전체 앱의 CRT/main, libc 콘솔·파일 스트림, float64 입출력과 동적 로더는 유지된다. 일반 allocator, 동적 행렬, 자체 소수 변환, 비동기 이벤트 루프·취소·signal 복구, reentrant API, 서버 격리, ARM64, 그래프와 웹 UI는 구현하지 않았다.

기존 수치 알고리즘과 `src/math.asm`/`src/kernels.asm` 내용은 v0.1.1과 동일하다. 기존 실패한 대입의 변수·ans 보존, 실제 SSE2 캡처, 한도와 문법을 유지한다. 속도 향상이나 MATLAB 호환성 확대를 주장하지 않는다.

다음 v0.3.0의 중심은 **정확한 binary64 입출력 -> typed 출력 통합 -> fd 스트림으로 전체 앱 연결 -> 자체 _start로 CRT 제거 -> 전체 L3-Core 감사**다. 현재 smoke 성공을 이 단계의 완료로 대체하지 않는다.
