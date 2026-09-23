# ASMlab 0.1.1 검증 보고서

검증일: 2026-09-23. 범위: **Linux x86-64 컨테이너에서 NASM으로 직접 빌드한 release/debug**. 이번 검증의 실행 시각은 `2026-09-23T02:18:59.713288+00:00`이다.

## 1. 결론

**v0.1.1 Native Gate를 통과했다.** 기존 회귀검사를 두 프로파일에 각각 실행하고, 네이티브 상수·명령·추적·프로파일 일치 검사를 추가했다. 릴리스·디버그 모두 NASM의 ELF64 출력으로 직접 만들었으며 GAS 변환 결과를 네이티브 성공으로 대신하지 않았다.

**Level 3 런타임 완료는 아니다.** libc와 CRT는 현재 설계대로 유지한다. 서버형 웹사이트, ARM64, Raspberry Pi, Windows 네이티브, 2D/3D plot은 구현하지 않았다. [범위 계약](LEVEL3-CONTRACT.md)

## 2. 실제 빌드 환경과 출처

| 항목 | 실제 기록 |
|---|---|
| OS | Debian GNU/Linux 13, Linux 6.18.44, x86_64 컨테이너 |
| NASM | 2.16.03, compiled on Sep 18 2026 |
| GCC / cc | Debian 14.2.0-19, 14.2.0 |
| GNU binutils / ld | 2.44 |
| glibc | 2.41 |
| Python | 3.13.5, 개발·테스트 전용 |
| release | NASM `-Ox`, symtab 보존, DWARF 없음 |
| debug | NASM `-O0 -g -F dwarf`, symtab/DWARF 보존 |
| 링크 | non-PIE, NX stack, RELRO, NOW, build ID |

이번 NASM은 공개 `holepunchto/nasm-runtime` CI artifact에서 확보한 **서드파티 사전 빌드 도구**다. 공식 NASM 소스를 이 환경에서 직접 빌드한 것이 아니다. NASM 바이너리와 artifact의 SHA256, commit/run 식별자를 [도구 출처](TOOLCHAIN-PROVENANCE.md)에 명시했다. 도구 자체는 배포하지 않는다.

빌드 스크립트는 NASM 명령을 직접 호출하고 GCC를 링크 드라이버로만 사용한다. 프로젝트 C 코드를 생성하거나 컴파일하지 않는다. 기본 NASM 경고는 오류이며 의도된 cross-section 재배치 등 모든 선택 경고를 켠다는 의미는 아니다.

실제 명령과 source/object/map/binary hash는 [release sidecar](../bin/asmlab.build.json), [debug sidecar](../bin/asmlab-debug.build.json)에 있다. [환경 원문](../evidence/native/environment.txt) · [빌드·전체 검사 로그](../evidence/native/build-and-test.log)

| 실행 파일 | SHA256 |
|---|---|
| `bin/asmlab` | `0e13e7ed198b3549cc33773d13ffe396a398bf4e46555f212505b6c5aa1b9ea9` |
| `bin/asmlab-debug` | `9323899e0ae69cb6b0b43935e87f4419db956c003bcb4ada6afa5028868de93f` |

## 3. 검사 결과와 수의 의미

| 검사 | 실행 수 | 실패 |
|---|---:|---:|
| 기존 regression corpus / release | 14,410 | 0 |
| 기존 regression corpus / debug | 14,410 | 0 |
| native contract / 두 프로파일과 비교 | 1,254 | 0 |
| **Native Gate 합계** | **30,074** | **0** |
| gate guard / 별도 검사 | 6 | 0 |
| ELF audit / 별도 pass-fail | 두 프로파일 통과 | 0 |

이 수는 **검사 실행·assertion 횟수**다. 두 프로파일에서 같은 corpus를 반복하므로 독립된 수식 30,074개라는 뜻이 아니다. 한 행렬 검사가 여러 셀을 검사할 수 있으며 일부 검사는 숫자가 아닌 오류·버퍼·재생·메타데이터를 검사한다. ELF audit 및 guard 6개를 30,074에 다시 합쳐 고유 수치 시험처럼 표기하지 않는다.

