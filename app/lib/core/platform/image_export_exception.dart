/// 사용자에게 그대로 보여줄 수 있는 내보내기 실패 사유.
class ImageExportException implements Exception {
  const ImageExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
