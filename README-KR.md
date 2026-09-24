# ASMlab 0.5.0 - Observable Workbench

**수식 → AST → 실제 어셈블리 명령 → SIMD 레지스터 → 결과**를 연결해 관찰하는 NASM x86-64 수치 계산 환경이다.

[English](README.md) · [변경 이력](CHANGELOG.md) · [Workbench 사용법](docs/OBSERVABLE-WORKBENCH-KR.md) · [Trace v2](docs/TRACE-V2.md) · [검증](docs/VERIFICATION.md)

## 이번 버전

| 기능 | 구현 |
|---|---|
| Observe / Compute | 같은 알고리즘의 빌드 시 특수화. Observe는 실제 캡처, Compute는 인라인 SSE2로 캡처·중앙 디스패치 없음 |
| Trace v2 | source span·AST 연결·알고리즘 단계·실제 명령 PC·원시 XMM·MXCSR·활성 lane·문맥·누락 수 |
| 작업화면 | AST·명령·레지스터·완료 값의 연동 패널, 키보드 포커스·검색·스크롤·수식 편집 |
| 이력 | 세션 내 최근 64개 **소스**. 현재 작업공간에서 다시 실행하며 과거 workspace/trace를 복원하지 않음 |
| 터미널 | 크기 변경, 오류·처리된 종료 신호·중단/재개 시 상태 복구, 공유 stdin 버퍼 |
| L3 / Dynamic | libc·CRT 없는 전체 앱, 동적 Value·quota·원자적 대입·생성자·인덱싱 유지 |

![실제 PTY 출력의 텍스트 셀 렌더링](docs/workbench-demo.png)

위 이미지는 실제 PTY 캡처를 이미지로 렌더링한 것이며, 별도로 상상해 만든 UI가 아니다. [원본 화면 텍스트](evidence/workbench/workbench-120x34.txt)

## 실행

Linux x86-64용 정적 ELF다. 실행 시 glibc·Python·NASM이 필요하지 않다. Windows x64의 WSL2 Linux는 실행 대상이지만 별도 WSL 장비는 시험하지 않았다. Windows EXE·ARM/Pi·웹·그래프는 아직 기획만 있다.

```sh
chmod +x bin/asmlab bin/asmlab-debug

# 최소 80열 x 24행의 ANSI 터미널에서 작업화면
./bin/asmlab --workbench -e 'sqrt([1,4,9,16])+2'

# 기존 REPL, 텍스트 캡처, 배치 계산도 유지
./bin/asmlab
./bin/asmlab --mode observe --bits -e 'sin(pi/4)'
./bin/asmlab --mode compute --json -e 'sum(sin(linspace(-3,3,8192)))'

# 한 줄 JSON으로 실제 Trace v2 저장. 자체 파일 읽기/재생은 아직 없음
./bin/asmlab --trace-json -e 'sqrt([1,4,9,16])+2' > trace.json
```

일반 출력은 Observe, JSON/quiet는 Compute가 기본이다. `--trace-json`은 Observe가 기본이며 `--mode`가 우선한다. `:trace off`는 v0.4.0과 달리 **Compute 전환**이다. `:mode observe`·`:mode compute`·`:trace on/all`은 다음 실행에 적용한다. 이미 보관된 캡처의 실행 모드를 바꾸지 않는다.

## 작업화면 조작

| 키 | 동작 |
|---|---|
| Tab, 방향키 | 명령·AST·값 포커스 이동 및 탐색 |
| Enter/n/p, PgUp/PgDn, g/G | 명령 프레임 이동·페이지·처음/끝 |
| b | 원시 64비트 패턴/십진수 표시 |
| /, f | 명령·알고리즘 단계 검색 / 다음 일치 |
| e | 수식 편집. Enter 실행, Esc 취소, 좌우/Home/End·Backspace/Delete 지원 |
| 편집 중 위/아래, Ctrl-U | 소스 이력 / 입력 지우기 |
| m, c, q | 다음 실행 모드 변경 / 작업공간 초기화 / 작업화면 종료 |