[gate-summary.json](../evidence/native/gate-summary.json) · [release 회귀](../evidence/native/release-regression.json) · [debug 회귀](../evidence/native/debug-regression.json) · [native contract](../evidence/native/native-contract.json) · [guard 결과](../evidence/native/gate-guards.json)

### 기존 14,410개 corpus

`tests/verify.py`는 v0.1.0과 바이트 단위로 동일하다. 기본 함수 비교 10,030건, 스칼라·행렬 연산, 오류 입력 2,500건 퍼징, 변수 복사/롤백, 입력 길이, 음의 0, 용량, 실제 XMM 비트·주소, PTY 다음/이전/종료, 파일/CLI 시험을 그대로 실행했다.

[기준본 비교](../evidence/native/baseline-comparison.json)와 [프로그램 소스 차이](../evidence/native/runtime-source.diff)를 확인할 수 있다. 이번 애플리케이션 `.asm/.inc` 변경은 표시 버전 문자열뿐이며 알고리즘·자료구조·문법은 변경하지 않았다.

### 추가 1,254개 native contract

고정 fixture의 **19개 상수 심볼, 50개의 64비트 값**을 두 바이너리에서 직접 읽어 대조했다. fixture는 검사 중 새로 생성하지 않는다. 주요 상수, 범위 축소 상수, 부호/절댓값 마스크, 다항식 계수의 NASM 인코딩을 확인한다.

12종 관찰 명령의 실제 opcode 바이트와 `objdump` 결과를 대조했다: `addsd/subsd/mulsd/divsd/sqrtsd`, `addpd/subpd/mulpd/divpd/sqrtpd`, `movapd`, `xorpd`.

프로파일별 16개 수식에서 86개 캡처 프레임을 확인했다. 실제 명령 주소, XMM 입력·출력 raw bits, scalar 비활성 상위 lane 보존, MXCSR 제어 필드와 precision 상태·다음 수식 초기화를 검사했다. scalar/packed/tail, 음의 0, 전치, 행렬 곱과 기본 함수 경로를 포함한다. 이것은 전체 CPU instruction stream 검사가 아니다.

두 프로파일의 **520개 결과 레코드**와 주소를 제외한 캡처 기록이 일치했다. NASM 인코딩 선택 때문에 release/debug의 명령 주소나 기계어 전체 파일이 동일하다고 요구하지 않는다. float 계산 알고리즘은 두 프로파일에서 동일하다.

### 별도 gate guard 6개

공백을 포함하는 다른 디렉터리로 복사해 재검증했다. 변조한 binary, GAS bridge라고 기록한 sidecar, 빌드 후 바뀐 소스, 누락된 debug metadata가 통과하지 않는지 확인했다. NASM 경로를 의도적으로 없애고 빌드하면 실패하며 오래된 release binary와 sidecar도 제거되는지 검사했다.

모든 변조는 임시 사본에서 수행한다. 이 검사는 실수·오래된 산출물 방지이며, 공격자가 테스트·해시·메타데이터까지 바꿀 수 있는 상황을 방어하는 서명/신뢰 체계가 아니다.

## 4. 수치 차이

아래 값은 두 네이티브 프로파일에서 재현된 기존 시험 결과다. 기준은 테스트 호스트의 Python `math`이며 MPFR 참값 시험은 아니다.

| 함수 | 프로파일당 비교 수 | 관측 최대 절대 차이 | 통과 기준 |
|---|---:|---:|---|
| sin | 3,009 | 1.1102230246251565e-16 | 절대 차이 3e-14 이하 |
| cos | 3,009 | 1.1102230246251565e-16 | 절대 차이 3e-14 이하 |
| log | 3,008 | 1.1368683772161603e-13 | 절대 차이 3e-13 이하 |
| sqrt | 1,004 | 표본에서는 0 | 상대 차이 1e-15 이하, 0 정확 비교 |

