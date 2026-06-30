import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:noema/core/analysis/local_image_analyzer.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/review_session.dart';
import 'package:noema/core/models/series_appraisal.dart';
import 'package:noema/core/models/similar_group.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

class ReviewAsset {
  const ReviewAsset({
    required this.photo,
    required this.displayName,
    this.previewBytes,
    this.analysisBytes,
  });

  final PhotoAsset photo;
  final String displayName;
  final Uint8List? previewBytes;
  final Uint8List? analysisBytes;

  ReviewAsset copyWith({
    PhotoAsset? photo,
    String? displayName,
    Uint8List? previewBytes,
    Uint8List? analysisBytes,
  }) {
    return ReviewAsset(
      photo: photo ?? this.photo,
      displayName: displayName ?? this.displayName,
      previewBytes: previewBytes ?? this.previewBytes,
      analysisBytes: analysisBytes ?? this.analysisBytes,
    );
  }

  Map<String, Object?> toJson() {
    return {'photo': photo.toJson(), 'displayName': displayName};
  }

  factory ReviewAsset.fromJson(Map<String, Object?> json) {
    return ReviewAsset(
      photo: PhotoAsset.fromJson(_jsonMap(json['photo'])),
      displayName: _stringValue(json['displayName'], 'photo'),
    );
  }
}

class MissingAssetIndex {
  const MissingAssetIndex({
    required this.photoId,
    required this.displayName,
    required this.detectedAt,
    this.notified = false,
  });

  final String photoId;
  final String displayName;
  final DateTime detectedAt;
  final bool notified;

  MissingAssetIndex copyWith({
    String? photoId,
    String? displayName,
    DateTime? detectedAt,
    bool? notified,
  }) {
    return MissingAssetIndex(
      photoId: photoId ?? this.photoId,
      displayName: displayName ?? this.displayName,
      detectedAt: detectedAt ?? this.detectedAt,
      notified: notified ?? this.notified,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'photoId': photoId,
      'displayName': displayName,
      'detectedAt': detectedAt.toIso8601String(),
      'notified': notified,
    };
  }

  factory MissingAssetIndex.fromJson(Map<String, Object?> json) {
    final fallbackTime = DateTime.now();
    return MissingAssetIndex(
      photoId: _stringValue(json['photoId'], ''),
      displayName: _stringValue(json['displayName'], 'photo'),
      detectedAt: _dateValue(json['detectedAt'], fallbackTime),
      notified: _boolValue(json['notified'], false),
    );
  }
}

class ObserveViewPreferences {
  const ObserveViewPreferences({
    this.timeSort = 'newestFirst',
    this.sortMode = 'time',
    this.scoreSort = 'highToLow',
    this.filterMode = 'all',
    this.density = 'balanced',
  });

  static const defaults = ObserveViewPreferences();

  final String timeSort;
  final String sortMode;
  final String scoreSort;
  final String filterMode;
  final String density;

  ObserveViewPreferences copyWith({
    String? timeSort,
    String? sortMode,
    String? scoreSort,
    String? filterMode,
    String? density,
  }) {
    return ObserveViewPreferences(
      timeSort: timeSort ?? this.timeSort,
      sortMode: sortMode ?? this.sortMode,
      scoreSort: scoreSort ?? this.scoreSort,
      filterMode: filterMode ?? this.filterMode,
      density: density ?? this.density,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'timeSort': timeSort,
      'sortMode': sortMode,
      'scoreSort': scoreSort,
      'filterMode': filterMode,
      'density': density,
    };
  }

  factory ObserveViewPreferences.fromJson(Map<String, Object?> json) {
    return ObserveViewPreferences(
      timeSort: _stringValue(json['timeSort'], defaults.timeSort),
      sortMode: _stringValue(json['sortMode'], defaults.sortMode),
      scoreSort: _stringValue(json['scoreSort'], defaults.scoreSort),
      filterMode: _stringValue(json['filterMode'], defaults.filterMode),
      density: _stringValue(json['density'], defaults.density),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ObserveViewPreferences &&
        other.timeSort == timeSort &&
        other.sortMode == sortMode &&
        other.scoreSort == scoreSort &&
        other.filterMode == filterMode &&
        other.density == density;
  }

  @override
  int get hashCode =>
      Object.hash(timeSort, sortMode, scoreSort, filterMode, density);
}

class AppreciateViewPreferences {
  const AppreciateViewPreferences({
    this.rangeMask = allRangeMask,
    this.order = 'sequence',
    this.intervalSeconds = 10,
  });

  static const defaults = AppreciateViewPreferences();
  static const allRangeMask = 0x0f;

  final int rangeMask;
  final String order;
  final int intervalSeconds;

  AppreciateViewPreferences copyWith({
    int? rangeMask,
    String? order,
    int? intervalSeconds,
  }) {
    return AppreciateViewPreferences(
      rangeMask: rangeMask ?? this.rangeMask,
      order: order ?? this.order,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'rangeMask': rangeMask,
      'order': order,
      'intervalSeconds': intervalSeconds,
    };
  }

