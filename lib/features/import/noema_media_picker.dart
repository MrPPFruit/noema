import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/features/import/noema_cached_file_deleter.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

const String noemaMediaPickerChannelName = 'noema/media_picker';

enum NoemaGalleryAccess {
  full,
  partial,
  denied,
  unavailable;

  bool get canReadMedia => this == full || this == partial;
}

class NoemaGalleryAccessDeniedException implements Exception {
  const NoemaGalleryAccessDeniedException();

  @override
  String toString() => 'NoemaGalleryAccessDeniedException';
}

class NoemaGalleryIndexRefreshResult {
  const NoemaGalleryIndexRefreshResult({
    required this.access,
    required this.count,
    this.path,
  });

  factory NoemaGalleryIndexRefreshResult.fromMap(Map<Object?, Object?> map) {
    return NoemaGalleryIndexRefreshResult(
      access: noemaGalleryAccessFromValue(map['access']),
      count: _positiveIntValue(map['count']) ?? 0,
      path: _stringValue(map['path']),
    );
  }

  final NoemaGalleryAccess access;
  final int count;
  final String? path;
}

class NoemaMediaPicker {
  const NoemaMediaPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(noemaMediaPickerChannelName);

  static final Map<String, Future<String?>> _cachedImageRequests = {};
  static final Map<String, Future<SelectedGalleryAsset?>> _metadataRequests =
      {};

  final MethodChannel _channel;

