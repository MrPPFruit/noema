import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/photo_decision.dart';
import 'package:noema/core/models/series_appraisal.dart';
import 'package:noema/core/models/similar_group.dart';
import 'package:noema/core/storage/noema_local_store.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

// ponytail: per-space guard for the current single-snapshot store; split
// workspaces into lazy-loaded records before raising this ceiling.
const noemaWorkspaceSoftPhotoLimit = 500;
const noemaWorkspaceHardPhotoLimit = 1000;
const noemaWorkspacePreviewCacheLimit = 64;
const _noemaWorkspaceBackgroundPreviewMaxSize = 3072;
const _noemaWorkspaceCaptureMetadataRefreshStartDelay = Duration(
  milliseconds: 700,
);
const _noemaWorkspaceCaptureMetadataRefreshItemGap = Duration(milliseconds: 64);

enum ReviewWorkspaceImportResult { applied, empty, unchanged, tooManyPhotos }

class ReviewWorkspaceScaleSnapshot {
  const ReviewWorkspaceScaleSnapshot({
    required this.workspaceCount,
    required this.totalPhotoCount,
    required this.largestWorkspacePhotoCount,
    required this.activePhotoCount,
  });

  final int workspaceCount;
  final int totalPhotoCount;
  final int largestWorkspacePhotoCount;
  final int activePhotoCount;

  bool get hasLargeWorkspace =>
      largestWorkspacePhotoCount >= noemaWorkspaceSoftPhotoLimit;

  bool get hasBlockedWorkspace =>
      largestWorkspacePhotoCount >= noemaWorkspaceHardPhotoLimit;
}

class ReviewWorkspaceController extends ChangeNotifier {
  ReviewWorkspaceController({
    NoemaLocalStore? localStore,
    NoemaMediaPicker mediaPicker = const NoemaMediaPicker(),
    bool backgroundPreviewCachingEnabled = false,
    Duration backgroundPreviewStartDelay = const Duration(milliseconds: 700),
    Duration backgroundPreviewItemGap = const Duration(milliseconds: 64),
  }) : this._(
         localStore: localStore,
         mediaPicker: mediaPicker,
         backgroundPreviewCachingEnabled: backgroundPreviewCachingEnabled,
         backgroundPreviewStartDelay: backgroundPreviewStartDelay,
         backgroundPreviewItemGap: backgroundPreviewItemGap,
       );

  ReviewWorkspaceController._({
    this.localStore,
    this._mediaPicker = const NoemaMediaPicker(),
    this._backgroundPreviewCachingEnabled = false,
    this._backgroundPreviewStartDelay = const Duration(milliseconds: 700),
    this._backgroundPreviewItemGap = const Duration(milliseconds: 64),
  }) : _emptyWorkspace = ReviewWorkspace.empty();

  final ReviewWorkspace _emptyWorkspace;
  final NoemaLocalStore? localStore;
  final NoemaMediaPicker _mediaPicker;
  final bool _backgroundPreviewCachingEnabled;
  final Duration _backgroundPreviewStartDelay;
  final Duration _backgroundPreviewItemGap;
  final List<ReviewWorkspace> _workspaces = [];
  String? _activeGroupId;
  String? _activeWorkspaceId;
  Timer? _saveTimer;
  DateTime? _backgroundPreviewDeferredUntil;
  int _backgroundPreviewGeneration = 0;
  int _captureMetadataRefreshGeneration = 0;
  bool _disposed = false;
  final Map<String, Map<String, PhotoDecision>> _decisionsByWorkspaceId = {};
  final Map<String, Queue<String>> _previewCacheOrderByWorkspaceId = {};
  final Set<String> _captureMetadataRefreshAttempts = {};
  final Set<String> _captureMetadataRefreshTimestamps = {};

  ReviewWorkspace get workspace => _activeWorkspace ?? _emptyWorkspace;

  UnmodifiableListView<ReviewWorkspace> get workspaces =>
      UnmodifiableListView(_workspaces);

  String? get activeWorkspaceId => _activeWorkspaceId;

  SimilarGroup? get activeGroup {
    final workspace = this.workspace;
    if (_activeGroupId == null) {
      return workspace.groups.isEmpty ? null : workspace.groups.first;
    }

    for (final group in workspace.groups) {
      if (group.id == _activeGroupId) {
        return group;
      }
    }
    return workspace.groups.isEmpty ? null : workspace.groups.first;
  }