  factory AppreciateViewPreferences.fromJson(Map<String, Object?> json) {
    return AppreciateViewPreferences(
      rangeMask: _intValue(json['rangeMask'], defaults.rangeMask),
      order: _stringValue(json['order'], defaults.order),
      intervalSeconds: _intValue(
        json['intervalSeconds'],
        defaults.intervalSeconds,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppreciateViewPreferences &&
        other.rangeMask == rangeMask &&
        other.order == order &&
        other.intervalSeconds == intervalSeconds;
  }

  @override
  int get hashCode => Object.hash(rangeMask, order, intervalSeconds);
}

class ReviewWorkspace {
  ReviewWorkspace({
    required this.session,
    required List<ReviewAsset> assets,
    required List<AnalysisResult> analysisResults,
    required List<SimilarGroup> groups,
    List<MissingAssetIndex> missingAssetIndexes = const [],
    List<PhotoSeriesAppraisal> seriesAppraisals = const [],
    this.observeViewPreferences = ObserveViewPreferences.defaults,
    this.appreciateViewPreferences = AppreciateViewPreferences.defaults,
  }) : _assets = List.unmodifiable(assets),
       _analysisResults = List.unmodifiable(analysisResults),
       _groups = List.unmodifiable(groups),
       _missingAssetIndexes = List.unmodifiable(missingAssetIndexes),
       _seriesAppraisals = List.unmodifiable(seriesAppraisals);

  factory ReviewWorkspace.fromSelectedAssets(
    List<SelectedGalleryAsset> selectedAssets, {
    String? name,
    DateTime? importedAt,
    String? sessionId,
  }) {
    final now = importedAt ?? DateTime.now();
    final session = ReviewSession(
      id: sessionId ?? 'session-${now.microsecondsSinceEpoch}',
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Selected photos',
      createdAt: now,
      updatedAt: now,
      totalCount: selectedAssets.length,
      importedCount: selectedAssets.length,
      analyzedCount: selectedAssets.length,
      currentStage: ReviewStage.reviewing,
      status: ReviewSessionStatus.ready,
    );

    final orderedSelectedAssets = _sortSelectedAssetsForImport(selectedAssets);
    final assets = orderedSelectedAssets
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final selected = entry.value;
          final dimensions = _dimensionsForSelected(selected, index);
          final createdAt = _createdAtForSelected(selected, now, index);
          final updatedAt = selected.updatedAt ?? createdAt.value;
          return ReviewAsset(
            photo: PhotoAsset(
              id: 'photo-${index + 1}',
              sessionId: session.id,
              platformAssetId: selected.id,
              createdAt: createdAt.value,
              updatedAt: updatedAt,
              width: dimensions.width,
              height: dimensions.height,
              mediaKind: MediaKind.photo,
              availability: selected.previewUnavailable
                  ? AssetAvailability.unavailable
                  : AssetAvailability.available,
              fileSize: selected.fileSize,
              mimeType: selected.mimeType,
              sourceUri: selected.sourceUri,
              thumbnailPath: selected.previewUnavailable
                  ? null
                  : selected.thumbnailPath,
              exif: selected.exif,
              dimensionsEstimated: dimensions.estimated,
              createdAtEstimated: createdAt.estimated,
            ),
            displayName: selected.name,
            previewBytes: selected.previewUnavailable
                ? null
                : selected.previewBytes,
            analysisBytes: selected.previewUnavailable
                ? null
                : selected.analysisBytes ?? selected.previewBytes,
          );
        })
        .toList(growable: false);

    const analyzer = LocalImageAnalyzer();
    final analysisResults = assets
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final asset = entry.value;
          final analysisBytes = asset.analysisBytes;
          if (analysisBytes != null) {
            return analyzer.analyze(
              photoId: asset.photo.id,
              bytes: analysisBytes,
              analyzedAt: now,
            );
          }

          if (asset.photo.availability == AssetAvailability.unavailable) {
            return AnalysisResult(
              photoId: asset.photo.id,
              blurScore: 0,
              brightnessScore: 0,
              exposureFlag: ExposureFlag.normal,
              similarityHash: 0,
              colorSignature: const [],
              luminanceSignature: const [],
              qualityFlags: const [QualityFlag.unavailable],
              analyzedAt: now,
            );
          }

          final hasAttention = index % 5 == 4;
          return AnalysisResult(
            photoId: asset.photo.id,
            blurScore: hasAttention ? 0.42 : 0.82,
            brightnessScore: hasAttention ? 0.34 : 0.56,
            exposureFlag: hasAttention
                ? ExposureFlag.dark
                : ExposureFlag.normal,
            similarityHash: 0,
            colorSignature: const [],
            luminanceSignature: const [],
            qualityFlags: hasAttention
                ? const [QualityFlag.possibleBlur]
                : const [],
            analyzedAt: now,
          );
        })
        .toList(growable: false);

    final groups = _buildGroups(session.id, assets, analysisResults, now);

