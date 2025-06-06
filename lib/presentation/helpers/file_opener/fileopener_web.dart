import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:dreamic/presentation/helpers/file_opener/fileopener.dart';

openFile(
  Uint8List bytes,
  FileOpenerFileType fileType, {
  String baseFileName = 'temp',
  bool preferDownload = true,
}) async {
  final blob = html.Blob([bytes], fileType.mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  if (preferDownload) {
    // Create an anchor element
    // ignore: unused_local_variable
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', '$baseFileName.${fileType.extension}')
      ..click();

    // Revoke the object URL after the download
    html.Url.revokeObjectUrl(url);
  } else {
    html.window.open(url, '_blank');
    // html.window.open(url, baseFileName);
  }
}
