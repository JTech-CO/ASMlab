# ASMlab 0.2.0

**수식 → AST → 실제 어셈블리 명령 → SIMD 레지스터 → 계산 결과**를 관찰하는 NASM x86-64 수치 계산 환경이다.

[English](README.md) · [변경 이력](CHANGELOG.md) · [런타임 구현](docs/RUNTIME-FOUNDATION-KR.md) · [검증 보고서](docs/VERIFICATION.md) · [로드맵](docs/ROADMAP-KR.md)

## v0.2.0: Runtime Foundation

코어의 외부 호출을 `rt_*` API로 분리하고, **기본 실행 파일의 메모리·문자열 처리를 자체 NASM 루틴으로 교체**했다. 파일·콘솔·float64 문자열 변환은 별도 libc 어댑터로 격리했다. 정수 변환·syscall·버퍼 입출력·자체 `_start`는 별도 독립 실행 파일에서 시험한다.

**전체 ASMlab은 아직 Level 2다.** CRT와 libc 입출력·strtod·printf를 제거하지 않았다. `asmlab-runtime-smoke`는 libc 없는 기본 루틴 시험 도구이며 전체 수식 계산기가 아니다. 웹·ARM64·그래프는 기획 문서만 유지한다.

| 검사 | 실제 결과 |
|---|---:|
| 기존 회귀: release / debug / libc 비교 빌드 | 각각 14,410 / 실패 0 |
| 기존 네이티브 상수·명령·추적 계약 | 1,254 / 실패 0 |
| 자체 런타임 독립 시험 | 26,123 / 실패 0 |
| 호출 경계·비교 결과·ELF 검사 | 712 / 실패 0 |
| **전체 릴리스 검사** | **71,319 / 실패 0** |
| 변조·누락·도구 실패 차단 검사 | 별도 15 / 실패 0 |

같은 corpus를 여러 빌드에서 반복하고 호출별 ABI assertion을 포함한 횟수다. 서로 다른 수식 71,319개나 정확성 증명을 뜻하지 않는다. [실제 요약 JSON](evidence/release-summary.json)

## 실행

대상은 **Linux x86-64**, 동봉 전체 앱은 **glibc 2.34 이상**이다. Windows x64 사용자는 WSL2 Linux 실행 대상이지만 이번에는 별도 WSL 장비에서 검증하지 않았다. `.exe`, ARM64 실행 파일, 웹 서버는 없다. 수치 코어는 실행 시 Python이나 외부 수학 라이브러리를 호출하지 않는다.

```sh
chmod +x bin/asmlab bin/asmlab-debug bin/asmlab-runtime-smoke
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
```

마지막 수식 결과:

```json
{"ok":true,"rows":2,"cols":2,"data":[19,22,43,50]}
```

## 네이티브 빌드와 검증

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

| 명령 | 동작 |
|---|---|
| `make` / `make release` | 기본 release 앱 재빌드 |
| `make debug` | DWARF 포함 debug 앱 재빌드 |
| `make reference` | 개발용 libc primitive 비교 앱 재빌드 |
| `make foundation` | 독립 runtime-smoke와 시험 fixture 빌드 |
| `make test` | 위 산출물 전부 재빌드한 뒤 Native + Runtime 전체 검사 |
| `make runtime-test` | 재빌드 후 런타임·비교 백엔드 검사 |
| `make verify` | 동봉 산출물·소스·오브젝트·맵 검사와 전체 시험. NASM 재빌드 없음 |
| `make test-guards` | 기본 6개 + 런타임 9개 실패 차단 검사 |

Python 3.10 이상은 빌드 기록과 테스트에만 필요하다. GCC/cc는 NASM 오브젝트와 시스템 라이브러리를 연결하는 드라이버이며 프로젝트 C 코드를 컴파일하지 않는다. 전체 앱에 libm/BLAS/LAPACK을 링크하지 않는다.

**검증 ZIP에는 `build/`의 필요한 `.o`·`.map`도 포함했다.** 엄격한 오브젝트 출처 검증 때문에 `make verify`는 이 파일들을 사용한다. `make clean` 후에는 `make test`로 재생성한다. 소스나 오브젝트가 바뀌었는데 오래된 sidecar만 남으면 검증에 실패한다. NASM 빌드 실패 시 이전 성공 실행 파일을 재사용하지 않는다. 과거 GAS 변환기는 현재 빌드 경로가 아니며 `make validate-gas`는 명시적으로 실패한다.

