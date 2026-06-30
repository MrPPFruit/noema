import 'dart:typed_data';

import 'import_analysis_source_stub.dart'
    if (dart.library.io) 'import_analysis_source_io.dart'
    as analysis_source;

Future<Uint8List?> loadImportAnalysisBytes(String? path) {
  return analysis_source.loadImportAnalysisBytes(path);
}
