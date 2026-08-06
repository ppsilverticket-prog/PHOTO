import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 브랜드 자산(앱 아이콘·스플래시 마크) 생성 스크립트.
///
/// 홈 화면의 스파클 마크를 그대로 아이콘으로 쓴다 (피치 소르베 테마).
/// 색을 바꾸고 싶으면 아래 상수를 수정하고 다시 실행:
///
///   dart run tool/generate_brand_assets.dart
///   dart run flutter_launcher_icons
///   dart run flutter_native_splash:create
void main() {
  const peach = (0xFF, 0x8E, 0x78);
  const cream = (0xFF, 0xF7, 0xF2);

  final outDir = Directory('assets/icon')..createSync(recursive: true);

  // 1) 마스터 아이콘 1024x1024 — 크림 배경 + 피치 스파클.
  final icon = img.Image(width: 1024, height: 1024);
  img.fill(icon,
      color: img.ColorRgb8(cream.$1, cream.$2, cream.$3));
  _drawSparkleSet(icon, cx: 470, cy: 540, size: 300, rgb: peach);
  File('${outDir.path}/app_icon.png')
      .writeAsBytesSync(img.encodePng(icon));

  // 2) 안드로이드 어댑티브 전경 — 투명 배경, 안전 영역(중앙 66%) 안에 마크.
  final foreground = img.Image(width: 1024, height: 1024, numChannels: 4);
  _drawSparkleSet(foreground, cx: 484, cy: 528, size: 210, rgb: peach);
  File('${outDir.path}/app_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));

  // 3) 스플래시 마크 — 투명 배경 스파클 (크림/다크 배경 공용).
  final splash = img.Image(width: 512, height: 512, numChannels: 4);
  _drawSparkleSet(splash, cx: 242, cy: 264, size: 150, rgb: peach);
  File('${outDir.path}/splash_mark.png')
      .writeAsBytesSync(img.encodePng(splash));

  stdout.writeln('generated: app_icon.png, app_icon_foreground.png, '
      'splash_mark.png in ${outDir.path}/');
}

/// 큰 스파클 하나 + 보조 점 두 개 (홈 화면 마크와 같은 구성).
void _drawSparkleSet(
  img.Image canvas, {
  required int cx,
  required int cy,
  required int size,
  required (int, int, int) rgb,
}) {
  final color = canvas.numChannels == 4
      ? img.ColorRgba8(rgb.$1, rgb.$2, rgb.$3, 255)
      : img.ColorRgb8(rgb.$1, rgb.$2, rgb.$3);
  final faded = canvas.numChannels == 4
      ? img.ColorRgba8(rgb.$1, rgb.$2, rgb.$3, 140)
      : _mixWithBackground(rgb, canvas);

  _fillSparkle(canvas, cx, cy, size, color);
  img.fillCircle(
    canvas,
    x: cx + (size * 1.02).round(),
    y: cy - (size * 0.98).round(),
    radius: (size * 0.13).round(),
    color: faded,
  );
  img.fillCircle(
    canvas,
    x: cx + (size * 1.18).round(),
    y: cy + (size * 0.62).round(),
    radius: (size * 0.09).round(),
    color: faded,
  );
}

/// RGB 캔버스에서는 반투명 대신 배경색과 섞은 색을 쓴다.
img.Color _mixWithBackground((int, int, int) rgb, img.Image canvas) {
  final bg = canvas.getPixel(0, 0);
  int mix(int a, num b) => ((a * 0.55) + (b * 0.45)).round();
  return img.ColorRgb8(mix(rgb.$1, bg.r), mix(rgb.$2, bg.g), mix(rgb.$3, bg.b));
}

/// 4갈래 스파클. 꼭짓점 사이를 오목한 원호로 이어 통통한 별 모양을 만든다.
void _fillSparkle(
    img.Image canvas, int cx, int cy, int radius, img.Color color) {
  // 오목 곡선: 점 (x, y)가 스파클 안쪽인지 판정.
  // |x|^p + |y|^p <= R^p (p < 1) 은 별 모양의 초타원(astroid 계열)이다.
  const p = 0.62;
  final rp = math.pow(radius.toDouble(), p);
  for (var y = -radius; y <= radius; y++) {
    for (var x = -radius; x <= radius; x++) {
      final v = math.pow(x.abs().toDouble(), p) +
          math.pow(y.abs().toDouble(), p);
      if (v <= rp) {
        final px = cx + x;
        final py = cy + y;
        if (px >= 0 && py >= 0 && px < canvas.width && py < canvas.height) {
          canvas.setPixel(px, py, color);
        }
      }
    }
  }
}
