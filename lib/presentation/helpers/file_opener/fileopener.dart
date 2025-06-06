export 'fileopener_mobile.dart' if (dart.library.html) 'fileopener_web.dart';

enum FileOpenerFileType {
  pdf('application/pdf', 'pdf'),
  ;

  final String mimeType;
  final String extension;

  const FileOpenerFileType(
    this.mimeType,
    this.extension,
  );
}
