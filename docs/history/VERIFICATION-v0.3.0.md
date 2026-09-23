# ASMlab v0.3.0 - L3-Core 검증 보고서

**검증일: 2026-09-23. 대상: 동봉한 Linux x86-64 NASM release/debug 앱과 개발용 비교·시험 산출물.**

## 1. 실제 결과

**전체 177,833개 assertion 통과, 실패 0. 별도 실패 차단 검사 24개 통과, 실패 0.**

| 구성 | 통과 수 | 결과 |
|---|---:|---|
| release 기존 회귀 | 14,410 | [report](../evidence/native/release-regression.json) |
| debug 기존 회귀 | 14,410 | [report](../evidence/native/debug-regression.json) |
| 네이티브 상수·명령·레지스터 계약 | 1,254 | [report](../evidence/native/native-contract.json) |
| 개발용 libc reference 기존 회귀 | 14,410 | [report](../evidence/runtime/libc-reference-regression.json) |
| 자체 기초 루틴·ABI·I/O·비교 decimal 어댑터 | 26,123 | [report](../evidence/runtime/runtime-unit.json) |
| 코어 경계·오브젝트·백엔드 비교 | 716 | [report](../evidence/runtime/runtime-boundary.json) |
| 자체 decimal 변환·독립 oracle·ABI | 106,439 | [report](../evidence/l3/decimal-exact.json) |
| 전체 L3 앱 통합·입출력·무라이브러리 실행 | 71 | [report](../evidence/l3/l3-core.json) |
| **릴리스 합계** | **177,833** | [summary](../evidence/release-summary.json) |
| 별도 native/runtime/L3 guard | **6 / 9 / 9** | [6](../evidence/native/gate-guards.json) · [9](../evidence/runtime/runtime-gate-guards.json) · [9](../evidence/l3/l3-gate-guards.json) |

Native 30,074 + Runtime 41,249 + L3 106,510이다. 같은 14,410 회귀 corpus를 세 빌드에서 실행하며 함수 호출마다 ABI assertions를 포함한다. **177,833개의 서로 다른 수식을 검사했다는 뜻이 아니다.** guard와 압축 해제 후 재검사 횟수는 릴리스 합계에 중복 합산하지 않는다.

[실제 빌드·검사 로그](../evidence/build-test.log) · [guard 로그](../evidence/guard-tests.log) · [환경 기록](../evidence/native/environment.txt)

## 2. 전체 앱의 외부 런타임 제거

기본 `bin/asmlab`과 `bin/asmlab-debug`는 11개의 프로젝트 NASM 오브젝트를 직접 GNU ld로 정적 링크한다. `_start`, 수식 파서·평가기, 기존 수학·행렬 커널, decimal 변환, Reader/Writer, 화면·재생을 모두 포함한다. smoke에 한정된 무의존 결과가 아니다.

다음을 실제로 검사했다.

- `PT_INTERP` 없음, `DT_NEEDED` 없음, 미해결 심볼 없음.
- libc·CRT·libm·BLAS·LAPACK·compiler-rt 입력 없음. 정확한 링크 명령과 프로젝트 오브젝트 목록을 대조한다.
- 실행 스택 없음, RWX LOAD 없음. non-PIE 정적 ELF이며 이를 ASLR 보안 개선으로 설명하지 않는다.
- 실행 중 `/proc/<pid>/maps`의 파일 기반 매핑에는 해당 앱 파일만 존재한다. 커널 제공 `[vdso]`, `[vvar]`, 스택 등은 사용자 라이브러리 의존성으로 세지 않는다.
- 자체 decimal·입출력 모듈이 실제 앱에 연결되며 시험 fixture/가짜 syscall provider는 생산 앱에 연결되지 않는다.

[ELF 감사](../evidence/l3/elf-runtime-audit.txt) · [실행 매핑·통합 증거](../evidence/l3/l3-core.json) · [release 입력/오브젝트 해시](../bin/asmlab.build.json) · [debug 해시](../bin/asmlab-debug.build.json)

### 빈 루트 파일시스템에서 실제 실행

