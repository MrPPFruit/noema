import 'package:image_picker/image_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

class GalleryImportPreparer {
  const GalleryImportPreparer();

  Future<List<SelectedGalleryAsset>> prepare(List<XFile> files) async {
    final assets = <SelectedGalleryAsset>[];
    for (final file in files) {
      assets.add(await _assetReference(file));
    }
    return assets;
  }

  Future<SelectedGalleryAsset> prepareOne(XFile file) async {
    return _assetReference(file);
  }

  Future<SelectedGalleryAsset> _assetReference(XFile file) async {
    final sourcePath = file.path;
    if (sourcePath.isEmpty) {
      return _unavailableAsset(file);
    }

    return SelectedGalleryAsset(
      id: sourcePath,
      name: file.name,
      thumbnailPath: sourcePath,
    );
  }

  SelectedGalleryAsset _unavailableAsset(XFile file) {
    return SelectedGalleryAsset(
      id: file.path,
      name: file.name,
      previewUnavailable: true,
    );
  }
}
