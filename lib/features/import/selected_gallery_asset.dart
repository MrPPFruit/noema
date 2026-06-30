import 'dart:typed_data';

import 'package:noema/core/models/photo_asset.dart';

class SelectedGalleryAsset {
  const SelectedGalleryAsset({
    required this.id,
    required this.name,
    this.thumbnailPath,
    this.sourceUri,
    this.previewBytes,
    this.analysisBytes,
    this.width,
    this.height,
    this.createdAt,
    this.updatedAt,
    this.mimeType,
    this.fileSize,
    this.exif,
    this.previewUnavailable = false,
  });

  final String id;
  final String name;
  final String? thumbnailPath;
  final String? sourceUri;
  final Uint8List? previewBytes;
  final Uint8List? analysisBytes;
  final int? width;
  final int? height;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? mimeType;
  final int? fileSize;
  final PhotoExif? exif;
  final bool previewUnavailable;

  SelectedGalleryAsset copyWith({
    String? id,
    String? name,
    String? thumbnailPath,
    String? sourceUri,
    Uint8List? previewBytes,
    Uint8List? analysisBytes,
    int? width,
    int? height,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mimeType,
    int? fileSize,
    PhotoExif? exif,
    bool? previewUnavailable,
  }) {
    return SelectedGalleryAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      sourceUri: sourceUri ?? this.sourceUri,
      previewBytes: previewBytes ?? this.previewBytes,
      analysisBytes: analysisBytes ?? this.analysisBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      exif: exif ?? this.exif,
      previewUnavailable: previewUnavailable ?? this.previewUnavailable,
    );
  }
}
