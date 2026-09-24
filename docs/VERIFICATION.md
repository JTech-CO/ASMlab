# ASMlab v0.5.0 Observable Workbench - 검증 보고서

검증 대상은 동봉된 Linux x86-64 release/debug, 개발용 libc 비교 실행 파일과 NASM 시험 fixture이다. 실제 실행 환경은 Linux 6.18.44 x86-64 컨테이너, NASM 2.16.03, GNU binutils 2.44이다. 도구 버전은 [환경 기록](../evidence/native/environment.txt), 각 입력·오브젝트·실행 파일 해시는 `bin/*.build.json`에 있다. 기록 시각은 보고서의 UTC 필드를 기준으로 한다.

## 1. 결론

전체 릴리스 검사 **225,984개 assertion, 실패 0**, 별도 실패 차단 검사 **41건, 실패 0**이다. [전체 결과](../evidence/release-summary.json) · [별도 guards](../evidence/guard-summary.json)

이는 유한한 시험의 실행 횟수다. 동일 corpus를 여러 프로파일/모드/백엔드에서 반복하고 ABI assertion도 포함하므로, 서로 다른 수식의 수나 전 입력에 대한 정확성 증명으로 해석하지 않는다. 원격 CI는 구성만 갱신했고 실행하지 않았다.

| 검사 묶음 | assertion | 실패 |
|---|---:|---:|
| Native: 기존 release/debug 회귀와 네이티브 계약 | 30,074 | 0 |
| Runtime: 독립 루틴·호출 경계·libc 비교 | 41,261 | 0 |
| L3: 정확 decimal·전체 정적 앱 통합 | 106,510 | 0 |
| Dynamic Workspace | 8,892 | 0 |
| Workbench: Observe 회귀 두 프로파일 + 새 기능 검사 | 39,247 | 0 |
| **합계** | **225,984** | **0** |

Workbench 39,247 = 기존 14,410개 corpus를 Observe 모드에서 release/debug 각각 실행한 28,820 + 추가 10,427이다. Native의 기존 JSON 수치 검사는 현재 기본 Compute 경로를 사용하며, 고전 캡처 검사는 Observe를 명시적으로 유지한다. Runtime 41,261 = libc 비교 14,410 + 기본 루틴 26,123 + 경계 검사 728이다. L3 106,510 = decimal 106,439 + 전체 앱 통합 71이다.

## 2. Observe / Compute의 실제 분리

`tests/observable_workbench.py`에서 프로파일·모드 조합별 **518개 결과 레코드**를 실행했다. 성공한 수식 결과의 binary64 비트를 비교하고, quota 초과 시 변수·ans 보존과 오류 상태도 비교했다. Trace v2 corpus의 **23개 수식 × 두 프로파일 = 46개** 성공 사례는 Observe/Compute의 결과와 평가 직후 최종 MXCSR를 비교했다.

Compute 코드의 실제 ELF 주소 범위를 역어셈블해 `exec_sse`, watched dispatch 및 Observe용 숫자 함수 호출이 없고 trace 저장 상태를 참조하지 않는지 검사했다. 같은 템플릿에서 생성된 인라인 SSE2 명령도 확인했다. 공유 allocator/검증/심볼 API 호출은 허용하며 프로그램 전체가 함수를 전혀 호출하지 않는다는 뜻은 아니다.

[검사 상세 및 실제 주소 범위](../evidence/workbench/observable-workbench.json)

두 모드의 수학 연산 순서는 같지만 이 사실이 향후 AVX/FMA/다른 합산 순서까지 동일성을 보장하지는 않는다. 현재 Compute는 JIT나 외부 수학 백엔드가 아닌 빌드 시 특수화이다.

## 3. Trace v2의 진실성 검사

두 프로파일에서 합계 **1,434개 보관 프레임**을 조사했다. 실제 명령 주소와 ELF 명령 바이트, AST 노드와 source span, raw XMM 비트, MXCSR 제어 상태, 활성/하드웨어 lane, 행렬 문맥을 대조했다. 알려진 `sqrt([1,4,9,16])+2` 결과도 비트로 비교했다.

8192프레임 prefix 보관 정책의 초과·누락 계수, 모드 변경 후 이전 실행의 모드 보존, 변수 삭제 후 복사된 trace의 수명, 인덱스 읽기의 문맥, 괄호를 포함한 span, 오류 JSON을 시험했다. Compute에는 캡처가 없으며 `executed_watched: null`로 표시한다. 0개를 마치 모든 실제 CPU 명령 수인 것처럼 표시하지 않는다.

[실제 Observe JSON](../evidence/workbench/trace-v2-example.json) · [같은 식의 Compute JSON](../evidence/workbench/compute-example.json) · [오류 JSON](../evidence/workbench/error-example.json)

범위는 선택된 SSE2 명령이다. 전체 CPU 명령·모든 메모리 접근·GPU·JIT 추적이 아니다. PC는 미리 작성된 공유 watched 명령 위치이며 개별 수식 토큰별로 새 기계어가 생성되는 것은 아니다. `sources`는 캡처된 레지스터 뷰 목록이며 모든 명령의 정밀한 읽기 집합 표기가 아니다.

## 4. 실제 터미널 시험

release/debug 각각 **제어 터미널이 설정된 Linux PTY**에서 다음을 실행했다.

