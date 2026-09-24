# ASMlab v0.5.0 - Observable Workbench

## 구현 범위

Linux x86-64 NASM 계산 코어에 **Observe/Compute 실행 특수화, Trace v2 JSON, 키보드 기반 연동 TUI**를 추가했다. 전체 native 앱은 자체 진입점·수치 변환·메모리·입출력·터미널 호스트를 사용한다. libc, CRT, ncurses, Python, JavaScript를 런타임에 호출하지 않는다. 이 버전은 웹 앱·Windows EXE·ARM 포팅·그래프 기능이 아니다.

## 1. 두 실행 경로

| 모드 | 실제 계산 | 추적 |
|---|---|---|
| Observe | 기존 순서의 SSE2 산술과 관찰 디스패치 | 실제 명령 직전·직후 XMM0/XMM1과 MXCSR 캡처 |
| Compute | 같은 알고리즘을 빌드 시 다시 특수화한 인라인 SSE2 | 캡처·scratch 기록·중앙 `exec_sse` 호출 없음 |

`include/observation.inc`의 `OP`는 Observe에서는 관찰 함수를 호출하고, `COMPUTE_BUILD`에서는 직접 SSE2 명령으로 확장된다. `TRACE_SET`/`TRACE_SHAPE`는 Compute에서 아무 코드도 만들지 않는다. 파서 뒤에서 평가 경로를 수식당 한 번 선택한다. 원소별 산술 연산 종류는 커널 진입 때 선택하며 루프의 산술 명령마다 opcode를 디스패치하지 않는다.

두 경로 모두 파싱·검증·할당·대입 비용은 존재한다. Compute가 무조건 빠르다거나 MATLAB·BLAS보다 빠르다고 주장하지 않는다. JIT가 아니며 실행 중 새 기계어를 만들지 않는다. 코드 크기는 두 특수화를 포함하므로 증가한다. 같은 연산 순서와 SSE2를 사용한 두 경로의 결과 비트와 최종 MXCSR를 비교한다. 향후 FMA·AVX·다른 합산 알고리즘까지 비트 일치를 일반화하지 않는다.

### 선택 규칙

```sh
./bin/asmlab --mode observe -e 'sin(pi/4)'
./bin/asmlab --mode compute --json -e 'sum(sin(linspace(-3,3,8192)))'
./bin/asmlab --trace-json -e 'sqrt([1,4,9,16])+2' > trace.json
```

일반·대화형은 Observe, `--json`/`--quiet`는 Compute가 기본이다. `--trace-json`은 Observe가 기본이다. 명시한 `--mode`가 우선한다. `:mode observe`/`:mode compute`는 **다음 수식**에 적용한다. `:trace off`는 이제 Compute의 별칭이며, `:trace on`/`:trace all`은 Observe를 선택한다. `--bits`는 표시 옵션이지 모드 강제 옵션이 아니다.

현재 선택 모드와 이전 실행의 모드는 따로 보관한다. 모드만 바꾸고 이전 실행을 내보내면 원래 모드와 캡처가 유지된다. Compute 실행 후에는 이전 Observe 기록을 새 실행의 것처럼 보여주지 않는다.

## 2. Trace v2

소스의 0-based 반열린 byte span, AST 노드 ID·자식 연결·평가된 차원, 수식 순번, 알고리즘 단계, 메모리 문맥, 실제 명령 PC, 원시 레지스터 bits, 활성 lane과 명령 폭, 전후 MXCSR를 기록한다. `sin/cos`는 범위 축소·다항식·복원, `log`는 정규화·변환·다항식·복원, 행렬 곱은 곱·누적·환원 단계를 구분한다.

관찰 범위는 기존의 **선택된 12종 SSE2 명령**이다. 분기, 모든 메모리 이동, 정수 생성자 채우기, 할당과 CPU 전체 명령 스트림을 기록하지 않는다. 생성자·변수 복사처럼 관찰 명령이 없는 실행도 정상이다. 모든 셀·명령이 캡처되었다고 해석하지 않는다.

