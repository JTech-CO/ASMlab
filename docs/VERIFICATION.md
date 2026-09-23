# ASMlab v0.4.0 Dynamic Workspace 검증 보고서

**검증일: 2026-09-24(Asia/Seoul). 실제 환경: Linux x86-64 컨테이너.** 기본 release/debug와 별도 개발용 비교·시험 산출물을 구분한다.

## 1. 실제 결과

**전체186,731 assertions 통과, 실패0. 별도 실패 차단32개 통과, 실패0.** 동일 corpus의 여러 프로파일·백엔드 반복, 네이티브 함수 호출별 ABI assertions를 포함한다. 서로 다른 수식186,731개, 전수검사 또는 형식 증명이라는 뜻이 아니다. 재압축 해제·재검사 횟수는 이 합계에 중복해서 더하지 않는다.

| 검사 | 횟수 | 보고서 |
|---|---:|---|
| 기존 회귀 release | 14,410 | [JSON](../evidence/native/release-regression.json) |
| 기존 회귀 debug | 14,410 | [JSON](../evidence/native/debug-regression.json) |
| 상수·실제 SSE2·프로파일 비교 | 1,254 | [JSON](../evidence/native/native-contract.json) |
| libc 비교 빌드 회귀 | 14,410 | [JSON](../evidence/runtime/libc-reference-regression.json) |
| 기초 메모리·정수·입출력·ABI | 26,123 | [JSON](../evidence/runtime/runtime-unit.json) |
| 호출·오브젝트·백엔드 경계 | 722 | [JSON](../evidence/runtime/runtime-boundary.json) |
| 정확 decimal·독립 기준·ABI | 106,439 | [JSON](../evidence/l3/decimal-exact.json) |
| 전체 L3 앱·입출력·무라이브러리 | 71 | [JSON](../evidence/l3/l3-core.json) |
| 동적 allocator·행렬·원자성·수명 | 8,892 | [JSON](../evidence/dynamic/dynamic-workspace.json) |
| **합계** | **186,731** | [summary](../evidence/release-summary.json) |
| 별도 native/runtime/L3/dynamic guards | **6/9/9/8** | [summary](../evidence/guard-summary.json) |

이전16×16 크기 거부 두 건은17-axis 성공 수치 검사로 옮겼고,64번째 변수 저장 성공으로 기대를 변경했다. 변경된 계약을 예전 제한 그대로 검증하지 않는다. 나머지 기본 수치 회귀와 decimal·입출력·추적 검증을 유지했다.

## 2. 새 동적 시험

실제 allocator가 반환한 포인터를 fixture에서 호출하고 독립 Python 모델과 byte-level 비교한다. size0·64비트 overflow·잘못된 quota·실사용보다 작은 quota·정확한 한도 도달·정렬·초기0·전체 payload 센티널·해제 accounting을 확인한다. 실제 매핑을 성공시키거나 거부하며 단순 mock 결과로 통과시키지 않는다. ABI probe는 callee-saved registers·DF·MXCSR 보존도 확인한다.

세 앱에서 동적 shape·생성자·비균일17×19 리터럴·전치·직사각 곱·상한1,048,576개 원소·다인수·인덱스·문법/정의역 거부를 시험했다. scalar/dense 복사·self assignment·원본 변경 후 복사본·중간 인덱스 읽기를 확인했다. 320개 사용자 변수와 중간/끝/시작 항목 삭제가 동작한다. 각 앱에서180회 반복 생성·재대입·삭제·clear 후 used/live=0과 map=unmap이 유지됐다.

각 앱의450개 새 함수/괄호/인수 조합 fuzzy input은1MiB quota에서 실행하고, 성공·오류 여부와 무관하게 매번 clear 후 회수 지표를 검사했다. 이는 모든 비정상 입력의 안전성 증명은 아니다.

### 늦은 commit 실패

`--memory-mib 1`, A=25,000원소와 ans=99를 둔 다음 A 또는 신규 B=40,000원소를 평가했다. 임시 결과와 target 복사까지 실제 성공하고 ans 복사에서 실패하도록 quota를 구성했다.

- 기존 A·ans가 각각 원래 값과99로 보존됐다.
- 실패한 신규 B는 변수 목록에 등록되지 않았다.
- 실패 후 persistent 동적 사용량208,896바이트와 live3이 유지됐다. 이전 성공 수식 arena는 새 수식 시작 시 회수되므로 실패 직전 used와 같아야 한다고 가정하지 않는다.
- clear 후 used/live=0, 누적map=unmap이었다.

