# ASMlab 0.1.1

**수식 → AST → 실제 어셈블리 명령 → SIMD 레지스터 → 계산 결과**를 관찰하는 NASM x86-64 수치 계산 환경이다.

[English](README.md) · [변경 이력](CHANGELOG.md) · [검증 보고서](docs/VERIFICATION.md) · [개발 로드맵](docs/ROADMAP-KR.md)

## v0.1.1: Native Gate 완료

이번 버전은 **NASM 2.16.03으로 직접 어셈블한 release/debug 실행 파일**을 제공한다. v0.1.0의 GNU assembler 문법 변환 경로를 공식 빌드에 사용하지 않았다. 기존 수학 알고리즘·문법·자료구조는 유지하고 빌드와 검증 기반을 정비했다.

| 검사 | 실행 결과 |
|---|---:|
| 기존 회귀검사: release | 14,410 / 실패 0 |
| 기존 회귀검사: debug | 14,410 / 실패 0 |
| 네이티브 상수·명령·추적·프로파일 비교 | 1,254 / 실패 0 |
| **Native Gate 합계** | **30,074 / 실패 0** |
| 검증기의 실패 차단·경로 이동 검사 | 별도 6 / 실패 0 |

30,074는 검사 실행·assertion 횟수다. 두 프로파일에서 같은 기존 corpus를 반복하므로 서로 다른 수식 30,074개라는 의미는 아니다. ELF 의존성 감사도 두 실행 파일에서 별도로 통과했다. [기계 판독 가능한 결과](evidence/native/gate-summary.json)

**아직 Level 2다.** libc·CRT를 입출력·문자열·메모리·숫자 문자열 변환과 시작 경로에 사용한다. `libm`, BLAS, LAPACK, Python 런타임으로 수학 계산을 위임하지 않는다. Level 3의 자체 런타임 전환은 후속 개발이다.

## 실행과 빌드

현재 대상은 **Linux x86-64**다. Windows x64에서는 WSL2 Linux 환경이 실행 대상이지만 이번 릴리스에서 별도 WSL 장비를 시험하지 않았다. Windows 네이티브 `.exe`, ARM64, 라즈베리파이, 웹 서버는 포함하지 않는다.

동봉 실행 파일에는 x86-64 Linux와 **glibc 2.34 이상**이 필요하다. 다른 glibc 환경에서는 해당 환경에서 다시 빌드한다.

```sh
# 제공 실행 파일로 시작: NASM/Python은 런타임에 필요하지 않음
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
```

