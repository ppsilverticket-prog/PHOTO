# PHOTO — AI 사진 보정 앱

EPIK · SNOW · SODA · Lightroom을 벤치마크한 Android/iOS AI 사진 보정 앱.

- 📋 **기획서**: [docs/PLANNING.md](docs/PLANNING.md)
- 핵심 기능: AI 지우개, 화질 개선(업스케일링), 얼굴/피부/체형 보정, 감성 필터, 생성형 개체 제거, AI 프로필
- 스택(예정): Flutter + 온디바이스 AI(TFLite/ONNX) + FastAPI 서버(생성형 기능)
- 수익화(예정): 구독 + 크레딧 하이브리드 (RevenueCat)

## 현재 상태

**M1 완료** — Flutter 앱 스캐폴딩 + 편집기 기본 셸:

- 사진 불러오기 (갤러리 / 카메라)
- 자르기 (자유 · 1:1 · 4:5 · 3:4 · 16:9 비율, 드래그 핸들 + 3분할 격자)
- 회전 (좌/우 90°) · 좌우/상하 반전
- 실행취소 / 다시실행
- 길게 눌러 원본 비교 (before/after)
- 갤러리 저장 · 공유 (원본 해상도 JPEG)

다음 마일스톤: **M2 — LUT 필터 + 색보정 슬라이더 (GPU 셰이더)**

## 개발

```bash
cd app
flutter pub get
flutter run          # 실기기/에뮬레이터 실행
flutter test         # 단위/위젯 테스트
flutter analyze      # 정적 분석
```

### 아키텍처 메모

- `lib/core/` — 편집 연산(`EditOp`), undo/redo 히스토리, 이미지 파이프라인.
  프리뷰는 1280px로 다운스케일해 백그라운드 isolate에서 처리하고,
  저장 시에만 원본 해상도로 전체 파이프라인을 실행한다.
- `lib/features/` — 화면 단위 (home, editor). M2부터 filters, face_retouch 등이 추가된다.
