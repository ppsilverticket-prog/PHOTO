import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'image_export_exception.dart';

export 'image_export_exception.dart';

/// 갤러리에 저장한다. 성공하면 사용자에게 보여줄 안내 문구를 돌려준다.
Future<String> saveImage(Uint8List bytes, String name) async {
  try {
    await Gal.putImageBytes(bytes, name: name);
    return '갤러리에 저장했습니다.';
  } on GalException catch (e) {
    throw ImageExportException(
      e.type == GalExceptionType.accessDenied
          ? '사진 접근 권한을 허용해 주세요.'
          : '저장에 실패했습니다: ${e.type.message}',
    );
  }
}

/// 임시 파일로 쓴 뒤 시스템 공유 시트를 연다.
Future<void> shareImage(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$name.jpg';
  await File(path).writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path, mimeType: 'image/jpeg')]),
  );
}
