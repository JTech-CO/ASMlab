# ASMlab Dynamic Workspace 구현 명세 - v0.5.0 유지

**상태: Linux x86-64 NASM 구현·로컬 검증 완료.** 미래 설계안과 구분한다. 기본 앱의 L3-Core 의존성 경계는 유지한다.

## 1. 데이터 구조

`include/layout.inc`가 레이아웃을 선언하고 `src/core_storage.asm`이 고정 저장소를 한 번만 정의한다. Value는 다음 8개의 uint64 필드로 구성된다.

| Offset | 필드 | 계약 |
|---:|---|---|
| 0 | rows | 양의 행 수 |
| 8 | cols | 양의 열 수 |
| 16 | data | 실제 연속 float64 데이터 포인터 |
| 24 | bytes | rows×cols×8 |
| 32 | row_stride | cols×8; 이번 버전은 연속 배열만 지원 |
| 40 | dtype | 1=f64 |
| 48 | owner | 1=temp, 2=workspace, 3=static |
| 56 | reserved | 0 |

descriptor와 데이터는 한 할당에 함께 배치하지만, 연산·화면 코드는 `V_DATA` 포인터를 따른다. 임의 stride/view/alias/COW를 지원한다는 뜻은 아니다. `1×1`은 스칼라다. 별도 bigint 수학 타입은 없다.

심볼은 이름32바이트, Value 포인터8바이트, next8바이트의 48바이트 연결 항목이다. `ans` 항목은 정적 head이며 사용자 항목은 동적이다. 탐색은 O(변수 수) 선형 검색이다. 메모리 효율이나 대형 심볼 테이블 성능을 최적화한 해시 테이블로 설명하지 않는다.

## 2. 매핑 allocator

`src/rt/dynamic_memory.asm`은 자체 `rt_sys_mmap/munmap`을 호출한다. syscall 자체는 `src/platform/linux/virtual_memory.asm`에만 있다.

```text
요청 payload N
  → N + private header32 + rounding4095 overflow 확인
  → 4096-byte 페이지 단위 올림
  → heap_used + charged_length overflow / quota 확인
  → anonymous private RW mmap
  → header 기록과 사용량·최고치·성공 횟수 증가
  → 16-byte 정렬을 만족하는 payload 반환
```

할당은 0으로 초기화된 익명 메모리를 사용한다. 실행 권한과 MAP_NORESERVE는 요청하지 않는다. 내부 header는 매핑 길이·요청 크기·예약 공간32바이트다. free는 해당 매핑을 munmap한 뒤에만 사용량을 차감한다. 올바른 소유 포인터의 munmap이 예기치 않게 실패하면 정상 해제를 꾸미지 않고 exit2로 종료한다.

기본 quota64MiB이며 CLI `--memory-mib 1..1024`로 정한다. 내부 byte API는1MiB..1GiB 범위와 현재 live 이상을 허용한다. 현재 세션 중 quota를 바꾸는 언어 명령은 없다.

**이 quota는 동적 매핑 제한이다.** descriptor·버퍼·arena 여유·심볼·매핑 header·페이지 올림을 센다. 고정 BSS AST/trace, 스택, executable, 전체 RSS, 타 프로세스 사용량, CPU 시간은 별개다. 작은 scalar 사용자 변수도 심볼과 Value 때문에 여러 페이지를 쓸 수 있다. 효율보다 단순한 소유권·회수·검증을 우선한 첫 구현이다.

Linux가 mmap 실패를 반환하면 복구 경로로 진행한다. overcommit이나 실제 호스트 전체 메모리 고갈로 OOM killer가 종료하는 경우를 복구한다고 보장하지 않는다. 임의 포인터·중복 free·손상된 header는 내부 ABI 밖이고 스레드 안전성도 없다.

## 3. 임시 값·작업공간·추적 수명

| 영역 | 저장 방식 | 수명 |
|---|---|---|
| AST 노드 | 기존 고정 BSS512개 | 다음 수식/reset까지 |
| 평가 임시 Value | mmap chunk 기반 bump arena, 최소 payload64KiB | 성공 시 재생을 위해 다음 수식까지 |
| 변수·ans | 항목과 Value의 개별 소유 매핑 | 성공한 재대입/drop/clear/종료까지 |
| 선택 명령 trace | 기존 BSS8192×96바이트, 실제 값 비트 복사 | 다음 수식/reset까지 |
| 초기 ans=0 | immutable 정적 descriptor·0 | 할당 없이 시작/clear에 재사용 |

