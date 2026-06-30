import 'package:flutter/widgets.dart';

Widget buildImportImageFromPath({
  Key? key,
  required String path,
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
  int? cacheWidth,
  int? cacheHeight,
  FilterQuality filterQuality = FilterQuality.low,
}) {
  return Image.network(
    path,
    key: key,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQuality,
    errorBuilder: errorBuilder,
  );
}

ImageProvider<Object> importImageProviderFromPath(String path) {
  return NetworkImage(path);
}
