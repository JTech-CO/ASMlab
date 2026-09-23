> 보존된 원래 계획 문서이다. 아래 v0.1.0 감사와 제안은 작성 당시 상태이며, 현재 v0.1.1의 실제 완료 결과는 [검증 보고서](../VERIFICATION.md), 후속 상태는 [로드맵](../ROADMAP-KR.md)을 따른다.

# ASMlab Level 3 개발 계획

**기준 버전:** 첨부된 ASMlab v0.1.0  
**계획 작성일:** 2026-09-23  
**문서 상태:** 구현 전 제안. 새 실행 파일이나 기능 구현을 포함하지 않는다.  
**우선 플랫폼:** Linux x86-64. WSL2는 별도 실행 검증 대상으로 둔다.  
**핵심 경험:** 수식 → AST → 실제 실행한 어셈블리 연산 → SIMD 레지스터 변화 → 결과.

## 0. 결론

첫 목표는 기능을 늘린 MATLAB 복제품이 아니라 **현재 기능을 잃지 않고 libc·CRT·외부 수학 라이브러리 없이 실행되는 ASMlab 코어**이다. 이것을 `L3-Core`로 정의한다. 그다음 동적 행렬, 관찰 가능한 수치 알고리즘, 정밀도 개선, 선형대수, 작업환경을 확장한 `L3-Workbench`를 구축한다.

개발의 주 경로는 다음과 같다.

```text
NASM 네이티브 빌드 확정
  → 런타임 호출 경계 분리
  → 자체 문자열/메모리/입출력 및 십진수 변환
  → _start + Linux syscall 통합
  → 기존 기능 회귀검사 + 런타임 의존성 0건 감사
  → L3-Core
  → 동적 Value/작업공간
  → 추적 포맷 및 TUI 개선
  → 수학 함수 정확도·정의역 확장
  → LU/solve → QR·Cholesky
  → 선택적 SIMD 최적화·저장·플로팅
  → L3-Workbench
```

**첫 변경은 `sin/cos`나 AVX2가 아니라 빌드 검증과 런타임 분리이다.** 일정은 소요 일수보다 아래 완료 조건으로 관리한다. 제안한 버전 번호는 구현 범위를 분리하기 위한 구분이며 출시 약속이 아니다.

## 1. Level 3의 정확한 정의

Level 1/2/3은 공인 규격이나 산업 표준이 아니라 이 프로젝트에서 사용한 범위 구분이다. 이번 계획에서는 아래 기준으로 고정한다.

| 경계 | L3-Core 기준 |
|---|---|
| 프로그램 본체 | NASM x86-64 `.asm` / `.inc`에서 만들어진 프로젝트 코드 |
| 시작/종료 | 자체 `_start`, 인수 해석, 초기화, 정리, Linux 종료 syscall |
| 런타임 의존성 | libc, CRT, libm, BLAS, LAPACK, libstdc++, libgcc/compiler-rt, ncurses 등을 링크하지 않음 |
| 운영체제 | Linux 커널과 ELF 로더, 터미널, 파일시스템은 사용함 |
| CPU 명령 | SSE2, 정수 명령, 하드웨어 `sqrt` 등은 사용 가능. CPU 산술을 소프트웨어로 다시 만들 필요는 없음 |
| 빌드 도구 | NASM, ld, make, 개발용 스크립트는 허용 |
| 시험 도구 | Python, MPFR, NumPy, GDB, objdump, strace 등을 별도 시험 환경에서 사용 가능 |
| 금지되는 우회 | 정적 libc를 묶고 무의존이라고 주장하기, C를 어셈블리로 출력해 본체로 채우기, Python 프로세스를 호출해 계산하기 |
| 알고리즘 참조 | 논문·공개 알고리즘을 참고해 어셈블리로 구현 가능. 포팅한 코드·표의 출처와 라이선스는 기록 |
| 네트워크 | 코어 실행·계산·재생에 외부 API나 온라인 서비스가 필요하지 않음 |

NASM의 ELF64 출력과 Linux의 syscall 인터페이스를 사용한다.[W1][W2] `syscall`은 **CPU 명령**을 직접 실행한다는 뜻이며 libc의 동명 `syscall()` 함수를 호출한다는 뜻이 아니다.

완료 수준은 두 개로 나눈다.

- **L3-Core:** 기존 언어·행렬·수학·실행 관찰 기능을 독립 런타임으로 보존한다. 16×16 행렬 제한이나 현재의 제한된 삼각함수 정의역이 남아 있어도 이 완료 조건을 충족할 수 있다.
- **L3-Workbench:** 동적 자료구조, 강화된 관찰 기능, 확장 수학 함수, 선형대수, 저장·재현 기능을 갖춘 연구·교육용 수치 작업환경이다.

CAS, 고유값/SVD, GPU, JIT, 네이티브 GUI, 멀티스레드, 운영체제 개발은 L3-Core의 필수 조건이 아니다. ‘모든 수학 함수’라는 끝없는 범위를 완료 조건으로 삼지 않는다.

## 2. 현재 코드에 대한 확인 결과

### 2.1 이번 검토의 범위

첨부 ZIP을 별도 디렉터리로 풀어 소스와 ELF를 확인했다. 기존 바이너리에서 다음 세 식의 JSON 실행을 확인했다.

```text
sqrt([1,4,9,16])+2          → [3,4,5,6]
[1,2;3,4]*[5,6;7,8]        → [19,22;43,50]
sin(pi/4)                  → 0.70710678118654746
```

이는 **세 건의 스모크 검사**이다. 기존 문서의 14,410개 검사를 이번에 다시 실행한 것이 아니며, NASM으로 새로 빌드한 결과도 아니다. 기존 검증 보고서는 GAS 문법 변환 경로에서 만든 실행 파일의 결과라고 명시한다.[P2] 현재 작업 환경에서도 NASM 실행 파일은 확인되지 않았다. 상세 ELF 출력과 입력 해시는 `BASELINE-AUDIT.txt`에 있다.

| 현 상태 | 실제 위치 | 계획에 주는 의미 |
|---|---|---|
| `main`과 CRT 진입 경로 | `src/main.asm:61-81`, Makefile | 독립 `_start`와 초기화/종료 경로가 필요 |
| libc 의존 선언 | `include/core.inc:90-92` | 선언 목록과 실제 바이너리 import를 구분해 제거 |
| 콘솔/파일 입력 | `src/main.asm:202-211,533-592` | `FILE*`를 자체 fd/버퍼 기반 Reader로 대체 |
| 십진수 해석 | `src/parser.asm:185-205` | 스캔은 어셈블리지만 값 변환은 `strtod`에 의존 |
| 숫자·화면 출력 | `src/view.asm:5-65`와 출력 루틴 | float64 포매터와 typed writer가 필요 |
| 고정 크기 Value | `include/core.inc:5-16,149-180` | DIM_CAP만 늘리는 방식은 안전하지 않음 |
| 변수 저장 | `src/runtime.asm:87-110` | 고정 크기 깊은 복사. 동적화 시 소유권/롤백 재설계 |
| 실제 레지스터 캡처 | `src/kernels.asm:20-40,121-126` | 기존 진실성은 유지하고 확장 |
| trace off 경로 | `src/kernels.asm:20-40` | 기록을 끄더라도 scratch 캡처와 디스패치 경로가 남음 |
| 단일 번역 단위 | `src/asmlab.asm:1-10` | 여러 `.asm` 파일을 `%include`한 하나의 오브젝트임 |

