import 'package:flutter_test/flutter_test.dart';
import 'package:photo_app/main.dart';

void main() {
  testWidgets('home screen renders picker buttons', (tester) async {
    await tester.pumpWidget(const PhotoApp());

    expect(find.text('찰칵'), findsOneWidget);
    expect(find.text('갤러리에서 선택'), findsOneWidget);
    expect(find.text('카메라로 촬영'), findsOneWidget);
  });
}