    return ReviewWorkspace(
      session: session,
      assets: assets,
      analysisResults: analysisResults,
      groups: groups,
    );
  }

  factory ReviewWorkspace.empty({DateTime? createdAt}) {
    final now = createdAt ?? DateTime.now();
    return ReviewWorkspace(
      session: ReviewSession(
        id: 'empty',
        name: '',
        createdAt: now,
        updatedAt: now,
        totalCount: 0,
        importedCount: 0,
        analyzedCount: 0,
        currentStage: ReviewStage.selecting,
        status: ReviewSessionStatus.draft,
      ),
      assets: const [],
      analysisResults: const [],
      groups: const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'session': session.toJson(),
      'assets': [for (final asset in _assets) asset.toJson()],
      'analysisResults': [
        for (final analysisResult in _analysisResults) analysisResult.toJson(),
      ],
      'groups': [for (final group in _groups) group.toJson()],
      'missingAssetIndexes': [
        for (final index in _missingAssetIndexes) index.toJson(),
      ],
      'seriesAppraisals': [
        for (final appraisal in _seriesAppraisals) appraisal.toJson(),
      ],
      'observeViewPreferences': observeViewPreferences.toJson(),
      'appreciateViewPreferences': appreciateViewPreferences.toJson(),
    };
  }

  factory ReviewWorkspace.fromJson(Map<String, Object?> json) {
    final session = ReviewSession.fromJson(_jsonMap(json['session']));
    final assets = [
      for (final asset in _jsonMapList(json['assets']))
        ReviewAsset.fromJson(asset),
    ];
    final analysisResults = [
      for (final analysisResult in _jsonMapList(json['analysisResults']))
        AnalysisResult.fromJson(analysisResult),
    ];
    final assetIds = {for (final asset in assets) asset.photo.id};
    final missingAssetIndexes =
        [
              for (final index in _jsonMapList(json['missingAssetIndexes']))
                MissingAssetIndex.fromJson(index),
            ]
            .where((index) => assetIds.contains(index.photoId))
            .toList(growable: false);
    final seriesAppraisals =
        [
              for (final appraisal in _jsonMapList(json['seriesAppraisals']))
                PhotoSeriesAppraisal.fromJson(appraisal),
            ]
            .where(
              (appraisal) =>
                  appraisal.photoIds.isNotEmpty &&
                  appraisal.photoIds.every(assetIds.contains),
            )
            .toList(growable: false);

    return ReviewWorkspace(
      session: session,
      assets: assets,
      analysisResults: analysisResults,
      groups: _buildGroups(
        session.id,
        assets,
        analysisResults,
        session.updatedAt,
      ),
      missingAssetIndexes: missingAssetIndexes,
      seriesAppraisals: seriesAppraisals,
      observeViewPreferences: ObserveViewPreferences.fromJson(
        _jsonMap(json['observeViewPreferences']),
      ),
      appreciateViewPreferences: AppreciateViewPreferences.fromJson(
        _jsonMap(json['appreciateViewPreferences']),
      ),
    );
  }

  ReviewWorkspace appendSelectedAssets(
    List<SelectedGalleryAsset> selectedAssets,
  ) {
    if (selectedAssets.isEmpty) {
      return this;
    }

    final knownPlatformIds = {
      for (final asset in _assets) asset.photo.platformAssetId,
    };
    final newSelectedAssets = <SelectedGalleryAsset>[];
    for (final selected in selectedAssets) {
      if (knownPlatformIds.add(selected.id)) {
        newSelectedAssets.add(selected);
      }
    }

    if (newSelectedAssets.isEmpty) {
      return this;
    }

    final now = DateTime.now();
    final startIndex = _assets.length;
    final orderedSelectedAssets = _sortSelectedAssetsForImport(
      newSelectedAssets,
    );
    final appendedAssets = orderedSelectedAssets
        .asMap()
        .entries
        .map((entry) {
          final absoluteIndex = startIndex + entry.key;
          final selected = entry.value;
          final dimensions = _dimensionsForSelected(selected, absoluteIndex);
          final createdAt = _createdAtForSelected(selected, now, absoluteIndex);
          final updatedAt = selected.updatedAt ?? createdAt.value;
          return ReviewAsset(
            photo: PhotoAsset(
              id: 'photo-${absoluteIndex + 1}',
              sessionId: session.id,
              platformAssetId: selected.id,
              createdAt: createdAt.value,
              updatedAt: updatedAt,
              width: dimensions.width,
              height: dimensions.height,
              mediaKind: MediaKind.photo,
              availability: selected.previewUnavailable
                  ? AssetAvailability.unavailable
                  : AssetAvailability.available,
              fileSize: selected.fileSize,
              mimeType: selected.mimeType,
              sourceUri: selected.sourceUri,
              thumbnailPath: selected.previewUnavailable
                  ? null
                  : selected.thumbnailPath,
              exif: selected.exif,
              dimensionsEstimated: dimensions.estimated,
              createdAtEstimated: createdAt.estimated,
            ),
            displayName: selected.name,
            previewBytes: selected.previewUnavailable
                ? null
                : selected.previewBytes,
            analysisBytes: selected.previewUnavailable
                ? null
                : selected.analysisBytes ?? selected.previewBytes,
          );
        })
        .toList(growable: false);

    const analyzer = LocalImageAnalyzer();
    final appendedAnalysis = appendedAssets
        .asMap()
        .entries
        .map((entry) {
          final absoluteIndex = startIndex + entry.key;
          final asset = entry.value;
          final analysisBytes = asset.analysisBytes;
          if (analysisBytes != null) {
            return analyzer.analyze(
              photoId: asset.photo.id,
              bytes: analysisBytes,
              analyzedAt: now,
            );
          }

          if (asset.photo.availability == AssetAvailability.unavailable) {
            return AnalysisResult(
              photoId: asset.photo.id,
              blurScore: 0,
              brightnessScore: 0,
              exposureFlag: ExposureFlag.normal,
              similarityHash: 0,
              colorSignature: const [],
              luminanceSignature: const [],
              qualityFlags: const [QualityFlag.unavailable],
              analyzedAt: now,
            );
          }

          final hasAttention = absoluteIndex % 5 == 4;
          return AnalysisResult(
            photoId: asset.photo.id,
            blurScore: hasAttention ? 0.42 : 0.82,
            brightnessScore: hasAttention ? 0.34 : 0.56,
            exposureFlag: hasAttention
                ? ExposureFlag.dark
                : ExposureFlag.normal,
            similarityHash: 0,
            colorSignature: const [],
            luminanceSignature: const [],
            qualityFlags: hasAttention
                ? const [QualityFlag.possibleBlur]
                : const [],
            analyzedAt: now,
          );
        })
        .toList(growable: false);

    final assets = [..._assets, ...appendedAssets];
    final analysisResults = [..._analysisResults, ...appendedAnalysis];
    final updatedSession = session.copyWith(
      updatedAt: now,
      totalCount: assets.length,
      importedCount: assets.length,
      analyzedCount: assets.length,
    );

    return ReviewWorkspace(
      session: updatedSession,
      assets: assets,
      analysisResults: analysisResults,
      groups: _buildGroups(session.id, assets, analysisResults, now),
      missingAssetIndexes: _missingAssetIndexes,
      seriesAppraisals: _seriesAppraisals,
      observeViewPreferences: observeViewPreferences,
      appreciateViewPreferences: appreciateViewPreferences,
    );
  }

  ReviewWorkspace removeAssetsByIds(Set<String> photoIds) {
    if (photoIds.isEmpty) {
      return this;
    }

    final assets = _assets
        .where((asset) => !photoIds.contains(asset.photo.id))
        .toList(growable: false);
    if (assets.length == _assets.length) {
      return this;
    }

    final now = DateTime.now();
    final analysisResults = _analysisResults
        .where((result) => !photoIds.contains(result.photoId))
        .toList(growable: false);
    final updatedSession = session.copyWith(
      updatedAt: now,
      totalCount: assets.length,
      importedCount: assets.length,
      analyzedCount: analysisResults.length,
    );

    return ReviewWorkspace(
      session: updatedSession,
      assets: assets,
      analysisResults: analysisResults,
      groups: _buildGroups(session.id, assets, analysisResults, now),
      missingAssetIndexes: _missingAssetIndexes
          .where((index) => !photoIds.contains(index.photoId))
          .toList(growable: false),
      seriesAppraisals: _seriesAppraisals
          .where(
            (appraisal) => appraisal.photoIds.every(
              (photoId) => !photoIds.contains(photoId),
            ),
          )
          .toList(growable: false),
      observeViewPreferences: observeViewPreferences,
      appreciateViewPreferences: appreciateViewPreferences,
    );
  }

  ReviewWorkspace upsertSeriesAppraisal(PhotoSeriesAppraisal appraisal) {
    if (appraisal.sessionId != session.id || appraisal.photoIds.isEmpty) {
      return this;
    }
    final assetIds = {for (final asset in _assets) asset.photo.id};
    if (!appraisal.photoIds.every(assetIds.contains)) {
      return this;
    }

    final appraisals = [
      for (final existing in _seriesAppraisals)
        if (existing.band != appraisal.band) existing,
      appraisal,
    ];
    return copyWith(seriesAppraisals: appraisals);
  }

  ReviewWorkspace upsertMissingAssetIndex({
    required String photoId,
    required String displayName,
    DateTime? detectedAt,
  }) {
    if (assetById(photoId) == null) {
      return this;
    }

    final existingIndex = _missingAssetIndexes.indexWhere(
      (index) => index.photoId == photoId,
    );
    if (existingIndex != -1) {
      final existing = _missingAssetIndexes[existingIndex];
      if (existing.displayName == displayName) {
        return this;
      }
      final indexes = [..._missingAssetIndexes];
      indexes[existingIndex] = existing.copyWith(displayName: displayName);
      return copyWith(missingAssetIndexes: indexes);
    }

    return copyWith(
      missingAssetIndexes: [
        ..._missingAssetIndexes,
        MissingAssetIndex(
          photoId: photoId,
          displayName: displayName,
          detectedAt: detectedAt ?? DateTime.now(),
        ),
      ],
    );
  }

  ReviewWorkspace markMissingAssetIndexesNotified(Set<String> photoIds) {
    if (photoIds.isEmpty || _missingAssetIndexes.isEmpty) {
      return this;
    }

    var changed = false;
    final indexes = [
      for (final index in _missingAssetIndexes)
        if (photoIds.contains(index.photoId) && !index.notified)
          () {
            changed = true;
            return index.copyWith(notified: true);
          }()
        else
          index,
    ];
    if (!changed) {
      return this;
    }
    return copyWith(missingAssetIndexes: indexes);
  }

  ReviewWorkspace removeMissingAssetIndex(String photoId) {
    if (_missingAssetIndexes.isEmpty) {
      return this;
    }
    final indexes = _missingAssetIndexes
        .where((index) => index.photoId != photoId)
        .toList(growable: false);
    if (indexes.length == _missingAssetIndexes.length) {
      return this;
    }
    return copyWith(missingAssetIndexes: indexes);
  }

  ReviewWorkspace updateAssetById(
    String photoId,
    ReviewAsset Function(ReviewAsset asset) update,
  ) {
    final index = _assets.indexWhere((asset) => asset.photo.id == photoId);
    if (index == -1) {
      return this;
    }

    final updatedAsset = update(_assets[index]);
    if (identical(updatedAsset, _assets[index])) {
      return this;
    }

    final assets = [..._assets];
    assets[index] = updatedAsset;
    return copyWith(
      assets: assets,
      groups: _buildGroups(
        session.id,
        assets,
        _analysisResults,
        DateTime.now(),
      ),
    );
  }

  static ({int width, int height, bool estimated}) _dimensionsForSelected(
    SelectedGalleryAsset selected,
    int index,
  ) {
    final selectedWidth = selected.width;
    final selectedHeight = selected.height;
    if (selectedWidth != null &&
        selectedHeight != null &&
        selectedWidth > 0 &&
        selectedHeight > 0) {
      return (width: selectedWidth, height: selectedHeight, estimated: false);
    }

    final bytes = selected.analysisBytes ?? selected.previewBytes;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final image = img.decodeImage(bytes);
        if (image != null && image.width > 0 && image.height > 0) {
          return (width: image.width, height: image.height, estimated: false);
        }
      } catch (_) {
        return _fallbackDimensions(index);
      }
    }

    return _fallbackDimensions(index);
  }

  static ({DateTime value, bool estimated}) _createdAtForSelected(
    SelectedGalleryAsset selected,
    DateTime importedAt,
    int index,
  ) {
    if (selected.createdAt != null) {
      return (value: selected.createdAt!, estimated: false);
    }
    return (
      value:
          selected.updatedAt ?? importedAt.add(Duration(microseconds: index)),
      estimated: true,
    );
  }

  static List<SelectedGalleryAsset> _sortSelectedAssetsForImport(
    List<SelectedGalleryAsset> selectedAssets,
  ) {
    final entries = selectedAssets.asMap().entries.toList(growable: false);
    entries.sort((a, b) {
      final aTime = a.value.createdAt ?? a.value.updatedAt;
      final bTime = b.value.createdAt ?? b.value.updatedAt;
      if (aTime == null && bTime == null) {
        return a.key.compareTo(b.key);
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      final byTime = aTime.compareTo(bTime);
      if (byTime != 0) {
        return byTime;
      }
      return a.key.compareTo(b.key);
    });
    return [for (final entry in entries) entry.value];
  }

  static ({int width, int height, bool estimated}) _fallbackDimensions(
    int index,
  ) {
    const dimensions = [
      (width: 3024, height: 2268),
      (width: 2268, height: 3024),
      (width: 2560, height: 2560),
      (width: 4032, height: 2268),
      (width: 2268, height: 4032),
      (width: 3200, height: 2400),
      (width: 2400, height: 3200),
      (width: 3000, height: 2100),
      (width: 2100, height: 3000),
    ];
    final dimension = dimensions[index % dimensions.length];
    return (width: dimension.width, height: dimension.height, estimated: true);
  }

  static const _nearDuplicateTightHashDistance = 4;
  static const _nearDuplicateLooseTimeWindow = Duration(minutes: 3);
  static const _nearDuplicateBrightnessDelta = 0.16;
  static const _nearDuplicateAspectDelta = 0.12;
  static const _nearDuplicateHardTimeWindow = Duration(minutes: 30);
  static const _nearDuplicateMinimumStructuralSimilarity = 0.82;
  static const _nearDuplicateMinimumLayoutSimilarity = 0.74;
  static const _nearDuplicateMinimumSsimSimilarity = 0.58;
  static const _nearDuplicateTightSsimFloor = 0.64;
  static const _nearDuplicateHardColorFloor = 0.66;
  static const _nearDuplicateMinimumColorSimilarity = 0.74;
  static const _nearDuplicateStrongCompositeSimilarity = 0.9;
  static const _nearDuplicateLooseCompositeSimilarity = 0.85;
  static const _nearDuplicateTemporalSceneWindow = Duration(minutes: 3);
  static const _nearDuplicateTemporalSceneEstimatedWindow = Duration(
    seconds: 1,
  );
  static const _nearDuplicateTemporalSceneBrightnessDelta = 0.14;
  static const _nearDuplicateTemporalSceneStructuralFloor = 0.58;
  static const _nearDuplicateTemporalSceneLayoutFloor = 0.75;
  static const _nearDuplicateTemporalSceneEstimatedLayoutFloor = 0.82;
  static const _nearDuplicateTemporalSceneColorFloor = 0.48;
  static const _nearDuplicateTemporalSceneEstimatedColorFloor = 0.62;
  static const _nearDuplicateTemporalSceneMinimumComposite = 0.66;
  static const _nearDuplicateTemporalSceneEstimatedMinimumComposite = 0.70;
  static const _nearDuplicateTemporalSceneSimilarity = 0.86;
  static const _nearDuplicateTemporalSceneEstimatedSimilarity = 0.91;
  static const _nearDuplicateTemporalMergeWindow = Duration(minutes: 3);
  static const _nearDuplicateTemporalMergeSimilarity =
      _nearDuplicateLooseCompositeSimilarity;
  static const _nearDuplicateTemporalMergeMaxSpan = Duration(minutes: 10);
  static const _burstMaxGap = Duration(seconds: 8);
  static const _burstMaxSpan = Duration(seconds: 28);
  static const _burstAspectDelta = 0.08;
  static const _burstBrightnessDelta = 0.24;
  static const _burstMinimumColorSimilarity =
      _nearDuplicateTemporalSceneColorFloor;
  static const _burstMinimumStructuralSimilarity = 0.68;
  static const _burstMinimumLayoutSimilarity = 0.58;

  static List<SimilarGroup> _buildGroups(
    String sessionId,
    List<ReviewAsset> assets,
    List<AnalysisResult> analysisResults,
    DateTime now,
  ) {
    if (assets.isEmpty) {
      return const [];
    }

    final analysisByPhotoId = {
      for (final result in analysisResults) result.photoId: result,
    };
    final groups = <SimilarGroup>[];
    final groupedPhotoIds = <String>{};
    final visuallyAnalyzed = assets
        .where((asset) {
          final result = analysisByPhotoId[asset.photo.id];
          return result != null && _hasReliableVisualSignature(asset, result);
        })
        .toList(growable: false);
    final pairSimilarities = _nearDuplicatePairSimilarities(
      visuallyAnalyzed,
      analysisByPhotoId,
    );
    final strongPairSimilarities = _filterPairSimilarities(
      pairSimilarities,
      _nearDuplicateStrongCompositeSimilarity,
    );
    final initialNearGroups = _extractNearDuplicateGroups(
      visuallyAnalyzed,
      strongPairSimilarities,
      groupedPhotoIds,
    );
    final mergedNearGroups = _mergeTemporalNearDuplicateGroups(
      initialGroups: initialNearGroups,
      candidates: visuallyAnalyzed,
      pairSimilarities: pairSimilarities,
    );
    for (final nearMatches in mergedNearGroups) {
      groupedPhotoIds.addAll(nearMatches.map((asset) => asset.photo.id));
      groups.add(
        _groupFromAssets(
          id: 'group-${groups.length + 1}',
          sessionId: sessionId,
          assets: _sortByCaptureTime(nearMatches),
          analysisByPhotoId: analysisByPhotoId,
          groupReason: GroupReason.nearDuplicate,
          now: now,
        ),
      );
    }

    final burstCandidates =
        assets
            .where((asset) => !groupedPhotoIds.contains(asset.photo.id))
            .toList(growable: true)
          ..sort((a, b) => a.photo.createdAt.compareTo(b.photo.createdAt));

    var burst = <ReviewAsset>[];
    for (final asset in burstCandidates) {
      if (burst.isEmpty) {
        burst = [asset];
        continue;
      }

      if (_canJoinBurst(burst.first, burst.last, asset, analysisByPhotoId)) {
        burst.add(asset);
        continue;
      }

      if (burst.length >= 2) {
        groupedPhotoIds.addAll(burst.map((item) => item.photo.id));
        groups.add(
          _groupFromAssets(
            id: 'group-${groups.length + 1}',
            sessionId: sessionId,
            assets: burst,
            analysisByPhotoId: analysisByPhotoId,
            groupReason: GroupReason.burst,
            now: now,
          ),
        );
      }
      burst = [asset];
    }
    if (burst.length >= 2) {
      groupedPhotoIds.addAll(burst.map((item) => item.photo.id));
      groups.add(
        _groupFromAssets(
          id: 'group-${groups.length + 1}',
          sessionId: sessionId,
          assets: burst,
          analysisByPhotoId: analysisByPhotoId,
          groupReason: GroupReason.burst,
          now: now,
        ),
      );
    }

    for (final asset in assets) {
      if (groupedPhotoIds.contains(asset.photo.id)) {
        continue;
      }
      if (_attentionReasons([asset], analysisByPhotoId).isEmpty) {
        continue;
      }
      groups.add(
        _groupFromAssets(
          id: 'group-${groups.length + 1}',
          sessionId: sessionId,
          assets: [asset],
          analysisByPhotoId: analysisByPhotoId,
          groupReason: GroupReason.needsAttention,
          now: now,
        ),
      );
    }

    return groups;
  }

  static List<ReviewAsset> _sortByCaptureTime(List<ReviewAsset> assets) {
    return [...assets]
      ..sort((a, b) => a.photo.createdAt.compareTo(b.photo.createdAt));
  }

  static Map<String, Map<String, double>> _nearDuplicatePairSimilarities(
    List<ReviewAsset> assets,
    Map<String, AnalysisResult> analysisByPhotoId,
  ) {
    final pairSimilarities = <String, Map<String, double>>{};
    for (var i = 0; i < assets.length - 1; i += 1) {
      final a = assets[i];
      for (var j = i + 1; j < assets.length; j += 1) {
        final b = assets[j];
        final similarity = _nearDuplicateSimilarity(a, b, analysisByPhotoId);
        if (similarity <= 0) {
          continue;
        }
        pairSimilarities.putIfAbsent(
          a.photo.id,
          () => <String, double>{},
        )[b.photo.id] = similarity;
        pairSimilarities.putIfAbsent(
          b.photo.id,
          () => <String, double>{},
        )[a.photo.id] = similarity;
      }
    }
    return pairSimilarities;
  }

  static Map<String, Map<String, double>> _filterPairSimilarities(
    Map<String, Map<String, double>> pairSimilarities,
    double minimumSimilarity,
  ) {
    final filtered = <String, Map<String, double>>{};
    for (final entry in pairSimilarities.entries) {
      for (final neighbor in entry.value.entries) {
        if (neighbor.value < minimumSimilarity) {
          continue;
        }
        filtered.putIfAbsent(
          entry.key,
          () => <String, double>{},
        )[neighbor.key] = neighbor.value;
      }
    }
    return filtered;
  }

  static List<List<ReviewAsset>> _mergeTemporalNearDuplicateGroups({
    required List<List<ReviewAsset>> initialGroups,
    required List<ReviewAsset> candidates,
    required Map<String, Map<String, double>> pairSimilarities,
  }) {
    final groupedIds = {
      for (final group in initialGroups)
        for (final asset in group) asset.photo.id,
    };
    final groups = <List<ReviewAsset>>[
      for (final group in initialGroups) _sortByCaptureTime(group),
      for (final asset in candidates)
        if (!groupedIds.contains(asset.photo.id)) [asset],
    ];

    while (true) {
      groups.sort(_compareGroupsByCaptureTime);
      _TemporalGroupMerge? bestMerge;
      for (var leftIndex = 0; leftIndex < groups.length - 1; leftIndex += 1) {
        for (
          var rightIndex = leftIndex + 1;
          rightIndex < groups.length;
          rightIndex += 1
        ) {
          final merge = _temporalGroupMergeCandidate(
            groups[leftIndex],
            groups[rightIndex],
            pairSimilarities,
            leftIndex,
            rightIndex,
          );
          if (merge == null) {
            continue;
          }
          if (bestMerge == null || merge.isBetterThan(bestMerge)) {
            bestMerge = merge;
          }
        }
      }

      if (bestMerge == null) {
        break;
      }
      final merged = _sortByCaptureTime([
        ...groups[bestMerge.leftIndex],
        ...groups[bestMerge.rightIndex],
      ]);
      groups[bestMerge.leftIndex] = merged;
      groups.removeAt(bestMerge.rightIndex);
    }

    return [
      for (final group in groups)
        if (group.length >= 2) _sortByCaptureTime(group),
    ];
  }

  static _TemporalGroupMerge? _temporalGroupMergeCandidate(
    List<ReviewAsset> left,
    List<ReviewAsset> right,
    Map<String, Map<String, double>> pairSimilarities,
    int leftIndex,
    int rightIndex,
  ) {
    _TemporalGroupMerge? closest;
    for (final leftAsset in left) {
      for (final rightAsset in right) {
        final delta = _captureTimeDelta(leftAsset.photo, rightAsset.photo);
        final similarity =
            pairSimilarities[leftAsset.photo.id]?[rightAsset.photo.id] ?? 0;
        final merge = _TemporalGroupMerge(
          leftIndex: leftIndex,
          rightIndex: rightIndex,
          timeDelta: delta,
          similarity: similarity,
        );
        if (closest == null || merge.isCloserThan(closest)) {
          closest = merge;
        }
      }
    }

    final closestPair = closest;
    if (closestPair == null ||
        closestPair.timeDelta > _nearDuplicateTemporalMergeWindow ||
        closestPair.similarity < _nearDuplicateTemporalMergeSimilarity) {
      return null;
    }
    if (left.any((asset) => asset.photo.createdAtEstimated) ||
        right.any((asset) => asset.photo.createdAtEstimated)) {
      return null;
    }
    final merged = _sortByCaptureTime([...left, ...right]);
    if (_groupCaptureSpan(merged) > _nearDuplicateTemporalMergeMaxSpan) {
      return null;
    }
    return closestPair;
  }

  static int _compareGroupsByCaptureTime(
    List<ReviewAsset> a,
    List<ReviewAsset> b,
  ) {
    return a.first.photo.createdAt.compareTo(b.first.photo.createdAt);
  }

  static Duration _groupCaptureSpan(List<ReviewAsset> group) {
    if (group.length < 2) {
      return Duration.zero;
    }
    return group.last.photo.createdAt.difference(group.first.photo.createdAt);
  }

  static List<List<ReviewAsset>> _extractNearDuplicateGroups(
    List<ReviewAsset> assets,
    Map<String, Map<String, double>> pairSimilarities,
    Set<String> groupedPhotoIds,
  ) {
    final assetById = {for (final asset in assets) asset.photo.id: asset};
    final clusters = <String, Set<String>>{
      for (final asset in assets)
        if (!groupedPhotoIds.contains(asset.photo.id))
          asset.photo.id: {asset.photo.id},
    };

    while (true) {
      final ids = clusters.keys.toList(growable: false);
      if (ids.length < 2) {
        break;
      }

      String? bestLeftId;
      String? bestRightId;
      var bestSimilarity = 0.0;
      for (var i = 0; i < ids.length - 1; i += 1) {
        for (var j = i + 1; j < ids.length; j += 1) {
          final leftId = ids[i];
          final rightId = ids[j];
          final similarity = _completeLinkageSimilarity(
            clusters[leftId]!,
            clusters[rightId]!,
            pairSimilarities,
          );
          if (similarity > bestSimilarity) {
            bestLeftId = leftId;
            bestRightId = rightId;
            bestSimilarity = similarity;
          }
        }
      }

      if (bestLeftId == null || bestRightId == null || bestSimilarity <= 0) {
        break;
      }
      clusters[bestLeftId]!.addAll(clusters.remove(bestRightId)!);
    }

    return [
      for (final cluster in clusters.values)
        if (cluster.length >= 2)
          _sortByCaptureTime([
            for (final photoId in cluster) ?assetById[photoId],
          ]),
    ];
  }

  static double _completeLinkageSimilarity(
    Set<String> left,
    Set<String> right,
    Map<String, Map<String, double>> pairSimilarities,
  ) {
    var weakest = 1.0;
    for (final leftId in left) {
      for (final rightId in right) {
        final similarity =
            pairSimilarities[leftId]?[rightId] ??
            pairSimilarities[rightId]?[leftId] ??
            0.0;
        if (similarity <= 0) {
          return 0;
        }
        weakest = min(weakest, similarity);
      }
    }
    return weakest;
  }

  static double _nearDuplicateSimilarity(
    ReviewAsset a,
    ReviewAsset b,
    Map<String, AnalysisResult> analysisByPhotoId,
  ) {
    if (!_sameOrientation(a.photo, b.photo)) {
      return 0;
    }
    if ((_aspectRatio(a.photo) - _aspectRatio(b.photo)).abs() >
        _nearDuplicateAspectDelta) {
      return 0;
    }

    final aResult = analysisByPhotoId[a.photo.id];
    final bResult = analysisByPhotoId[b.photo.id];
    if (aResult == null ||
        bResult == null ||
        !_hasReliableVisualSignature(a, aResult) ||
        !_hasReliableVisualSignature(b, bResult)) {
      return 0;
    }
    final brightnessDelta = (aResult.brightnessScore - bResult.brightnessScore)
        .abs();
    if (brightnessDelta > _nearDuplicateBrightnessDelta) {
      return 0;
    }
    final timeDelta = _captureTimeDelta(a.photo, b.photo);
    if (timeDelta > _nearDuplicateHardTimeWindow) {
      return 0;
    }

    final structuralSimilarity = _structuralSimilarity(aResult, bResult);
    final colorSimilarity = _channelSimilarity(
      aResult.colorSignature,
      bResult.colorSignature,
    );
    final layoutSimilarity = _layoutSimilarity(
      aResult.luminanceSignature,
      bResult.luminanceSignature,
    );
    final ssimSimilarity = _ssimSimilarity(
      aResult.luminanceSignature,
      bResult.luminanceSignature,
    );
    final temporalSceneSimilarity = _temporalSceneSimilarity(
      a: a,
      b: b,
      timeDelta: timeDelta,
      brightnessDelta: brightnessDelta,
      structuralSimilarity: structuralSimilarity,
      colorSimilarity: colorSimilarity,
      layoutSimilarity: layoutSimilarity,
    );
    if (temporalSceneSimilarity != null) {
      return temporalSceneSimilarity;
    }

    if (structuralSimilarity != null &&
        structuralSimilarity < _nearDuplicateMinimumStructuralSimilarity) {
      return 0;
    }
    if (colorSimilarity != null) {
      if (colorSimilarity < _nearDuplicateHardColorFloor) {
        return 0;
      }
      if (colorSimilarity < _nearDuplicateMinimumColorSimilarity &&
          timeDelta > const Duration(minutes: 2)) {
        return 0;
      }
    }
    if (layoutSimilarity != null &&
        layoutSimilarity < _nearDuplicateMinimumLayoutSimilarity) {
      return 0;
    }
    if (ssimSimilarity != null &&
        ssimSimilarity < _nearDuplicateMinimumSsimSimilarity &&
        timeDelta > const Duration(seconds: 20)) {
      return 0;
    }

    final compositeSimilarity = _weightedAverage([
      if (structuralSimilarity != null)
        (weight: 0.44, value: structuralSimilarity),
      if (ssimSimilarity != null) (weight: 0.24, value: ssimSimilarity),
      if (layoutSimilarity != null) (weight: 0.18, value: layoutSimilarity),
      if (colorSimilarity != null) (weight: 0.14, value: colorSimilarity),
    ]);
    if (compositeSimilarity == null) {
      return 0;
    }
    if (compositeSimilarity >= _nearDuplicateStrongCompositeSimilarity) {
      return compositeSimilarity;
    }

    final hashDistance = _hashDistanceFromResults(aResult, bResult);
    if (hashDistance != null &&
        hashDistance <= _nearDuplicateTightHashDistance &&
        (ssimSimilarity == null ||
            ssimSimilarity >= _nearDuplicateTightSsimFloor)) {
      return compositeSimilarity;
    }

    if (timeDelta <= _nearDuplicateLooseTimeWindow &&
        compositeSimilarity >= _nearDuplicateLooseCompositeSimilarity) {
      return compositeSimilarity;
    }
    return 0;
  }

  static double? _temporalSceneSimilarity({
    required ReviewAsset a,
    required ReviewAsset b,
    required Duration timeDelta,
    required double brightnessDelta,
    required double? structuralSimilarity,
    required double? colorSimilarity,
    required double? layoutSimilarity,
  }) {
    if (a.photo.createdAtEstimated != b.photo.createdAtEstimated) {
      return null;
    }
    if (structuralSimilarity == null ||
        colorSimilarity == null ||
        layoutSimilarity == null) {
      return null;
    }

    final usesEstimatedTime =
        a.photo.createdAtEstimated && b.photo.createdAtEstimated;
    final timeWindow = usesEstimatedTime
        ? _nearDuplicateTemporalSceneEstimatedWindow
        : _nearDuplicateTemporalSceneWindow;
    if (timeDelta > timeWindow ||
        brightnessDelta > _nearDuplicateTemporalSceneBrightnessDelta) {
      return null;
    }

    final layoutFloor = usesEstimatedTime
        ? _nearDuplicateTemporalSceneEstimatedLayoutFloor
        : _nearDuplicateTemporalSceneLayoutFloor;
    final colorFloor = usesEstimatedTime
        ? _nearDuplicateTemporalSceneEstimatedColorFloor
        : _nearDuplicateTemporalSceneColorFloor;
    if (structuralSimilarity < _nearDuplicateTemporalSceneStructuralFloor ||
        layoutSimilarity < layoutFloor ||
        colorSimilarity < colorFloor) {
      return null;
    }

    final sceneComposite = _weightedAverage([
      (weight: 0.42, value: structuralSimilarity),
      (weight: 0.36, value: layoutSimilarity),
      (weight: 0.22, value: colorSimilarity),
    ]);
    if (sceneComposite == null) {
      return null;
    }

    final minimumComposite = usesEstimatedTime
        ? _nearDuplicateTemporalSceneEstimatedMinimumComposite
        : _nearDuplicateTemporalSceneMinimumComposite;
    if (sceneComposite < minimumComposite) {
      return null;
    }

    final boostedSimilarity = usesEstimatedTime
        ? _nearDuplicateTemporalSceneEstimatedSimilarity
        : _nearDuplicateTemporalSceneSimilarity;
    return max(sceneComposite, boostedSimilarity);
  }

  static bool _canJoinBurst(
    ReviewAsset anchor,
    ReviewAsset previous,
    ReviewAsset candidate,
    Map<String, AnalysisResult> analysisByPhotoId,
  ) {
    if (anchor.photo.createdAtEstimated ||
        previous.photo.createdAtEstimated ||
        candidate.photo.createdAtEstimated) {
      return false;
    }
    if (!_sameOrientation(anchor.photo, candidate.photo)) {
      return false;
    }
    if ((_aspectRatio(anchor.photo) - _aspectRatio(candidate.photo)).abs() >
        _burstAspectDelta) {
      return false;
    }
    if (_captureTimeDelta(previous.photo, candidate.photo) > _burstMaxGap ||
        _captureTimeDelta(anchor.photo, candidate.photo) > _burstMaxSpan) {
      return false;
    }

    final anchorResult = analysisByPhotoId[anchor.photo.id];
    final candidateResult = analysisByPhotoId[candidate.photo.id];
    if (anchorResult != null &&
        candidateResult != null &&
        _hasReliableVisualSignature(anchor, anchorResult) &&
        _hasReliableVisualSignature(candidate, candidateResult)) {
      if ((anchorResult.brightnessScore - candidateResult.brightnessScore)
              .abs() >
          _burstBrightnessDelta) {
        return false;
      }
      final colorSimilarity = _channelSimilarity(
        anchorResult.colorSignature,
        candidateResult.colorSignature,
      );
      if (colorSimilarity != null &&
          colorSimilarity < _burstMinimumColorSimilarity) {
        return false;
      }
      final structuralSimilarity = _structuralSimilarity(
        anchorResult,
        candidateResult,
      );
      if (structuralSimilarity != null &&
          structuralSimilarity < _burstMinimumStructuralSimilarity) {
        return false;
      }
      final layoutSimilarity = _layoutSimilarity(
        anchorResult.luminanceSignature,
        candidateResult.luminanceSignature,
      );
      if (layoutSimilarity != null &&
          layoutSimilarity < _burstMinimumLayoutSimilarity) {
        return false;
      }
      return structuralSimilarity != null || layoutSimilarity != null;
    }

    return !anchor.photo.dimensionsEstimated &&
        !previous.photo.dimensionsEstimated &&
        !candidate.photo.dimensionsEstimated;
  }

  static bool _hasReliableVisualSignature(
    ReviewAsset asset,
    AnalysisResult result,
  ) {
    final hasModernSignature =
        result.averageHashHex != null ||
        result.differenceHashHex != null ||
        result.perceptualHashHex != null ||
        result.waveletHashHex != null;
    if (!hasModernSignature && result.similarityHash == 0) {
      return false;
    }
    return !_looksLikeLegacyPlaceholderAnalysis(asset, result);
  }

  static bool _looksLikeLegacyPlaceholderAnalysis(
    ReviewAsset asset,
    AnalysisResult result,
  ) {
    if (asset.previewBytes != null || asset.analysisBytes != null) {
      return false;
    }
    if (result.similarityHash < 1000 || result.similarityHash >= 2000) {
      return false;
    }
    final flags = result.qualityFlags;
    final defaultClear =
        _almostEqual(result.blurScore, 0.82) &&
        _almostEqual(result.brightnessScore, 0.56) &&
        flags.isEmpty;
    final defaultAttention =
        _almostEqual(result.blurScore, 0.42) &&
        _almostEqual(result.brightnessScore, 0.34) &&
        flags.length == 1 &&
        flags.single == QualityFlag.possibleBlur;
    return result.exposureFlag == ExposureFlag.normal &&
        (defaultClear || defaultAttention);
  }

  static bool _almostEqual(double a, double b) {
    return (a - b).abs() < 0.000001;
  }

  static Duration _captureTimeDelta(PhotoAsset a, PhotoAsset b) {
    final delta = a.createdAt.difference(b.createdAt).abs();
    return delta;
  }

  static bool _sameOrientation(PhotoAsset a, PhotoAsset b) {
    return (a.width >= a.height) == (b.width >= b.height);
  }

  static double _aspectRatio(PhotoAsset asset) {
    if (asset.width <= 0 || asset.height <= 0) {
      return 1;
    }
    return asset.width / asset.height;
  }

  static int _hashDistance(int a, int b) {
    var value = BigInt.from(a) ^ BigInt.from(b);
    var distance = 0;
    while (value != BigInt.zero) {
      if ((value & BigInt.one) == BigInt.one) {
        distance += 1;
      }
      value = value >> 1;
    }
    return distance;
  }

  static int? _hashDistanceFromResults(AnalysisResult a, AnalysisResult b) {
    final distances = <int>[];
    final averageDistance = _hashDistanceHex(
      a.averageHashHex,
      b.averageHashHex,
    );
    if (averageDistance != null) {
      distances.add(averageDistance);
    }
    final differenceDistance = _hashDistanceHex(
      a.differenceHashHex,
      b.differenceHashHex,
    );
    if (differenceDistance != null) {
      distances.add(differenceDistance);
    }
    final perceptualDistance = _hashDistanceHex(
      a.perceptualHashHex,
      b.perceptualHashHex,
    );
    if (perceptualDistance != null) {
      distances.add(perceptualDistance);
    }
    final waveletDistance = _hashDistanceHex(
      a.waveletHashHex,
      b.waveletHashHex,
    );
    if (waveletDistance != null) {
      distances.add(waveletDistance);
    }
    if (distances.isNotEmpty) {
      distances.sort();
      return distances.first;
    }
    if (a.similarityHash == 0 || b.similarityHash == 0) {
      return null;
    }
    return _hashDistance(a.similarityHash, b.similarityHash);
  }

  static int? _hashDistanceHex(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) {
      return null;
    }
    final aValue = BigInt.tryParse(a, radix: 16);
    final bValue = BigInt.tryParse(b, radix: 16);
    if (aValue == null || bValue == null) {
      return null;
    }
    var value = aValue ^ bValue;
    var distance = 0;
    while (value != BigInt.zero) {
      if ((value & BigInt.one) == BigInt.one) {
        distance += 1;
      }
      value = value >> 1;
    }
    return distance;
  }

  static double? _hashSimilarityHex(String? a, String? b) {
    final distance = _hashDistanceHex(a, b);
    if (distance == null) {
      return null;
    }
    return max(0.0, 1 - distance / 64);
  }

  static double? _structuralSimilarity(AnalysisResult a, AnalysisResult b) {
    final similarity = _weightedAverage([
      if (_hashSimilarityHex(a.averageHashHex, b.averageHashHex)
          case final value?)
        (weight: 0.24, value: value),
      if (_hashSimilarityHex(a.differenceHashHex, b.differenceHashHex)
          case final value?)
        (weight: 0.42, value: value),
      if (_hashSimilarityHex(a.perceptualHashHex, b.perceptualHashHex)
          case final value?)
        (weight: 0.28, value: value),
      if (_hashSimilarityHex(a.waveletHashHex, b.waveletHashHex)
          case final value?)
        (weight: 0.24, value: value),
    ]);
    if (similarity != null) {
      return similarity;
    }
    if (a.similarityHash == 0 || b.similarityHash == 0) {
      return null;
    }
    final legacyDistance = _hashDistance(a.similarityHash, b.similarityHash);
    return max(0.0, 1 - legacyDistance / 31);
  }

  static double? _weightedAverage(
    List<({double weight, double value})> contributions,
  ) {
    if (contributions.isEmpty) {
      return null;
    }
    var totalWeight = 0.0;
    var weightedValue = 0.0;
    for (final contribution in contributions) {
      totalWeight += contribution.weight;
      weightedValue += contribution.weight * contribution.value;
    }
    if (totalWeight <= 0) {
      return null;
    }
    return weightedValue / totalWeight;
  }

  static double? _channelSimilarity(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return null;
    }
    if (a.length == 144) {
      return _histogramIntersectionSimilarity(a, b);
    }
    var totalDelta = 0.0;
    for (var index = 0; index < a.length; index += 1) {
      totalDelta += (a[index] - b[index]).abs() / 255;
    }
    final normalizedDelta = totalDelta / a.length;
    return max(0.0, 1 - normalizedDelta);
  }

  static double? _histogramIntersectionSimilarity(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return null;
    }
    var intersection = 0.0;
    var total = 0.0;
    for (var index = 0; index < a.length; index += 1) {
      final av = a[index].clamp(0, 255).toDouble();
      final bv = b[index].clamp(0, 255).toDouble();
      intersection += min(av, bv);
      total += max(av, bv);
    }
    if (total <= 0) {
      return null;
    }
    return (intersection / total).clamp(0.0, 1.0);
  }

  static double? _layoutSimilarity(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return null;
    }
    var totalDelta = 0.0;
    for (var index = 0; index < a.length; index += 1) {
      totalDelta += (a[index] - b[index]).abs() / 255;
    }
    final normalizedDelta = totalDelta / a.length;
    return max(0.0, 1 - normalizedDelta);
  }

  static double? _ssimSimilarity(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return null;
    }
    final size = sqrt(a.length).round();
    if (size < 2 || size * size != a.length) {
      return null;
    }

    final windowSize = size >= 16 ? 4 : size;
    var total = 0.0;
    var count = 0;
    for (var y = 0; y <= size - windowSize; y += windowSize) {
      for (var x = 0; x <= size - windowSize; x += windowSize) {
        total += _ssimWindow(a, b, size, x, y, windowSize);
        count += 1;
      }
    }
    if (count == 0) {
      return null;
    }
    return (total / count).clamp(0.0, 1.0);
  }

  static double _ssimWindow(
    List<int> a,
    List<int> b,
    int width,
    int startX,
    int startY,
    int size,
  ) {
    final n = size * size;
    var meanA = 0.0;
    var meanB = 0.0;
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final index = (startY + y) * width + startX + x;
        meanA += a[index] / 255;
        meanB += b[index] / 255;
      }
    }
    meanA /= n;
    meanB /= n;

    var varianceA = 0.0;
    var varianceB = 0.0;
    var covariance = 0.0;
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final index = (startY + y) * width + startX + x;
        final av = a[index] / 255 - meanA;
        final bv = b[index] / 255 - meanB;
        varianceA += av * av;
        varianceB += bv * bv;
        covariance += av * bv;
      }
    }
    varianceA /= n;
    varianceB /= n;
    covariance /= n;

    const c1 = 0.0001;
    const c2 = 0.0009;
    final luminance = 2 * meanA * meanB + c1;
    final contrastStructure = 2 * covariance + c2;
    final denominator =
        (meanA * meanA + meanB * meanB + c1) * (varianceA + varianceB + c2);
    if (denominator <= 0) {
      return 0;
    }
    return (luminance * contrastStructure / denominator).clamp(0.0, 1.0);
  }

  static SimilarGroup _groupFromAssets({
    required String id,
    required String sessionId,
    required List<ReviewAsset> assets,
    required Map<String, AnalysisResult> analysisByPhotoId,
    required GroupReason groupReason,
    required DateTime now,
  }) {
    return SimilarGroup(
      id: id,
      sessionId: sessionId,
      photoIds: assets.map((asset) => asset.photo.id).toList(growable: false),
      groupReason: groupReason,
      attentionReasons: _attentionReasons(assets, analysisByPhotoId),
      reviewStatus: ReviewStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
  }

  static List<QualityFlag> _attentionReasons(
    List<ReviewAsset> assets,
    Map<String, AnalysisResult> analysisByPhotoId,
  ) {
    final reasons = <QualityFlag>[];
    for (final asset in assets) {
      final result = analysisByPhotoId[asset.photo.id];
      if (result == null) {
        continue;
      }
      for (final flag in result.qualityFlags) {
        if (!reasons.contains(flag)) {
          reasons.add(flag);
        }
      }
    }
    return reasons;
  }

  final ReviewSession session;
  final List<ReviewAsset> _assets;
  final List<AnalysisResult> _analysisResults;
  final List<SimilarGroup> _groups;
  final List<MissingAssetIndex> _missingAssetIndexes;
  final List<PhotoSeriesAppraisal> _seriesAppraisals;
  final ObserveViewPreferences observeViewPreferences;
  final AppreciateViewPreferences appreciateViewPreferences;

  UnmodifiableListView<ReviewAsset> get assets => UnmodifiableListView(_assets);

  UnmodifiableListView<AnalysisResult> get analysisResults =>
      UnmodifiableListView(_analysisResults);

  UnmodifiableListView<SimilarGroup> get groups =>
      UnmodifiableListView(_groups);

  UnmodifiableListView<MissingAssetIndex> get missingAssetIndexes =>
      UnmodifiableListView(_missingAssetIndexes);

  UnmodifiableListView<PhotoSeriesAppraisal> get seriesAppraisals =>
      UnmodifiableListView(_seriesAppraisals);

  PhotoSeriesAppraisal? seriesAppraisalFor(SeriesAppraisalBand band) {
    for (final appraisal in _seriesAppraisals) {
      if (appraisal.band == band) {
        return appraisal;
      }
    }
    return null;
  }

  ReviewWorkspace copyWith({
    ReviewSession? session,
    List<ReviewAsset>? assets,
    List<AnalysisResult>? analysisResults,
    List<SimilarGroup>? groups,
    List<MissingAssetIndex>? missingAssetIndexes,
    List<PhotoSeriesAppraisal>? seriesAppraisals,
    ObserveViewPreferences? observeViewPreferences,
    AppreciateViewPreferences? appreciateViewPreferences,
  }) {
    return ReviewWorkspace(
      session: session ?? this.session,
      assets: assets ?? _assets,
      analysisResults: analysisResults ?? _analysisResults,
      groups: groups ?? _groups,
      missingAssetIndexes: missingAssetIndexes ?? _missingAssetIndexes,
      seriesAppraisals: seriesAppraisals ?? _seriesAppraisals,
      observeViewPreferences:
          observeViewPreferences ?? this.observeViewPreferences,
      appreciateViewPreferences:
          appreciateViewPreferences ?? this.appreciateViewPreferences,
    );
  }

  ReviewAsset? assetById(String id) {
    for (final asset in _assets) {
      if (asset.photo.id == id) {
        return asset;
      }
    }
    return null;
  }
}

class _TemporalGroupMerge {
  const _TemporalGroupMerge({
    required this.leftIndex,
    required this.rightIndex,
    required this.timeDelta,
    required this.similarity,
  });

  final int leftIndex;
  final int rightIndex;
  final Duration timeDelta;
  final double similarity;

  bool isCloserThan(_TemporalGroupMerge other) {
    final timeComparison = timeDelta.compareTo(other.timeDelta);
    if (timeComparison != 0) {
      return timeComparison < 0;
    }
    return similarity > other.similarity;
  }

  bool isBetterThan(_TemporalGroupMerge other) => isCloserThan(other);
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _jsonMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [for (final item in value) _jsonMap(item)];
}

String _stringValue(Object? value, String fallback) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return fallback;
}

int _intValue(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

bool _boolValue(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

DateTime _dateValue(Object? value, DateTime fallback) {
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}