실제 동적 함수 의존은 `printf`, `puts`, `fgets`, `fflush`, `fgetc`, `ferror`, `fopen`, `fclose`, `isatty`, `strcmp`, `strlen`, `memcpy`, `memset`, `strtod`이며, CRT 쪽 `__libc_start_main`과 약한 심볼 `__gmon_start__`도 보인다. `stdin`은 동적 객체/COPY relocation으로 존재한다. 따라서 `nm -u`만으로 목록을 완성하면 안 된다.

`getchar`, `strchr`, `__errno_location`은 헤더에 선언되어 있지만 이번 ELF에서는 실제 import로 확인되지 않았다. **`malloc/free`는 현재 의존성이 아니다.** 데이터는 고정 BSS 공간에 들어가므로, 범용 malloc을 만드는 것은 지금 제거할 의존성이 아니라 후속 확장 설계이다.

### 2.2 유지해야 하는 기존 계약

float64, row-major, 1×1의 스칼라 취급, 쉼표 기반 행렬 문법, `*`와 `.*`의 구분, 스칼라 오른쪽 나눗셈 `/`, 전체 원소 합 `sum`, 실패한 대입에서 변수와 `ans` 보존, 입력 전체 거부, 실제 캡처 기반 재생을 우선 유지한다.[P1][P3]

L3 전환과 동시에 MATLAB 호환 문법이나 결과 정책을 바꾸지 않는다. 예를 들어 `sum(A)`를 갑자기 열별 합으로 바꾸거나 NaN/Inf 전파를 기본값으로 바꾸지 않는다.

## 3. 전체 구성 요소 목록

우선순위는 `C = L3-Core 필수`, `W = Workbench 목표`, `X = 선택 확장`이다. W/X를 완료하지 않았다는 이유로 C의 독립 런타임 완료를 부정하지 않는다.

| ID | 구성 요소 | 포함 작업 | 우선순위 |
|---|---|---|---|
| BLD | 네이티브 빌드/링크 | NASM 빌드, debug/release, 의존 오브젝트 목록, 링크 맵, CI, 빌드 출처 | C |
| ABI | 실행/호출 규약 | `_start`, argc/argv/envp, 스택 정렬, callee-saved, DF, syscall 레지스터, 종료 | C |
| SYS | OS 계층 | read/write/openat/close/ioctl, syscall 오류 전달, 필요한 후속 mmap·signal·clock | C/W |
| IO | 입출력 | 버퍼 Reader/Writer, partial read/write, EOF/EINTR, 마지막 무개행 줄, 파이프 | C |
| PRIM | 문자열/메모리 | compare/length/copy/fill, 용량 제한, 필요 시 overlap-safe move | C |
| DEC | 숫자 문자열 변환 | 정수·16진수 출력, decimal→binary64, binary64→decimal, 지수/부분정규수/-0 | C |
| ERR | 오류 체계 | code/span/node/status, stderr 분리, 실패 상태 전파, 취소 및 자원 정리 | C/W |
| MEM | 메모리/소유권 | 기존 arena 보존, 이후 동적 descriptor/arena/pool, quota, OOM 롤백 | C→W |
| LANG | 수식 언어 | 기존 lexer/parser/evaluator, 이후 다인수 함수·생성자·인덱싱·소스 span | C→W |
| FP | 부동소수점 계약 | binary64, MXCSR, signed zero, subnormal, overflow/domain, ULP 검증 규칙 | C→W |
| MATH | 기본 수학 | 기존 sqrt/sin/cos/log/powi 유지, 이후 range reduction·함수 확장·오차 개선 | C→W |
| DENSE | 벡터/행렬 | 기존 연산, 이후 동적 차원·dot/norm·정확한 합산·일부 블록화 | C→W |
| LA | 선형대수 | 피벗 LU, 삼각해법, solve, slogdet/det, QR, Cholesky, 최소제곱·조건 진단 | W |
| OBS | 관찰/추적 | 실제 명령·레지스터 보존, schema version, 단계/메모리 위치, overflow 표시 | C→W |
| TUI | 터미널 화면 | 기존 AST/레지스터/결과/재생, 이후 패널·키보드·resize·검색·히스토리 | C→W |
| STORE | 저장/재현 | 기존 script/JSON 유지, 이후 CSV·workspace·trace 파일 및 버전/해시 | C→W |
| OPT | 성능 경로 | 관찰/계산 커널 분리, baseline SSE2, 선택적 AVX/FMA dispatch·benchmark | W/X |
| QA | 정확도/내구성 | 기존 회귀, 수치 oracle, ABI 검사, 퍼징, OOM/IO fault injection, PTY, sanitizer 대안 | C→W |
| DOC | 문서/배포 | 언어·수치·ABI·trace 명세, 지원 플랫폼, 검증 범위, 라이선스·상수 출처 | C→W |
| ADV | 후속 연구 | CAS, SVD/eig, FFT/ODE, sparse/complex, JIT, GUI, GPU, 다른 ISA | X |

## 4. 런타임 제거 설계

### 4.1 libc 호출을 한 번에 이름만 바꾸지 않는다

`src/parser.asm`, `src/evaluator.asm`, `src/view.asm` 등의 코어가 외부 구현을 직접 알지 않도록 프로젝트 API를 둔다.

```text
현재:
    parser  → strtod
    view    → printf
    main    → fopen / fgetc / stdin

중간 단계:
    core → rt_* API → 개발용 libc backend
                   → 새 Linux/assembly backend

L3-Core 배포:
    core → 자체 rt_* 구현 → 필요한 Linux syscall
```

중간 libc backend는 비교와 전환을 위한 개발 경로이며 L3 배포 대상에서는 제외한다. 모듈을 나누며 쓰는 NASM `extern`은 프로젝트의 다른 `.asm`에 정의된 심볼일 수 있으므로, `extern` 키워드 자체를 전면 금지하지 않는다.

