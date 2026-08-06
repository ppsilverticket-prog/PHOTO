import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'shared/app_theme.dart';

void main() {
  runApp(const PhotoApp());
}

class PhotoApp extends StatelessWidget {
  const PhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PHOTO',
      debugShowCheckedModeBanner: false,
      // 기본은 편집기용 무채색 다크. 사진이 없는 화면(홈·페이월)은
      // 각자 buildLightTheme()으로 감싼다.
      theme: buildEditorTheme(),
      home: const HomeScreen(),
    );
  }
}
