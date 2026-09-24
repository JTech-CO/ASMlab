# ASMlab 로드맵 - v0.5.0 기준

Level은 프로젝트 경계이며 외부 인증이 아니다.

| 버전 | 상태 | 범위 |
|---|---|---|
| v0.1.1 Native Gate | 완료 | NASM 직접 빌드·상수·명령·회귀 |
| v0.2.0 Runtime Foundation | 완료 | 호출 경계·자체 기초 루틴·독립 시험 |
| v0.3.0 L3-Core | 완료 | 전체 앱 libc/CRT 제거·exact decimal·자체 진입점/입출력 |
| v0.4.0 Dynamic Workspace | 완료 | 동적 Value·quota·소유권·원자적 대입·생성자·인덱싱 |
| **v0.5.0 Observable Workbench** | **구현·로컬 검증 완료** | **Observe/Compute 특수화·Trace v2 내보내기·연동 TUI·편집/이력/검색/resize/복구** |
| v0.6.0 Numerical Foundation+ | 미구현 | 수학 함수 정확도·정의역 강화, 안정적인 벡터 연산 |
| v0.7.0 Linear Solve | 미구현 | 피벗 LU·solve·잔차·조건 진단 |
| v0.8.0 Factorization | 미구현 | QR·Cholesky·제한된 최소제곱 |
| v0.9.0 성능·저장 | 미구현 | 추가 커널 최적화·선택 SIMD·workspace/trace import·저장 |
| v1.0.0 L3-Workbench | 미구현 | 통합 배포·지원 환경·장기 검증 |

v0.5.0은 첫 번째 로컬 Workbench 릴리스다. Trace JSON **내보내기**는 구현했으나 디스크 trace 불러오기나 과거 workspace 복원까지 구현한 것은 아니다. Compute는 관찰 비용을 제거한 동일 SSE2 알고리즘이며 AVX/FMA/멀티스레드/새 선형대수는 아직 없다.

[Pi5·ARM64·서버형 웹·2D/3D 그래프 계획](plans/RASPBERRY-PI5-SERVER-PLAN-KR.md)은 문서만 보존한다. 아키텍처·운영 결정을 승인하기 전에 현재 NASM 코어를 다른 ISA/웹 구현으로 대체하지 않는다. [원래 전체 계획](plans/LEVEL3-PLAN-KR.md)은 당시 문서로 유지한다.