권한을 가진 시험 호스트가 `chroot` 후 그룹을 비우고 GID/UID 65534로 낮췄다. 루트에는 `/asmlab`과 `/script.asmlab`만 복사했으며 **동적 로더·라이브러리·셸은 없다.** release/debug 각각 수식 인수, stdin 파이프, 스크립트 실행 3건을 성공했다. 이번 릴리스에서는 해당 시험이 skipped되지 않았다.

이것은 사용자 공간 의존성을 확인한 시험이며, 네트워크 서비스의 보안 sandbox를 구현·인증했다는 뜻이 아니다. 실제 Linux 커널과 상속된 표준 파일 디스크립터는 사용한다.

## 3. 정확 decimal 변환 시험

런타임의 구현은 NASM 정수·다중 워드 정수 연산이다. Python/Decimal/Fraction은 독립 기준을 만드는 개발 시험 호스트에만 사용한다.

| 독립 입력군 | 수 |
|---|---:|
| 유효 decimal → binary64 | 10,095 |
| 잘못된 decimal 거부 | 24 |
| raw binary64 → 지정 유효숫자 문자열 | 14,143 |
| 포매터 출력의 raw bit 왕복 확인 | 14,143 |

파싱 결과는 **인접 binary64 사이의 정확한 유리수 midpoint 구간과 ties-to-even**을 기준으로 비교한다. Python `float(s)`가 단지 같은 결과를 냈다는 사실에만 의존하지 않는다. 출력은 충분한 Decimal 정밀도에서 정확하게 양자화한 값과 비교하고, Python의 문자열 형식도 별도로 교차 확인한다. 왕복만 검사하면 두 구현이 같은 버그를 공유할 수 있으므로 각 방향의 독립 기준 시험을 유지한다.

정상·부분정규수·±0·최대 유한값·overflow/underflow 경계·극단 지수·반올림 경계·1~17 유효숫자·버퍼 부족 시 무변경·3개 보호 페이지 프로세스 시험·ABI/MXCSR 보존을 포함한다. 입력은 기존 숫자 토큰 상한 127바이트를 늘리지 않는다.

알고리즘은 지원 범위에서 nearest-even 정확 변환을 목표로 구현했지만, 유한 표본 시험이 **모든 문자열/모든 float64 비트패턴의 형식적 증명**은 아니다. `sin/cos/log`의 전체 정의역에 대한 올바른 반올림을 새로 입증했다는 뜻도 아니다. [알고리즘·용량 경계](DECIMAL-CONVERSION.md)

## 4. 기존 계산·관찰 계약 보존

`src/math.asm`과 `src/kernels.asm`은 v0.2.0 원본과 바이트 단위로 동일하다. 기본 언어 문법, 자료구조·행렬·변수 한도, 함수 정의역, 실패한 대입의 변수/ans 보존을 유지했다. [원본 ZIP과 소스 비교](../evidence/baseline-v0.2.0/source-comparison.json)

50개 64비트 상수, 관찰 대상 SSE2 명령 12종, 실제 명령 위치·XMM 원시 비트·MXCSR를 검사한다. Runtime boundary는 639개 JSON 결과 레코드와 백엔드별 74개 trace frame을 비교한다. 추가 L3 통합 시험은 33가지 수식/표시 모드 조합에서 실제 화면 텍스트를 개발용 libc reference와 비교한다. 링크에 따른 PC 차이는 정규화하되 PC의 유효성은 별도 네이티브 검사로 확인한다.

**수정한 FP 진입 계약:** 파싱 성공 뒤 실제 평가 직전에 MXCSR를 `0x1f80`으로 다시 설정한다. 숫자 문자열 변환에서 발생한 sticky flag가 수학 커널의 첫 캡처에 섞이지 않게 한다. 자체 decimal은 FP 명령을 사용하지 않으며 MXCSR를 보존한다. 개발용 libc reference에도 같은 평가 경계를 적용한다. 그러므로 v0.2.0의 일부 파싱 유래 초기 플래그와 같다고 주장하지 않는다.

[실제 벡터 캡처](../evidence/l3/sqrt-vector-trace.txt) · [0.1+0.2의 FP 경계](../evidence/l3/decimal-fp-trace.txt)

## 5. I/O와 상태 시험