REPL에서는 `:workbench`로 진입하고 q로 되돌아온다. `:replay`의 기존 Enter/n/p/q 재생도 유지한다. 작업화면의 값 패널은 선택 노드의 **완료 값**이며 선택 명령 시점의 부분 행렬이 아니다. 실제 CPU를 정지·재개하는 디버거나 JIT가 아니다. Compute 실행에는 만들지 않은 캡처를 표시하지 않는다.

## 계산 예

```text
A = ones(32,48)
B = A
A = A + 2
B(32,48)
size(A)
x = linspace(-10,10,1001)
y = sin(x)
:memory
:drop B
:clear
```

실수 float64·row-major, 스칼라는1×1이다. `*`는 행렬 또는 스칼라 곱, `.*`는 원소별 곱, `/`는 오른쪽 스칼라 나눗셈이다. `sum`은 전체 원소 합이다. `zeros/ones/eye/size/linspace`와 1-based `A(row,col)` 읽기를 지원한다. 실패한 대입은 변수와 `ans`를 함께 보존한다. [언어 명세](docs/LANGUAGE.md)

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
| `make` / `make debug` | NASM + GNU ld로 정적 앱 빌드, Python으로 출처 기록 |
| `make test` | native/runtime/L3/dynamic/workbench 전체 검증 |
| `make workbench-test` | native 두 프로파일과 Workbench 추가 검증 |
| `make verify` | 재빌드 없이 산출물·오브젝트·입력 해시 확인 후 전체 시험 |
| `make test-guards` | 손상·누락·오래된 입력·잘못된 build ID·숨겨진 의존성 차단 시험 |

Python3.10+와 binutils는 시험 도구다. GCC와 glibc는 개발용 비교 바이너리/fixture에만 사용하며 기본 앱의 실행 의존성이 아니다. 동봉 비교 바이너리를 포함한 전체 시험에는 glibc2.34+가 필요하다. `.o`·`.map`·빌드 sidecar는 제공 파일 검증을 위해 포함한다. NASM 부재 시 GAS로 우회하거나 오래된 바이너리를 새 성공으로 재사용하지 않는다.

## 한계와 검증 범위

값당 최대1,048,576원소, 기본 동적 매핑 quota64MiB(`--memory-mib 1..1024`), AST512·재귀64·입력4095바이트·숫자 토큰127바이트·trace8192프레임·matmul16,777,216항 제한을 유지한다. quota는 고정 trace/TUI/이력·스택·전체RSS를 제한하지 않는다. 큰 표·JSON 출력과 CPU 시간도 별도 자원이다.

관찰은 선택된 SSE2 명령에 한정되며 전체 CPU 추적이 아니다. 캡처는 계산 후 재생하고 이후 수식/clear에서 교체된다. 처리된 종료 신호의 정리는 UI 경계에서 수행하며 계산 중 즉시 취소 기능은 아니다. SIGKILL/외부 SIGSTOP/크래시에서 터미널 복구를 보장하지 않는다. 편집은 ASCII이며 Unicode/마우스/디스크 workspace/trace import는 미구현이다. `sin/cos`의 |x|≤1,000,000 등 기존 수학 계약을 유지한다.

[검증 결과](evidence/release-summary.json)와 [검증 보고서](docs/VERIFICATION.md)는 로컬 Linux x86-64 시험이다. 횟수는 반복 corpus와 ABI assertion을 포함하며 전 입력 증명이나 성능 우위·서버 보안 인증이 아니다. 원격 GitHub Actions는 구성만 갱신했고 실행하지 않았다. [Pi5·ARM64·웹·2D/3D 그래프](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)는 기획만 보존했다.

[ABI](docs/RUNTIME-ABI.md) · [L3 경계](docs/LEVEL3-CONTRACT.md) · [수치 계약](docs/NUMERICS.md) · [로드맵](docs/ROADMAP-KR.md) · [도구 출처](docs/TOOLCHAIN-PROVENANCE.md)

압축 해제 직후 `sha256sum -c MANIFEST.sha256`으로 무결성을 확인한다. 해시는 전자서명이나 안전성 인증이 아니다.
