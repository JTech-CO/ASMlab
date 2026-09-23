# ASMlab 0.4.0 - Dynamic Workspace

**수식 → AST → 실제 어셈블리 명령 → SIMD 레지스터 → 결과**를 관찰하는 NASM x86-64 수치 계산 환경이다.

[English](README.md) · [변경 이력](CHANGELOG.md) · [동적 작업공간](docs/DYNAMIC-WORKSPACE-KR.md) · [검증](docs/VERIFICATION.md) · [로드맵](docs/ROADMAP-KR.md)

## 이번 버전

고정 16×16 Value를 **64바이트 descriptor와 동적 데이터 버퍼**로 교체했다. 동적 변수 목록, mmap 기반 임시 arena·지속 값 저장, 페이지 단위 quota, 실패한 대입의 원자적 롤백을 구현했다. 기본 release/debug는 계속 **libc·CRT·libm·BLAS·LAPACK 없는 정적 Linux x86-64 ELF**다.

| 기능 | 지원 내용 |
|---|---|
| 행렬·벡터 | 값당 최대 1,048,576개 float64 원소. 실제 할당은 세션 메모리 예산 안에서만 성공 |
| 변수 | 기존 63개 제한 제거. 동적 연결 목록이며 quota 한도와 이름 규칙은 유지 |
| 생성자 | `zeros(n[,m])`, `ones(n[,m])`, `eye(n[,m])`, `linspace(a,b,n)` |
| 크기·읽기 | `size(A)`, `size(A,1)`, `size(A,2)`, 이름이 있는 변수의 `A(row,col)` |
| 메모리 관리 | 기본 64MiB, `--memory-mib 1..1024`, `:memory`, `:drop NAME`, `:clear` |
| 원자적 대입 | 새 항목·변수 값·ans 복사를 모두 확보한 뒤 commit. 실패 시 기존 둘 모두 보존 |
| 화면 | 큰 값은 앞 16행×16열 미리보기. JSON/quiet는 전체 데이터 출력 |

인덱스는 **1부터 시작**하고 읽기 전용이다. 현재 표의 0-based 행·열 표시는 내부 저장·진단 좌표이며 언어 인덱싱 규칙과 다르다. 슬라이스·선형 인덱스·인덱스 대입·빈 행렬은 아직 지원하지 않는다.

## 실행

```sh
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --json -e 'size(ones(32,48))'
./bin/asmlab --bits -e 'linspace(-1,1,5)'
./bin/asmlab --memory-mib 64 -f examples/dynamic-workspace.asmlab
```

```text
A = ones(32,48)
B = A
A = A + 2
B(32,48)
A(32,48)
size(A)
x = linspace(-10,10,1001)
y = sin(x)
size(y)
:memory
:drop B
:clear
:memory
```

위에서 `B(32,48)`은 1, `A(32,48)`은 3이다. `:clear` 직후 동적 사용량은 0이며 `ans`는 0이다. `:memory`의 peak와 누적 map/unmap 횟수는 초기화하지 않는다.

**Linux x86-64용이다.** 기본 앱의 실행에 glibc, NASM, Python은 필요하지 않다. Windows x64 WSL2 Linux는 실행 대상이지만 이번에는 별도 WSL 장비에서 시험하지 않았다. Windows 네이티브·ARM64·Pi·웹 앱·그래프는 포함하지 않았다.

## 빌드와 시험

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

| 명령 | 동작 |
|---|---|
| `make` / `make debug` | NASM + ld로 기본 정적 앱 빌드; Python으로 출처 기록 |
| `make test` | release/debug·개발 비교·fixture를 빌드한 후 네이티브/기초 런타임/L3/동적 작업공간 검사 |
| `make workspace-test` | 필요한 산출물을 빌드하고 동적 작업공간 검사 |
| `make verify` | 재빌드 없이 제공 산출물·오브젝트·입력 해시 확인 후 전체 검사 |
| `make test-guards` | 손상·누락·과거 소스·잘못된 링크 조합을 실행 전에 차단하는지 검사 |
| `make audit` | 정적 ELF와 호출·오브젝트 의존성 감사 |

