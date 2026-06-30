import 'package:flutter/widgets.dart';

import 'import_image_source_stub.dart'
    if (dart.library.io) 'import_image_source_io.dart'
    if (dart.library.html) 'import_image_source_web.dart'
    as image_source;

Widget buildImportImageFromPath({
  Key? key,
  required String path,
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
  int? cacheWidth,
  int? cacheHeight,
  FilterQuality filterQuality = FilterQuality.low,
}) {
  return image_source.buildImportImageFromPath(
    key: key,
    path: path,
    fit: fit,
    errorBuilder: errorBuilder,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQuality,
  );
}

ImageProvider<Object> importImageProviderFromPath(String path) {
  return image_source.importImageProviderFromPath(path);
}