| 현재 의존 | 대체 설계 | 중요 조건 |
|---|---|---|
| CRT / `main` 시작 | `platform/linux/start.asm`의 `_start` | 진입 스택과 함수 ABI를 구분, 종료는 syscall |
| `stdin`, `FILE*`, `fopen/fclose` | 자체 Stream + fd, openat/close | stdin fd와 파일 fd의 소유권 구분 |
| `fgetc/fgets/ferror` | 버퍼 Reader + 상태 코드 | 한 바이트마다 read syscall을 하지 않음 |
| `printf/puts/fflush` | typed writer + 정수/float 포매터 | 전체 printf 규격을 재구현하지 않음 |
| `isatty` | tty ioctl probe | 비TTY는 ANSI 없는 기존 batch 경로 |
| `strcmp/strlen` | 자체 ASCII 비교·길이 루틴 | 입력 한도와 NUL 종료 계약 명시 |
| `memcpy/memset` | 자체 복사·채우기 | overlap이 필요하면 별도 memmove 계약 |
| `strtod` | `decimal_parse_f64` | 유효 범위에서 올바른 nearest-even 반올림 |

### 4.2 syscall 계층

최소 코어는 read/write/openat/close/ioctl/exit 계열부터 시작한다. 메모리 동적화에는 mmap/munmap, raw TUI에는 rt_sigaction과 터미널 ioctl, 계측에는 clock_gettime을 추가한다. 실제 사용하는 것만 래핑한다.

Linux x86-64 syscall 인수와 일반 함수 호출 인수 규약은 같지 않다. 특히 syscall의 네 번째 인수는 r10이다.[W2] 레지스터 훼손 규칙, 스택 정렬, 반환값/오류값, 길이와 signed/unsigned 해석은 `ABI.md`에서 고정한다. libc의 errno나 TLS가 있다는 가정을 제거한다.

`write` 한 번이 요청한 모든 바이트를 기록한다는 보장은 없으므로, 실제 쓴 바이트 수만큼 진행하는 `write_all`이 필요하다.[W3] 읽기/쓰기 재시도는 호출별로 설계하고, 모든 syscall에 무조건 같은 재시도 루프를 씌우지 않는다. stdout 파이프 종료와 SIGPIPE, 파일 읽기 실패, 버퍼 flush 실패를 시험한다.

### 4.3 빌드와 의존성 감사

NASM→ELF64 object→ld→자체 `_start`의 정적 ELF 경로를 우선한다. 초기에는 현재의 관찰 목적을 따라 non-PIE로 단순화할 수 있지만 이를 ASLR 보안 최적화라고 설명하지 않는다. PIE/재배치는 별도 변경으로 남긴다.

L3-Core 완료 감사에는 다음이 모두 필요하다.

1. `readelf -lW`: PT_INTERP 없음, 실행 가능한 스택 없음, 불필요한 RWX segment 없음.
2. `readelf -dW`: 외부 DT_NEEDED 없음.
3. unstripped 산출물의 `nm -u`와 relocation/symbol 검사: 미해결 런타임 참조 없음.
4. 링크 명령·link map·오브젝트 manifest: CRT, libc, libgcc, 외부 `.a`/`.so`, 타 언어 런타임 코드가 섞이지 않음.
5. 실행 의존성 시험: 동적 로더·libc가 없는 최소 파일시스템에서도 지원되는 기능 실행.
6. 실행 경로 시험: 외부 Python, shell, 수학 도구, 네트워크 호출 없이 계산·재생 가능.

**DT_NEEDED가 없다는 사실만으로 충분하지 않다. 정적 libc도 DT_NEEDED 없이 포함될 수 있다.** GNU ld의 링크 옵션과 입력 파일 규칙은 공식 문서를 기준으로 적용한다.[W4]

## 5. 가장 위험한 개발 항목

### 5.1 십진수 입출력: 독립된 수치 알고리즘으로 취급

현재 lexer는 숫자 문법을 스캔한 뒤 `strtod`로 값을 만들고 출력은 libc에 맡긴다.[P3] 따라서 단순 입출력 교체가 아니라 입력값과 최종 출력값의 수치 정확도를 새로 책임지는 작업이다.

다음 항목을 지원 계약으로 고정한다.

| 항목 | L3-Core 정책 |
|---|---|
| 문법 | 기존 소수점·e/E 지수 문법 유지, locale과 무관한 `.` |
| 범위 | 현재 127바이트 숫자 토큰 한도를 우선 유지, 긴 입력을 잘라 계산하지 않음 |
| 극단값 | 매우 크거나 작은 지수는 일찍 분류하여 메모리/정수 overflow 방지 |
| 반올림 | nearest, ties-to-even |
| 부분정규수 | FTZ/DAZ에 의존하지 않고 정확한 변환 경계를 처리 |
| -0 | 파싱·출력·재파싱에서 비트 보존 |
| nonfinite | 기존 언어와 같이 NaN/Inf 값을 허용하지 않는 기본 정책 |
| 표시 모드 | 일반 표시는 간략화 가능, 저장/JSON은 왕복 가능한 표현 |

제안 구현 순서는 다음과 같다.

1. 정수와 16진수 포매터를 먼저 만들어 부동소수점 포매터 없이 비트패턴을 검사한다.
2. 자체 다중 워드 정수 보조 루틴으로 **느리지만 검증하기 쉬운 정확 변환 기준 경로**를 만든다. 이는 사용자용 임의정밀도 수학 엔진이 아니라 변환 내부 부품이다.
3. decimal을 정수 유효숫자와 10의 지수로 나눈 뒤, 유리수/정수 기반 비교와 guard/sticky 비트로 최종 binary64 반올림을 한 번 수행한다. 반복적인 float64 `×10` 누적을 정확 파서로 취급하지 않는다.
4. 초기 출력은 정확히 반올림한 최대 17 유효숫자 과학적 표기로 왕복 보존을 달성한다. ‘17자리 출력’ 자체만으로 정확성이 성립하는 것은 아니므로 포매터도 검증한다.
5. 짧고 빠른 출력은 Ryu 계열, 빠른 파싱은 Eisel-Lemire 계열의 알고리즘을 검토하되 정확 기준 경로와 검증을 유지한다. 구현 포팅 시 출처/라이선스를 보존한다.[W5][W6]

핵심 불변식은 유한 binary64에 대해 다음과 같다.

```text
bits(parse(format_roundtrip(x))) == bits(x)
```

이 시험만으로는 파서/포매터가 같은 오류를 공유하는 경우를 놓칠 수 있다. **파서와 포매터 각각을 독립 oracle과 비교**하고, 숫자 문자열을 거치지 않고 float64 비트를 주입하는 개발용 시험 진입점도 둔다.

### 5.2 메모리: 크기 상수보다 Value 구조를 바꾼다