`make verify`에는 Python 3.10 이상과 binutils가 필요하다. 개발 비교 바이너리 때문에 **시험 호스트**에는 glibc 2.34 이상이 필요하지만 기본 `bin/asmlab`의 요구 사항은 아니다. GCC는 개발 비교 타깃에만 사용한다. NASM 부재 시 GAS로 우회하지 않으며 오래된 산출물도 성공으로 재사용하지 않는다.

로컬 릴리스 검사 **186,731개 assertion, 실패 0**, 별도 실패 차단 **32개, 실패 0**이다. 같은 corpus의 여러 빌드 반복과 ABI checks를 포함한 실행 횟수이지 서로 다른 수식의 개수나 전 입력 증명이 아니다. [실제 결과](evidence/release-summary.json) · [동적 시험 상세](evidence/dynamic/dynamic-workspace.json)

## 메모리와 수명

메모리 quota는 descriptor·데이터·심볼·arena의 **메타데이터를 포함한 페이지 단위 동적 매핑**을 센다. 고정 AST/trace BSS, 스택, 전체 RSS, CPU 시간을 제한하는 보안 sandbox가 아니다. 작업공간의 기존 값, 평가 중간값, commit용 복사가 동시에 존재할 수 있어 최종 배열 크기보다 더 많은 여유가 필요하다.

`B=A`는 독립 복사다. 성공한 수식의 임시 arena는 AST·재생을 위해 다음 수식까지 보존한다. 다음 수식·`:clear`는 이전 임시 참조를 무효화하고 해제한다. 실패한 수식은 자체 임시 공간을 회수한다. `:drop A`는 A의 지속 값만 해제하며 별도 임시 복사·trace를 깨뜨리지 않는다.

예산 초과나 반환된 Linux 할당 오류는 복구하여 기존 변수·ans를 보존한다. **호스트 전체 메모리 압박으로 OOM killer가 프로세스를 종료하는 경우까지 복구한다고 보장하지 않는다.** 소유 포인터에 대한 중복·임의 free, 동시 접근은 내부 ABI 밖이다.

## 유지한 제한

AST 512개, 임시 Value 최대 512개, 재귀 64, 한 줄 4,095바이트, 숫자 토큰 127바이트, trace 8,192프레임이다. 따라서 큰 배열은 거대한 리터럴보다 생성자로 만든다. 한 행렬 곱의 `m*n*k`는 16,777,216항 이하로 제한한다. 이는 성능 보증이나 세션 전체 실행 시간 제한은 아니다.

`sin/cos`는 `|x| <= 1,000,000`, `sqrt`는 비음수, `log`는 양수, `^`는 -1024~1024 정수 지수다. 모든 숫자는 float64이며 부분정규수·음의 0은 허용하고 NaN·무한대 계산 결과는 오류다. `sum(A)`는 전체 원소의 합이다. 수학 함수의 전 범위 올바른 반올림을 증명한 것은 아니다.

## 관찰과 후속 작업

`:bits on`, `:replay`, `:step on`을 유지한다. 실제 선택 명령의 PC·XMM·MXCSR를 기록하고 계산 후 탐색한다. JIT·실시간 디버거가 아니며 `:trace off`도 중앙 명령 디스패치 비용을 제거하지 않는다. 생성자의 정수 채우기·메타데이터·메모리 할당은 SSE2 전 명령 추적에 포함되지 않는다. `linspace`의 표본 산술과 인덱스 읽기의 관찰 명령은 실제 캡처다.

[Pi 5·ARM64·서버형 웹·2D/3D 그래프 계획](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 문서만 보존했다. 원격 GitHub Actions·별도 WSL/Pi 실기기 시험은 실행하지 않았다. 현재 제품은 로컬 단일 사용자용이며 공개 계산 서버로 검증하지 않았다.

[언어](docs/LANGUAGE.md) · [ABI](docs/RUNTIME-ABI.md) · [수치 계약](docs/NUMERICS.md) · [L3 경계](docs/LEVEL3-CONTRACT.md) · [도구 출처](docs/TOOLCHAIN-PROVENANCE.md)

해제 직후 `sha256sum -c MANIFEST.sha256`으로 패키지를 확인한다. 해시는 무결성 기록이지 서명·안전성 인증은 아니다.
