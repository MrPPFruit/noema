import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:noema/features/import/selected_gallery_asset.dart';

const int maxPreviewBytes = 1024 * 1024;

class GalleryImportPreparer {
  const GalleryImportPreparer({this.maxBytes = maxPreviewBytes});

  final int maxBytes;

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
    final path = file.path;
    if (path.isEmpty) {
      return _unavailableAsset(file);
    }

    final dimensions = await _imageDimensions(file);
    return SelectedGalleryAsset(
      id: path,
      name: file.name,
      thumbnailPath: path,
      width: dimensions?.width,
      height: dimensions?.height,
    );
  }

  SelectedGalleryAsset _unavailableAsset(XFile file) {
    return SelectedGalleryAsset(
      id: file.path,
      name: file.name,
      previewUnavailable: true,
    );
  }

  Future<({int width, int height})?> _imageDimensions(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) {
        return null;
      }
      return (width: info.width, height: info.height);
    } catch (_) {
      return null;
    }
  }
}
