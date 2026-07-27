# PHOTO — AI 사진 보정 앱

EPIK · SNOW · SODA · Lightroom을 벤치마크한 Android/iOS AI 사진 보정 앱.

- 📋 **기획서**: [docs/PLANNING.md](docs/PLANNING.md)
- 📱 **아이폰에서 웹으로 바로 테스트** (맥 불필요): [docs/WEB_PREVIEW.md](docs/WEB_PREVIEW.md)
- 🍎 **실기기 iOS 빌드** (맥 필요): [docs/IOS_SETUP.md](docs/IOS_SETUP.md)
- 핵심 기능: AI 지우개, 화질 개선(업스케일링), 얼굴/피부/체형 보정, 감성 필터, 생성형 개체 제거, AI 프로필
- 스택(예정): Flutter + 온디바이스 AI(TFLite/ONNX) + FastAPI 서버(생성형 기능)
- 수익화(예정): 구독 + 크레딧 하이브리드 (RevenueCat)

## 현재 상태

**M3 완료** — 얼굴 인식 보정 + 피부 보정:

- ML Kit 얼굴 검출 (랜드마크 + 윤곽), 여러 얼굴 동시 처리
- 얼굴 워핑: 눈 크기 · 얼굴 슬림 · 코 · 턱 · 입술
- 피부 보정: 주파수 분리 기반 스무딩(피부결 유지) + 피부톤, 눈·입은 선명하게 유지
- 원터치 프리셋: 자연스럽게 / 또렷하게
- M2: 필터 19종 + 강도 슬라이더 + 실시간 썸네일, 색보정 7종(밝기·대비·채도·온도·색조·하이라이트·그림자), GPU 셰이더 실시간 프리뷰
- M1: 사진 불러오기(갤러리/카메라), 자르기(비율 프리셋 + 드래그 핸들), 회전/반전, undo/redo, 길게 눌러 원본 비교, 갤러리 저장/공유

다음 마일스톤: **M4 — AI 지우개 + 화질 개선 (온디바이스 모델)**

### 플랫폼 요구사항

ML Kit 얼굴 검출 때문에 **Android API 21+**, **iOS 15.5+** 가 필요하다
(`android/app/build.gradle.kts`, `ios/Podfile`에 반영됨).

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
- `lib/core/face/` — 얼굴 보정. 검출(ML Kit)은 `face_detection_service.dart`에
  격리돼 있고, 나머지(워핑 수학, guided filter 스무딩)는 전부 순수 Dart라
  단위 테스트가 가능하다. 랜드마크는 정규화 좌표로 저장해 프리뷰와 원본
  해상도에서 그대로 재사용된다.
- 피부 스무딩은 **fast guided filter**(He & Sun): 축소본에서 선형 계수만 구하고
  원본 해상도에서 `q = a·I + b`로 복원하므로 1200만 화소도 수백 KB 작업
  메모리로 처리된다. `I - q`(고주파 = 피부결)를 일부 되살려 뭉개짐을 막는다.
- 워프 감쇠 곡선 `(1 - d²/r²)²`는 반경 경계에서 값과 기울기가 모두 0이라
  경계 자국이 없다. 변위가 반경의 65%를 넘으면 접히므로 워프 생성값이 그
  한계 안에 있는지 테스트로 고정해 두었다.
- 프리뷰는 1280px로 다운스케일. 기하 연산과 얼굴 보정은 isolate에서 굽고,
  색보정/필터는 셰이더로 실시간 렌더링. 저장 시에만 원본 해상도로 전체
  파이프라인 실행.
- 필터는 LUT 텍스처 대신 파라메트릭(기본 보정값 + 채널별 lift/gamma/gain)으로
  정의 — 에셋 없이 GPU/CPU 경로가 같은 파라미터를 공유한다.
- `lib/features/` — 화면 단위 (home, editor).
- `lib/core/platform/`, `lib/core/face/face_detection_service.dart` — 조건부
  import으로 플랫폼별 구현을 고른다. 웹에는 갤러리 저장 API가 없고 ML Kit
  얼굴 검출도 없으므로 각각 브라우저 다운로드와 빈 결과 스텁으로 대체된다.
  덕분에 맥 없이도 웹 미리보기로 앱 대부분을 테스트할 수 있다.

### 알려진 한계

- 얼굴 보정 슬라이더는 CPU(isolate)에서 처리하므로 드래그를 놓았을 때
  프리뷰가 갱신된다. 워핑은 UV 변환이라 색보정처럼 셰이더로 옮기면
  실시간이 되며, 이는 M4 이후 최적화 대상이다.
- 이 저장소의 코드는 실기기 빌드 없이 정적 분석과 단위 테스트로만
  검증됐다. 실제 얼굴 사진에서의 보정 강도는 실기기에서 눈으로 확인하며
  튜닝해야 한다.