  UnmodifiableMapView<String, PhotoDecision> get decisions =>
      UnmodifiableMapView(_activeDecisionMap);

  Map<Decision, int> get decisionCounts {
    final activeDecisions = _activeDecisionMap;
    return {
      for (final decision in Decision.values)
        decision: activeDecisions.values
            .where((photoDecision) => photoDecision.decision == decision)
            .length,
    };
  }

  UnmodifiableListView<MissingAssetIndex> get missingAssetIndexes =>
      UnmodifiableListView(_visibleMissingAssetIndexes());

  UnmodifiableListView<MissingAssetIndex> get unnotifiedMissingAssetIndexes =>
      UnmodifiableListView(
        _visibleMissingAssetIndexes()
            .where((index) => !index.notified)
            .toList(growable: false),
      );

  int get undecidedCount => workspace.assets.length - _activeDecisionMap.length;

  bool get hasActionableCullGroups =>
      _hasActionableCullGroups(workspace, _activeDecisionMap.keys);

  ReviewWorkspaceScaleSnapshot get scaleSnapshot {
    var totalPhotoCount = 0;
    var largestWorkspacePhotoCount = 0;
    for (final workspace in _workspaces) {
      final count = workspace.assets.length;
      totalPhotoCount += count;
      if (count > largestWorkspacePhotoCount) {
        largestWorkspacePhotoCount = count;
      }
    }

    return ReviewWorkspaceScaleSnapshot(
      workspaceCount: _workspaces.length,
      totalPhotoCount: totalPhotoCount,
      largestWorkspacePhotoCount: largestWorkspacePhotoCount,
      activePhotoCount: workspace.assets.length,
    );
  }

  bool _hasDisplayableCache(String photoId) {
    final asset = workspace.assetById(photoId);
    final thumbnailPath = asset?.photo.thumbnailPath;
    final previewPath = asset?.photo.previewPath;
    return thumbnailPath != null && thumbnailPath.isNotEmpty ||
        previewPath != null && previewPath.isNotEmpty;
  }

  List<MissingAssetIndex> _visibleMissingAssetIndexes() {
    return workspace.missingAssetIndexes
        .where((index) => !_hasDisplayableCache(index.photoId))
        .toList(growable: false);
  }

  Future<void> restore() async {
    final store = localStore;
    if (store == null) {
      return;
    }
    final snapshot = await store.readSnapshot();
    if (snapshot == null) {
      return;
    }

    _saveTimer?.cancel();
    _saveTimer = null;
    _workspaces
      ..clear()
      ..addAll(snapshot.workspaces);
    _decisionsByWorkspaceId
      ..clear()
      ..addAll({
        for (final entry in snapshot.decisionsByWorkspaceId.entries)
          entry.key: Map<String, PhotoDecision>.from(entry.value),
      });
    _previewCacheOrderByWorkspaceId
      ..clear()
      ..addEntries(
        _workspaces.map(
          (workspace) => MapEntry(
            workspace.session.id,
            Queue<String>.of(_previewCachedPhotoIds(workspace)),
          ),
        ),
      );
    _activeWorkspaceId = _validWorkspaceId(snapshot.activeWorkspaceId);
    _syncActiveGroupToActiveWorkspace();
    _sanitizeDecisions();
    notifyListeners();
    _scheduleCaptureMetadataRefresh(_activeWorkspaceId);
  }

  ReviewWorkspace? get _activeWorkspace {
    final activeId = _activeWorkspaceId;
    if (activeId == null) {
      return null;
    }
    final index = _workspaces.indexWhere(
      (workspace) => workspace.session.id == activeId,
    );
    if (index == -1) {
      return null;
    }
    return _workspaces[index];
  }

