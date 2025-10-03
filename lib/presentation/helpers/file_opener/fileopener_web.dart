import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dreamic/presentation/helpers/file_opener/fileopener.dart';
import 'package:web/web.dart';

Future<void> openFile(
  Uint8List bytes,
  FileOpenerFileType fileType, {
  String baseFileName = 'temp',
  bool preferDownload = true,
}) async {
  final blob = Blob([bytes.toJS].toJS, BlobPropertyBag(type: fileType.mimeType));
  final url = URL.createObjectURL(blob);

  if (preferDownload) {
    // Create an anchor element and trigger download
    (HTMLAnchorElement()
      ..href = url
      ..setAttribute('download', '$baseFileName.${fileType.extension}'))
        .click();

    // Revoke the object URL after the download
    URL.revokeObjectURL(url);
  } else {
    window.open(url, '_blank');
    // window.open(url, baseFileName);
  }
}
