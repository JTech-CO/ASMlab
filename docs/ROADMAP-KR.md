# ASMlab 개발 상태와 다음 단계

상태 기준: v0.1.1 / 2026-09-23. 버전 표는 순서 제안이며 일정 약속이 아니다.

| 단계 | 상태 | 범위 |
|---|---|---|
| v0.1.0 | 과거 MVP | GAS 변환 빌드의 14,410개 검사 |
| **v0.1.1 Native Gate** | **로컬 검증 완료** | NASM release/debug, 기존 corpus, 상수·명령·레지스터, provenance, 실패 차단 |
| v0.2.0 Runtime Foundation | 미구현 | rt_* 경계, 자체 primitive, syscall/decimal 독립 시험 |
| v0.3.0 L3-Core | 미구현 | libc·CRT 제거와 기존 기능 보존 |
| 동적 배열·관찰 확장 | 미구현 | Value 수명·OOM, trace v2, 계산/관찰 경로 분리 |
| 함수·선형대수 | 미구현 | 수치 오차 계약, LU/solve, QR/Cholesky |
| 서버·Pi 5·ARM64·2D/3D | **기획만 작성** | 플랫폼 결정, API·브라우저·그래프·보안 설계 |

다음 코드 변경은 v0.2.0의 런타임 API 격리다. 먼저 기존 libc backend로 동작을 유지하고, 자체 구현을 독립 시험으로 추가한다. 이번 v0.1.1에 대형 리팩터링을 섞지 않았다.

## 서버·플랫폼 개발 착수 조건

현재 x86 네이티브 회귀와 데이터·추적 계약을 유지한 상태에서 별도 승인한다. Pi 단독 네이티브 운영이면 ARM64 전체 코어 포팅이 필요하다. x86 NASM-only를 유지하면 계산 서버를 x86 장비에 두는 안을 선택한다. QEMU는 별도 호환성 실험이며 실제 Pi SIMD를 관찰하는 모드와 구분한다.

웹 그래프는 고급 선형대수 완료의 필수 후속이 아니다. 동적 표본 데이터·API·trace snapshot 계약이 준비되면 별도 작업선으로 개발할 수 있다. v0.1.1에서는 네트워크 리스너, 공개 서비스, 브라우저 코드, Pi 배포를 추가하지 않는다.

## 문서

[Level 3 원안](plans/LEVEL3-PLAN-KR.md) · [코어 경계](LEVEL3-CONTRACT.md) · [Pi 서버 계획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md) · [이번 검증](VERIFICATION.md)