현재 Value는 2,064바이트이며 그 안에 256개의 float64가 고정으로 들어간다. Workspace entry도 Value 전체를 내장한다. `DIM_CAP`만 늘리면 저장 공간·복사 크기와 검사 범위가 어긋날 수 있다.

L3-Core에서는 이 구조를 유지해 전환 위험을 줄인다. Workbench 단계에서는 다음으로 바꾼다.

```text
Value descriptor
    dtype / rows / cols / row_stride / data_pointer / byte_length / ownership

Storage lifetimes
    parse+evaluation arena : 식 하나의 임시 노드·결과
    workspace storage     : 변수와 ans, 재대입까지 유지
    trace snapshot arena  : 해당 실행의 재생이 끝날 때까지 유지
```

처음에는 연속 row-major 데이터와 명시적 깊은 복사를 유지한다. view, alias, copy-on-write, 참조 카운팅은 나중에 도입한다. 범용 malloc 호환보다 mmap 기반 arena와 단순한 작업공간 할당 정책이 먼저다.

반드시 구현할 검사는 `rows*cols`, `element_count*8`, 정렬용 덧셈의 overflow, 최대 메모리 quota, OOM, 해제 후 접근, arena reset 이후의 참조, trace snapshot 수명이다. 대입은 **새 변수 값과 ans 갱신에 필요한 할당을 모두 성공시킨 뒤 commit**하여 실패 시 기존 상태를 보존한다.

차원 상한은 ‘무제한’이 아니라 구성 가능한 메모리 예산으로 바꾼다. 예를 들어 기본 quota나 최대 행렬 크기는 벤치마크 뒤 정하며 현재부터 임의의 대용량 지원을 약속하지 않는다.

### 5.3 부동소수점: 동작 정책과 정확도 주장을 분리

L3-Core는 기존의 binary64, MXCSR `0x1f80`, nearest-even, FTZ/DAZ 비활성, 유한 결과 검사 정책을 보존한다.[P3] CPU가 계산하는 `sqrt`를 쓰는 것은 외부 수학 라이브러리 사용이 아니다.[W7]

수학 함수의 정확도 목표는 이후 별도 표로 관리한다. 목표와 측정값, 증명 여부를 섞지 않는다.

| 분류 | 제안 목표 | 입증 방법 |
|---|---|---|
| decimal 변환 | 지원 문법/범위의 correctly-rounded 변환 | 정확 유리수 기준/MPFR, midpoint·subnormal 시험 |
| 기본 산술/sqrt | 선택한 하드웨어 명령 의미와 FP 환경 보존 | 원시 비트 입력과 독립 기준 비교 |
| sin/cos/log 및 확장 | 함수/구간별 ULP와 절대 오차 계약 설정 | 고정밀 oracle, 경계 집중 검사, 실패 corpus |
| sum/dot/matmul | 합산 순서·알고리즘을 명시 | 고정밀 기준, cancellation 사례, backend별 규칙 |
| solve/factorization | 잔차·후방오차·조건 진단 | 재구성/잔차 시험 및 고정밀 비교 |

MPFR은 테스트 환경에서만 사용한다. 고정 256비트 계산을 무조건 참값으로 삼지 않고 반올림 경계에서 정밀도를 올리거나 상·하한으로 binary64 반올림 결과를 확정한다. MPFR 자체는 IEEE subnormal을 그대로 갖지 않으므로, binary64의 지수 범위와 부분정규수 변환을 명시적으로 처리한다.[W8]

삼각함수는 현재 제한된 정의역을 유지한 상태에서 라이브러리를 제거한다. 이후 큰 인수의 quadrant/range reduction을 정확하게 처리하는 경로를 추가한 다음 정의역 제한을 넓힌다. 단순히 `|x| <= 1,000,000` 검사를 삭제하지 않는다.

### 5.4 관찰 기능: 실제 캡처를 제품의 중심 계약으로 유지

현재 기록은 실제 실행한 선택 명령의 XMM0 전후, XMM1 입력, MXCSR를 보관한다. 전체 CPU trace나 실시간 디버거는 아니다.[P1][P2]

다음 모드는 **제안**이며 아직 구현되지 않았다.

| 모드 | 목적 | 구현 기준 |
|---|---|---|
| Observe | 연산 과정을 자세히 학습 | 실제 명령 직전·직후 캡처, 선택한 단위 표시 |
| Compute | 관찰 비용 없이 계산 | 캡처·scratch 기록·중앙 명령 디스패치를 없는 커널 경로 |
| 개발용 Compare | 회귀와 backend 비교 | 같은 입력에서 값/오류/trace 계약을 검증 |

동일 SSE2 알고리즘과 연산 순서를 사용하는 Observe/Compute는 결과 비트 일치를 목표로 한다. AVX/FMA, 블록화, 합산 순서가 다른 backend까지 무조건 비트 일치를 요구하지 않고 수치 계약으로 비교한다.

Trace v2에는 다음 필드를 설계한다.

```text
schema_version / expression_id / sequence
source_span / ast_node_id / algorithm_stage
kernel_id / instruction_site_id / PC-or-module-offset
register_ids / vector_width / active_lane_mask
raw_operands_before / raw_destination_after
mxcsr_before / mxcsr_after
matrix_id + row/column/tile or memory offset (해당 이벤트에서만)
build_id / backend / capture-policy / dropped-event count
```

FMA처럼 입력이 세 개인 명령도 표현할 수 있어야 한다. 사용하지 않는 lane과 계산에 참여한 lane을 구분한다. 루프 일부를 생략하거나 표본 추출하면 **전체 기록처럼 표시하지 않는다.** 행렬 곱의 i/j/k, LU의 pivot, sin의 range reduction/다항식 같은 알고리즘 단계는 별도 의미 이벤트로 넣는다.

캡처 자체가 operand나 MXCSR 상태를 바꾸지 않도록 하고 포매팅은 캡처 이후 수행한다. 소스 위치는 실행한 명령 주소와 build map으로 연결한다. 별도의 범용 x86 디스어셈블러를 런타임에 구현할 필요는 없다. objdump/링크 맵은 개발·패키징 검증에 사용한다.

기본은 계산 후 재생이다. 실시간 한 단계 정지는 VM/continuation/디버거 제어 문제가 추가되므로 별도 기능으로 분리한다.

## 6. 수학·행렬 기능 확장 순서

### 6.1 함수 목록과 범위

