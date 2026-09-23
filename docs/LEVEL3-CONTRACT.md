# ASMlab 런타임 경계 / Level 3 contract

작성: 2026-09-23. **현재 릴리스: v0.1.1, Level 2.**

## 현재 승인 범위

v0.1.1은 NASM 직접 빌드와 검증 기준선 확보만 완료한다. 프로그램 본체는 x86-64 어셈블리이며 libc/CRT는 시작, 입출력, 문자열·메모리, 십진수 변환을 담당한다. 외부 libm/BLAS/LAPACK로 계산을 위임하지 않는다. 빌드용 Python·GCC·NASM·ld와 시험용 Python은 프로그램 실행 의존성과 구분한다.

`make test` 성공은 v0.1.1 Native Gate 성공이지 L3-Core 성공이 아니다. `DT_NEEDED`에 libc가 남는 것은 이번 범위에서는 의도된 상태다.

## L3-Core의 후속 완료 기준

자체 `_start`, 인수 처리, Reader/Writer, 문자열·메모리 루틴, 정확한 숫자 문자열 변환을 갖추고 기존 수학·행렬·추적 계약을 보존한다. Linux kernel·ELF loader·파일시스템은 사용하되 libc·CRT·외부 수학 런타임·숨겨진 정적 libc·외부 Python 계산 프로세스는 사용하지 않는다.

PT_INTERP/DT_NEEDED뿐 아니라 link map과 모든 입력 오브젝트를 감사한다. 정적 libc를 묶고 런타임 무의존이라고 표시하지 않는다. 모든 기존 회귀와 ABI·숫자 변환·실패 처리를 새 산출물에 실행한다.

## 이번에 하지 않은 변경

자체 런타임, rt_* 분리, 동적 Value, 고급 선형대수, ARM64, Windows 네이티브, HTTP/API, 그래프, 웹 UI는 구현하지 않았다. 버전마다 범위와 증거를 따로 남긴다.

## 향후 서버의 경계

Assembly-only는 계산 코어의 구현 조건으로 유지하는 안을 검토한다. 웹 서버·TLS·인증·브라우저 UI를 포함한 서비스 전체를 어셈블리-only라고 주장하지 않는다. ARM64 코어는 NASM 코드의 빌드 옵션 변경이 아니라 별도 ISA 구현이며 도입 결정도 현재 보류다.

[원래 개발 계획](plans/LEVEL3-PLAN-KR.md) · [서버 계획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)
