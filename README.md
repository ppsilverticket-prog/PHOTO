# PHOTO — AI 사진 보정 앱

EPIK · SNOW · SODA · Lightroom을 벤치마크한 Android/iOS AI 사진 보정 앱.

- 📋 **기획서**: [docs/PLANNING.md](docs/PLANNING.md)
- 핵심 기능: AI 지우개, 화질 개선(업스케일링), 얼굴/피부/체형 보정, 감성 필터, 생성형 개체 제거, AI 프로필
- 스택(예정): Flutter + 온디바이스 AI(TFLite/ONNX) + FastAPI 서버(생성형 기능)
- 수익화(예정): 구독 + 크레딧 하이브리드 (RevenueCat)

## 현재 상태

**M2 완료** — 필터 + 색보정 (GPU 셰이더 실시간 프리뷰):

- 필터 19종 (청아/필름/빈티지/세피아/모노/느와르/시네마/틸오렌지/포근/새벽/노을/민트/라벤더/로즈/카페/숲/바다/네온/페이드) + 강도 슬라이더 + 실시간 썸네일
- 색보정 슬라이더 7종: 밝기 · 대비 · 채도 · 온도 · 색조 · 하이라이트 · 그림자
- GPU 프래그먼트 셰이더로 60fps 실시간 프리뷰 (셰이더 로드 실패 시 CPU 폴백)
- M1: 사진 불러오기(갤러리/카메라), 자르기(비율 프리셋 + 드래그 핸들), 회전/반전, undo/redo, 길게 눌러 원본 비교, 갤러리 저장/공유

다음 마일스톤: **M3 — 얼굴 인식 보정 + 피부 보정 (MediaPipe Face Mesh)**

## 개발

```bash
cd app
flutter pub get
flutter run          # 실기기/에뮬레이터 실행
flutter test         # 단위/위젯 테스트
flutter analyze      # 정적 분석
```

### 아키텍처 메모

- `lib/core/` — 편집 상태(`EditSnapshot` + 스냅샷 undo/redo), 기하 연산(`EditOp`),
  색보정(`ColorAdjustments`), 파라메트릭 필터 프리셋, CPU 이미지 파이프라인.
- `shaders/adjustments.frag` — 색보정/필터 GPU 셰이더. **CPU 구현
  (`color_adjustments.dart`)과 수식이 반드시 일치해야 한다** — 프리뷰는 GPU,
  저장은 CPU 경로를 쓰기 때문.
- 프리뷰는 1280px로 다운스케일: 기하 연산은 isolate에서 굽고, 색보정/필터는
  셰이더로 실시간 렌더링. 저장 시에만 원본 해상도로 전체 파이프라인 실행.
- 필터는 LUT 텍스처 대신 파라메트릭(기본 보정값 + 채널별 lift/gamma/gain)으로
  정의 — 에셋 없이 GPU/CPU 경로가 같은 파라미터를 공유한다.
- `lib/features/` — 화면 단위 (home, editor). M3부터 face_retouch 등이 추가된다.