- AST/명령/레지스터/완료 값 패널, 선택 연동, 값 행·열 스크롤, 비트 표시.
- 수식 편집·커서 키·제출, 소스 이력 호출, opcode/단계 검색·다음 일치·검색 실패.
- 120×34, 80×24, 최소 미만 화면과 1×1로 축소 후 복귀.
- 다음 실행 모드와 마지막 실행 모드 분리, Compute 무캡처 화면.
- 잘못된 수식 이후 유효하지 않은 값 포인터를 접근하지 않고 탐색, 기존 ans 보존, 다음 실행.
- 정상 종료 후 termios 복원; SIGINT/SIGTERM/SIGHUP/SIGQUIT/SIGPIPE 각 처리 후 복원.
- SIGTSTP 요청 시 terminal 복원·중단, SIGCONT 후 재진입·화면 복구·종료.
- REPL Reader가 미리 읽은 작업화면 키/후속 수식을 잃지 않는 경로.

[120×34 실제 화면](../evidence/workbench/workbench-120x34.txt) · [80×24 화면](../evidence/workbench/workbench-80x24.txt) · [PNG 렌더링](workbench-demo.png)

시험 중 오류 수식 뒤 AST 값 패널이 해제된 임시 Value를 참조할 수 있는 문제를 발견했다. 렌더와 키 탐색을 모두 유효한 성공 snapshot으로 제한해 수정하고, divide-by-zero 뒤 탐색·ans·재실행을 회귀 사례로 추가했다. 현재 보고서는 수정 후의 결과다.

신호 정리는 UI의 안전한 경계에서 수행한다. 긴 수식 계산 중 즉시 취소하는 기능은 아니며 SIGKILL, 외부 SIGSTOP, 심각한 크래시에 복구를 보장하지 않는다. 테스트는 실제 WSL/Windows Terminal/원격 SSH 장비 시험을 대신하지 않는다. 이력은 소스만이며 디스크 저장·workspace snapshot 복원은 지원하지 않는다.

## 5. L3 및 동적 작업공간 보존

기본 release/debug는 프로젝트 NASM 오브젝트 **14개**를 GNU ld로 링크했다. PT_INTERP/DT_NEEDED/미해결 심볼 없음, 비실행 스택, 링크 입력과 오브젝트 출처를 검사했다. 정적 libc를 숨겨 넣고 무의존이라고 선언한 방식이 아니다. 개발용 libc-reference/decimal adapter는 별도 시험 대상이다.

release/debug 각각 `/asmlab`, `/script.asmlab`만 있는 별도 루트 파일시스템에서 UID 65534로 인수·stdin·스크립트 3건씩, 총 **6건**을 실제 실행했다. 동적 행렬 생성/계산/삭제의 empty-root 시험도 실행했으며 생략되지 않았다. [L3 통합](../evidence/l3/l3-core.json) · [동적 시험](../evidence/dynamic/dynamic-workspace.json) · [ELF 감사](../evidence/l3/elf-runtime-audit.txt)

quota/운영체제 반환 할당 실패/부분 대입 준비 실패에서 기존 변수와 ans를 유지하는 검사를 보존했다. 메모리 quota는 전체 RSS나 고정 trace/UI 저장소, CPU시간을 제한하는 sandbox가 아니다. empty-root 실행 시험도 공개 서버 보안 인증이 아니다.

## 6. 별도 실패 차단

기존 Native6 + Runtime9 + L39 + Dynamic8 + 신규 Workbench9 = **41건**이다. 새 Workbench guard는 다른 경로로 옮긴 원본의 무결성 검사, terminal/workbench/trace/macro/오브젝트 변조, 잘못된 source build ID, debug 누락, 숨겨진 ncurses 링크 인수를 검사한다.

이는 해시·빌드 출처 검증이 실패하는지 보는 시험이며 각 guard에서 전체 기능 시험을 다시 실행한 것은 아니다. source build ID는 입력 digest/profile/backend이고 ELF SHA256이나 전자서명이 아니다.

## 7. 성능 수치 해석

추가 보고서에는 `sum(sin(linspace(-3,3,8192)))`를 모드별 5회 실행한 시간 표본이 있다. 이 로컬 실행의 중앙값은 Observe 약 **11.37ms**, Compute 약 **3.73ms**였다. 프로세스 시작·파싱·할당·JSON 출력까지 포함한 한 호스트/한 부하의 예시다. 커널만의 벤치마크, 일반적 배속 보장, MATLAB/BLAS와의 비교가 아니다. 시간 값은 테스트 합격 조건으로 사용하지 않았다.

## 8. 재현과 경계

```sh
# 제공 산출물과 input/object hash를 검사한 뒤 전체 suite, NASM 재빌드 없음
make verify

# 직접 NASM 재빌드와 전체 suite
make clean
make -j2 test
make test-guards

# 추가 Workbench gate만 재빌드·실행
make workbench-test
```

Python3.10+와 binutils가 시험 도구이며 비교 실행 파일 때문에 시험 호스트에 glibc가 필요하다. 기본 앱 런타임의 무의존성과 혼동하지 않는다. NASM 출처는 [도구 기록](TOOLCHAIN-PROVENANCE.md)과 동일한 서드파티 2.16.03 prebuild이며 ZIP에 도구를 배포하지 않는다.

파일별 해시는 MANIFEST.sha256으로 확인한다. 패키지 압축 해제 후 검증/재빌드는 별도 전달되는 `ASMlab-v0.5.0-release-check.txt`에 기록한다. 이 보고서의 원본 evidence를 다른 기기에서 재실행해 덮어썼다면 해당 기기의 새 보고서와 분리해 보관한다.

미검증/미구현: 원격 CI, 별도 WSL/Pi/ARM 장비, Windows EXE, 공개 웹 서버, 2D/3D 그래프, Unicode/mouse TUI, 디스크 history/workspace·trace import, 실시간 CPU step, AVX/GPU, 전체 정의역 올바른 반올림·완전한 메모리 안전의 형식 증명.
