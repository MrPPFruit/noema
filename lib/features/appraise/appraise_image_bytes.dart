import 'dart:typed_data';

import 'package:noema/core/workflow/review_workspace.dart';

import 'appraise_image_bytes_stub.dart'
    if (dart.library.io) 'appraise_image_bytes_io.dart'
    if (dart.library.html) 'appraise_image_bytes_web.dart'
    as source;

Future<Uint8List?> appraiseImageBytesForAsset(ReviewAsset asset) async {
  final bytes = asset.analysisBytes ?? asset.previewBytes;
  if (bytes != null && bytes.isNotEmpty) {
    return bytes;
  }

  final path =
      asset.photo.previewPath ??
      asset.photo.thumbnailPath ??
      asset.photo.sourceUri;
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  return source.readAppraiseImageBytes(path);
}

String appraiseImageMimeTypeForAsset(ReviewAsset asset) {
  final mimeType = asset.photo.mimeType;
  if (mimeType != null && mimeType.startsWith('image/')) {
    return mimeType;
  }
  return 'image/jpeg';
}