Ubuntu 계열의 네이티브 빌드·시험:

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
python3 tests/gate_guards.py --report build/gate-guards.json
```

| 명령 | 동작 |
|---|---|
| `make` 또는 `make release` | NASM 최적 인코딩 `-Ox`, `bin/asmlab` |
| `make debug` | NASM `-O0`, DWARF 포함 `bin/asmlab-debug` |
| `make test` | 두 프로파일을 직접 재빌드하고 전체 Native Gate 실행 |
| `make verify` | 동봉 바이너리와 빌드 입력 해시를 확인하고 전체 시험. NASM 재빌드 없음 |
| `make audit` | 두 ELF의 의존성·스택·RELRO 등 확인 |
| `make disasm` | 두 프로파일 재빌드 후 역어셈블 파일 생성 |
| `make validate-gas` | 역사적 비교용 선택 경로. 공식 Native Gate를 대체하지 않음 |

GCC는 링커 드라이버로만 사용하며 프로젝트 C 코드를 컴파일하지 않는다. Python은 빌드 기록·테스트에만 사용한다. `make verify`에는 Python 3.10 이상과 binutils가 필요하다. 기본 NASM 경고를 오류로 승격하며, 의도된 ELF 재배치까지 포함하는 모든 선택 경고를 활성화했다고 주장하지 않는다.

공식 빌드 target은 항상 새로 빌드한다. NASM이 없거나 빌드에 실패하면 이전 실행 파일을 성공 결과처럼 남기지 않는다. 변경된 소스와 오래된 `.build.json` 조합도 검증에 실패한다. 의도적으로 소스를 수정했다면 `make test`로 새 기록을 만든다.

## 계산 기능

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

스칼라·벡터·행렬은 float64다. 사칙연산, 괄호, 단항 부호, 제한된 정수 지수, 전치, 원소별 함수와 행렬 곱을 지원한다. 열 구분은 쉼표이며 `[1 2]`는 지원하지 않는다. `*`는 행렬 곱 또는 스칼라 곱, `.*`는 원소별 곱이다. `/`는 오른쪽 스칼라 나눗셈이며 `./`는 원소별 나눗셈이다. `sum(A)`는 전체 원소 합으로 MATLAB의 기본 열별 합과 다르다.

실패한 대입은 기존 변수와 `ans`를 바꾸지 않는다. [문법과 CLI](docs/LANGUAGE.md) · [수치 계약](docs/NUMERICS.md)

## 실제 레지스터 관찰

```text
:bits on
sqrt([1,4,9,16]) + 2
:replay
```

```text
sqrtpd : [1,4] → [1,2]
sqrtpd : [9,16] → [3,4]
addpd  : [1,2] + [2,2] → [3,4]
addpd  : [3,4] + [2,2] → [5,6]
결과   : [3,4,5,6]
```

각 프레임은 AST 노드, 실제 명령 주소, XMM0 실행 전후, XMM1 입력, 원시 64비트 값, MXCSR를 연결한다. 계산을 별도로 재현해 레지스터 값처럼 꾸미는 화면이 아니다. 실제 출력은 [캡처 기록](evidence/native/sqrt-vector-trace.txt)에서 확인할 수 있다.

재생의 `n`+Enter는 다음, `p`+Enter는 이전, `q`+Enter는 종료다. `:step on`은 이후 수식의 **계산 후 캡처 재생**을 자동으로 연다. 실시간 명령 단위 디버거나 JIT는 아니며 선택한 SSE2 명령만 추적한다. `:trace off`도 중앙 디스패치·scratch 처리 비용을 제거하지 않는다. debug/release는 어셈블러 인코딩 프로파일이지 새 고속 수학 알고리즘 모드가 아니다.

## 제한과 검증 경계

행렬은 최대 16×16, 사용자 변수 63개, AST 노드 512개, 재귀 64단계, 한 줄 4,095바이트, 수식당 추적 8,192프레임이다. 초과 추적은 누락 사실을 표시하고 계산은 계속한다.

`sin/cos`는 라디안 `|x| <= 1,000,000`, `sqrt`는 비음수, `log`는 양수, `^`는 -1024..1024의 스칼라 정수 지수만 허용한다. 부분정규수와 언더플로는 허용하지만 NaN/무한대 결과는 오류다. 전 정의역의 올바른 반올림을 증명한 수학 라이브러리는 아니다.

이번에 실제 검증한 환경은 Linux x86-64 컨테이너다. Ubuntu 22.04/24.04용 GitHub Actions를 구성했지만 **원격 CI를 실행하지 않았으므로 해당 matrix 통과를 주장하지 않는다.** 공개 다중 사용자 서버, Windows 네이티브, ARM64, Pi 장비, 성능 우위도 검증하지 않았다.

## 라즈베리파이·웹·그래프: 기획만 포함

[Pi 5 서버·ARM64·웹 그래프 계획](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 **미구현 설계 문서**다. NASM x86-64 코어를 우선 보존하고 이후 ARM64 포팅 또는 별도 x86 계산 서버를 선택하는 조건을 기록했다. HTML/JS 앱, API 서버, 2D/3D plot 명령, ARM 코드나 배포 설정을 이번 실행 파일에 추가하지 않았다.

## 출처와 문서

이번 빌드에 사용한 NASM은 `holepunchto/nasm-runtime`의 공개 CI artifact에서 확보한 **서드파티 사전 빌드 NASM 2.16.03**이다. 공식 NASM 소스를 이번 환경에서 직접 빌드했다는 의미는 아니다. 해당 도구는 릴리스 ZIP에 포함하지 않으며 [도구 출처와 SHA256](docs/TOOLCHAIN-PROVENANCE.md)을 기록했다.

[아키텍처](docs/ARCHITECTURE.md) · [Level 3 경계](docs/LEVEL3-CONTRACT.md) · [원래 Level 3 계획](docs/plans/LEVEL3-PLAN-KR.md) · [검증 상세](docs/VERIFICATION.md)

`evidence/native/`는 v0.1.1의 실제 검사, `evidence/baseline-0.1.0/`는 과거 GAS 검증 기록이다. 두 기록을 혼용하지 않는다. `bin/*.build.json`에는 소스·도구·출력 해시와 실제 빌드 명령이 있다. 최상위 `MANIFEST.sha256`은 제공 패키지의 무결성 확인용이며 디지털 서명이나 보안 인증은 아니다. 압축 해제 직후 `sha256sum -c MANIFEST.sha256`으로 검사할 수 있다.