arena chunk는 next/capacity16바이트 뒤부터16바이트 정렬 bump 할당을 한다. 최소 chunk payload64KiB도 header와 페이지 올림을 더하면 실제 quota 청구가69,632바이트일 수 있다. 더 큰 단일 Value는 필요한 큰 chunk로 배치한다. 개별 임시 값은 free하지 않으며 arena 전체를 회수한다.

순서는 **이전 root/result/trace 소비자를 무효화 → 이전 temp 해제 → 새 AST 초기화**다. 실패한 새 수식은 오류 출력 뒤 root/result/trace를 무효화하고 temp를 해제한다. 마지막 성공 trace를 실패 전 상태로 별도 보관하는 기능은 아직 없다.

변수 읽기는 temp로 깊은 복사한다. 따라서 `:drop A`가 workspace A를 해제해도 이미 계산된 AST·추적·결과는 독립적으로 살아 있다. `:clear`는 root/result를 먼저 무효화하고 모든 temp·사용자 항목·지속 값을 해제하여 동적 사용량0과 정적 ans0으로 돌아간다. peak/map/unmap 누적 지표는 계속 유지한다.

## 4. 원자적 대입

예시: `A = expression`.

```text
1. expression 전체 평가 + 결과 finite/shape 검사
2. 신규 변수라면 아직 목록에 연결하지 않은 심볼 항목 확보
3. 새 A용 persistent descriptor+payload 확보 및 복사
4. 새 ans용 persistent descriptor+payload 확보 및 복사
5. 위 단계가 모두 성공한 경우에만 publish
6. 이전 A와 ans 해제
```

어느 staging 할당이 실패해도 확보한 새 값·새 심볼만 회수하고 기존 A·ans·변수 수를 보존한다. 단순 표현식은 새 ans만 staging한다. 기존 상태를 먼저 free해서 메모리를 억지로 확보하지 않는다. 그래서 **최종 workspace 크기가 quota 안이어도 갱신 순간 여유가 부족하면 실패**할 수 있다.

`B=A`, `A=A`, `A=A'`는 aliases가 아니라 독립 복사로 처리한다. 직접 `ans=...`와 내장 함수명 대입은 예약 이름 규칙에 따라 거부된다.

원자성은 **평가/할당 실패에 대한 workspace 계약**이다. commit 이후 화면 출력이 실패하면 exit2를 반환하지만 이미 성공한 대입을 되돌리지 않는다. 강제 종료·시그널·손상된 임의 포인터의 fail-stop을 지속성 트랜잭션처럼 복구하는 기능은 없다.

## 5. 수식 언어 확장

`parse_arguments`는 쉼표 구분 인수 AST를 최대3개까지 구성하고, evaluator는 각 함수의 arity를 평가 전에 확인한다. 괄호·단항·전치·우선순위·전체 줄 검사 규칙을 보존한다.

| 표현 | 지원 |
|---|---|
| `zeros(n)` / `ones(n)` | n×n |
| `zeros(n,m)` / `ones(n,m)` | n×m |
| `eye(n[,m])` | 직사각형 포함 대각선1 |
| `size(A)` | `[rows,cols]` |
| `size(A,d)` | d=1 또는2만 허용 |
| `linspace(a,b,n)` | finite 스칼라 끝점·양의 정수 개수. n=1이면 b |
| `A(r,c)` | 이름 있는 변수 A의 1-based 두 스칼라 인덱스 읽기 |

크기·인덱스는 잘라서 정수로 만드는 것이 아니라 **입력값이 정확히 양의 정수인지 검사**한다. 0·음수·소수·배열 인수와 범위 밖 접근을 거부한다. 차원 곱의 64비트 overflow와 원소 상한을 할당 전에 확인한다. dtype·범위 불일치는 오류이지 조용한 차원 수정이 아니다.

슬라이스, `end`, 단일 선형 인덱스, `A(r,c)=v`, 함수 반환값의 즉시 인덱싱, 빈 배열, block concatenation, 전체 MATLAB 문법은 없다. 기본 내장 이름은 계속 예약된다.