| 단계 | 기능 | 선행 조건/주의 |
|---|---|---|
| Core 보존 | + - * /, 원소별 연산, 전치, sum, sqrt/sin/cos/log, 정수 pow | 현재 의미 보존 |
| 기초 도구 | abs, min/max, floor/ceil/trunc/round, sign, scalbn/frexp 유사 내부 도구 | signed zero·반올림 규칙 결정 |
| 유틸리티 | zeros, ones, eye, size, linspace, 다인수 함수, 인덱싱 | 동적 Value와 함수 호출 문법 |
| 벡터 기반 | dot, norm, mean, 안정적 sum | pairwise/compensated 합산 정책, overflow 회피 |
| 초월함수 확장 | exp, expm1, log1p, log2/log10, tan, atan/atan2 | 각 정의역·경계값과 안정적 알고리즘 |
| 거듭제곱 확장 | 실수 지수 pow | 음수 밑·정수성·0·overflow·log/exp 조합 오차를 별도 처리 |
| 선형해법 1 | LU + 부분 피벗, 전진/후진 대입, solve, det/slogdet | 다인수 함수, dynamic matrix, singular 진단 |
| 선형해법 2 | Cholesky, Householder QR, full-rank least squares | SPD 조건, pivot/rank/조건 진단 범위 명시 |
| 후속 | inverse, 정교한 조건수 추정/iterative refinement | solve/factorization 기반 재사용 |

원소별 함수와 행렬 함수의 의미를 구분한다. 예를 들어 향후 `exp(A)`가 원소별 지수함수일 때 행렬 지수함수 `expm(A)`까지 구현한 것으로 보이지 않게 문서화한다.

### 6.2 역행렬보다 solve부터

선형대수 핵심 경로는 다음이다.

```text
pivot를 포함한 LU
  → 전진/후진 대입
  → solve(A,b) 및 다중 RHS
  → 재구성 잔차·해 잔차·조건 진단
  → det/slogdet
  → inverse는 solve(A,I)로 후속 구성
```

선형대수의 factorization, solve, condition estimation, error refinement를 분리한 구조는 LAPACK의 공식 설계에서도 확인할 수 있다. ASMlab에서는 알고리즘 구조만 참고하고 라이브러리를 링크하지 않는다.[W9]

역행렬을 먼저 계산해 `inv(A)*b`로 모든 문제를 푸는 구조는 채택하지 않는다. LU를 여러 우변에 재사용할 수 있게 하고, 작은 determinant만으로 singular 여부를 결정하지 않는다.

정규화된 해 잔차의 한 예는 다음과 같다.

```text
eta = ||A*x - b||∞ / (||A||∞*||x||∞ + ||b||∞)
```

분모 0의 경우는 별도로 정의한다. 잔차가 작더라도 ill-conditioned 문제의 해가 정확하다는 결론은 내리지 않는다. 피벗 0, rank 결손, 매우 작은 rcond, 실패한 Cholesky는 서로 다른 진단으로 표시한다.

QR 최소제곱은 Householder 방식부터 검토한다.[W10] 초기에는 지원하는 행렬 모양과 full-rank 가정을 제한해 명시하고, rank-deficient 최소노름 해는 SVD 등 후속 범위로 남긴다. LU/QR의 부호·피벗·저장 포맷은 계약에 포함한다.

## 7. 터미널과 저장 기능

### 7.1 순수 어셈블리 TUI

Workbench에서는 화면을 AST, 실행 단계/명령, 레지스터, 행렬/결과, 입력/진단으로 나눈다. AST 선택과 trace frame 선택을 연결하고 변경된 lane을 표시한다. 좁은 터미널에서는 탭/단일 패널로 전환한다. 기존처럼 plain 출력과 JSON batch 경로는 별도 유지한다.

입력 편집, 히스토리, 방향키/페이지키, 검색, 스크롤, 화면 resize, 긴 행렬의 viewport를 구현한다. 터미널 모드와 화면 크기는 Linux tty ioctl로 다룰 수 있다.[W11] ncurses를 추가하지 않는다.

raw 모드 도입 시 정상 종료·처리 가능한 인터럽트·중단/재개에서 원래 터미널 상태를 복구한다. 신호 핸들러는 최소한의 플래그만 바꾸고 정리/포매팅은 안전한 주 실행 흐름에서 수행한다. SIGKILL이나 전원 차단까지 복구를 보장하지 않는다. UTF-8 입력 바이트 처리와 화면 열 너비 문제는 분리하며, 최초 수식 식별자는 ASCII를 유지해도 된다.

### 7.2 재현과 파일 형식

기존 `.asmlab` script와 JSON을 보존한 후 CSV 입출력, workspace 저장, trace 저장을 추가한다. 입력 길이·파일 크기·경로 오류·disk full·부분 write를 처리한다. 파일 포맷은 version, dtype, endian, shape, 길이 검증을 포함한다.

Trace 파일은 source expression, 언어 버전, backend/CPU 기능, 반올림 환경, build ID, 캡처/누락 정책을 함께 기록한다. 숫자는 원시 bits 또는 왕복 보장 문자열로 저장한다. 외부로 내보낸 데이터는 사용자 코드나 터미널 제어 시퀀스로 실행하지 않는다.

간단한 plotting은 TUI 그래프나 자체 SVG 파일 출력부터 가능하도록 설계한다. SVG를 외부 뷰어에서 여는 일은 선택적 이용 방식이며 코어 계산이 브라우저에 의존해서는 안 된다. GUI, 웹 뷰어, HTML/JS 구현을 코어에 섞는 변경은 별도 제품 경계로 다룬다.

## 8. 권장 디렉터리 구조

아래는 목표 구조이며 기존 파일을 즉시 모두 분리해야 한다는 뜻은 아니다. 현재 `core.inc`의 정의·데이터를 여러 오브젝트에서 중복 포함하지 않도록, 선언/레이아웃과 실제 저장소를 분리한 후 다중 오브젝트로 전환한다.

```text
ASMlab/
├─ Makefile
├─ include/
│  ├─ abi.inc
│  ├─ limits.inc
│  ├─ layouts.inc
│  ├─ runtime_api.inc
│  ├─ trace.inc
│  └─ linux.inc
├─ src/
│  ├─ platform/linux/
│  │  ├─ start.asm
│  │  ├─ syscalls.asm
│  │  ├─ tty.asm
│  │  └─ signals.asm
│  ├─ runtime/
│  │  ├─ memory.asm
│  │  ├─ strings.asm
│  │  ├─ reader.asm
│  │  ├─ writer.asm
│  │  ├─ errors.asm
│  │  ├─ arena.asm
│  │  └─ state.asm
│  ├─ numeric/
│  │  ├─ integer_format.asm
│  │  ├─ bigint_helpers.asm
│  │  ├─ decimal_parse.asm
│  │  ├─ decimal_format.asm
│  │  ├─ fp_environment.asm
│  │  └─ constants.inc
│  ├─ language/
│  │  ├─ lexer.asm
│  │  ├─ parser.asm
│  │  ├─ evaluator.asm
│  │  ├─ values.asm
│  │  └─ symbols.asm
│  ├─ math/
│  ├─ linalg/
│  ├─ kernels/
│  │  ├─ sse2/
│  │  ├─ observed/
│  │  └─ dispatch.asm
│  ├─ trace/
│  ├─ ui/
│  ├─ storage/
│  └─ main.asm
├─ tests/
│  ├─ native/
│  ├─ regression/
│  ├─ numeric_oracle/
│  ├─ fault_injection/
│  ├─ pty/
│  └─ fixtures/
├─ tools/                   # 개발·검증 전용
├─ docs/
└─ evidence/
```

