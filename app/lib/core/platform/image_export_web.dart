import 'dart:js_interop';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

export 'image_export_exception.dart';

/// 웹에는 갤러리가 없으므로 브라우저 다운로드로 대신한다.
Future<String> saveImage(Uint8List bytes, String name) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/jpeg'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = '$name.jpg';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return '이미지를 내려받았어요. 사진 앱에 넣으려면 공유 버튼을 쓰세요.';
}

/// Web Share API로 시스템 공유 시트를 연다. iOS 사파리에서는 여기서
/// "이미지 저장"을 골라 사진 앱에 넣을 수 있다.
Future<void> shareImage(Uint8List bytes, String name) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(bytes, name: '$name.jpg', mimeType: 'image/jpeg'),
      ],
    ),
  );
}
