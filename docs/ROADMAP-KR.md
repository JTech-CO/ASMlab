# ASMlab 로드맵 - v0.4.0 기준

Level 구분은 이 프로젝트의 개발 범위이며 외부 인증이 아니다.

| 단계 | 상태 | 범위 |
|---|---|---|
| v0.1.1 Native Gate | 완료·이전 단계 | NASM 직접 빌드, 상수/명령/회귀 검증 |
| v0.2.0 Runtime Foundation | 완료·이전 단계 | 호출 경계, 자체 기본 루틴, 독립 시험 |
| v0.3.0 L3-Core | 완료·이전 단계 | 정확한 decimal 입출력, 앱 I/O·진입 통합, libc/CRT 제거 |
| **v0.4.0 Dynamic Workspace** | **구현·로컬 검증 완료** | 동적 Value·arena·quota·원자적 대입·생성자·다인수·2D 읽기 인덱싱 |
| v0.5.0 Observable Workbench | 미구현 | trace v2, 관찰/계산 경로, 패널 개선 |
| v0.6.0 Numerical Foundation+ | 미구현 | 함수 정확도·정의역 강화, 안정적 벡터 계산 |
| v0.7.0 Linear Solve | 미구현 | 피벗 LU·solve·잔차·조건 진단 |
| v0.8.0 Factorization | 미구현 | QR·Cholesky·제한된 최소제곱 |
| v0.9.0 성능·저장 | 미구현 | 계산 커널, 선택적 SIMD, workspace·trace 저장 |
| v1.0.0 L3-Workbench | 미구현 | 통합 작업환경과 배포 검증 |

v0.4.0은 기존 libc-free 계산 코어를 유지하면서 실제 동적 저장과 언어 확장을 연결했다. 다음 v0.5.0의 Observe/Compute 분리·trace v2·연동 패널은 아직 구현하지 않았다. 현재 `:trace off`는 성능 전용 커널이 아니다.

라즈베리파이5 16GB의 ARM64 포팅, 서버형 웹사이트, 브라우저 2D/3D 그래프는 [별도 기획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)만 유지한다. 실행 아키텍처 선택과 승인 없이 NASM 코어를 ARM/웹 구현으로 대체하지 않는다. [원래 상세 Level 3 계획](plans/LEVEL3-PLAN-KR.md)은 당시 계획으로 보존한다.