OS 레벨 실패는 별도 프로세스 RLIMIT_AS=8MiB 아래에서, 기본64MiB 앱 quota에는 맞는 큰 결과를 mmap하도록 해 유도했다. 이 역시 기존 A와 ans를 보존했다. 호스트 OOM killer나 시스템 종료까지 복구한다는 뜻은 아니다.

## 3. 실제 캡처와 수명

`math.asm`은0.3.0과 동일하며 `exec_sse` dispatch/capture prefix도 동일하다. 전체 `kernels.asm`은 descriptor payload 접근과 work preflight를 위해 바뀌었으므로 전체 동일성을 주장하지 않는다. [소스 비교](../evidence/baseline-v0.3.0/source-comparison.json)

기존12종 SSE2 실제 명령 주소·opcode·XMM/MXCSR 검증을 유지했다. linspace endpoint/interior와 indexing의 실제 copy도 검사한다. constructors의 integer fill·shape 변환·메모리 관리까지 CPU 전 명령을 추적한다고 설명하지 않는다.

PTY에서 `A(17,19)+2` 평가 후 A를 drop하고 재생 n/p/q를 수행했다. temp 값이 persistent A와 독립이므로 재생이 유지됐다. clear 또는 새 실패 수식 후에는 재생을 거부한다. 큐에 들어온 입력이 공유 Reader를 통해 순서대로 처리되는지도 확인했다. trace cap을 넘기는 새 그래프용 표본 배열 계산은 누락 사실을 표시했다. 그래프 자체는 미구현이다.

## 4. L3 의존성 경계와 빈 루트 실행

release/debug는13개 프로젝트 NASM 오브젝트를 직접 ld로 정적 링크한다. 동적 로더·DT_NEEDED·미해결 import·CRT·외부 archive·libc·수학 라이브러리·Python runtime이 기본 앱에 없다. NX stack, RWX LOAD 부재, 실제 `/proc` file-backed mapping, 정확한 링크 입력도 검사한다. 정적 libc를 포함하고 동적 의존성만 없다고 주장하는 방식이 아니다.

기존 L36건 외에 추가4건을 실행했다. 빈 루트에는 `/asmlab`과 스크립트만 두고 chroot 후 GID/UID65534로 낮췄다. release/debug 각각32×33 생성·복사·재대입·인덱스·삭제·clear를 파일과stdin 방식으로 실행했다. 동적 로더·사용자 라이브러리·셸은 없으며 이번 로컬 시험에서 이 항목을 생략하지 않았다.

이것은 실행 의존성 시험이지 공개 서버 보안 sandbox 인증이 아니다. Linux 커널, 상속된 표준 fd, 커널 매핑은 사용한다. 일반 개발 환경에서 chroot 권한이 없으면 해당 시험은 skipped로 기록한다.

## 5. 범위와 재현

```sh
make clean
make -j2 test
make test-guards
# 또는 동봉 바이너리·오브젝트 검증, 재빌드 없음
make verify
```

`make test-guards`는 프로파일·런타임·L3·dynamic relocation 및 변조 검사를 실행한다. NASM 미존재, 소스/object/fixture/linkmap 변조, 누락 inventory, 비교 경계 침범을 실행 전에 거부한다. 해시는 무결성 검증이며 디지털 서명은 아니다.

구현된 메모리 한도는 전체 RSS·CPU 시간·스택·고정 BSS 또는 OS OOM 정책을 통제하지 않는다. 할당이 실패로 반환되는 경우의 트랜잭션을 검증했지 임의 포인터·중복 free·스레드 경합·host OOM-killer를 안전하게 복구하는 ABI가 아니다.

원격 GitHub Actions는 갱신만 했고 실행하지 않았다. WSL·Windows 네이티브·ARM/Pi 하드웨어·웹 공개 서비스는 미검증/미구현이다. 수학 함수의 전체 정의역 correctly-rounded 증명, LLVM/GCC보다 빠르다는 성능 주장, 메모리 안전 형식 증명도 하지 않는다.

[도구 출처](TOOLCHAIN-PROVENANCE.md) · [동적 ABI와 수명](DYNAMIC-WORKSPACE-KR.md) · [빌드/시험 로그](../evidence/build-test.log) · [환경](../evidence/native/environment.txt)
