# ASMlab v0.5.0 런타임 통합

v0.2.0의 자체 기본 루틴과 독립 smoke를 **전체 수치 계산 앱으로 통합**했다. 과거 v0.2.0 설명은 [보관 문서](history/v0.2.0/RUNTIME-FOUNDATION-KR.md)에 있다.

```text
자체 _start
  → Reader/Writer 초기화
  → 기존 main / Lexer / Parser / AST / Evaluator
      ├─ 자체 memory/string
      ├─ 정확한 decimal↔binary64
      ├─ 기존 math / SSE2 kernel / 실제 캡처
      └─ 기존 terminal view → 자체 제한형 formatter → Writer
  → temp와 workspace 해제 / 스크립트 정리 / 최종 flush 검사
  → exit_group
```

기본 앱은 별도 NASM 오브젝트 13개를 GNU ld로 직접 연결한다. C를 어셈블리로 변환한 코드, 정적 libc, CRT, 수학 라이브러리를 포함하지 않았다. Linux 커널·파일시스템·터미널 의존성은 허용한다. AST/trace 등 고정 BSS는 유지하고 Value·심볼은 자체 mmap allocator로 동적화했다. [Dynamic Workspace](DYNAMIC-WORKSPACE-KR.md)에 quota·소유권·원자적 대입을 명시했다.

자체 decimal 입력은 정수 유리수를 이용해 반올림한다. 출력은 binary64를 정확한 십진수 정수 계수로 변환한 뒤 표시 자릿수에서 반올림한다. 단순 float64 ×10 누적이나 `strtod` 우회 호출이 아니다. 가장 짧고 빠른 변환 구현이라는 주장도 하지 않는다.

기존 수학 함수와 실제 SSE2 dispatch/capture 부분을 유지했다. 행렬 payload 접근과 크기 검사는 동적 descriptor에 맞춰 수정했다. 코어에서는 출력 함수 이름을 `rt_console_format`으로 명확히 하고, 평가 직전 FP 상태 초기화·스크립트 close 실패 처리를 추가했다. 새 포매터가 지원하는 것은 기존 화면이 사용하는 정해진 형식 부분집합이며 전체 printf 호환 기능은 아니다.

입력과 재생은 같은 stdin Reader를 공유한다. 출력은 마지막 flush 결과까지 확인하며 반환된 I/O 오류는 종료 코드2로 처리한다. 기본 SIGPIPE/SIGINT 신호 종료는 그대로 유지한다. 부분 쓰기/EINTR 처리와 기본 루틴 검사는 v0.2.0의 독립 시험을 계속 실행한다.

**개발용 libc 비교 실행 파일/fixture는 남아 있지만 기본 앱에는 연결하지 않는다.** 사용자 배포 시 계산 실행만 필요하면 `bin/asmlab` 한 파일이면 된다. 소스 재빌드·검증 패키지에는 `.o`·링크 맵·테스트도 포함한다.

[ABI](RUNTIME-ABI.md) · [decimal 알고리즘](DECIMAL-CONVERSION.md) · [전체 검증](VERIFICATION.md)

## v0.5.0 터미널 경계

`src/platform/linux/terminal.asm`가 kernel termios·signal·poll·winsize를 소유하며 코어는 `rt_terminal_*` API만 호출한다. 원래 Reader에 이미 읽힌 바이트를 먼저 소비한다. native는14개 오브젝트, libc 비교 빌드는 native TUI를 지원하지 않는다. 기존 기본 루틴·exact decimal·동적 allocator는 유지한다. [상세 ABI](RUNTIME-ABI.md).