`tools/`는 **개발·검증 전용**이며 배포 런타임에서는 사용하지 않는다. 전환용 libc backend는 개발 전용 디렉터리에 두고 L3 링크 입력에서 명시적으로 제외한다. 기존 GAS 변환기는 개발 자료로 남길 수 있지만 공식 NASM 빌드의 자동 fallback으로 사용하지 않는다.

## 9. 단계별 릴리스와 완료 조건

| 제안 버전 | 목적 | 주요 작업 | 완료 조건 |
|---|---|---|---|
| v0.1.1 | Native Gate | NASM 네이티브 빌드·기존 회귀·상수/비트 확인·build provenance | 실제 NASM 산출물의 시험과 증거 저장 |
| v0.2.0 | Runtime Foundation | rt_* 경계, libc 비교 backend, 자체 primitive, `_start`/syscall 스모크, decimal 독립 시험 | 기존 앱 유지 + 새 하위 계층 단위시험. 아직 L3로 표기하지 않음 |
| v0.3.0 | L3-Core | 자체 reader/writer/decimal, CRT 제거, 기존 코어 전체 통합 | 기존 기능 보존 + 외부 런타임 0건 + native/debug/release 검증 |
| v0.4.0 | Dynamic Workspace | descriptor/arena/소유권/quota, 다인수 함수·생성자·인덱싱 | 16×16 초과 지원, OOM 및 재대입/ans 원자성 시험 |
| v0.5.0 | Observable Workbench | trace v2, Observe/Compute, 패널 TUI, viewport, 히스토리 | 동일 backend 결과 일치, 실제 주소/비트 검사, PTY·resize·복구 |
| v0.6.0 | Numerical Foundation+ | 범위 축소 개선, 함수 확장, sum/dot/norm 안정화 | 함수별 정의역·오차 계약, 고정밀 oracle와 실패 corpus |
| v0.7.0 | Linear Solve | 부분 피벗 LU, solve, det/slogdet, 잔차/조건 진단 | pivot·singular·다중 RHS·스케일링 시험 및 관찰 단계 |
| v0.8.0 | Factorization | Householder QR, Cholesky, 제한된 최소제곱, 후속 inverse | 재구성/직교성/잔차와 지원 조건 검증 |
| v0.9.0 | Performance & Persistence | 계산 경로 개선, 선택적 AVX/FMA, CSV/workspace/trace, 간단한 plot | fallback 및 정확도 기준, 내보내기·재로드 일치 |
| v1.0.0 | L3-Workbench | 문서·패키지·지원환경·장기 회귀 정리 | 필수 기능/한계/검증 증거를 포함한 독립 배포 |

AVX/FMA는 CPU 기능과 OS의 확장 레지스터 상태 지원을 확인한 뒤 선택해야 한다. baseline SSE2는 유지한다.[W7] AVX2 지원만 보고 FMA를 동일한 기능으로 취급하지 않는다. 성능은 추적 포함/미포함, backend, 행렬 크기를 분리해 측정하며 MATLAB/BLAS보다 빠르다고 사전 가정하지 않는다.

버전별 공개 완료 조건이 충족되기 전에 다음 대형 리팩터링을 같은 변경에 섞지 않는다. 함수 이름과 알고리즘 수를 늘리는 일보다 실패를 탐지할 수 있는 테스트를 앞세운다.

## 10. 바로 시작할 첫 작업 묶음

### PR-01: 네이티브 기준선 확보

대상: `Makefile`, `.github/workflows/test.yml`, `tests/`, `evidence/`, `docs/LEVEL3-CONTRACT.md`.

NASM 직접 빌드가 실패하면 여기서 멈추고 수정한다. GAS 변환 성공으로 우회하지 않는다. 기존 테스트를 실제 NASM 산출물에 실행하고, 상수의 float64 bit pattern, SSE2 trace 주소, MXCSR 정책, CLI 종료 코드를 기록한다. 기존 GAS 실행 파일은 보조 비교용으로만 구분한다.

**통과 조건:** native debug/release 빌드와 기존 회귀, 사용한 도구 버전 및 빌드 입력 해시 기록. 현재 계산 알고리즘과 언어 기능은 변경하지 않는다.

### PR-02: libc 경계 격리

대상: `include/core.inc`, `src/parser.asm`, `src/runtime.asm`, `src/evaluator.asm`, `src/main.asm`, `src/view.asm`.

직접 libc 호출을 프로젝트 API로 분리한다. 비교/복사, 입력 스트림, decimal 변환부터 경계를 확정한다. `printf` 전체 호환 함수를 만드는 대신 화면 구성 루틴을 typed writer로 옮길 설계를 정한다. 현재 고정 Value와 기존 수학 커널은 유지한다.

**통과 조건:** 개발용 libc backend에서 기존 동작 유지, 코어의 직접 libc 참조가 경계 밖에 남지 않음.

### PR-03: 자체 기본 런타임과 syscall 스모크

대상: 새 `platform/linux/start.asm`, `syscalls.asm`, `runtime/memory.asm`, `strings.asm`, `reader.asm`, `writer.asm`.

자체 `_start`로 `--version`, 인수 읽기, fd 읽기/쓰기, 정수/16진수 출력, 오류 종료를 구현하는 작은 독립 target부터 만든다. 이후 reader buffering과 partial write를 검증한다. 이 단계의 smoke 실행 파일을 완성된 ASMlab로 표시하지 않는다.

**통과 조건:** 해당 smoke target에는 libc/CRT/PT_INTERP가 없음. 인터페이스와 에러 전파가 시험됨.

### PR-04: float64 입출력

대상: 새 `numeric/decimal_parse.asm`, `decimal_format.asm`, `bigint_helpers.asm`, `tests/numeric_oracle/`.

정확 기준 변환부터 구현한다. 예제 몇 개에 맞춘 근사 변환으로 `strtod`를 대체하지 않는다. midpoint, ±0, 부분정규수, 최소/최대 유한값, 긴 지수, 잘못된 문자열, 버퍼 경계를 독립 시험한다.

**통과 조건:** 별도 parser/formatter oracle 비교와 bit-exact roundtrip. 합의한 현재 숫자 문법을 보존함.

### PR-05: 기존 전체 코어를 독립 런타임에 연결

