# 아이폰에서 실행하기

실기기 테스트 절차. iOS 앱 빌드는 **맥에서만** 가능하다.

## 준비물

| 항목 | 요구사항 |
|---|---|
| 맥 | Xcode 최신 버전 (App Store) |
| 아이폰 | **iOS 15.5 이상** (ML Kit 얼굴 검출 요구사항) |
| Apple ID | 무료 계정으로 충분 (아래 "무료 계정의 제약" 참고) |
| Flutter | 3.44 이상 |

## 1. Flutter 설치

```bash
# Homebrew가 없다면 먼저 설치: https://brew.sh
brew install --cask flutter
flutter doctor
```

`flutter doctor`에서 Xcode 항목에 체크가 뜰 때까지 안내대로 따라간다.
보통 아래 두 줄이 추가로 필요하다.

```bash
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

## 2. 코드 받기

```bash
git clone https://github.com/ppsilverticket-prog/photo.git
cd photo
git checkout claude/ai-photo-editing-app-v94b4f
```

## 3. 의존성 설치

```bash
cd app
flutter pub get
cd ios && pod install && cd ..
```

`pod install`이 CocoaPods 없다고 하면: `brew install cocoapods`
(맥 기본 루비의 `sudo gem install`은 애플 실리콘에서 자주 실패한다.)

첫 `pod install`은 ML Kit 얼굴 검출 프레임워크를 받느라 몇 분 걸린다.

## 4. 서명 설정 (첫 실행에서 가장 많이 막히는 단계)

Xcode로 **워크스페이스**를 연다. `.xcodeproj`가 아니라 `.xcworkspace`여야 한다.

```bash
open ios/Runner.xcworkspace
```

왼쪽 네비게이터에서 **Runner** 프로젝트 → **TARGETS의 Runner** →
**Signing & Capabilities** 탭에서:

1. **Automatically manage signing** 체크
2. **Team** — Apple ID 계정 선택
   (목록이 비어 있으면 Xcode → Settings → Accounts에서 Apple ID를 먼저 추가)
3. **Bundle Identifier** — `com.photoapp.photoApp`를 **본인만의 값으로 바꾼다.**
   예: `com.본인이름.photo`

> Bundle ID를 바꾸는 이유: 애플은 번들 ID를 전 세계에서 고유하게 관리한다.
> 기본값은 누군가 이미 등록했을 가능성이 높고, 그러면
> `Failed to register bundle identifier` 오류로 서명이 실패한다.

## 5. 실행

아이폰을 케이블로 연결하고, 폰에 뜨는 **"이 컴퓨터를 신뢰하시겠습니까?"**에
신뢰를 누른다.

```bash
flutter devices        # 아이폰이 목록에 보이는지 확인
flutter run --release  # 실사용 속도로 테스트 (지우개·화질 개선이 몇 배 빠름)
```

> 개발 중 수정-새로고침이 필요하면 `flutter run`(디버그)을 쓰되,
> 디버그 모드는 Dart가 JIT로 돌아 이미지 처리 속도가 실제보다 훨씬
> 느리다. **성능 평가는 반드시 `--release`로** 한다.

### 첫 실행 시 "신뢰되지 않은 개발자" 알림이 뜬다면

아이폰에서: **설정 → 일반 → VPN 및 기기 관리 → 개발자 앱** →
본인 Apple ID를 선택하고 **신뢰**를 누른 뒤 앱을 다시 실행한다.

## 무료 계정의 제약

무료 Apple ID로 서명하면 **앱이 7일 뒤 만료**되어 실행되지 않는다.
`flutter run`을 다시 돌리면 갱신된다. 유료 개발자 프로그램(연 $99)에
가입하면 1년으로 늘어나고, TestFlight로 다른 사람에게 배포할 수 있다.

지금은 본인 테스트 단계이므로 무료 계정으로 충분하다.

## 테스트해 볼 것

웹 미리보기와 달리 실기기에서는 **전 기능**이 동작한다.

1. **도구** — 사진 불러오기, 자르기(비율 프리셋), 회전/반전, 실행취소
2. **지우개** — 잡티나 작은 물체를 문질러 지우기. 손을 뗀 뒤 처리 시간과
   메워진 품질 (균일한 배경에서 특히)
3. **화질 개선** — 저해상도 사진(예: 카톡으로 받은 압축본)에 2배 적용 후
   저장, 사진 앱에서 해상도와 선명도 확인
4. **얼굴** — 셀피에서 얼굴 인식 여부, "자연스럽게" 프리셋,
   눈 크기·얼굴 슬림 등 **워핑 슬라이더** (웹에서는 비활성이던 기능)
5. **필터** — 19종 썸네일과 강도 슬라이더
6. **보정** — 밝기/대비/채도 등 7종 슬라이더가 **끊김 없이 즉시** 반응하는지
   (여기가 GPU 셰이더 경로다)
7. 사진을 **길게 눌러** 원본과 비교
8. **저장** 후 사진 앱에서 결과 확인 — 화면에서 본 것과 일치하는지

## 문제가 생기면 알려줄 정보

- `flutter doctor -v` 출력
- 실패한 명령의 오류 메시지 전체
- 앱이 실행은 되는데 이상하다면: 어느 탭에서 무엇이 이상한지 + 스크린샷

특히 확인이 필요한 부분:

- **보정 슬라이더가 버벅인다** → 셰이더 로드 실패로 CPU 폴백 중일 수 있다
- **저장한 사진이 화면과 색이 다르다** → GPU/CPU 수식 불일치 (설계상 없어야 함)
- **얼굴 보정 강도가 과하거나 약하다** → 실기기에서 눈으로 보고 튜닝할 값들이다
