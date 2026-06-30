import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> loadImportAnalysisBytes(String? path) async {
  if (path == null || path.isEmpty) {
    return null;
  }
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsBytesSync();
  } catch (_) {
    return null;
  }
}