  Map<String, PhotoDecision> get _activeDecisionMap {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return const {};
    }
    return _decisionsByWorkspaceId.putIfAbsent(
      activeWorkspace.session.id,
      () => {},
    );
  }

  bool activateWorkspace(String workspaceId) {
    final index = _workspaces.indexWhere(
      (workspace) => workspace.session.id == workspaceId,
    );
    if (index == -1) {
      return false;
    }
    if (_activeWorkspaceId == workspaceId) {
      return true;
    }
    _activeWorkspaceId = workspaceId;
    _syncActiveGroupToActiveWorkspace();
    _persistSoon();
    notifyListeners();
    _scheduleCaptureMetadataRefresh(workspaceId);
    return true;
  }

  ReviewWorkspaceImportResult loadSelectedAssets(
    List<SelectedGalleryAsset> assets, {
    String? name,
  }) {
    final importableAssets = _importableAssets(assets);
    if (importableAssets.isEmpty) {
      return ReviewWorkspaceImportResult.empty;
    }
    if (importableAssets.length > noemaWorkspaceHardPhotoLimit) {
      return ReviewWorkspaceImportResult.tooManyPhotos;
    }
    final nextWorkspace = ReviewWorkspace.fromSelectedAssets(
      importableAssets,
      name: name,
    );
    _workspaces.insert(0, nextWorkspace);
    _activeWorkspaceId = nextWorkspace.session.id;
    _activeGroupId = nextWorkspace.groups.isEmpty
        ? null
        : nextWorkspace.groups.first.id;
    _decisionsByWorkspaceId[nextWorkspace.session.id] = {};
    _persistSoon();
    notifyListeners();
    _scheduleBackgroundPreviewCaching(nextWorkspace.session.id);
    _scheduleCaptureMetadataRefresh(nextWorkspace.session.id);
    return ReviewWorkspaceImportResult.applied;
  }

  ReviewWorkspaceImportResult appendSelectedAssets(
    List<SelectedGalleryAsset> assets,
  ) {
    final importableAssets = _importableAssets(assets);
    if (importableAssets.isEmpty) {
      return ReviewWorkspaceImportResult.empty;
    }
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return loadSelectedAssets(importableAssets);
    }

    final incomingCount = _newPlatformAssetCount(
      activeWorkspace,
      importableAssets,
    );
    if (incomingCount == 0) {
      return ReviewWorkspaceImportResult.unchanged;
    }
    if (activeWorkspace.assets.length + incomingCount >
        noemaWorkspaceHardPhotoLimit) {
      return ReviewWorkspaceImportResult.tooManyPhotos;
    }

    final nextWorkspace = activeWorkspace.appendSelectedAssets(
      importableAssets,
    );
    if (identical(nextWorkspace, activeWorkspace)) {
      return ReviewWorkspaceImportResult.unchanged;
    }

    _replaceWorkspace(nextWorkspace);
    _activeGroupId = nextWorkspace.groups.isEmpty
        ? null
        : nextWorkspace.groups.first.id;
    _persistSoon();
    notifyListeners();
    _scheduleBackgroundPreviewCaching(nextWorkspace.session.id);
    _scheduleCaptureMetadataRefresh(nextWorkspace.session.id);
    return ReviewWorkspaceImportResult.applied;
  }

  void deleteWorkspace(String workspaceId) {
    final removedIndex = _workspaces.indexWhere(
      (workspace) => workspace.session.id == workspaceId,
    );
    if (removedIndex == -1) {
      return;
    }
    final removedCachePaths = _cachedPathsForAssets(
      _workspaces[removedIndex].assets,
    );
    _workspaces.removeAt(removedIndex);
    _decisionsByWorkspaceId.remove(workspaceId);
    _previewCacheOrderByWorkspaceId.remove(workspaceId);
    if (_activeWorkspaceId == workspaceId) {
      final nextActive = _workspaces.firstOrNull;
      _activeWorkspaceId = nextActive?.session.id;
      _activeGroupId = nextActive == null || nextActive.groups.isEmpty
          ? null
          : nextActive.groups.first.id;
    }
    _deleteUnreferencedCachedFiles(removedCachePaths);
    _persistSoon();
    notifyListeners();
  }

  void renameWorkspace(String name) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == activeWorkspace.session.name) {
      return;
    }

    _replaceWorkspace(
      activeWorkspace.copyWith(
        session: activeWorkspace.session.copyWith(
          name: trimmed,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    _persistSoon();
    notifyListeners();
  }

  void setObserveViewPreferences(ObserveViewPreferences preferences) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null ||
        activeWorkspace.observeViewPreferences == preferences) {
      return;
    }

    _replaceWorkspace(
      activeWorkspace.copyWith(observeViewPreferences: preferences),
    );
    _persistSoon();
    notifyListeners();
  }

  void setAppreciateViewPreferences(AppreciateViewPreferences preferences) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null ||
        activeWorkspace.appreciateViewPreferences == preferences) {
      return;
    }

    _replaceWorkspace(
      activeWorkspace.copyWith(appreciateViewPreferences: preferences),
    );
    _persistSoon();
    notifyListeners();
  }

  void removeAssetsByIds(
    Set<String> photoIds, {
    bool deleteCachedFiles = true,
  }) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final nextWorkspace = activeWorkspace.removeAssetsByIds(photoIds);
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }
    final removedAssets = activeWorkspace.assets.where(
      (asset) => photoIds.contains(asset.photo.id),
    );
    final removedCachePaths = _cachedPathsForAssets(removedAssets);

    _replaceWorkspace(nextWorkspace);
    _activeDecisionMap.removeWhere((photoId, _) => photoIds.contains(photoId));
    _activeGroupId = nextWorkspace.groups.isEmpty
        ? null
        : nextWorkspace.groups.first.id;
    if (deleteCachedFiles) {
      _deleteUnreferencedCachedFiles(removedCachePaths);
    }
    _persistSoon();
    notifyListeners();
  }

  void markAssetMissing(String photoId) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final asset = activeWorkspace.assetById(photoId);
    if (asset == null) {
      return;
    }

    final nextWorkspace = activeWorkspace.upsertMissingAssetIndex(
      photoId: photoId,
      displayName: asset.displayName,
    );
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void markMissingAssetIndexesNotified(Set<String> photoIds) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final nextWorkspace = activeWorkspace.markMissingAssetIndexesNotified(
      photoIds,
    );
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void clearMissingAssetIndexes(Set<String> photoIds) {
    removeAssetsByIds(photoIds);
  }

  void updateAssetMetadata(String photoId, SelectedGalleryAsset metadata) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final nextWorkspace = activeWorkspace.updateAssetById(photoId, (asset) {
      final width = metadata.width;
      final height = metadata.height;
      final hasDimensions =
          width != null && height != null && width > 0 && height > 0;
      final nextPhoto = asset.photo.copyWith(
        width: hasDimensions ? width : asset.photo.width,
        height: hasDimensions ? height : asset.photo.height,
        createdAt: metadata.createdAt ?? asset.photo.createdAt,
        updatedAt: metadata.updatedAt ?? asset.photo.updatedAt,
        mimeType: metadata.mimeType ?? asset.photo.mimeType,
        fileSize: metadata.fileSize ?? asset.photo.fileSize,
        exif: metadata.exif ?? asset.photo.exif,
        dimensionsEstimated: hasDimensions
            ? false
            : asset.photo.dimensionsEstimated,
        createdAtEstimated: metadata.createdAt == null
            ? asset.photo.createdAtEstimated
            : false,
      );
      return asset.copyWith(
        photo: nextPhoto,
        displayName: metadata.name.isNotEmpty
            ? metadata.name
            : asset.displayName,
      );
    });
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void updateAssetPreviewPath(String photoId, String previewPath) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null || previewPath.isEmpty) {
      return;
    }
    final currentAsset = activeWorkspace.assetById(photoId);
    if (currentAsset == null) {
      return;
    }
    if (currentAsset.photo.previewPath == previewPath) {
      return;
    }

    final nextWorkspace = _updateCachedAssetPath(
      activeWorkspace,
      photoId,
      (asset) =>
          asset.copyWith(photo: asset.photo.copyWith(previewPath: previewPath)),
    ).removeMissingAssetIndex(photoId);
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }
    final pruned = _pruneWorkspacePreviewCache(
      nextWorkspace,
      touchedPhotoId: photoId,
    );

    _replaceWorkspace(pruned.workspace);
    _deleteUnreferencedCachedFiles(pruned.removedPaths);
    _persistSoon();
    notifyListeners();
  }

  void updateAssetThumbnailPath(String photoId, String thumbnailPath) {
    final workspaceId = _activeWorkspaceId;
    if (workspaceId == null) {
      return;
    }
    updateWorkspaceAssetThumbnailPath(workspaceId, photoId, thumbnailPath);
  }

  void updateWorkspaceAssetThumbnailPath(
    String workspaceId,
    String photoId,
    String thumbnailPath,
  ) {
    final workspace = _workspaceById(workspaceId);
    if (workspace == null || thumbnailPath.isEmpty) {
      return;
    }
    final currentAsset = workspace.assetById(photoId);
    if (currentAsset == null) {
      return;
    }
    if (currentAsset.photo.thumbnailPath == thumbnailPath) {
      return;
    }

    final nextWorkspace = _updateCachedAssetPath(
      workspace,
      photoId,
      (asset) => asset.copyWith(
        photo: asset.photo.copyWith(thumbnailPath: thumbnailPath),
      ),
    ).removeMissingAssetIndex(photoId);
    if (identical(nextWorkspace, workspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void setAssetCherished(String photoId, bool cherished) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final currentAsset = activeWorkspace.assetById(photoId);
    if (currentAsset == null || currentAsset.photo.isCherished == cherished) {
      return;
    }

    final nextWorkspace = activeWorkspace.updateAssetById(photoId, (asset) {
      return asset.copyWith(
        photo: asset.photo.copyWith(isCherished: cherished),
      );
    });
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void setAssetAppraisalScore(String photoId, int score) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final normalizedScore = score.clamp(0, 100).toInt();
    final currentAsset = activeWorkspace.assetById(photoId);
    if (currentAsset == null ||
        currentAsset.photo.appraisalScore == normalizedScore) {
      return;
    }

    final nextWorkspace = activeWorkspace.updateAssetById(photoId, (asset) {
      return asset.copyWith(
        photo: asset.photo.copyWith(appraisalScore: normalizedScore),
      );
    });
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void setAssetAppraisal(String photoId, PhotoAppraisal appraisal) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final currentAsset = activeWorkspace.assetById(photoId);
    if (currentAsset == null) {
      return;
    }
    final normalizedScore = appraisal.totalScore.clamp(0, 100).toInt();

    final nextWorkspace = activeWorkspace.updateAssetById(photoId, (asset) {
      return asset.copyWith(
        photo: asset.photo.copyWith(
          appraisalScore: normalizedScore,
          appraisal: appraisal,
        ),
      );
    });
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void setSeriesAppraisal(PhotoSeriesAppraisal appraisal) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null ||
        appraisal.sessionId != activeWorkspace.session.id) {
      return;
    }
    final nextWorkspace = activeWorkspace.upsertSeriesAppraisal(appraisal);
    if (identical(nextWorkspace, activeWorkspace)) {
      return;
    }

    _replaceWorkspace(nextWorkspace);
    _persistSoon();
    notifyListeners();
  }

  void setActiveGroup(String groupId) {
    _activeGroupId = groupId;
    notifyListeners();
  }

  void recordDecision(String photoId, Decision decision) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    final now = DateTime.now();
    final activeDecisions = _activeDecisionMap;
    activeDecisions[photoId] = PhotoDecision(
      photoId: photoId,
      decision: decision,
      decidedAt: activeDecisions[photoId]?.decidedAt ?? now,
      updatedAt: now,
      source: DecisionSource.user,
    );
    _persistSoon();
    notifyListeners();
  }

  void clearDecision(String photoId) {
    final activeWorkspace = _activeWorkspace;
    if (activeWorkspace == null) {
      return;
    }
    if (_activeDecisionMap.remove(photoId) == null) {
      return;
    }
    _persistSoon();
    notifyListeners();
  }

  void _replaceWorkspace(ReviewWorkspace nextWorkspace) {
    final index = _workspaces.indexWhere(
      (workspace) => workspace.session.id == nextWorkspace.session.id,
    );
    if (index == -1) {
      return;
    }
    _workspaces[index] = nextWorkspace;
  }

  Set<String> _cachedPathsForAssets(Iterable<ReviewAsset> assets) {
    return {
      for (final asset in assets) ...[
        if (asset.photo.thumbnailPath case final path? when path.isNotEmpty)
          path,
        if (asset.photo.previewPath case final path? when path.isNotEmpty) path,
      ],
    };
  }

  Iterable<String> _previewCachedPhotoIds(ReviewWorkspace workspace) sync* {
    for (final asset in workspace.assets) {
      final previewPath = asset.photo.previewPath;
      if (previewPath != null && previewPath.isNotEmpty) {
        yield asset.photo.id;
      }
    }
  }

  ({ReviewWorkspace workspace, Set<String> removedPaths})
  _pruneWorkspacePreviewCache(
    ReviewWorkspace workspace, {
    required String touchedPhotoId,
  }) {
    final workspaceId = workspace.session.id;
    final previewIds = _previewCachedPhotoIds(workspace).toSet();
    final order = _previewCacheOrderByWorkspaceId.putIfAbsent(
      workspaceId,
      () => Queue<String>(),
    );
    order.removeWhere((id) => !previewIds.contains(id));
    for (final id in previewIds) {
      if (!order.contains(id)) {
        order.add(id);
      }
    }
    order
      ..remove(touchedPhotoId)
      ..add(touchedPhotoId);
    if (order.length <= noemaWorkspacePreviewCacheLimit) {
      return (workspace: workspace, removedPaths: const <String>{});
    }

    final removedPhotoIds = <String>{};
    while (order.length > noemaWorkspacePreviewCacheLimit) {
      removedPhotoIds.add(order.removeFirst());
    }
    final removedPaths = <String>{};
    final assets = [
      for (final asset in workspace.assets)
        removedPhotoIds.contains(asset.photo.id) &&
                asset.photo.previewPath != null &&
                asset.photo.previewPath!.isNotEmpty
            ? asset.copyWith(
                photo: asset.photo.copyWith(clearPreviewPath: true),
              )
            : asset,
    ];
    for (final asset in workspace.assets) {
      if (removedPhotoIds.contains(asset.photo.id)) {
        final previewPath = asset.photo.previewPath;
        if (previewPath != null && previewPath.isNotEmpty) {
          removedPaths.add(previewPath);
        }
      }
    }
    return (
      workspace: workspace.copyWith(assets: assets),
      removedPaths: removedPaths,
    );
  }

  void _deleteUnreferencedCachedFiles(Set<String> candidatePaths) {
    if (candidatePaths.isEmpty) {
      return;
    }
    final stillReferencedPaths = _cachedPathsForAssets(
      _workspaces.expand((workspace) => workspace.assets),
    );
    final pathsToDelete = candidatePaths.difference(stillReferencedPaths);
    if (pathsToDelete.isEmpty) {
      return;
    }
    unawaited(_mediaPicker.deleteCachedFiles(pathsToDelete));
  }

  void deferBackgroundPreviewCaching([
    Duration duration = const Duration(milliseconds: 900),
  ]) {
    if (!_backgroundPreviewCachingEnabled || _disposed) {
      return;
    }
    final nextUntil = DateTime.now().add(duration);
    final currentUntil = _backgroundPreviewDeferredUntil;
    if (currentUntil == null || nextUntil.isAfter(currentUntil)) {
      _backgroundPreviewDeferredUntil = nextUntil;
    }
  }

  void _scheduleBackgroundPreviewCaching(String workspaceId) {
    if (!_backgroundPreviewCachingEnabled) {
      return;
    }
    final generation = ++_backgroundPreviewGeneration;
    unawaited(_runBackgroundPreviewCaching(workspaceId, generation));
  }

  void _scheduleCaptureMetadataRefresh(String? workspaceId) {
    if (!NoemaMediaPicker.isAndroidSupported ||
        workspaceId == null ||
        _disposed) {
      return;
    }
    final workspace = _workspaceById(workspaceId);
    if (workspace == null ||
        _nextCaptureMetadataRefreshTarget(workspace) == null) {
      return;
    }

    final generation = ++_captureMetadataRefreshGeneration;
    unawaited(_runCaptureMetadataRefresh(workspaceId, generation));
  }

  Future<void> _runCaptureMetadataRefresh(
    String workspaceId,
    int generation,
  ) async {
    await Future<void>.delayed(_noemaWorkspaceCaptureMetadataRefreshStartDelay);

    while (!_disposed && generation == _captureMetadataRefreshGeneration) {
      final workspace = _workspaceById(workspaceId);
      if (workspace == null || _activeWorkspaceId != workspaceId) {
        return;
      }
      final target = _nextCaptureMetadataRefreshTarget(workspace);
      if (target == null) {
        return;
      }

      final sourceUri = target.photo.sourceUri;
      if (sourceUri == null || sourceUri.isEmpty) {
        return;
      }

      _captureMetadataRefreshAttempts.add(
        _captureMetadataRefreshKey(workspaceId, target),
      );
      SelectedGalleryAsset? metadata;
      try {
        metadata = await _mediaPicker.loadMetadata(uri: sourceUri);
      } catch (_) {
        metadata = null;
      }

      if (_disposed || generation != _captureMetadataRefreshGeneration) {
        return;
      }
      if (metadata != null && _activeWorkspaceId == workspaceId) {
        updateAssetMetadata(target.photo.id, metadata);
      }

      await Future<void>.delayed(_noemaWorkspaceCaptureMetadataRefreshItemGap);
    }
  }

  ReviewAsset? _nextCaptureMetadataRefreshTarget(ReviewWorkspace workspace) {
    final timestampCounts = <int, int>{};
    for (final asset in workspace.assets) {
      final sourceUri = asset.photo.sourceUri;
      if (sourceUri == null || sourceUri.isEmpty) {
        continue;
      }
      final timestamp = asset.photo.createdAt.millisecondsSinceEpoch;
      timestampCounts[timestamp] = (timestampCounts[timestamp] ?? 0) + 1;
    }

    for (final asset in workspace.assets) {
      final sourceUri = asset.photo.sourceUri;
      if (sourceUri == null || sourceUri.isEmpty) {
        continue;
      }
      final timestamp = asset.photo.createdAt.millisecondsSinceEpoch;
      final timestampKey = _captureMetadataRefreshTimestampKey(
        workspace.session.id,
        timestamp,
      );
      final isRepeatedTimestamp = (timestampCounts[timestamp] ?? 0) >= 2;
      if (!isRepeatedTimestamp &&
          !_captureMetadataRefreshTimestamps.contains(timestampKey)) {
        continue;
      }
      if (isRepeatedTimestamp) {
        _captureMetadataRefreshTimestamps.add(timestampKey);
      }
      if (_captureMetadataRefreshAttempts.contains(
        _captureMetadataRefreshKey(workspace.session.id, asset),
      )) {
        continue;
      }
      return asset;
    }
    return null;
  }

  String _captureMetadataRefreshKey(String workspaceId, ReviewAsset asset) {
    return [
      workspaceId,
      asset.photo.id,
      asset.photo.createdAt.millisecondsSinceEpoch,
    ].join('|');
  }

  String _captureMetadataRefreshTimestampKey(
    String workspaceId,
    int timestamp,
  ) {
    return '$workspaceId|$timestamp';
  }

  Future<void> _runBackgroundPreviewCaching(
    String workspaceId,
    int generation,
  ) async {
    await Future<void>.delayed(_backgroundPreviewStartDelay);
    final failedPhotoIds = <String>{};

    while (!_disposed && generation == _backgroundPreviewGeneration) {
      if (!await _waitForBackgroundPreviewDeferral(generation)) {
        return;
      }
      final workspace = _workspaceById(workspaceId);
      if (workspace == null || _activeWorkspaceId != workspaceId) {
        return;
      }
      if (_previewCachedPhotoIds(workspace).length >=
          noemaWorkspacePreviewCacheLimit) {
        return;
      }

      final target = _nextBackgroundPreviewTarget(workspace, failedPhotoIds);
      if (target == null) {
        return;
      }

      String? previewPath;
      try {
        previewPath = await _mediaPicker.createPreview(
          uri: target.photo.sourceUri!,
          maxSize: _noemaWorkspaceBackgroundPreviewMaxSize,
        );
      } catch (_) {
        previewPath = null;
      }

      if (_disposed || generation != _backgroundPreviewGeneration) {
        return;
      }
      if (previewPath == null || previewPath.isEmpty) {
        failedPhotoIds.add(target.photo.id);
      } else if (_activeWorkspaceId == workspaceId) {
        updateAssetPreviewPath(target.photo.id, previewPath);
      }

      if (_backgroundPreviewItemGap > Duration.zero) {
        await Future<void>.delayed(_backgroundPreviewItemGap);
      }
    }
  }

  Future<bool> _waitForBackgroundPreviewDeferral(int generation) async {
    while (!_disposed && generation == _backgroundPreviewGeneration) {
      final deferredUntil = _backgroundPreviewDeferredUntil;
      final now = DateTime.now();
      if (deferredUntil == null || !deferredUntil.isAfter(now)) {
        return true;
      }
      await Future<void>.delayed(deferredUntil.difference(now));
    }
    return false;
  }

  ReviewAsset? _nextBackgroundPreviewTarget(
    ReviewWorkspace workspace,
    Set<String> failedPhotoIds,
  ) {
    for (final asset in workspace.assets) {
      final photo = asset.photo;
      final sourceUri = photo.sourceUri;
      final previewPath = photo.previewPath;
      if (failedPhotoIds.contains(photo.id) ||
          photo.availability != AssetAvailability.available ||
          sourceUri == null ||
          sourceUri.isEmpty ||
          previewPath != null && previewPath.isNotEmpty) {
        continue;
      }
      return asset;
    }
    return null;
  }

  ReviewWorkspace? _workspaceById(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.session.id == workspaceId) {
        return workspace;
      }
    }
    return null;
  }

  int _newPlatformAssetCount(
    ReviewWorkspace workspace,
    List<SelectedGalleryAsset> assets,
  ) {
    final knownPlatformIds = {
      for (final asset in workspace.assets) asset.photo.platformAssetId,
    };
    var count = 0;
    for (final asset in assets) {
      if (knownPlatformIds.add(asset.id)) {
        count += 1;
      }
    }
    return count;
  }

  List<SelectedGalleryAsset> _importableAssets(
    List<SelectedGalleryAsset> assets,
  ) {
    return [
      for (final asset in assets)
        if (!asset.previewUnavailable) asset,
    ];
  }

  ReviewWorkspace _updateCachedAssetPath(
    ReviewWorkspace workspace,
    String photoId,
    ReviewAsset Function(ReviewAsset asset) update,
  ) {
    final index = workspace.assets.indexWhere(
      (asset) => asset.photo.id == photoId,
    );
    if (index == -1) {
      return workspace;
    }

    final assets = [...workspace.assets];
    assets[index] = update(assets[index]);
    return workspace.copyWith(assets: assets);
  }

  String? _validWorkspaceId(String? workspaceId) {
    if (workspaceId != null &&
        _workspaces.any((workspace) => workspace.session.id == workspaceId)) {
      return workspaceId;
    }
    return _workspaces.isEmpty ? null : _workspaces.first.session.id;
  }

  void _syncActiveGroupToActiveWorkspace() {
    final activeWorkspace = _activeWorkspace;
    _activeGroupId = activeWorkspace == null || activeWorkspace.groups.isEmpty
        ? null
        : activeWorkspace.groups.first.id;
  }

  void _sanitizeDecisions() {
    final workspaceIds = {
      for (final workspace in _workspaces) workspace.session.id,
    };
    _decisionsByWorkspaceId.removeWhere(
      (workspaceId, _) => !workspaceIds.contains(workspaceId),
    );
    for (final workspace in _workspaces) {
      final photoIds = {for (final asset in workspace.assets) asset.photo.id};
      final decisions = _decisionsByWorkspaceId.putIfAbsent(
        workspace.session.id,
        () => {},
      );
      decisions.removeWhere((photoId, _) => !photoIds.contains(photoId));
    }
  }

  void _persistSoon() {
    if (localStore == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 220), () {
      _saveTimer = null;
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    final store = localStore;
    if (store == null) {
      return;
    }
    _sanitizeDecisions();
    await store.writeSnapshot(
      NoemaStoreSnapshot(
        workspaces: _workspaces,
        activeWorkspaceId: _validWorkspaceId(_activeWorkspaceId),
        decisionsByWorkspaceId: _decisionsByWorkspaceId,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _backgroundPreviewGeneration += 1;
    _captureMetadataRefreshGeneration += 1;
    _saveTimer?.cancel();
    unawaited(_persistNow());
    super.dispose();
  }
}

bool _hasActionableCullGroups(
  ReviewWorkspace workspace,
  Iterable<String> decidedPhotoIds,
) {
  final existingPhotoIds = {
    for (final asset in workspace.assets) asset.photo.id,
  };
  final decidedIds = decidedPhotoIds is Set<String>
      ? decidedPhotoIds
      : decidedPhotoIds.toSet();

  return workspace.groups.any((group) {
    var validPhotoCount = 0;
    var hasPendingPhoto = false;

    for (final photoId in group.photoIds) {
      if (!existingPhotoIds.contains(photoId)) {
        continue;
      }
      validPhotoCount += 1;
      hasPendingPhoto = hasPendingPhoto || !decidedIds.contains(photoId);
      if (validPhotoCount > 1 && hasPendingPhoto) {
        return true;
      }
    }

    return false;
  });
}