## 6. 수치·관찰 계약

`math.asm`은 v0.3.0과 동일하다. `exec_sse` 명령 디스패치·캡처 부분도 동일하며, 행렬 payload 주소 계산은 새로운 descriptor에 맞게 수정했다. 원래 pair-wise SSE2 곱·누적 순서를 바꾸지 않았다. 한 행렬 곱의 `m*n*k`가16,777,216을 넘으면 계산 전에 거부한다.

`linspace`는 첫/끝 표본 비트를 복사하고 내부 표본은 `t=i/(n-1)`, `t*b+(1-t)*a`로 계산한다. 반대 부호의 큰 값에서 먼저 `b-a`를 만들지 않는다. 균일한 실수 좌표의 correctly-rounded 변환이나 NumPy/MATLAB과 비트 동일성을 보장하지 않는다. 부동소수점 반올림으로 일부 표본이 같아질 수 있다. n=1은 b만 복사한다.

linspace의 실제 산술·끝점 copy와 인덱스 선택 copy는 기존 관찰 커널을 사용한다. 생성자의 정수 채우기, shape 변환, allocator 및 모든 CPU 명령을 추적하는 것은 아니다. 큰 표본 수에서 trace가8192를 넘으면 누락을 명시하고 계산은 계속한다. v0.5.0의 `:trace off`는 Compute로 전환하므로 scratch/관찰 디스패치를 실행하지 않는다.

## 7. 출력과 관리

큰 표는 앞16행×16열을 4열 묶음으로 보여 주고 전체 shape 및 미리보기 사실을 명시한다. 작은 기존16×16 이하는 기존 출력 계약을 보존한다. JSON/quiet는 모든 원소를 출력하므로 네트워크·출력 용량 제한을 대신하지 않는다. `:vars`는 ans와 최신 항목부터 최대64개 미리보기이다.

`:memory`는 used/peak/quota/live/successful maps/unmaps/user_variables를 출력한다. JSON 모드에서는 `{"memory":{...}}` 타입이며 수식 결과의 `ok/data` 레코드와 구분해야 한다. `:drop NAME`은 사용자 변수만 삭제하고 ans는 바꾸지 않는다. 존재하지 않는 변수/예약 ans 삭제는 오류다.

## 8. 검증과 남은 일

[시험](../tests/dynamic_workspace.py)은 실제 mmap allocator fixture를 ABI probe로 호출한다. 32/64비트 overflow·quota·정렬·초기0·센티널·변수 내용·개별 해제 지표, matrix indexing·transposition·rectangular matmul·constructor, 원자적 실패,320변수,180회 churn,450개 형태 혼합 fuzz를 각 대상에서 검사한다. 앱 수준 OS실패는 별도 프로세스 RLIMIT_AS로 유도한다. quota 실패와 RLIMIT_AS실패를 같은 원인으로 기록하지 않는다.

1MiB에서 기존 A=25,000원소를 둔 채 A/B=40,000원소의 새 복사를 staging하면 target 복사 성공 후 ans 복사에서 실패하도록 실제 예산을 구성한다. 기존 변수·ans 보존과 mapping수 차이를 검사한다. 할당 성공을 가짜로 반환하는 테스트가 아니다.

[결과](../evidence/dynamic/dynamic-workspace.json): 동적8,892 assertions, 실패0. 전체186,731 assertions, 별도guard32개. 실제 CPU·OS는 로컬 Linux x86-64이며 원격 CI/ARM/WSL 실기기는 미검증이다. quota로 임의 어셈블리 실행을 sandbox한 제품은 아니다.

v0.5.0에서 [Trace v2](TRACE-V2.md), Observe/Compute 특수화와 [연동 패널](OBSERVABLE-WORKBENCH-KR.md)을 추가했다. 메모리 pool·해시 테이블·COW·범용 dtype·동시성·save/load는 이번 버전에 없으며 공개 서버/Pi/그래프 역시 계획만 유지한다.

## 근거

Linux mmap/munmap 인터페이스는 [Linux man-pages](https://man7.org/linux/man-pages/man2/mmap.2.html)를 기준으로 한다. 이 자료는 OS 계약 설명이며 구현 검증은 첨부한 실행 증거에 따른다. 운영체제별 페이지 크기/ISA가 다른 포팅은 별도 구현이 필요하다.
