# ASMlab 0.3.0 - L3-Core

**수식 → AST → 실제 어셈블리 명령 → SIMD 레지스터 → 결과**를 관찰하는 NASM x86-64 수치 계산 환경이다.

[English](README.md) · [변경 이력](CHANGELOG.md) · [검증](docs/VERIFICATION.md) · [로드맵](docs/ROADMAP-KR.md)

## v0.3.0에서 달라진 점

기본 release/debug 실행 파일 전체가 자체 `_start`, float64 문자열 변환, Reader/Writer, 터미널 포매터를 사용한다. **libc·CRT·libm·BLAS·LAPACK 없이 실행**하며, 동적 로더와 `DT_NEEDED`도 없다. 수식 평가기가 없는 독립 smoke만을 L3로 부르는 것이 아니라, 파서·평가기·행렬·추적·재생까지 포함한 앱 전체를 전환했다.

| 영역 | 상태 |
|---|---|
| float64 입력 | 최대 127바이트 숫자 토큰, 정수 유리수 기반 nearest-even 변환 |
| float64 출력 | 자체 1~17 유효숫자 포매터. JSON/quiet는 왕복 가능한 17자리 |
| 파일·콘솔 | Linux syscall과 자체 Reader/Writer. REPL·재생이 같은 입력 버퍼 사용 |
| 시작·종료 | 자체 `_start`, 최종 flush 확인, 쓰기/flush 실패 시 종료 코드 2 |
| 수치 계산 | 기존 `math.asm`·`kernels.asm` 유지. 평가 직전에 MXCSR 초기화 |
| 화면 | 기존 터미널 AST·실제 명령 주소·XMM 원시 비트·재생 유지 |

**Linux x86-64용 정적 ELF**다. 동봉 앱에 glibc 버전 요구가 더는 없다. Linux 커널·터미널·파일시스템은 사용한다. ARM/Pi, Windows 네이티브 `.exe`, 웹 서버, 그래프 기능을 추가한 버전은 아니다. Windows x64의 WSL2 Linux는 실행 대상이지만 이번에 별도 WSL 장비를 시험하지 않았다.

## 바로 실행

```sh
chmod +x bin/asmlab bin/asmlab-debug
./bin/asmlab
./bin/asmlab --bits -e 'sqrt([1,4,9,16]) + 2'
./bin/asmlab --json -e '[1,2;3,4] * [5,6;7,8]'
./bin/asmlab -f examples/walkthrough.asmlab
```

마지막 행렬 곱의 JSON은 `{"ok":true,"rows":2,"cols":2,"data":[19,22,43,50]}`이다. NASM·Python은 제공 실행 파일의 런타임에 필요하지 않는다. 기본 SIGPIPE·SIGINT 동작은 유지하므로 신호에 의한 종료까지 종료 코드 2로 바꾸지는 않는다.

## 빌드·시험

```sh
sudo apt-get update
sudo apt-get install -y nasm gcc make binutils python3
make clean
make -j2 test
make test-guards
```

| 명령 | 내용 |
|---|---|
| `make` / `make debug` | NASM + **ld**로 앱 빌드, Python으로 출처 기록 |
| `make test` | release/debug, 개발용 비교 백엔드·fixture를 빌드하고 전체 검사 |
| `make verify` | 동봉 산출물·입력/오브젝트 해시 확인 후 전체 검사. 재빌드 없음 |
| `make audit` | ELF·링크·호출 경계 감사 |
| `make l3-test` | 정확한 decimal 변환과 L3 통합 검사 |
| `sudo make empty-root-test` | 권한이 필요한 무라이브러리 격리 실행 검사 |

`make verify`에는 Python 3.10 이상과 binutils가 필요하다. NASM/GCC는 재빌드하지 않는다. 일반 `make test`에서 chroot 권한이 없으면 해당 검사만 **skipped로 명시**한다. 제공된 릴리스에서는 두 바이너리를 라이브러리 없는 루트에서 UID 65534로 각각 3건씩 실행했다. 이는 서버 보안 격리 인증이 아니다.

**개발용 `bin/asmlab-libc-reference`와 `decimal-adapter.so`는 의도적으로 libc에 링크**한다. 기본 앱의 의존성과 혼동하지 않는다. 전체 시험에 필요한 GCC·Python·ctypes·Decimal/Fraction은 개발 도구일 뿐이다. 동봉 비교 실행 파일은 glibc 2.34 이상을 요구하므로 전체 시험 호스트에는 libc가 필요하다. 기본 계산 앱의 무의존 실행과는 별개다. 빌드 실패 시 오래된 앱을 성공 산출물처럼 재사용하지 않으며, GAS 자동 대체도 없다.

## 계산과 실제 실행 관찰

```text
x = 3
x^2 + 4^2
A = [1,2;3,4]
A * A
A .* A
A'
sin(pi / 4)
log(e)
:bits on
sqrt([1,4,9,16]) + 2
:replay
```

재생은 **계산 완료 후 실제 캡처 기록 탐색**이다. `n`+Enter는 다음, `p`+Enter는 이전, `q`+Enter는 종료다. 실시간 디버거나 JIT가 아니며 선택한 SSE2 명령만 기록한다. `:trace off`는 캡처·디스패치 비용을 모두 없애는 성능 모드가 아니다.

## 현재 제한

행렬 16×16, 사용자 변수 63개, AST 512개 노드, 재귀 깊이 64, 입력 한 줄 4,095바이트, 수식당 trace 8,192프레임을 유지한다. `sin/cos`는 `|x| <= 1,000,000`, `sqrt`는 비음수, `log`는 양수, `^`는 -1024~1024의 정수 지수다. 부분정규수와 부호 있는 0은 허용하며 NaN·무한대 결과는 오류다. `sum(A)`는 전체 원소 합이고 행렬 열 구분에는 쉼표가 필요하다.

함수 추가·동적 행렬·선형대수·공개 서버는 후속 단계다. 단일 사용자 로컬 연구·교육 프로그램이며 임의 네트워크 입력을 받는 서비스로 검증하지 않았다.

## 검증 자료

[전체 결과](evidence/release-summary.json) · [정확 decimal 시험](evidence/l3/decimal-exact.json) · [L3 통합·격리 실행](evidence/l3/l3-core.json) · [실제 캡처 예제](evidence/l3/sqrt-vector-trace.txt)

검사 횟수는 프로파일·백엔드 반복과 ABI assertion을 포함한다. 전 입력에 대한 형식 증명이나 함수 전 범위 correct-rounding 인증이 아니다. 실제 검증은 Linux x86-64 컨테이너에서 수행했다. Ubuntu 22.04/24.04 CI는 구성했지만 원격 실행하지 않았다.

[ABI](docs/RUNTIME-ABI.md) · [decimal 알고리즘](docs/DECIMAL-CONVERSION.md) · [L3 경계](docs/LEVEL3-CONTRACT.md) · [수치 계약](docs/NUMERICS.md) · [도구 출처](docs/TOOLCHAIN-PROVENANCE.md)

[Pi 5·ARM64·웹·그래프 계획](docs/plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 문서만 보존했다. `MANIFEST.sha256`은 압축 해제 직후 `sha256sum -c MANIFEST.sha256`으로 확인한다. 해시는 무결성 기록이며 전자서명이나 보안 인증이 아니다.