  static bool get isAndroidSupported {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static bool get isIOSSupported {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool get isNativePickerSupported {
    return isAndroidSupported || isIOSSupported;
  }

  Future<NoemaGalleryAccess> galleryAccessStatus() async {
    final result = await _channel.invokeMethod<Object?>('galleryAccessStatus');
    return noemaGalleryAccessFromValue(result);
  }

  Future<NoemaGalleryAccess> requestGalleryAccess() async {
    final result = await _channel.invokeMethod<Object?>('requestGalleryAccess');
    return noemaGalleryAccessFromValue(result);
  }

  Future<NoemaGalleryIndexRefreshResult> refreshGalleryIndex({
    int maxItems = 0,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'refreshGalleryIndex',
      {'maxItems': maxItems},
    );
    return NoemaGalleryIndexRefreshResult.fromMap(
      result ?? const <Object?, Object?>{},
    );
  }

  Future<int> warmGalleryThumbnails({
    int maxItems = 96,
    int maxSize = 320,
  }) async {
    final result = await _channel.invokeMethod<Object?>(
      'warmGalleryThumbnails',
      {'maxItems': maxItems, 'maxSize': maxSize},
    );
    return _positiveIntValue(result) ?? 0;
  }

  Future<List<SelectedGalleryAsset>> pickImages({required int limit}) async {
    final result = await _channel.invokeListMethod<Object?>('pickImages', {
      'limit': limit,
    });
    return [
      for (final item in result ?? const <Object?>[])
        if (item case final Map<Object?, Object?> map)
          selectedGalleryAssetFromMediaMap(map),
    ];
  }

  Future<String?> createThumbnail({
    required String uri,
    int maxSize = 320,
  }) async {
    return _sharedCachedImageRequest(
      method: 'createThumbnail',
      uri: uri,
      maxSize: maxSize,
    );
  }

  Future<SelectedGalleryAsset?> loadMetadata({required String uri}) async {
    final key = '${_channel.name}|loadMetadata|$uri';
    final activeRequest = _metadataRequests[key];
    if (activeRequest != null) {
      return activeRequest;
    }

    late final Future<SelectedGalleryAsset?> request;
    request = _channel
        .invokeMapMethod<Object?, Object?>('loadMetadata', {'uri': uri})
        .then((result) {
          if (result == null) {
            return null;
          }
          return selectedGalleryAssetFromMediaMap(result);
        })
        .whenComplete(() {
          if (identical(_metadataRequests[key], request)) {
            _metadataRequests.remove(key);
          }
        });
    _metadataRequests[key] = request;
    return request;
  }

  Future<String?> createPreview({required String uri, int maxSize = 1800}) {
    return _sharedCachedImageRequest(
      method: 'createPreview',
      uri: uri,
      maxSize: maxSize,
    );
  }

  Future<int> deleteCachedFiles(Iterable<String> paths) async {
    final uniquePaths = {
      for (final path in paths)
        if (path.trim().isNotEmpty) path,
    }.toList(growable: false);
    if (uniquePaths.isEmpty) {
      return 0;
    }
    try {
      final result = await _channel.invokeMethod<Object?>('deleteCachedFiles', {
        'paths': uniquePaths,
      });
      return _positiveIntValue(result) ?? 0;
    } on MissingPluginException {
      return deleteNoemaLocalCachedFiles(uniquePaths);
    } on PlatformException {
      return deleteNoemaLocalCachedFiles(uniquePaths);
    }
  }

  Future<bool> deleteSystemMediaItems(Iterable<String> uris) async {
    final uniqueUris = {
      for (final uri in uris)
        if (uri.trim().isNotEmpty) uri.trim(),
    }.toList(growable: false);
    if (uniqueUris.isEmpty) {
      return false;
    }
    final result = await _channel.invokeMethod<Object?>('deleteMediaItems', {
      'uris': uniqueUris,
    });
    if (result is bool) {
      return result;
    }
    if (result is Map<Object?, Object?>) {
      return _boolValue(result['deleted']) ?? false;
    }
    return false;
  }

  Future<String?> _sharedCachedImageRequest({
    required String method,
    required String uri,
    required int maxSize,
  }) {
    final key = '${_channel.name}|$method|$uri|$maxSize';
    final activeRequest = _cachedImageRequests[key];
    if (activeRequest != null) {
      return activeRequest;
    }

    late final Future<String?> request;
    request = _channel
        .invokeMethod<String>(method, {'uri': uri, 'maxSize': maxSize})
        .whenComplete(() {
          if (identical(_cachedImageRequests[key], request)) {
            _cachedImageRequests.remove(key);
          }
        });
    _cachedImageRequests[key] = request;
    return request;
  }
}

NoemaGalleryAccess noemaGalleryAccessFromValue(Object? value) {
  return switch (_stringValue(value)) {
    'full' => NoemaGalleryAccess.full,
    'partial' => NoemaGalleryAccess.partial,
    'denied' => NoemaGalleryAccess.denied,
    _ => NoemaGalleryAccess.unavailable,
  };
}

SelectedGalleryAsset selectedGalleryAssetFromMediaMap(
  Map<Object?, Object?> map,
) {
  final uri = _stringValue(map['uri']);
  final id = _stringValue(map['id']) ?? uri ?? _stringValue(map['name']) ?? '';
  final name = _stringValue(map['name']) ?? 'photo';
  final width = _positiveIntValue(map['width']);
  final height = _positiveIntValue(map['height']);
  final takenAt =
      _dateValue(map['exifTakenAtMillis']) ?? _dateValue(map['takenAtMillis']);

  return SelectedGalleryAsset(
    id: id,
    name: name,
    sourceUri: uri,
    thumbnailPath: _stringValue(map['thumbnailPath']),
    width: width,
    height: height,
    createdAt: takenAt,
    updatedAt: _dateValue(map['modifiedAtMillis']),
    mimeType: _stringValue(map['mimeType']),
    fileSize: _positiveIntValue(map['fileSize']),
    exif: _exifValue(map),
    previewUnavailable:
        uri == null && _stringValue(map['thumbnailPath']) == null,
  );
}

PhotoExif? _exifValue(Map<Object?, Object?> map) {
  final exif = PhotoExif(
    iso: _positiveIntValue(map['iso']),
    shutterSpeed: _stringValue(map['shutterSpeed']),
    aperture: _positiveDoubleValue(map['aperture']),
    focalLengthMm: _positiveDoubleValue(map['focalLengthMm']),
    whiteBalance: _stringValue(map['whiteBalance']),
  );
  return exif.isEmpty ? null : exif;
}

String? _stringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

int? _positiveIntValue(Object? value) {
  final intValue = switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
  if (intValue == null || intValue <= 0) {
    return null;
  }
  return intValue;
}

double? _positiveDoubleValue(Object? value) {
  final doubleValue = switch (value) {
    double() => value,
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  if (doubleValue == null || doubleValue <= 0) {
    return null;
  }
  return doubleValue;
}

DateTime? _dateValue(Object? value) {
  final millis = _positiveIntValue(value);
  if (millis == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
