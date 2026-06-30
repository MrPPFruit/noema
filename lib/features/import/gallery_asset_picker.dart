import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noema/features/import/gallery_import_preparer.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

const int galleryPickerLimit = 300;

typedef GalleryAssetPicker =
    Future<List<SelectedGalleryAsset>> Function(BuildContext context);

Future<List<SelectedGalleryAsset>> pickGalleryAssets(
  BuildContext context,
) async {
  if (NoemaMediaPicker.isAndroidSupported) {
    try {
      const mediaPicker = NoemaMediaPicker();
      final access = await mediaPicker.requestGalleryAccess();
      if (!access.canReadMedia) {
        throw const NoemaGalleryAccessDeniedException();
      }
      unawaited(_ignoreGalleryWarmup(mediaPicker.refreshGalleryIndex()));
      unawaited(_ignoreGalleryWarmup(mediaPicker.warmGalleryThumbnails()));
      return mediaPicker.pickImages(limit: galleryPickerLimit);
    } on MissingPluginException {
      // Fall through to image_picker for tests or older app shells.
    }
  }

  final picker = ImagePicker();
  final images = await picker.pickMultiImage(
    limit: galleryPickerLimit,
    requestFullMetadata: false,
  );

  return const GalleryImportPreparer().prepare(images);
}

Future<void> _ignoreGalleryWarmup<T>(Future<T> future) async {
  try {
    await future;
  } catch (_) {
    // Indexing and thumbnail prewarm are opportunistic. The selected import
    // still works because each image can rebuild its own derived files later.
  }
}
