import 'dart:io';
import 'dart:typed_data';

import 'package:dreamic/presentation/helpers/file_opener/fileopener.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

openFile(
  Uint8List bytes,
  FileOpenerFileType fileType, {
  String baseFileName = 'temp',
  bool preferDownload = true,
}) async {
  // Get temporary directory
  final tempDir = await getTemporaryDirectory();
  // Assume FileOpenerFileType has an 'extension' property, e.g., "pdf", "txt", etc.
  final filePath = '${tempDir.path}/$baseFileName.${fileType.extension}';
  final file = File(filePath);

  // Write bytes to the file
  await file.writeAsBytes(bytes, flush: true);
  // Open the file with the default app
  await OpenFile.open(file.path);
}
