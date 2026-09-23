# ASMlab 런타임 경계 / Level 3 contract

작성: 2026-09-23. **현재 릴리스: v0.2.0, 전체 앱 Level 2.**

## 현재 승인 범위

전체 수치 앱은 NASM 직접 빌드한다. 기본 release/debug의 메모리·문자열 호출은 자체 NASM 구현이며, 코어에서 libc를 직접 호출하지 않고 `rt_*` 경계를 통한다. libc와 CRT는 여전히 시작, 콘솔·파일 입출력, float64 문자열 변환과 출력에 사용한다. 외부 libm/BLAS/LAPACK로 수학 계산을 위임하지 않는다.

`src/rt/adapters/libc_io.asm`은 명시적인 임시 Level 2 어댑터다. printf 호환 전달 경계도 남아 있다. 개발용 libc primitive 비교 실행 파일은 기본 앱이 아니다.

별도 `asmlab-runtime-smoke`는 자체 `_start`, syscall, 메모리·문자열·정수 변환과 버퍼 입출력을 사용하며 libc/CRT/PT_INTERP/DT_NEEDED가 없다. **이 도구에는 수식 평가기가 없으므로 전체 ASMlab의 L3-Core 완료를 의미하지 않는다.**

## L3-Core의 후속 완료 기준

정확한 binary64 문자열 변환과 typed 출력, Reader/Writer 전체 앱 통합, 자체 시작·종료 경로를 갖추고 기존 수학·행렬·추적 계약을 보존한다. Linux kernel·ELF loader·파일시스템은 사용하되 libc·CRT·외부 수학 런타임·숨겨진 정적 libc·외부 Python 계산 프로세스는 사용하지 않는다.

PT_INTERP/DT_NEEDED뿐 아니라 모든 링크 입력 오브젝트를 감사한다. 정적 libc를 묶고 런타임 무의존이라고 표시하지 않는다. 모든 기존 회귀와 ABI·숫자 변환·실패 처리를 새 산출물에 실행한다. Foundation의 테스트 호스트와 가짜 syscall 공급자를 프로덕션에 포함하지 않는다.

## 도구와 런타임

NASM/ld/cc는 빌드 도구, Python/ctypes/독립 수치 기준은 개발 시험 도구다. 전체 애플리케이션의 자체 코드는 `.asm/.inc`이며 프로젝트 C/C++/Python이 계산을 대행하지 않는다. OS libc의 내부 구현까지 어셈블리-only라고 주장하지 않는다.

## 보류된 확장

동적 Value, 고급 선형대수, ARM64, Windows 네이티브, HTTP/API, 그래프와 웹 UI는 이번 버전에서 구현하지 않았다. 향후 Assembly-only는 계산 코어의 구현 조건으로 유지하는 안을 검토하고, 웹 서버·TLS·인증·브라우저까지 모두 어셈블리-only라고 주장하지 않는다.

[현재 런타임 구현](RUNTIME-FOUNDATION-KR.md) · [원래 개발 계획](plans/LEVEL3-PLAN-KR.md) · [Pi 서버 기획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)