수식당 앞의 8,192개 프레임만 보관한다. 실행한 관찰 명령 수와 누락 수를 함께 공개한다. Compute의 `executed_watched`는 `null`로, 관찰 명령 횟수를 세지 않았다는 의미다. 산술을 전혀 수행하지 않았다는 뜻이 아니다. `dispatcher_entries=0`과 Compute 코드 영역의 역어셈블 검사로 디스패치 제거를 검증한다.

`--trace-json`은 수식당 한 줄 JSON을 stdout으로 내보낸다. `:trace json`은 최근 성공 스냅샷을 내보낸다. 출력 리다이렉션으로 파일 저장이 가능하지만 **trace 읽기·파일 재생·전체 workspace 복원 API는 이번 범위가 아니다.** 오류 수식에는 실패 envelope를 내보내고 이전 임시 스냅샷을 사용할 수 없게 한다. 자세한 형식은 [TRACE-V2.md](TRACE-V2.md)에 있다.

## 3. 작업화면

```sh
./bin/asmlab --workbench -e 'sqrt([1,4,9,16])+2'
# 또는 일반 REPL에서
# :workbench
```

stdin과 stdout이 모두 TTY여야 한다. ANSI alternate-screen/CUP를 지원하는 터미널을 대상으로 한다. 최소 80열×24행, 최대 그리기 영역 200열×64행이며 자동 줄바꿈 방지를 위해 마지막 물리 열은 비운다. 작은 창에서는 크기 안내만 표시한다. 크기와 신호를 읽어 다시 그리며 키 입력을 요구하지 않는 유휴 resize도 처리한다. GUI·마우스·Unicode 편집기는 아니다.

| 영역 | 표시와 연결 |
|---|---|
| 상단 | 다음 모드, 스냅샷 실행 모드·순번, 소스, 선택 노드 span, retained/executed/dropped |
| 왼쪽 AST | 실제 구문 트리, 선택 표시, 계산 완료 차원 |
| 오른쪽 명령 | 선택 노드 ID, 실제 산술 명령, 알고리즘 단계 |
| 레지스터 | 선택 프레임의 실제 PC·원소 문맥·활성 lane/명령 폭·입력/출력·MXCSR |
| 하단 값 | 선택한 노드의 **계산이 완료된 값**, 최종 결과 shape, 행·열 viewport |

명령 프레임을 옮기면 대응 AST 노드와 값이 따라간다. AST 노드를 옮기면 해당 노드의 첫 보관 프레임을 선택한다. 그 노드의 프레임이 없으면 없다고 표시한다. 값 영역은 **선택 프레임 시점의 부분 행렬이 아니라 해당 노드의 완료 값**이다. 실행을 정지하거나 중간 상태에서 재개하는 디버거가 아니다.

### 키

| 키 | 동작 |
|---|---|
| Tab | 명령 → AST → 값으로 포커스 이동 |
| 방향키 | 명령/AST 이동 또는 값의 행·열 스크롤 |
| Enter / n / p | 명령 포커스에서 다음/다음/이전 프레임 |
| PgUp / PgDn | 명령 목록에서 페이지 이동 |
| g / G, Home / End | 현재 지원 목록·값의 처음/끝 |
| b | 레지스터 십진수/원시 hex 표시 전환 |
| /, f | opcode·알고리즘 단계의 대소문자 구분 부분문자열 검색 / 다음 일치 |
| e | 새 수식 편집. Enter 실행, Esc 취소 |
| 편집 중 ←/→, Home/End | 커서 이동 |
| 편집 중 Backspace/Delete/Ctrl-U | 삭제 / 삭제 / 입력 지우기 |
| 편집 중 ↑/↓ | 최근 64개 소스 이력 탐색, 새 draft로 복귀 |
| m | 다음 실행의 Observe/Compute 전환 |
| c | 값·AST·trace 해제 및 작업공간 초기화. 소스 이력은 유지 |
| q 또는 Ctrl-D | 작업화면 종료. REPL에서 열었으면 원래 REPL로 돌아감 |