기존 parser/evaluator/math/kernels/AST·register·result view를 새로운 I/O와 `_start`에 연결한다. `FILE*`와 fd가 섞이지 않게 한다. 입력과 재생이 같은 reader 버퍼 상태를 안전하게 공유하도록 한다.

**통과 조건:** 기존 기능 전체 회귀와 dependency audit. 여기서 처음 L3-Core를 선언한다. 동적 행렬, AVX2, 새로운 수학 함수는 이 PR에 넣지 않는다.

## 11. 작업 분해 구조(WBS)

다음 목록은 구현할 작업을 누락하지 않기 위한 제안 backlog이다. ‘완료’ 표시는 현재 상태가 아니라 각 작업의 통과 조건을 뜻한다.

| 작업 ID | 작업 | 선행 | 완료 조건 |
|---|---|---|---|
| C01 | L3 범위/허용 의존성 명세 | 없음 | runtime/toolchain/test 경계 문서 |
| C02 | NASM 네이티브 기준 빌드 | C01 | 실제 빌드 로그와 도구 버전 |
| C03 | 기존 회귀를 native 산출물에 재실행 | C02 | baseline report, 실패 수정 |
| C04 | 상수 인코딩/trace 주소 대조 | C02 | 원시 bits와 objdump 비교 |
| C05 | runtime ABI/error 계약 | C01 | 인수/반환/레지스터/오류표 |
| C06 | 레이아웃/선언/저장소 분리 | C05 | 중복 storage 없는 모듈 경계 |
| C07 | 전환용 libc backend | C05 | 코어 기능 유지 및 import 격리 |
| C08 | memory copy/fill/필요한 move | C05 | 길이0/경계/정렬/overlap 계약 시험 |
| C09 | 문자열 length/compare/scan | C05 | bounded input 및 종료 조건 시험 |
| C10 | 정수/hex writer | C08,C09 | 음수 최솟값·최댓값/버퍼 경계 |
| C11 | `_start`와 종료 | C05 | argc/argv 및 exit code 시험 |
| C12 | syscall wrappers | C05 | 인수/오류/훼손 레지스터 시험 |
| C13 | fd Reader | C08,C12 | partial read/EOF/EINTR/무개행 마지막 줄 |
| C14 | Writer/write_all/flush | C10,C12 | partial write/오류/pipe 시험 |
| C15 | TTY 감지와 plain fallback | C12 | TTY/pipe/file 경로 시험 |
| C16 | 숫자용 다중 워드 정수 보조 | C08 | shifts/multiply/divide/compare 불변식 |
| C17 | 정확 decimal parser | C16 | 독립 oracle, 한도/정의역 정책 |
| C18 | 정확 decimal formatter | C16 | 독립 oracle, -0/부분정규수/왕복 |
| C19 | 숫자 parser/formatter 결합 시험 | C17,C18 | raw-bits 기반 roundtrip corpus |
| C20 | typed AST/result/register renderer | C10,C18 | 값·주소·비트·정렬 표시 |
| C21 | JSON writer/escaping | C14,C18 | 유효 JSON, 오류 channel 분리 |
| C22 | 기존 언어와 no-libc backend 결합 | C07,C13,C17 | 기존 수식 의미/오류 유지 |
| C23 | 기존 trace/replay 결합 | C15,C20 | 실제 캡처·재생 기능 유지 |
| C24 | CRT/libc 참조 제거 및 ld target | C11,C22,C23 | 링크 map, unstripped 심볼 감사 |
| C25 | 무의존 실행/회귀 release gate | C03,C19,C21,C24 | PT_INTERP/NEEDED/외부코드 없음 |
| W01 | Value descriptor/ownership 명세 | C25 | 라이프타임/stride/차원 계약 |
| W02 | arena와 workspace 할당 | W01 | 정렬/overflow/quota/OOM 시험 |
| W03 | transactional assignment/ans | W02 | 모든 할당 실패 지점에서 롤백 |
| W04 | 동적 행렬/기존 연산 이식 | W02,W03 | 기존 결과 및 16×16 초과 사례 |
| W05 | 다인수 함수/생성자 | W04 | arity/shape/문법 회귀 |
| W06 | 인덱싱/범위 검사 | W04,W05 | 경계값·잘못된 인덱스·정책 |
| W07 | 확장 심볼 저장소 | W03 | 이름 한도/충돌/재대입/삭제 |
| W08 | trace v2 schema/site map | C25 | raw register·operand·PC·stage 계약 |
| W09 | observe/compute 커널 분리 | W08 | 동일 backend 결과 비트 보존 |
| W10 | snapshot 수명/trace quota | W02,W08 | drop count/선택 캡처/재생 안전 |
| W11 | TUI 패널/viewport | W08,W10 | AST/명령/레지스터/결과 연동 |
| W12 | 키 입력/히스토리/검색 | W11 | raw key/escape/붙여넣기/한도 |
| W13 | resize/signal/terminal 복구 | W12 | PTY 정상종료·중단/재개 시험 |
| W14 | FP 분류/scaling 내부 도구 | C25 | -0/subnormal/유한값 경계 |
| W15 | MPFR/정확수 oracle 하네스 | C19 | raw input bits·반올림 확정 방식 |
| W16 | sin/cos range reduction 확장 | W14,W15 | quadrant/거대 입력 경계 corpus |
| W17 | log/log1p 개선 | W14,W15 | 1 근처·subnormal·극단 지수 |
| W18 | exp/expm1/추가 초월함수 | W14,W15 | 함수별 오차/정의역 표 |
| W19 | pow 확장 | W17,W18 | 음수 밑/정수성/특수값 정책 |
| W20 | sum/dot/norm 안정화 | W04,W15 | cancellation/overflow/underflow 사례 |
| W21 | LU 부분 피벗 | W04,W05,W20 | P/L/U 재구성·pivot 단계 trace |
| W22 | 삼각해법/solve | W21 | 다중 RHS/잔차/singular 처리 |
| W23 | slogdet/det | W21 | 부호/크기/overflow 정책 |
| W24 | 조건 진단/잔차/후방오차 | W22 | ill-conditioned 경고와 의미 구분 |
| W25 | Cholesky | W04,W20 | SPD 성공·비SPD 실패·재구성 |
| W26 | Householder QR | W04,W20 | 직교성·재구성·안정적 norm |
| W27 | 제한된 최소제곱 | W26 | full-rank 가정·잔차·범위 오류 |
| W28 | inverse | W22 | solve(A,I) 기반·잔차·진단 |
| W29 | CSV read/write | C13,C18,W04 | 따옴표/행렬 직사각형/오류 정책 |
| W30 | workspace snapshot | W03,C18 | version/길이/값/재로드 일치 |
| W31 | trace export/import | W08,W10 | build/backend/source/drop 메타정보 |
| W32 | SSE2 compute 최적화 | W09,W20 | 정확도 유지·비추적 benchmark |
| W33 | 독립 배포/문서 정리 | W13,W24,W27,W30,W31 | 한계/플랫폼/증거/출처 일치 |
| X01 | AVX/AVX2/FMA dispatch | W32 | CPU+OS 검사, fallback, 오류 기준 |
| X02 | TUI plot/자체 SVG 출력 | W05,W29 | 정의역/축/불연속/저장 오류 |
| X03 | 반복 개선/정교한 rcond | W22,W24,W15 | 개선 전후 오차·수렴 실패 처리 |
| X04 | 복소수·희소행렬 | W01 | 새 dtype/소유권/커널 계약 |
| X05 | 고유값·SVD | W26 | 별도 수치 알고리즘 프로젝트 |
| X06 | FFT·ODE·수치 적분 | W18,W20 | 정확도/안정성/스텝 제어 명세 |
| X07 | 사용자 함수·제어문 | W05 | scope/call frame/실행 예산 |
| X08 | CAS | 별도 설계 | symbolic AST/rewrite/정확수 계층 |
| X09 | JIT·실시간 step | 별도 설계 | 실행 메모리/재개 상태/추적 계약 |
| X10 | GUI·Windows·ARM 포팅 | 별도 설계 | OS/ISA/ABI별 backend와 시험 |

