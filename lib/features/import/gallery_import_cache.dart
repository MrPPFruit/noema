import 'package:image_picker/image_picker.dart';

import 'gallery_import_cache_stub.dart'
    if (dart.library.io) 'gallery_import_cache_io.dart'
    as impl;

typedef GalleryImportPersister = Future<String?> Function(XFile file);

Future<String?> persistGalleryImportFile(XFile file) {
  return impl.persistGalleryImportFile(file);
}
