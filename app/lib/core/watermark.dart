import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 무료 저장본 우하단에 반투명 "PHOTO" 워터마크를 얹는다.
///
/// 비트맵 폰트(arial48)로 작은 라벨을 만든 뒤 이미지 폭에 비례해
/// 리사이즈해 합성하므로, 해상도와 무관하게 같은 비율로 보인다.
img.Image applyWatermark(img.Image image) {
  const text = 'PHOTO';

  final label = img.Image(width: 176, height: 60, numChannels: 4);
  // 그림자 → 본문 순서로 두 번 그려 어두운 배경에서도 읽히게 한다.
  img.drawString(label, text,
      font: img.arial48, x: 3, y: 3, color: img.ColorRgba8(0, 0, 0, 130));
  img.drawString(label, text,
      font: img.arial48, x: 0, y: 0, color: img.ColorRgba8(255, 255, 255, 200));

  final targetWidth =
      math.max(88, (image.width * 0.16).round()).clamp(1, image.width);
  final scaled = img.copyResize(label, width: targetWidth);
  final pad = math.max(8, image.width ~/ 60);

  img.compositeImage(
    image,
    scaled,
    dstX: math.max(0, image.width - scaled.width - pad),
    dstY: math.max(0, image.height - scaled.height - pad),
  );
  return image;
}
