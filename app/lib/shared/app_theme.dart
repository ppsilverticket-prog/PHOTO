import 'package:flutter/material.dart';

/// 피치 소르베 테마 토큰.
///
/// 규칙:
/// - 편집기(사진이 보이는 화면)는 항상 무채색 다크 — 사진 옆에 색이 있으면
///   눈이 색을 잘못 읽는다. 피치는 선택 상태·버튼에만 쓴다.
/// - 홈·페이월처럼 사진이 없는 화면만 크림빛 라이트.
/// - 귀여움은 색보다 모양(곡률)과 말투로: 버튼 16, 칩 12, 시트/다이얼로그 24.
abstract final class AppColors {
  /// 주색 — 복숭아빛 코랄.
  static const Color peach = Color(0xFFFF8E78);

  /// 다크 배경 위에서 글자·아이콘으로 쓸 때의 밝은 피치.
  static const Color peachBright = Color(0xFFFF9D89);

  /// 피치 버튼 위 글자색 (짙은 코코아).
  static const Color onPeach = Color(0xFF47160C);

  // 라이트 (홈·페이월)
  static const Color cream = Color(0xFFFFF7F2);
  static const Color creamSurface = Color(0xFFFFFDFB);
  static const Color cocoa = Color(0xFF322622);
  static const Color cocoaMuted = Color(0xFF9A8880);
  static const Color creamLine = Color(0x1F322622);

  // 다크 (편집기) — 무채색에 아주 살짝만 온기를 준다.
  static const Color canvas = Color(0xFF121114);
  static const Color panel = Color(0xFF1A1716);
  static const Color inkDark = Color(0xFFEAE6E2);
  static const Color mutedDark = Color(0xFF9B948E);
}

const String _fontFamily = 'Pretendard';

/// 화면 곡률 언어 — 앱 전체에서 같은 값을 쓴다.
abstract final class AppRadius {
  static const double button = 16;
  static const double chip = 12;
  static const double sheet = 24;
  static const double snack = 14;
}

/// 홈·페이월 등 사진이 없는 화면의 크림 라이트 테마.
ThemeData buildLightTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.peach,
    onPrimary: AppColors.onPeach,
    secondary: AppColors.peach,
    onSecondary: AppColors.onPeach,
    surface: AppColors.creamSurface,
    onSurface: AppColors.cocoa,
    onSurfaceVariant: AppColors.cocoaMuted,
    outline: AppColors.cocoaMuted,
    outlineVariant: AppColors.creamLine,
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.cocoa,
      elevation: 0,
    ),
  );
}

/// 편집기 계열 화면의 무채색 다크 테마 (MaterialApp 기본).
ThemeData buildEditorTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.peach,
    onPrimary: AppColors.onPeach,
    secondary: AppColors.peachBright,
    onSecondary: AppColors.onPeach,
    surface: AppColors.canvas,
    onSurface: AppColors.inkDark,
    onSurfaceVariant: AppColors.mutedDark,
    outline: AppColors.mutedDark,
    outlineVariant: Color(0x26EAE6E2),
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.inkDark,
      elevation: 0,
    ),
  );
}

ThemeData _base(ColorScheme scheme) {
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        side: BorderSide(color: scheme.primary.withValues(alpha: .45)),
        foregroundColor: scheme.onSurface,
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.snack),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
