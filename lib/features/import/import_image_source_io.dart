import 'dart:io';

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
  final uri = Uri.tryParse(path);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isNetwork) {
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

  return Image.file(
    File(path),
    key: key,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQuality,
    errorBuilder: errorBuilder,
  );
}

ImageProvider<Object> importImageProviderFromPath(String path) {
  final uri = Uri.tryParse(path);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isNetwork) {
    return NetworkImage(path);
  }
  return FileImage(File(path));
}
