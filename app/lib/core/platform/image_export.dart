/// 편집 결과를 기기에 내보내는 플랫폼별 구현을 고른다.
///
/// 모바일에서는 갤러리에 저장하고, 웹에서는 브라우저 다운로드로 대체한다.
/// 공유는 양쪽 모두 share_plus를 쓰지만 임시 파일 경로가 필요한지가 달라
/// 구현을 나눈다.
///
/// 기본값이 웹 구현인 이유: `dart.library.io`는 네이티브에서만 참이라
/// 조건이 맞지 않는 플랫폼이 `dart:io`를 건드리는 일이 없다.
library;

export 'image_export_web.dart'
    if (dart.library.io) 'image_export_io.dart';