이력은 세션 안의 **소스 문자열 64개만** 보관한다. 이전 변수 상태나 과거 레지스터 스냅샷을 보관하지 않으며 디스크에 저장하지 않는다. 이력의 수식을 실행하면 **현재 작업공간에서 새 실행**이다. 수식 편집은 ASCII 4,095바이트, 검색은 63바이트로 제한한다. 넘는 입력 바이트는 삽입하지 않고 제한 알림을 표시한다. 기존 배치/REPL 입력의 전체 거부 정책은 별도로 유지한다. 콜론 명령은 작업화면 편집란에서 실행하지 않으며 q로 REPL에 돌아가 사용한다.

## 4. 터미널 상태와 수명

Linux kernel termios를 저장하고 ICANON/echo/일부 입력 변환/OPOST를 해제한다. ISIG는 유지한다. 자체 Reader에 이미 보관된 stdin 바이트를 먼저 소비해 REPL에서 넘어올 때 미리 읽은 입력을 잃지 않는다. 정상 종료·EOF/I/O 오류와 처리한 신호에서는 원래 termios·커서·화면을 복구한다.

SIGINT/SIGTERM/SIGHUP/SIGQUIT/SIGPIPE 핸들러는 플래그만 기록하고 UI 경계에서 정리 후 종료한다. 처리한 종료 신호의 상태는 `128+signal`이다. SIGTSTP는 먼저 터미널을 복구한 뒤 SIGSTOP으로 실제 중단하고, SIGCONT 후 작업화면을 복구한다. SIGWINCH는 크기 갱신을 요청한다. **수식 계산 중 즉시 취소/롤백하는 기능은 아니며 다음 UI 경계에서 처리**한다. 잡을 수 없는 SIGKILL/외부 SIGSTOP·프로그램 크래시·시스템 장애에서 복구를 보장하지 않는다.

성공한 수식의 arena·AST·trace는 다음 수식/clear까지 유효하다. `:drop`은 별도 persistent 값만 지우므로 기존 임시 값·원시 캡처를 손상시키지 않는다. 실패한 수식은 해당 임시 값을 회수하고 재생 스냅샷을 무효화한다. trace·화면·이력 고정 BSS는 동적 quota 밖이며 전체 프로세스 RSS 제한이 아니다. 구현은 단일 스레드·단일 세션이다.

## 5. 검증과 비목표

기존 Compute 기본 회귀 외에 Observe 모드로 동일 수치 corpus를 다시 실행한다. trace raw bits/실제 PC·명령 bytes/span·연결·오버플로를 검사하고, 두 경로의 결과·최종 MXCSR를 비교한다. Compute 코드 영역의 디스패치·관찰 함수 호출·trace 상태 접근 부재를 역어셈블로 검사한다. 제어 PTY에서 편집/이력/검색/초소형 resize/신호/중단·재개/입력 버퍼/termios 복원을 확인한다.

[검증 보고서](VERIFICATION.md)와 [실행 결과](../evidence/workbench/observable-workbench.json)는 로컬 Linux 컨테이너의 실제 시험이다. 원격 CI·Windows/WSL 실기기·모든 terminal emulator·ARM/Pi·웹 공개 서비스·수학적 전수 증명을 포함하지 않는다. [Pi/web/그래프 계획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 이전 문서만 그대로 유지한다.

## 기술 참조

플랫폼 계약을 참고한 문서이며 ASMlab 자체의 성공 증거와는 별개다.

- NASM preprocessor: https://www.nasm.us/doc/nasm05.html
- Linux kernel termios ioctls: https://man7.org/linux/man-pages/man2/TCSETS.2const.html
- Window size and SIGWINCH: https://man7.org/linux/man-pages/man2/TIOCGWINSZ.2const.html
- Signal handlers and restorer: https://man7.org/linux/man-pages/man2/sigaction.2.html
- poll: https://man7.org/linux/man-pages/man2/poll.2.html