이는 함수의 모든 입력·반올림 경계에 대한 정확성 증명이 아니다. 상수 fixture 검사는 인코딩 검증이지 다항식 오차 증명도 아니다. 수치 정의역·연산 순서·실패 규칙은 [NUMERICS](NUMERICS.md)에 유지했다.

## 5. 의존성과 ELF 감사

두 바이너리의 `DT_NEEDED`는 `libc.so.6` 하나다. 수학 함수의 외부 libm·BLAS·LAPACK 위임은 없다. CRT 시작 심볼, libc import, `stdin` COPY relocation은 허용된 현재 Level 2 의존성으로 명시한다. `nm -u`만으로 객체 의존성을 놓치지 않도록 dynamic symbols와 relocation도 확인한다.

NX stack, RWX LOAD 부재, GNU_RELRO, NOW를 확인했다. 이 설정만으로 공개 서버용 sandbox가 완성된 것은 아니다. non-PIE는 실제 주소와 역어셈블을 쉽게 연결하기 위한 현재 선택이며 ASLR 강화라고 주장하지 않는다.

[release audit](../evidence/native/release-audit.log) · [debug audit](../evidence/native/debug-audit.log) · [release link map](../evidence/native/release-link.map) · [debug link map](../evidence/native/debug-link.map)

## 6. 실제 화면·명령 기록

[벡터 sqrt와 덧셈 캡처](../evidence/native/sqrt-vector-trace.txt)는 `sqrtpd` 두 번과 `addpd` 두 번의 실제 native 출력을 보존한다. [walkthrough](../evidence/native/walkthrough.txt), [release disassembly](../evidence/native/release-disassembly.txt), [debug disassembly](../evidence/native/debug-disassembly.txt)도 포함했다.

재생은 계산이 끝난 뒤 기록을 탐색한다. 라이브 step/JIT가 아니며 `:trace off`가 fast compute backend를 구현한 것은 아니다. 스칼라 상위 lane도 raw state로 보여주지만 유효 계산 lane 수와 구분한다.

## 7. 재현 명령

```sh
# 동봉 binary/sidecar/소스를 검사: NASM 재빌드 없음
make verify

# NASM 직접 재빌드 후 전체 검증
make clean
make -j2 test
python3 tests/gate_guards.py --report build/gate-guards.json
```

Python 3.10 이상과 binutils가 시험에 필요하다. 네이티브 빌드에는 NASM, GCC, make가 추가로 필요하다. 배포 실행 파일은 glibc 2.34 이상의 x86-64 Linux를 대상으로 한다. GNU build ID와 sidecar checksum은 추적을 돕지만 다른 툴체인/OS에서 바이너리가 byte-identical해야 한다는 보증은 아니다.

`make clean`은 `build/`와 새 바이너리를 지우지만 `evidence/native/`의 제공 기록은 보존한다. 재검증 결과는 `build/evidence` 또는 `build/verify-existing`에 생긴다. 과거 기록을 새 환경의 성공으로 읽지 않는다.

## 8. 미검증·미구현

원격 GitHub Actions 실행은 하지 않았다. Ubuntu 22.04/24.04 matrix는 구성만 했고 로컬에서 YAML 구조만 확인했다. 이번에 받은 NASM artifact가 다른 프로젝트의 원격 CI에서 생성된 사실은 **ASMlab의 원격 CI 통과**가 아니다.

별도 WSL2/Windows/ARM/Pi 장비, 웹 API와 네트워크, 공개 다중 사용자 보안, MPFR 전 범위 시험, 장시간 성능·열 측정, 고급 선형대수, 2D/3D 그래프, 실시간 디버거, Level 3 자체 런타임은 이번 검증 범위가 아니다.

`docs/plans/`의 Pi/웹/ARM/그래프 설명은 미래 설계다. 현재 동작과 혼용하지 않는다. [서버 계획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)