자체 Reader를 REPL과 재생이 공유한다. PTY에서 수식·재생 다음/이전/종료·두 번째 수식·종료 명령을 한꺼번에 보내도 미리 읽은 입력을 잃지 않는지 검사했다. EOF 직전 무개행 줄, 4,096바이트 초과 줄의 전체 거부와 다음 줄 복구, 닫힌 stdin, 디렉터리 읽기 오류, decimal overflow 후 기존 값 보존을 확인했다.

모든 짧은 실행 경로에서 최종 flush가 수행되며 `/dev/full` 쓰기 실패에서는 stderr 진단과 종료 코드 2를 확인했다. 부분 입출력/EINTR/EAGAIN/sticky error는 기존 foundation 오류 주입 시험을 다시 실행했다. **기본 SIGPIPE/SIGINT는 유지**하므로 신호에 의한 종료까지 코드 2로 변환한 것은 아니다. 프로그램 자체가 termios raw mode로 바꾸지는 않는다.

명령 형식은 기존 화면에 필요한 제한된 trusted formatter이며 전체 printf 규격 구현이 아니다. 외부 사용자 문자열을 format으로 실행하지 않는다. locale·LD_PRELOAD·외부 PATH 없이 동일하게 계산되는지 확인했다.

## 6. 개발용 의존성은 구분

`bin/asmlab-libc-reference`, `bin/tests/decimal-adapter.so`는 비교용으로 libc에 연결한다. 나머지 production release/debug/smoke 및 자체 decimal fixture와 구분한다. Python ctypes가 시험 fixture를 로드한다는 사실은 production 앱이 Python을 필요로 한다는 뜻이 아니다. 동봉 개발용 비교 실행 파일은 glibc 2.34 이상을 요구하므로 전체 make verify는 이를 제공하는 시험 호스트에서 수행한다.

NASM 2.16.03은 이전 단계에서 확보한 서드파티 사전 빌드를 해시 재확인해 사용했다. 이번에 공식 NASM 소스로 어셈블러 자체를 빌드하지 않았고 도구 파일은 ZIP에 넣지 않는다. [도구 출처](TOOLCHAIN-PROVENANCE.md)

검증 sidecar, SHA256, 오브젝트 목록은 일반 무결성·오래된 산출물 혼용 방지다. 모든 소스·검증기·메타데이터를 함께 고치는 악의적 공격에 대한 전자서명/공급망 인증은 아니다. L3 guard는 숨긴 `-lc`, 잘못된 모듈 그룹, 변조한 decimal fixture/오브젝트/맵/소스, 누락된 fixture, NASM 부재에서 오래된 산출물 제거를 시험한다.

## 7. 재현

```sh
# 동봉 실행 파일·선택된 오브젝트/맵·소스 검사; NASM 재빌드 없음
make verify
make test-guards

# Linux x86-64에서 NASM 직접 빌드부터 전체 시험
make clean
make -j2 test
make test-guards

# 권한 필요. 일반 사용자 환경에서 skipped되는 빈 루트 검사를 엄격히 요구
sudo make empty-root-test
```

현재 환경의 실제 로그와 결과는 위 링크에 있다. 일반 사용자 시험에서 chroot 권한이 없으면 그 시험만 skipped라고 명시하며, 독립 실행으로 확인한 것처럼 결과를 확대하지 않는다.

## 8. 미검증/미구현

원격 Ubuntu 22.04/24.04 Actions는 **구성만 했고 실행하지 않았다.** 별도 WSL2/Windows/ARM64/Pi 장비·웹 서버·2D/3D 그래프는 이번 구현/실행 시험에 포함하지 않는다. 고정 16×16 구조를 동적 메모리로 바꾸거나 CAS·선형대수·고속 Compute backend를 추가하지 않았다.

메모리 안전성의 완전한 증명, 외부 네트워크 공격 내성, 멀티스레드/reentrant 실행, 전체 수학 함수 correct-rounding, MATLAB/BLAS 대비 성능 우위를 주장하지 않는다. 실제 레지스터 추적은 선택 명령의 계산 후 재생이며 JIT·실시간 CPU 디버거가 아니다.

과거 evidence/baseline-* 자료는 해당 과거 버전의 기록으로 보존하며 현재 검증 합계와 혼용하지 않는다.