## 12. 검증 전략과 중단 조건

| 축 | 시험 방법 | 통과 기준 |
|---|---|---|
| 빌드 진실성 | native NASM debug/release, link map, provenance | 변환 경로를 native로 오인하지 않음 |
| 외부 의존성 | ELF+심볼+오브젝트+최소 runtime | 숨은 정적 라이브러리까지 제외 |
| ABI | register canary, stack alignment, DF, syscall 상태 | 호출 전후 계약 위반 없음 |
| 언어 회귀 | 기존 식·오류·대입·ans·script·JSON | 의도하지 않은 의미 변경 없음 |
| 숫자 입출력 | 독립 oracle+bit roundtrip+midpoint corpus | 계약 내 정확 반올림/보존 |
| 수학 | 고정밀 비교+경계+랜덤 raw binary64 | 명시한 함수/구간별 오차 계약 |
| 선형대수 | factor reconstruction/residual/condition | 단순 출력 일치보다 수치 품질 확인 |
| trace | 실제 PC/명령/bits/MXCSR 및 compute 비교 | 가짜 레지스터/누락 은폐 없음 |
| 메모리 | guard page/canary/quota/fault injection | 범위 초과/수명 위반/롤백 실패 없음 |
| IO/TUI | PTY, EOF/short IO/resize/signals | plain/interactive 모드 모두 정상 |
| 내구성 | malformed input fuzz, 긴 실행/반복 대입 | 비정상 종료와 누적 누수 탐지 |
| 플랫폼 | 실제 Linux, 별도 WSL2, CPU fallback | 시험한 조합만 검증됨으로 표시 |

순수 어셈블리에 고수준 언어용 sanitizer를 붙였다고 모든 접근이 자동 계측되는 것으로 가정하지 않는다. guard page, 경계 canary, 별도 test harness, 디버거와 실행 기반 검사를 조합한다.

개발 중 아래 상황에서는 다음 기능을 추가하지 않고 원인을 해결한다: native build 실패, 기존 계약 회귀, 수치 oracle 불일치의 원인 미확인, Observe/Compute 동일 backend 불일치, 실패한 대입의 부분 commit, trace 수명 위반, 의도하지 않은 import 발견.

## 13. 이번 범위에서 미루는 것

전체 MATLAB 문법 호환, Simulink, 툴박스, 전문 CAS, 범용 임의정밀도/유리수 엔진, GPU/CUDA, 다중 스레드, 실시간 OS, 자체 커널/부트로더, 다른 ISA, 원격 다중 사용자 계산 서버는 L3-Core에 포함하지 않는다.

특히 기능 시각화를 이유로 계산을 JavaScript로 재구현하거나 외부 그래프 프로그램을 필수 런타임으로 추가하지 않는다. 최종 성능을 높이기 전에 수치 정확도와 관찰의 진실성을 고정한다.

**바로 실행할 개발 목표는 `v0.1.1 Native Gate → v0.2.0 Runtime Foundation`이다.** 이 두 단계에서는 현재 식·행렬·수학 함수·trace 계약을 보존하고, Level 3 전환을 검증할 수 있는 경계를 만드는 데 집중한다.

## 참고 근거

### 프로젝트 자료

[P1] 첨부 ASMlab v0.1.0 `README-KR.md`: 범위, 입력/출력, trace, 플랫폼, 한계.  
[P2] 첨부 `docs/VERIFICATION.md`: GAS 검증 빌드 출처, 14,410개 기존 검사, 미검증 범위.  
[P3] 첨부 `docs/NUMERICS.md`: binary64/row-major, MXCSR, strtod, 수학 정의역과 정확도 한계.  
[P4] 첨부 ZIP의 `src/*.asm`, `include/core.inc`, `Makefile`, ELF. 이번 점검 결과는 동봉 `BASELINE-AUDIT.txt` 참조.

### 1차 기술 자료

[W1] NASM, Output Formats / ELF64. `https://www.nasm.us/doc/nasm09.html`  
[W2] Linux man-pages, syscall(2). `https://man7.org/linux/man-pages/man2/syscall.2.html`  
[W3] Linux man-pages, write(2). `https://www.man7.org/linux/man-pages/man2/write.2.html`  
[W4] GNU Binutils, ld Options. `https://sourceware.org/binutils/docs/ld/Options.html`  
[W5] Ulf Adams, Ryu reference implementation and algorithm description. `https://github.com/ulfjack/ryu`  
[W6] Daniel Lemire, Number Parsing at a Gigabyte per Second. `https://arxiv.org/abs/2101.11408`  
[W7] Intel, Intel 64 and IA-32 Architecture manuals. `https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html`  
[W8] GNU MPFR manual, rounding/transcendental functions/binary64 emulation. `https://www.mpfr.org/mpfr-current/mpfr.html`  
[W9] LAPACK Users' Guide, Linear Equations. `https://www.netlib.org/lapack/lug/node38.html`  
[W10] LAPACK Users' Guide, QR Factorization. `https://www.netlib.org/lapack/lug/node40.html`  
[W11] Linux man-pages, ioctl_tty(2). `https://www.man7.org/linux/man-pages/man2/ioctl_tty.2.html`

외부 자료는 OS/ISA/알고리즘 설계 근거이며 ASMlab 구현의 정확성 증거 자체가 아니다. 앞으로의 구현 완료 여부는 해당 산출물의 테스트 로그로 판정한다.