## 독립 기본 루틴 도구

```sh
./bin/asmlab-runtime-smoke --version
./bin/asmlab-runtime-smoke --i64 -9223372036854775808
./bin/asmlab-runtime-smoke --u64 18446744073709551615
./bin/asmlab-runtime-smoke --hex64 18446744073709551615
printf 'hello\n' | ./bin/asmlab-runtime-smoke --echo
./bin/asmlab-runtime-smoke --cat examples/walkthrough.asmlab
```

이 도구만 자체 `_start`와 직접 syscall로 시작·입출력·종료한다. 정수/16진수 용량 제한 포매터, strict 정수 파서, 4KiB Reader/Writer를 시험하며 libc·CRT·동적 인터프리터가 없다. **수식 평가기와 수학 함수는 포함하지 않는다.** [실제 실행 기록](evidence/runtime/smoke-demo.txt) · [ABI와 오류 계약](docs/RUNTIME-ABI.md)

## 기존 계산과 관찰

```text
x = 3
x^2 + 4^2
A = [1,2;3,4]
B = [5,6;7,8]
A * B
A .* B
A + 2
A / 2
A'
sin(pi / 4)
cos([0,pi/2,pi])
sqrt([1,4,9,16])
log(e)
sum(A)
```

모든 수치는 float64다. 행렬 열 구분에는 쉼표가 필요하다. `*`는 행렬/스칼라 곱, `.*`는 원소별 곱이다. `/`는 오른쪽 스칼라 나눗셈, `./`는 원소별 나눗셈이다. `sum(A)`는 전체 원소 합이다. 실패한 대입은 기존 변수와 `ans`를 보존한다. [문법](docs/LANGUAGE.md) · [수치 계약](docs/NUMERICS.md)

```text
:bits on
sqrt([1,4,9,16]) + 2
:replay
```

실제 `sqrtpd` 두 번과 `addpd` 두 번의 레지스터 캡처가 `[3,4,5,6]` 결과로 이어진다. 재생에서 `n`+Enter는 다음, `p`+Enter는 이전, `q`+Enter는 종료다. `:step on`은 이후 계산 후 재생을 자동으로 연다. 전체 CPU 추적이나 실시간 디버거/JIT가 아니며, `:trace off`도 중앙 디스패치 비용을 없애지 않는다. [캡처 기록](evidence/native/sqrt-vector-trace.txt)

## 범위와 출처

행렬 최대 16×16, 사용자 변수 63개, AST 512개, 재귀 64단계, 입력 4,095바이트, 수식당 trace 8,192프레임의 기존 제한을 유지한다. `sin/cos`는 라디안 `|x| <= 1,000,000`, `sqrt`는 비음수, `log`는 양수, `^`는 -1024..1024의 스칼라 정수 지수만 지원한다. NaN/무한대 결과는 오류이며 부분정규수와 언더플로는 허용한다.

실제 검증은 Linux x86-64 컨테이너에서 수행했다. CI의 Ubuntu 22.04/24.04 구성을 갱신했지만 **원격 실행하지 않았다**. 모든 입력의 정확성·메모리 안전·보안 격리·성능 우위를 보증하지 않는다. 독립 decimal 시험은 현재 libc 어댑터 검증이며 자체 float64 변환 구현이 아니다.

NASM은 v0.1.1에 첨부된 서드파티 사전 빌드 2.16.03을 해시 확인 후 재사용했다. 공식 소스를 이 환경에서 빌드했다는 뜻이 아니며 도구 바이너리는 배포 ZIP에 넣지 않는다. [도구 출처](docs/TOOLCHAIN-PROVENANCE.md)

[Pi·서버·웹·그래프 계획](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 문서만 보존했다. [Level 3 경계](docs/LEVEL3-CONTRACT.md) · [아키텍처](docs/ARCHITECTURE.md)

`evidence/native/`와 `evidence/runtime/`는 현재 버전의 기록이다. `evidence/baseline-0.1.1/`과 `baseline-0.1.0/`는 역사적 기록이며 현재 검증에 더하지 않는다. 압축 해제 직후 `sha256sum -c MANIFEST.sha256`으로 파일 무결성을 확인할 수 있다. 체크섬은 디지털 서명이 아니다.
