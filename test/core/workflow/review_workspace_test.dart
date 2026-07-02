import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/analysis/grouping_evaluator.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/review_session.dart';
import 'package:noema/core/models/series_appraisal.dart';
import 'package:noema/core/models/similar_group.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  test('workspace builds deterministic session from selected assets', () {
    final bytes = _solidPng(8, 8, img.ColorRgb8(8, 8, 8));
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        thumbnailPath: '/tmp/a.jpg',
        previewBytes: bytes,
        exif: const PhotoExif(
          iso: 100,
          shutterSpeed: '1/500s',
          aperture: 5.6,
          focalLengthMm: 24,
          whiteBalance: 'WB 5600K',
        ),
      ),
      const SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
      const SelectedGalleryAsset(id: '/tmp/c.jpg', name: 'C.jpg'),
    ]);

    expect(workspace.session.totalCount, 3);
    expect(workspace.assets.map((asset) => asset.photo.platformAssetId), [
      '/tmp/a.jpg',
      '/tmp/b.jpg',
      '/tmp/c.jpg',
    ]);
    expect(workspace.assets.map((asset) => asset.displayName), [
      'A.jpg',
      'B.jpg',
      'C.jpg',
    ]);
    expect(workspace.assets.first.photo.thumbnailPath, '/tmp/a.jpg');
    expect(workspace.assets.first.photo.exif?.iso, 100);
    expect(workspace.assets.first.photo.exif?.shutterSpeed, '1/500s');
    expect(workspace.assets.first.photo.dimensionsEstimated, isFalse);
    expect(workspace.assets[1].photo.dimensionsEstimated, isTrue);
    expect(workspace.assets.first.previewBytes, bytes);
    expect(
      workspace.analysisResults.first.qualityFlags,
      contains(QualityFlag.dark),
    );
    expect(workspace.groups, hasLength(1));
    expect(workspace.groups.single.groupReason, GroupReason.needsAttention);
    expect(workspace.groups.single.photoIds, ['photo-1']);

    final restored = ReviewWorkspace.fromJson(workspace.toJson());
    expect(restored.assets.first.photo.exif?.iso, 100);
    expect(restored.assets.first.photo.exif?.aperture, 5.6);
  });

  test('workspace orders imported assets by capture metadata', () {
    final capturedAt = DateTime(2026, 4, 1, 8);
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: 'late',
        name: 'Late.jpg',
        createdAt: capturedAt.add(const Duration(minutes: 3)),
      ),
      const SelectedGalleryAsset(id: 'missing', name: 'Missing.jpg'),
      SelectedGalleryAsset(
        id: 'modified',
        name: 'Modified.jpg',
        updatedAt: capturedAt.add(const Duration(minutes: 2)),
      ),
      SelectedGalleryAsset(
        id: 'early',
        name: 'Early.jpg',
        createdAt: capturedAt,
      ),
    ], importedAt: capturedAt);

    expect(workspace.assets.map((asset) => asset.photo.platformAssetId), [
      'early',
      'modified',
      'late',
      'missing',
    ]);
    expect(workspace.assets.map((asset) => asset.photo.id), [
      'photo-1',
      'photo-2',
      'photo-3',
      'photo-4',
    ]);
    expect(workspace.assets[1].photo.createdAtEstimated, isTrue);
    expect(workspace.assets[3].photo.createdAtEstimated, isTrue);
  });

  test('observe view preferences persist in workspace snapshots', () {
    final workspace =
        ReviewWorkspace.fromSelectedAssets(const [
          SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
        ]).copyWith(
          observeViewPreferences: const ObserveViewPreferences(
            timeSort: 'oldestFirst',
            sortMode: 'score',
            scoreSort: 'lowToHigh',
            filterMode: 'cherished',
            density: 'spacious',
          ),
        );

    final restored = ReviewWorkspace.fromJson(workspace.toJson());

    expect(restored.observeViewPreferences.timeSort, 'oldestFirst');
    expect(restored.observeViewPreferences.sortMode, 'score');
    expect(restored.observeViewPreferences.scoreSort, 'lowToHigh');
    expect(restored.observeViewPreferences.filterMode, 'cherished');
    expect(restored.observeViewPreferences.density, 'spacious');
  });

  test('appreciate view preferences persist in workspace snapshots', () {
    final workspace =
        ReviewWorkspace.fromSelectedAssets(const [
          SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
        ]).copyWith(
          appreciateViewPreferences: const AppreciateViewPreferences(
            rangeMask: 0x08,
            order: 'shuffle',
            intervalSeconds: 18,
          ),
        );

    final restored = ReviewWorkspace.fromJson(workspace.toJson());

    expect(restored.appreciateViewPreferences.rangeMask, 0x08);
    expect(restored.appreciateViewPreferences.order, 'shuffle');
    expect(restored.appreciateViewPreferences.intervalSeconds, 18);
  });

  test('photo appraisal markers persist in workspace snapshots', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
    ]);

    controller.setAssetCherished('photo-1', true);
    controller.setAssetAppraisalScore('photo-1', 108);
    controller.setAssetAppraisal(
      'photo-1',
      PhotoAppraisal(
        initial: '画面成立。',
        overall: '总观内容。',
        refine: '打磨内容。',
        question: '你最想保留什么？',
        metrics: [
          const PhotoAppraisalMetric(label: '主题', value: 19, text: '主题明确。'),
          const PhotoAppraisalMetric(label: '技术', value: 18, text: '技术稳定。'),
          const PhotoAppraisalMetric(label: '情感', value: 20, text: '情感成立。'),
          const PhotoAppraisalMetric(label: '联想', value: 17, text: '联想可加强。'),
        ],
      ),
    );

    final restored = ReviewWorkspace.fromJson(controller.workspace.toJson());
    expect(restored.assets.single.photo.isCherished, isTrue);
    expect(restored.assets.single.photo.appraisalScore, 74);
    expect(restored.assets.single.photo.appraisal?.initial, '画面成立。');
    expect(restored.assets.single.photo.appraisal?.metrics, hasLength(4));
  });

  test('series appraisal persists as workspace-level category result', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ]);
    final workspace = controller.workspace;

    controller.setSeriesAppraisal(
      PhotoSeriesAppraisal(
        id: '${workspace.session.id}-fine-series',
        sessionId: workspace.session.id,
        band: SeriesAppraisalBand.fine,
        photoIds: const ['photo-1', 'photo-2'],
        photoSetHash: 'photo-1|photo-2',
        captureStartAt: workspace.assets.first.photo.createdAt,
        captureEndAt: workspace.assets.last.photo.createdAt,
        createdAt: DateTime(2026, 4, 1, 8),
        updatedAt: DateTime(2026, 4, 1, 8, 1),
        provider: 'mock',
        model: 'mock-series',
        promptVersion: 'series-v1',
        result: PhotoSeriesAppraisalResult(
          title: '春日回声',
          overall: '总观。',
          themeLine: '主题线。',
          relationships: [
            PhotoSeriesRelationship(
              photoIds: const ['photo-1', 'photo-2'],
              role: '呼应',
              text: '关系。',
            ),
          ],
          sequence: PhotoSeriesSequence(
            suggestedPhotoIds: const ['photo-1', 'photo-2'],
            text: '编排。',
          ),
          refine: '打磨。',
          question: '自问？',
          scores: const PhotoSeriesScoreSet(
            theme: 18,
            technique: 17,
            emotion: 19,
            association: 16,
            editing: 18,
          ),
        ),
      ),
    );

    final restored = ReviewWorkspace.fromJson(controller.workspace.toJson());
    final appraisal = restored.seriesAppraisalFor(SeriesAppraisalBand.fine);
    expect(appraisal?.result.title, '春日回声');
    expect(appraisal?.result.scores.total, 88);
    expect(appraisal?.photoIds, ['photo-1', 'photo-2']);
  });

  test(
    'workspace does not create cull groups from unanalysed placeholders',
    () {
      final workspace = ReviewWorkspace.fromSelectedAssets(const [
        SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
        SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
        SelectedGalleryAsset(id: '/tmp/c.jpg', name: 'C.jpg'),
        SelectedGalleryAsset(id: '/tmp/d.jpg', name: 'D.jpg'),
      ]);

      expect(workspace.groups, isEmpty);
    },
  );

  test(
    'workspace marks unavailable picker previews without analysing them',
    () {
      final workspace = ReviewWorkspace.fromSelectedAssets(const [
        SelectedGalleryAsset(
          id: '/tmp/empty.jpg',
          name: 'Empty.jpg',
          previewUnavailable: true,
        ),
      ]);

      expect(
        workspace.assets.single.photo.availability,
        AssetAvailability.unavailable,
      );
      expect(workspace.assets.single.photo.thumbnailPath, isNull);
      expect(workspace.assets.single.previewBytes, isNull);
      expect(workspace.groups.single.groupReason, GroupReason.needsAttention);
      expect(
        workspace.groups.single.attentionReasons,
        contains(QualityFlag.unavailable),
      );
    },
  );

  test('workspace groups matching preview hashes as near duplicates', () {
    final matchingBytes = _checkerPng(inverted: false);
    final differentBytes = _checkerPng(inverted: true);
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        previewBytes: matchingBytes,
      ),
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        previewBytes: matchingBytes,
      ),
      SelectedGalleryAsset(
        id: '/tmp/c.jpg',
        name: 'C.jpg',
        previewBytes: differentBytes,
      ),
    ]);

    expect(workspace.groups.first.groupReason, GroupReason.nearDuplicate);
    expect(workspace.groups.first.photoIds, ['photo-1', 'photo-2']);
  });

  test('workspace keeps actual analysis flags on attention groups', () {
    final bytes = _solidPng(8, 8, img.ColorRgb8(8, 8, 8));
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        previewBytes: bytes,
      ),
    ]);

    expect(workspace.groups.single.groupReason, GroupReason.needsAttention);
    expect(
      workspace.groups.single.attentionReasons,
      contains(QualityFlag.dark),
    );
  });

  test(
    'workspace preserves Android source uri for later observe hydration',
    () {
      final workspace = ReviewWorkspace.fromSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'content://media/photo/1',
          name: 'IMG_0001.JPG',
          sourceUri: 'content://media/photo/1',
          thumbnailPath: '/cache/thumb.jpg',
        ),
      ]);

      final photo = workspace.assets.single.photo;
      expect(photo.sourceUri, 'content://media/photo/1');
      expect(photo.thumbnailPath, '/cache/thumb.jpg');
      expect(photo.dimensionsEstimated, isTrue);
    },
  );

  test(
    'workspace restores legacy snapshots without groups by rebuilding them',
    () {
      final original = ReviewWorkspace.fromSelectedAssets(const [
        SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
        SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
        SelectedGalleryAsset(id: '/tmp/c.jpg', name: 'C.jpg'),
      ]);
      final legacyJson = Map<String, Object?>.from(original.toJson())
        ..['groups'] = const [];

      final restored = ReviewWorkspace.fromJson(legacyJson);

      expect(restored.assets, hasLength(3));
      expect(restored.groups, isEmpty);
    },
  );

  test('workspace rebuilds stale persisted time clusters on restore', () {
    final original = ReviewWorkspace.fromSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
      SelectedGalleryAsset(id: '/tmp/c.jpg', name: 'C.jpg'),
    ]);
    final legacyJson = Map<String, Object?>.from(original.toJson())
      ..['groups'] = [
        SimilarGroup(
          id: 'legacy-group',
          sessionId: original.session.id,
          photoIds: const ['photo-1', 'photo-2', 'photo-3'],
          groupReason: GroupReason.timeCluster,
          attentionReasons: const [],
          reviewStatus: ReviewStatus.pending,
          createdAt: original.session.createdAt,
          updatedAt: original.session.updatedAt,
        ).toJson(),
      ];

    final restored = ReviewWorkspace.fromJson(legacyJson);

    expect(restored.assets, hasLength(3));
    expect(restored.groups, isEmpty);
  });

  test('workspace ignores legacy placeholder hashes on restore', () {
    final original = ReviewWorkspace.fromSelectedAssets(const [
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        width: 6000,
        height: 4000,
      ),
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        width: 6000,
        height: 4000,
      ),
      SelectedGalleryAsset(
        id: '/tmp/c.jpg',
        name: 'C.jpg',
        width: 6000,
        height: 4000,
      ),
    ]);
    final legacyJson = Map<String, Object?>.from(original.toJson())
      ..['analysisResults'] = [
        AnalysisResult(
          photoId: 'photo-1',
          blurScore: 0.82,
          brightnessScore: 0.56,
          exposureFlag: ExposureFlag.normal,
          similarityHash: 1000,
          colorSignature: const [],
          luminanceSignature: const [],
          qualityFlags: const [],
          analyzedAt: original.session.updatedAt,
        ).toJson(),
        AnalysisResult(
          photoId: 'photo-2',
          blurScore: 0.82,
          brightnessScore: 0.56,
          exposureFlag: ExposureFlag.normal,
          similarityHash: 1001,
          colorSignature: const [],
          luminanceSignature: const [],
          qualityFlags: const [],
          analyzedAt: original.session.updatedAt,
        ).toJson(),
        AnalysisResult(
          photoId: 'photo-3',
          blurScore: 0.82,
          brightnessScore: 0.56,
          exposureFlag: ExposureFlag.normal,
          similarityHash: 1002,
          colorSignature: const [],
          luminanceSignature: const [],
          qualityFlags: const [],
          analyzedAt: original.session.updatedAt,
        ).toJson(),
      ];

    final restored = ReviewWorkspace.fromJson(legacyJson);

    expect(restored.groups, isEmpty);
  });

  test('workspace groups true burst shots by real capture metadata', () {
    final capturedAt = DateTime(2026, 6, 3, 14);
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 3)),
      ),
      SelectedGalleryAsset(
        id: '/tmp/c.jpg',
        name: 'C.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 6)),
      ),
    ]);

    expect(workspace.groups, hasLength(1));
    expect(workspace.groups.single.groupReason, GroupReason.burst);
    expect(workspace.groups.single.photoIds, ['photo-1', 'photo-2', 'photo-3']);
  });

  test('workspace does not group broad same-period photos as similar', () {
    final capturedAt = DateTime(2026, 6, 3, 15);
    final workspace = ReviewWorkspace.fromSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt,
      ),
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(minutes: 2)),
      ),
      SelectedGalleryAsset(
        id: '/tmp/c.jpg',
        name: 'C.jpg',
        width: 3024,
        height: 4032,
        createdAt: capturedAt.add(const Duration(minutes: 3)),
      ),
    ]);

    expect(workspace.groups, isEmpty);
  });

  test(
    'workspace rejects visually different photos captured close together',
    () {
      final capturedAt = DateTime(2026, 6, 3, 16);
      final workspace = ReviewWorkspace.fromSelectedAssets([
        SelectedGalleryAsset(
          id: '/tmp/a.jpg',
          name: 'A.jpg',
          previewBytes: _checkerPng(inverted: false),
          createdAt: capturedAt,
        ),
        SelectedGalleryAsset(
          id: '/tmp/b.jpg',
          name: 'B.jpg',
          previewBytes: _checkerPng(inverted: true),
          createdAt: capturedAt.add(const Duration(seconds: 3)),
        ),
      ]);

      expect(workspace.groups, isEmpty);
    },
  );

  test('workspace rejects color-shifted close-time photos as burst shots', () {
    final capturedAt = DateTime(2026, 6, 3, 16, 30);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-burst-color-reject',
        name: 'Burst Color Reject',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        totalCount: 2,
        importedCount: 2,
        analyzedCount: 2,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', capturedAt),
        _reviewAsset('photo-2', capturedAt),
      ],
      analysisResults: [
        _manualAnalysis(
          photoId: 'photo-1',
          hashHex: 'ffffffffffffffff',
          colorSignature: _signature(length: 12, value: 0),
          luminanceSignature: _signature(length: 16, value: 128),
        ),
        _manualAnalysis(
          photoId: 'photo-2',
          hashHex: 'ffffffffffffffff',
          colorSignature: _signature(length: 12, value: 255),
          luminanceSignature: _signature(length: 16, value: 128),
        ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());

    expect(restored.groups, isEmpty);
  });

  test('workspace allows moderate color-shifted close-time burst shots', () {
    final capturedAt = DateTime(2026, 6, 3, 16, 45);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-burst-color-allow',
        name: 'Burst Color Allow',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        totalCount: 2,
        importedCount: 2,
        analyzedCount: 2,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', capturedAt),
        _reviewAsset('photo-2', capturedAt.add(const Duration(seconds: 3))),
      ],
      analysisResults: [
        _manualAnalysis(
          photoId: 'photo-1',
          hashHex: '0000000000000000',
          colorSignature: _signature(length: 12, value: 0),
          luminanceSignature: _signature(length: 16, value: 0),
        ),
        _manualAnalysis(
          photoId: 'photo-2',
          hashHex: '000000000007ffff',
          colorSignature: _signature(length: 12, value: 127),
          luminanceSignature: _signature(length: 16, value: 102),
        ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());

    expect(restored.groups, hasLength(1));
    expect(restored.groups.single.groupReason, GroupReason.burst);
  });

  test(
    'workspace rejects same-luminance but color-shifted scenes as duplicates',
    () {
      final capturedAt = DateTime(2026, 6, 4, 10);
      final workspace = ReviewWorkspace.fromSelectedAssets([
        SelectedGalleryAsset(
          id: '/tmp/a.jpg',
          name: 'A.jpg',
          previewBytes: _paletteScenePng(
            low: img.ColorRgb8(255, 0, 255),
            high: img.ColorRgb8(0, 255, 255),
          ),
          createdAt: capturedAt,
        ),
        SelectedGalleryAsset(
          id: '/tmp/b.jpg',
          name: 'B.jpg',
          previewBytes: _paletteScenePng(
            low: img.ColorRgb8(0, 102, 0),
            high: img.ColorRgb8(255, 205, 0),
          ),
          createdAt: capturedAt.add(const Duration(seconds: 12)),
        ),
      ]);

      expect(
        workspace.groups.where(
          (group) => group.groupReason == GroupReason.nearDuplicate,
        ),
        isEmpty,
      );
    },
  );

  test('workspace groups short-time scene sequences with shifted framing', () {
    final capturedAt = DateTime(2026, 6, 4, 10, 30);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-temporal-scene',
        name: 'Temporal Scene',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        totalCount: 3,
        importedCount: 3,
        analyzedCount: 3,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', capturedAt),
        _reviewAsset('photo-2', capturedAt.add(const Duration(seconds: 45))),
        _reviewAsset(
          'photo-3',
          capturedAt.add(const Duration(minutes: 2, seconds: 10)),
        ),
      ],
      analysisResults: [
        _manualAnalysis(
          photoId: 'photo-1',
          hashHex: '0000000000000000',
          colorSignature: _signature(length: 12, value: 102),
          luminanceSignature: _signature(length: 16, value: 92),
        ),
        _manualAnalysis(
          photoId: 'photo-2',
          hashHex: '0000000000ffffff',
          colorSignature: _signature(length: 12, value: 116),
          luminanceSignature: _signature(length: 16, value: 110),
        ),
        _manualAnalysis(
          photoId: 'photo-3',
          hashHex: '00000000ffff0000',
          colorSignature: _signature(length: 12, value: 130),
          luminanceSignature: _signature(length: 16, value: 126),
        ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());
    final nearGroups = restored.groups
        .where((group) => group.groupReason == GroupReason.nearDuplicate)
        .toList(growable: false);

    expect(nearGroups, hasLength(1));
    expect(nearGroups.single.photoIds, ['photo-1', 'photo-2', 'photo-3']);
  });

  test(
    'workspace groups adjacent estimated-time scene sequences cautiously',
    () {
      final importedAt = DateTime(2026, 6, 4, 10, 45);
      final seeded = ReviewWorkspace(
        session: ReviewSession(
          id: 'session-estimated-temporal-scene',
          name: 'Estimated Temporal Scene',
          createdAt: importedAt,
          updatedAt: importedAt,
          totalCount: 3,
          importedCount: 3,
          analyzedCount: 3,
          currentStage: ReviewStage.reviewing,
          status: ReviewSessionStatus.ready,
        ),
        assets: [
          _reviewAsset('photo-1', importedAt, createdAtEstimated: true),
          _reviewAsset(
            'photo-2',
            importedAt.add(const Duration(microseconds: 1)),
            createdAtEstimated: true,
          ),
          _reviewAsset(
            'photo-3',
            importedAt.add(const Duration(microseconds: 2)),
            createdAtEstimated: true,
          ),
        ],
        analysisResults: [
          _manualAnalysis(
            photoId: 'photo-1',
            hashHex: '0000000000000000',
            colorSignature: _signature(length: 12, value: 100),
            luminanceSignature: _signature(length: 16, value: 100),
          ),
          _manualAnalysis(
            photoId: 'photo-2',
            hashHex: '0000000000ffffff',
            colorSignature: _signature(length: 12, value: 114),
            luminanceSignature: _signature(length: 16, value: 114),
          ),
          _manualAnalysis(
            photoId: 'photo-3',
            hashHex: '00000000ffff0000',
            colorSignature: _signature(length: 12, value: 126),
            luminanceSignature: _signature(length: 16, value: 126),
          ),
        ],
        groups: const [],
      );

      final restored = ReviewWorkspace.fromJson(seeded.toJson());
      final nearGroups = restored.groups
          .where((group) => group.groupReason == GroupReason.nearDuplicate)
          .toList(growable: false);

      expect(nearGroups, hasLength(1));
      expect(nearGroups.single.photoIds, ['photo-1', 'photo-2', 'photo-3']);
    },
  );

  test('workspace rejects close-time scene sequences when layout drifts', () {
    final capturedAt = DateTime(2026, 6, 4, 10, 55);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-temporal-scene-reject',
        name: 'Temporal Scene Reject',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        totalCount: 2,
        importedCount: 2,
        analyzedCount: 2,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', capturedAt),
        _reviewAsset('photo-2', capturedAt.add(const Duration(seconds: 12))),
      ],
      analysisResults: [
        _manualAnalysis(
          photoId: 'photo-1',
          hashHex: '0000000000000000',
          colorSignature: _signature(length: 12, value: 100),
          luminanceSignature: _signature(length: 16, value: 40),
        ),
        _manualAnalysis(
          photoId: 'photo-2',
          hashHex: '000000000000ffff',
          colorSignature: _signature(length: 12, value: 112),
          luminanceSignature: _signature(length: 16, value: 120),
        ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());

    expect(
      restored.groups.where(
        (group) => group.groupReason == GroupReason.nearDuplicate,
      ),
      isEmpty,
    );
  });

  test('temporal scene merging skips unmergeable blockers between matches', () {
    final capturedAt = DateTime(2026, 6, 4, 11, 5);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-temporal-blocker',
        name: 'Temporal Blocker',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        totalCount: 3,
        importedCount: 3,
        analyzedCount: 3,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', capturedAt),
        _reviewAsset('photo-2', capturedAt.add(const Duration(seconds: 10))),
        _reviewAsset('photo-3', capturedAt.add(const Duration(seconds: 20))),
      ],
      analysisResults: [
        _manualAnalysis(
          photoId: 'photo-1',
          hashHex: '0000000000000000',
          colorSignature: _signature(length: 12, value: 104),
          luminanceSignature: _signature(length: 16, value: 96),
        ),
        _manualAnalysis(
          photoId: 'photo-2',
          hashHex: 'ffffffffffffffff',
          colorSignature: _signature(length: 12, value: 230),
          luminanceSignature: _signature(length: 16, value: 220),
        ),
        _manualAnalysis(
          photoId: 'photo-3',
          hashHex: '0000000000ffffff',
          colorSignature: _signature(length: 12, value: 118),
          luminanceSignature: _signature(length: 16, value: 112),
        ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());
    final nearGroups = restored.groups
        .where((group) => group.groupReason == GroupReason.nearDuplicate)
        .toList(growable: false);

    expect(nearGroups, hasLength(1));
    expect(nearGroups.single.photoIds, ['photo-1', 'photo-3']);
  });

  test(
    'workspace merges temporally adjacent groups at the loose threshold',
    () {
      final createdAt = DateTime(2026, 6, 4, 11);
      final seeded = ReviewWorkspace(
        session: ReviewSession(
          id: 'session-temporal-chain',
          name: 'Temporal Chain',
          createdAt: createdAt,
          updatedAt: createdAt,
          totalCount: 3,
          importedCount: 3,
          analyzedCount: 3,
          currentStage: ReviewStage.reviewing,
          status: ReviewSessionStatus.ready,
        ),
        assets: [
          _reviewAsset('photo-1', createdAt),
          _reviewAsset('photo-2', createdAt.add(const Duration(minutes: 1))),
          _reviewAsset('photo-3', createdAt.add(const Duration(minutes: 2))),
        ],
        analysisResults: [
          _manualAnalysis(
            photoId: 'photo-1',
            hashHex: '0000000000000000',
            colorSignature: _signature(length: 12, value: 100),
            luminanceSignature: _signature(length: 16, value: 100),
          ),
          _manualAnalysis(
            photoId: 'photo-2',
            hashHex: '0000000000000000',
            colorSignature: _signature(length: 12, value: 100),
            luminanceSignature: _signature(length: 16, value: 100),
          ),
          _manualAnalysis(
            photoId: 'photo-3',
            hashHex: '00000000000000ff',
            colorSignature: _signature(length: 12, value: 136),
            luminanceSignature: _signature(length: 16, value: 126),
          ),
        ],
        groups: const [],
      );

      final restored = ReviewWorkspace.fromJson(seeded.toJson());
      final nearGroups = restored.groups
          .where((group) => group.groupReason == GroupReason.nearDuplicate)
          .toList(growable: false);

      expect(nearGroups, hasLength(1));
      expect(nearGroups.single.photoIds, ['photo-1', 'photo-2', 'photo-3']);
    },
  );

  test(
    'near-duplicate grouping avoids chain pollution outside the short window',
    () {
      final createdAt = DateTime(2026, 6, 4, 11);
      final seeded = ReviewWorkspace(
        session: ReviewSession(
          id: 'session-chain',
          name: 'Chain',
          createdAt: createdAt,
          updatedAt: createdAt,
          totalCount: 3,
          importedCount: 3,
          analyzedCount: 3,
          currentStage: ReviewStage.reviewing,
          status: ReviewSessionStatus.ready,
        ),
        assets: [
          _reviewAsset('photo-1', createdAt),
          _reviewAsset('photo-2', createdAt.add(const Duration(minutes: 4))),
          _reviewAsset('photo-3', createdAt.add(const Duration(minutes: 8))),
        ],
        analysisResults: [
          _manualAnalysis(photoId: 'photo-1', hashHex: '0000000000000000'),
          _manualAnalysis(photoId: 'photo-2', hashHex: '00000000000000ff'),
          _manualAnalysis(photoId: 'photo-3', hashHex: '000000000000ffff'),
        ],
        groups: const [],
      );

      final restored = ReviewWorkspace.fromJson(seeded.toJson());
      final nearGroups = restored.groups
          .where((group) => group.groupReason == GroupReason.nearDuplicate)
          .toList(growable: false);

      expect(nearGroups, hasLength(1));
      expect(nearGroups.single.photoIds.length, 2);
    },
  );

  test('complete linkage rejects bridge groups when endpoints fail', () {
    final createdAt = DateTime(2026, 6, 4, 11);
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-complete-linkage',
        name: 'Complete Linkage',
        createdAt: createdAt,
        updatedAt: createdAt,
        totalCount: 3,
        importedCount: 3,
        analyzedCount: 3,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        _reviewAsset('photo-1', createdAt),
        _reviewAsset('photo-2', createdAt.add(const Duration(minutes: 29))),
        _reviewAsset('photo-3', createdAt.add(const Duration(minutes: 58))),
      ],
      analysisResults: [
        _manualAnalysis(photoId: 'photo-1', hashHex: '0000000000000000'),
        _manualAnalysis(photoId: 'photo-2', hashHex: '0000000000000000'),
        _manualAnalysis(photoId: 'photo-3', hashHex: '0000000000000000'),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());
    final nearGroups = restored.groups
        .where((group) => group.groupReason == GroupReason.nearDuplicate)
        .toList(growable: false);

    expect(nearGroups, hasLength(1));
    expect(nearGroups.single.photoIds, ['photo-1', 'photo-2']);
  });

  test('temporal near-duplicate merging stops at the maximum group span', () {
    final createdAt = DateTime(2026, 6, 4, 11);
    const hashHexes = [
      '0000000000000000',
      '00000000000000ff',
      '000000000000ffff',
      '00000000ffffff',
      '000000ffffffff',
      '0000ffffffffff',
      '00ffffffffffff',
    ];
    final seeded = ReviewWorkspace(
      session: ReviewSession(
        id: 'session-long-chain',
        name: 'Long Chain',
        createdAt: createdAt,
        updatedAt: createdAt,
        totalCount: 7,
        importedCount: 7,
        analyzedCount: 7,
        currentStage: ReviewStage.reviewing,
        status: ReviewSessionStatus.ready,
      ),
      assets: [
        for (var index = 0; index < 7; index += 1)
          _reviewAsset(
            'photo-${index + 1}',
            createdAt.add(Duration(minutes: index * 2)),
          ),
      ],
      analysisResults: [
        for (var index = 0; index < hashHexes.length; index += 1)
          _manualAnalysis(
            photoId: 'photo-${index + 1}',
            hashHex: hashHexes[index],
          ),
      ],
      groups: const [],
    );

    final restored = ReviewWorkspace.fromJson(seeded.toJson());
    final nearGroups = restored.groups
        .where((group) => group.groupReason == GroupReason.nearDuplicate)
        .toList(growable: false);

    expect(nearGroups, isNotEmpty);
    for (final group in nearGroups) {
      final groupAssets = group.photoIds
          .map(restored.assetById)
          .nonNulls
          .toList(growable: false);
      final span = groupAssets.last.photo.createdAt.difference(
        groupAssets.first.photo.createdAt,
      );
      expect(span, lessThanOrEqualTo(const Duration(minutes: 10)));
    }
  });

  test(
    'grouping evaluator reports clean precision and recall on synthetic cull set',
    () {
      final capturedAt = DateTime(2026, 6, 4, 12);
      final workspace = ReviewWorkspace.fromSelectedAssets([
        SelectedGalleryAsset(
          id: '/tmp/a1.jpg',
          name: 'A1.jpg',
          previewBytes: _checkerPng(inverted: false),
          createdAt: capturedAt,
        ),
        SelectedGalleryAsset(
          id: '/tmp/a2.jpg',
          name: 'A2.jpg',
          previewBytes: _checkerPng(inverted: false),
          createdAt: capturedAt.add(const Duration(seconds: 2)),
        ),
        SelectedGalleryAsset(
          id: '/tmp/b1.jpg',
          name: 'B1.jpg',
          previewBytes: _solidPng(16, 16, img.ColorRgb8(16, 16, 16)),
          createdAt: capturedAt.add(const Duration(minutes: 3)),
        ),
        SelectedGalleryAsset(
          id: '/tmp/b2.jpg',
          name: 'B2.jpg',
          previewBytes: _solidPng(16, 16, img.ColorRgb8(16, 16, 16)),
          createdAt: capturedAt.add(const Duration(minutes: 3, seconds: 1)),
        ),
        SelectedGalleryAsset(
          id: '/tmp/c1.jpg',
          name: 'C1.jpg',
          previewBytes: _paletteScenePng(
            low: img.ColorRgb8(255, 0, 255),
            high: img.ColorRgb8(0, 255, 255),
          ),
          createdAt: capturedAt.add(const Duration(minutes: 7)),
        ),
        SelectedGalleryAsset(
          id: '/tmp/c2.jpg',
          name: 'C2.jpg',
          previewBytes: _paletteScenePng(
            low: img.ColorRgb8(0, 102, 0),
            high: img.ColorRgb8(255, 205, 0),
          ),
          createdAt: capturedAt.add(const Duration(minutes: 7, seconds: 6)),
        ),
      ]);

      final report = evaluateGrouping(
        itemIds: [for (final asset in workspace.assets) asset.photo.id],
        expectedGroups: const [
          ['photo-1', 'photo-2'],
          ['photo-3', 'photo-4'],
        ],
        actualGroups: [
          for (final group in workspace.groups)
            if (group.groupReason == GroupReason.nearDuplicate)
              group.photoIds.toList(growable: false),
        ],
      );

      expect(report.falsePositivePairs, 0);
      expect(report.falseNegativePairs, 0);
      expect(report.precision, 1);
      expect(report.recall, 1);
      expect(report.f1Score, 1);
    },
  );

  test('controller metadata hydration can create a burst group later', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ]);

    expect(controller.workspace.groups, isEmpty);

    final capturedAt = DateTime(2026, 6, 3, 17);
    controller.updateAssetMetadata(
      'photo-1',
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt,
      ),
    );
    controller.updateAssetMetadata(
      'photo-2',
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        width: 4032,
        height: 3024,
        createdAt: capturedAt.add(const Duration(seconds: 3)),
      ),
    );

    expect(controller.workspace.groups, hasLength(1));
    expect(controller.workspace.groups.single.groupReason, GroupReason.burst);
  });

  test('controller metadata hydration preserves existing dimensions', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'content://media/photo/old',
        name: 'old.jpg',
        width: 4000,
        height: 3000,
      ),
    ]);

    controller.updateAssetMetadata(
      'photo-1',
      const SelectedGalleryAsset(
        id: 'content://media/photo/old',
        name: 'old.jpg',
        exif: PhotoExif(iso: 25, shutterSpeed: '1/2094s'),
      ),
    );

    final photo = controller.workspace.assets.single.photo;
    expect(photo.width, 4000);
    expect(photo.height, 3000);
    expect(photo.dimensionsEstimated, isFalse);
    expect(photo.exif?.iso, 25);
    expect(photo.exif?.shutterSpeed, '1/2094s');
  });

  test(
    'controller refreshes duplicate capture timestamps from Android EXIF',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });

      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method != 'loadMetadata') {
          return Future<Object?>.value(null);
        }
        final uri = call.arguments['uri'] as String;
        final exifTakenAtMillis = uri.endsWith('/a')
            ? DateTime(2026, 4, 1, 8).millisecondsSinceEpoch
            : DateTime(2026, 4, 4, 8).millisecondsSinceEpoch;
        return Future<Object?>.value({
          'uri': uri,
          'name': uri.endsWith('/a') ? 'A.jpg' : 'B.jpg',
          'width': 6000,
          'height': 4000,
          'takenAtMillis': DateTime(
            2026,
            4,
            24,
            10,
            58,
            20,
          ).millisecondsSinceEpoch,
          'exifTakenAtMillis': exifTakenAtMillis,
          'iso': 100,
        });
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final staleTime = DateTime(2026, 4, 24, 10, 58, 20);
      final controller = ReviewWorkspaceController();
      addTearDown(controller.dispose);
      controller.loadSelectedAssets([
        SelectedGalleryAsset(
          id: 'content://media/photo/a',
          name: 'A.jpg',
          sourceUri: 'content://media/photo/a',
          width: 6000,
          height: 4000,
          createdAt: staleTime,
          exif: const PhotoExif(iso: 100),
        ),
        SelectedGalleryAsset(
          id: 'content://media/photo/b',
          name: 'B.jpg',
          sourceUri: 'content://media/photo/b',
          width: 6000,
          height: 4000,
          createdAt: staleTime,
          exif: const PhotoExif(iso: 100),
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(
        calls.where((call) => call.method == 'loadMetadata'),
        hasLength(2),
      );
      expect(
        controller.workspace.assets.map((asset) => asset.photo.createdAt),
        [DateTime(2026, 4, 1, 8), DateTime(2026, 4, 4, 8)],
      );
      expect(controller.workspace.groups, isEmpty);
    },
  );

  test(
    'controller reports actionable cull groups only while photos are pending',
    () {
      final controller = ReviewWorkspaceController();
      final capturedAt = DateTime(2026, 6, 3, 18);
      controller.loadSelectedAssets([
        SelectedGalleryAsset(
          id: '/tmp/a.jpg',
          name: 'A.jpg',
          width: 4032,
          height: 3024,
          createdAt: capturedAt,
        ),
        SelectedGalleryAsset(
          id: '/tmp/b.jpg',
          name: 'B.jpg',
          width: 4032,
          height: 3024,
          createdAt: capturedAt.add(const Duration(seconds: 3)),
        ),
      ]);

      expect(controller.workspace.groups, hasLength(1));
      expect(controller.hasActionableCullGroups, isTrue);

      controller.recordDecision('photo-1', Decision.keep);
      expect(controller.hasActionableCullGroups, isTrue);

      controller.recordDecision('photo-2', Decision.reviewForRemoval);
      expect(controller.hasActionableCullGroups, isFalse);

      controller.clearDecision('photo-2');
      expect(controller.hasActionableCullGroups, isTrue);
    },
  );

  test('controller records decisions and summarizes buckets', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ]);

    controller.recordDecision('photo-1', Decision.keep);
    controller.recordDecision('photo-2', Decision.reviewForRemoval);

    expect(controller.decisionCounts[Decision.keep], 1);
    expect(controller.decisionCounts[Decision.maybe], 0);
    expect(controller.decisionCounts[Decision.reviewForRemoval], 1);
    expect(controller.undecidedCount, 0);

    controller.clearDecision('photo-2');

    expect(controller.decisionCounts[Decision.keep], 1);
    expect(controller.decisionCounts[Decision.reviewForRemoval], 0);
    expect(controller.undecidedCount, 1);
  });

  test('controller renames workspace without changing assets', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ], name: '友人');
    final originalUpdatedAt = controller.workspace.session.updatedAt;

    controller.renameWorkspace('  城市散步  ');

    expect(controller.workspace.session.name, '城市散步');
    expect(controller.workspace.session.updatedAt, isNot(originalUpdatedAt));
    expect(controller.workspace.assets, hasLength(2));
  });

  test(
    'controller appends selected assets and skips existing platform ids',
    () {
      final controller = ReviewWorkspaceController();
      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(id: 'sample-1', name: 'existing.jpg'),
      ], name: '友人');

      controller.appendSelectedAssets([
        const SelectedGalleryAsset(id: 'sample-1', name: 'duplicate.jpg'),
        const SelectedGalleryAsset(id: 'new-1', name: 'new.jpg'),
      ]);

      expect(controller.workspace.session.name, '友人');
      expect(controller.workspace.assets, hasLength(2));
      expect(controller.workspace.assets.last.displayName, 'new.jpg');
    },
  );

  test('controller reports scale and rejects oversized workspaces', () {
    final controller = ReviewWorkspaceController();
    final oversizedAssets = [
      for (var index = 0; index <= noemaWorkspaceHardPhotoLimit; index += 1)
        SelectedGalleryAsset(id: 'too-many-$index', name: 'IMG_$index.JPG'),
    ];

    expect(
      controller.loadSelectedAssets(oversizedAssets, name: '过大'),
      ReviewWorkspaceImportResult.tooManyPhotos,
    );
    expect(controller.workspaces, isEmpty);

    final nearLimitAssets = [
      for (var index = 0; index < noemaWorkspaceHardPhotoLimit - 1; index += 1)
        SelectedGalleryAsset(id: 'base-$index', name: 'IMG_$index.JPG'),
    ];
    expect(
      controller.loadSelectedAssets(nearLimitAssets, name: '接近上限'),
      ReviewWorkspaceImportResult.applied,
    );

    final snapshot = controller.scaleSnapshot;
    expect(snapshot.workspaceCount, 1);
    expect(snapshot.totalPhotoCount, noemaWorkspaceHardPhotoLimit - 1);
    expect(
      snapshot.largestWorkspacePhotoCount,
      noemaWorkspaceHardPhotoLimit - 1,
    );
    expect(snapshot.hasLargeWorkspace, isTrue);
    expect(snapshot.hasBlockedWorkspace, isFalse);

    expect(
      controller.appendSelectedAssets(const [
        SelectedGalleryAsset(id: 'extra-1', name: 'extra-1.jpg'),
        SelectedGalleryAsset(id: 'extra-2', name: 'extra-2.jpg'),
      ]),
      ReviewWorkspaceImportResult.tooManyPhotos,
    );
    expect(
      controller.workspace.assets,
      hasLength(noemaWorkspaceHardPhotoLimit - 1),
    );
  });

  test('controller cache path updates keep existing cull groups', () {
    final matchingBytes = _checkerPng(inverted: false);
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets([
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        previewBytes: matchingBytes,
      ),
      SelectedGalleryAsset(
        id: '/tmp/b.jpg',
        name: 'B.jpg',
        previewBytes: matchingBytes,
      ),
    ], name: '友人');

    expect(controller.workspace.groups, hasLength(1));
    expect(
      controller.workspace.groups.single.groupReason,
      GroupReason.nearDuplicate,
    );
    final originalGroup = controller.workspace.groups.single;

    controller.updateAssetPreviewPath('photo-1', '/cache/a-preview.jpg');
    expect(
      controller.workspace.assetById('photo-1')?.photo.previewPath,
      '/cache/a-preview.jpg',
    );
    expect(controller.workspace.groups.single, same(originalGroup));

    controller.updateAssetThumbnailPath('photo-2', '/cache/b-thumb.jpg');
    expect(
      controller.workspace.assetById('photo-2')?.photo.thumbnailPath,
      '/cache/b-thumb.jpg',
    );
    expect(controller.workspace.groups.single, same(originalGroup));
  });

  test('controller removes assets by ids and clears decisions', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
      SelectedGalleryAsset(id: '/tmp/c.jpg', name: 'C.jpg'),
    ], name: '友人');
    controller.recordDecision('photo-1', Decision.keep);

    controller.removeAssetsByIds({'photo-1', 'photo-2'});

    expect(controller.workspace.assets, hasLength(1));
    expect(controller.workspace.assetById('photo-1'), isNull);
    expect(controller.decisions.containsKey('photo-1'), isFalse);
  });

  test('controller can remove assets without deleting cached files', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final deletedPaths = <Object?>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'deleteCachedFiles') {
        deletedPaths.addAll(call.arguments['paths'] as List<Object?>);
      }
      return Future<Object?>.value(1);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        thumbnailPath: '/cache/a-thumb.jpg',
      ),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ], name: '友人');

    controller.removeAssetsByIds({'photo-1'}, deleteCachedFiles: false);
    await Future<void>.delayed(Duration.zero);

    expect(controller.workspace.assetById('photo-1'), isNull);
    expect(deletedPaths, isEmpty);
  });

  test(
    'controller removes assets after system media delete succeeds',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'galleryAccessStatus') {
          return Future<Object?>.value('full');
        }
        if (call.method == 'deleteMediaItems') {
          return Future<Object?>.value({
            'deleted': true,
            'count': 1,
            'cancelled': false,
          });
        }
        if (call.method == 'deleteCachedFiles') {
          return Future<Object?>.value(1);
        }
        return Future<Object?>.value(null);
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final controller = ReviewWorkspaceController(
        mediaPicker: const NoemaMediaPicker(channel: channel),
      );
      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'asset-1',
          name: 'A.jpg',
          sourceUri: 'content://media/external/images/media/1',
          thumbnailPath: '/cache/a-thumb.jpg',
        ),
        SelectedGalleryAsset(id: 'asset-2', name: 'B.jpg'),
      ], name: '友人');

      final removed = await controller.removeAssetsByIdsAfterSystemDelete({
        'photo-1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(removed, isTrue);
      expect(controller.workspace.assetById('photo-1'), isNull);
      expect(
        calls
            .where((call) => call.method == 'deleteMediaItems')
            .single
            .arguments['uris'],
        ['content://media/external/images/media/1'],
      );
      expect(
        calls
            .where((call) => call.method == 'deleteCachedFiles')
            .single
            .arguments['paths'],
        ['/cache/a-thumb.jpg'],
      );
    },
  );

  test(
    'controller requests gallery access before system media delete',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'galleryAccessStatus') {
          return Future<Object?>.value('denied');
        }
        if (call.method == 'requestGalleryAccess') {
          return Future<Object?>.value('full');
        }
        if (call.method == 'deleteMediaItems') {
          return Future<Object?>.value({
            'deleted': true,
            'count': 1,
            'cancelled': false,
          });
        }
        if (call.method == 'deleteCachedFiles') {
          return Future<Object?>.value(1);
        }
        return Future<Object?>.value(null);
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final controller = ReviewWorkspaceController(
        mediaPicker: const NoemaMediaPicker(channel: channel),
      );
      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'asset-1',
          name: 'A.jpg',
          sourceUri: 'content://media/external/images/media/1',
        ),
      ], name: '友人');

      final removed = await controller.removeAssetsByIdsAfterSystemDelete({
        'photo-1',
      });

      expect(removed, isTrue);
      expect(
        calls.map((call) => call.method),
        containsAllInOrder([
          'galleryAccessStatus',
          'requestGalleryAccess',
          'deleteMediaItems',
        ]),
      );
      expect(controller.workspace.assetById('photo-1'), isNull);
    },
  );

  test(
    'controller keeps assets when system media delete is cancelled',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'galleryAccessStatus') {
          return Future<Object?>.value('full');
        }
        if (call.method == 'deleteMediaItems') {
          return Future<Object?>.value({
            'deleted': false,
            'count': 0,
            'cancelled': true,
          });
        }
        return Future<Object?>.value(null);
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final controller = ReviewWorkspaceController(
        mediaPicker: const NoemaMediaPicker(channel: channel),
      );
      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'asset-1',
          name: 'A.jpg',
          sourceUri: 'content://media/external/images/media/1',
          thumbnailPath: '/cache/a-thumb.jpg',
        ),
      ], name: '友人');

      final removed = await controller.removeAssetsByIdsAfterSystemDelete({
        'photo-1',
      });

      expect(removed, isFalse);
      expect(controller.workspace.assetById('photo-1'), isNotNull);
      expect(
        calls.where((call) => call.method == 'deleteCachedFiles'),
        isEmpty,
      );
    },
  );

  test('controller rejects system media delete without source uris', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return Future<Object?>.value(null);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController(
      mediaPicker: const NoemaMediaPicker(channel: channel),
    );
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: 'asset-1', name: 'A.jpg'),
    ], name: '友人');

    expect(
      controller.removeAssetsByIdsAfterSystemDelete({'photo-1'}),
      throwsA(isA<NoemaSystemPhotoDeleteUnavailableException>()),
    );
    expect(controller.workspace.assetById('photo-1'), isNotNull);
    expect(calls, isEmpty);
  });

  test(
    'controller reports whether selected assets can delete system media',
    () {
      final controller = ReviewWorkspaceController();
      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'asset-1',
          name: 'A.jpg',
          sourceUri: 'content://media/external/images/media/1',
        ),
        SelectedGalleryAsset(id: 'asset-2', name: 'B.jpg'),
      ], name: '友人');

      expect(controller.canDeleteSystemMediaForAssetIds({'photo-1'}), isTrue);
      expect(controller.canDeleteSystemMediaForAssetIds({'photo-2'}), isFalse);
      expect(
        controller.canDeleteSystemMediaForAssetIds({'photo-1', 'photo-2'}),
        isFalse,
      );
    },
  );

  test('controller skips import-time unavailable assets', () {
    final controller = ReviewWorkspaceController();

    final result = controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: '/tmp/missing.jpg',
        name: 'Missing.jpg',
        previewUnavailable: true,
      ),
      SelectedGalleryAsset(id: '/tmp/ok.jpg', name: 'OK.jpg'),
    ], name: '友人');

    expect(result, ReviewWorkspaceImportResult.applied);
    expect(controller.workspace.assets, hasLength(1));
    expect(controller.workspace.assets.single.displayName, 'OK.jpg');
  });

  test('controller persists notified missing indexes and clears them', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ], name: '友人');

    controller.markAssetMissing('photo-1');
    expect(controller.missingAssetIndexes, hasLength(1));
    expect(controller.unnotifiedMissingAssetIndexes, hasLength(1));
    expect(controller.missingAssetIndexes.single.displayName, 'A.jpg');

    controller.markMissingAssetIndexesNotified({'photo-1'});
    expect(controller.unnotifiedMissingAssetIndexes, isEmpty);
    expect(controller.missingAssetIndexes.single.notified, isTrue);

    final restored = ReviewWorkspace.fromJson(controller.workspace.toJson());
    expect(restored.missingAssetIndexes, hasLength(1));
    expect(restored.missingAssetIndexes.single.notified, isTrue);

    controller.clearMissingAssetIndexes({'photo-1'});
    expect(controller.workspace.assets.map((asset) => asset.photo.id), [
      'photo-2',
    ]);
    expect(controller.missingAssetIndexes, isEmpty);
  });

  test('controller clears missing index when cache recovers', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
    ], name: '友人');

    controller.markAssetMissing('photo-1');
    expect(controller.missingAssetIndexes, hasLength(1));

    controller.updateAssetThumbnailPath('photo-1', '/cache/a-thumb.jpg');
    expect(controller.missingAssetIndexes, isEmpty);
  });

  test('controller does not auto-notify missing assets with cache', () {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: '/tmp/a.jpg',
        name: 'A.jpg',
        thumbnailPath: '/cache/a-thumb.jpg',
      ),
    ], name: '友人');

    controller.markAssetMissing('photo-1');

    expect(controller.workspace.missingAssetIndexes, hasLength(1));
    expect(controller.missingAssetIndexes, isEmpty);
    expect(controller.unnotifiedMissingAssetIndexes, isEmpty);
  });

  test('controller generates import previews in background', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final previewCompleters = <Completer<String?>>[];
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      if (call.method == 'createPreview') {
        final completer = Completer<String?>();
        previewCompleters.add(completer);
        return completer.future;
      }
      return Future<Object?>.value(1);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController(
      backgroundPreviewCachingEnabled: true,
      backgroundPreviewStartDelay: Duration.zero,
      backgroundPreviewItemGap: Duration.zero,
    );
    addTearDown(controller.dispose);

    final result = controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'content://media/photo/1',
        name: 'A.jpg',
        sourceUri: 'content://media/photo/1',
        thumbnailPath: '/cache/a-thumb.jpg',
      ),
    ], name: '友人');

    expect(result, ReviewWorkspaceImportResult.applied);
    expect(controller.workspace.assets.single.photo.previewPath, isNull);

    await Future<void>.delayed(Duration.zero);
    expect(previewCompleters, hasLength(1));
    expect(calls.single.method, 'createPreview');
    expect(calls.single.arguments['maxSize'], 3072);

    previewCompleters.single.complete('/cache/a-preview.jpg');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.workspace.assets.single.photo.previewPath,
      '/cache/a-preview.jpg',
    );
  });

  test(
    'controller defers background preview work during interaction',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(noemaMediaPickerChannelName);
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'createPreview') {
          return Future<String?>.value('/cache/a-preview.jpg');
        }
        return Future<Object?>.value(1);
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final controller = ReviewWorkspaceController(
        backgroundPreviewCachingEnabled: true,
        backgroundPreviewStartDelay: Duration.zero,
        backgroundPreviewItemGap: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.loadSelectedAssets(const [
        SelectedGalleryAsset(
          id: 'content://media/photo/1',
          name: 'A.jpg',
          sourceUri: 'content://media/photo/1',
          thumbnailPath: '/cache/a-thumb.jpg',
        ),
      ], name: '友人');
      controller.deferBackgroundPreviewCaching(
        const Duration(milliseconds: 40),
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'createPreview'), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        calls.where((call) => call.method == 'createPreview'),
        hasLength(1),
      );
    },
  );

  test('controller deletes only unreferenced local cache paths', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return Future<Object?>.value(1);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'a',
        name: 'A.jpg',
        thumbnailPath: '/cache/a-thumb.jpg',
      ),
      SelectedGalleryAsset(
        id: 'shared',
        name: 'Shared A.jpg',
        thumbnailPath: '/cache/shared-thumb.jpg',
      ),
    ], name: 'A');
    final firstWorkspaceId = controller.workspace.session.id;
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'shared',
        name: 'Shared B.jpg',
        thumbnailPath: '/cache/shared-thumb.jpg',
      ),
    ], name: 'B');

    controller.deleteWorkspace(firstWorkspaceId);
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    final paths = calls.single.arguments['paths'] as List<Object?>;
    expect(paths, contains('/cache/a-thumb.jpg'));
    expect(paths, isNot(contains('/cache/shared-thumb.jpg')));
  });

  test('controller caps per-workspace preview cache paths', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final deletedPaths = <Object?>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'deleteCachedFiles') {
        deletedPaths.addAll(call.arguments['paths'] as List<Object?>);
      }
      return Future<Object?>.value(1);
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets([
      for (var index = 0; index < noemaWorkspacePreviewCacheLimit + 2; index++)
        SelectedGalleryAsset(id: 'asset-$index', name: 'Asset $index.jpg'),
    ], name: 'Cache cap');

    for (var index = 0; index < noemaWorkspacePreviewCacheLimit + 2; index++) {
      controller.updateAssetPreviewPath(
        'photo-${index + 1}',
        '/cache/preview-$index.jpg',
      );
    }
    await Future<void>.delayed(Duration.zero);

    final previewPaths = [
      for (final asset in controller.workspace.assets) asset.photo.previewPath,
    ];

    expect(
      previewPaths.where((path) => path != null),
      hasLength(noemaWorkspacePreviewCacheLimit),
    );
    expect(
      controller.workspace.assetById('photo-1')?.photo.previewPath,
      isNull,
    );
    expect(
      controller.workspace.assetById('photo-2')?.photo.previewPath,
      isNull,
    );
    expect(
      controller.workspace.assetById('photo-3')?.photo.previewPath,
      '/cache/preview-2.jpg',
    );
    expect(deletedPaths, contains('/cache/preview-0.jpg'));
    expect(deletedPaths, contains('/cache/preview-1.jpg'));
    expect(deletedPaths, isNot(contains('/cache/preview-2.jpg')));
  });
}

Uint8List _solidPng(int width, int height, img.Color color) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _checkerPng({required bool inverted}) {
  final image = img.Image(width: 8, height: 8);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      final light = (x + y).isEven != inverted;
      final value = light ? 240 : 24;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _paletteScenePng({required img.Color low, required img.Color high}) {
  final image = img.Image(width: 24, height: 24);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      image.setPixel(x, y, x < image.width ~/ 2 ? low : high);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

ReviewAsset _reviewAsset(
  String photoId,
  DateTime createdAt, {
  bool createdAtEstimated = false,
}) {
  return ReviewAsset(
    photo: PhotoAsset(
      id: photoId,
      sessionId: 'session-chain',
      platformAssetId: photoId,
      createdAt: createdAt,
      updatedAt: createdAt,
      width: 4032,
      height: 3024,
      mediaKind: MediaKind.photo,
      availability: AssetAvailability.available,
      createdAtEstimated: createdAtEstimated,
    ),
    displayName: '$photoId.jpg',
  );
}

AnalysisResult _manualAnalysis({
  required String photoId,
  required String hashHex,
  double brightnessScore = 0.55,
  List<int>? colorSignature,
  List<int>? luminanceSignature,
}) {
  return AnalysisResult(
    photoId: photoId,
    blurScore: 0.9,
    brightnessScore: brightnessScore,
    exposureFlag: ExposureFlag.normal,
    similarityHash: 1,
    averageHashHex: hashHex,
    differenceHashHex: hashHex,
    perceptualHashHex: hashHex,
    colorSignature:
        colorSignature ??
        const [90, 70, 50, 40, 40, 50, 70, 90, 55, 55, 55, 55],
    luminanceSignature:
        luminanceSignature ??
        const [30, 40, 50, 60, 35, 45, 55, 65, 40, 50, 60, 70, 45, 55, 65, 75],
    qualityFlags: const [],
    analyzedAt: DateTime(2026, 6, 4, 11),
  );
}

List<int> _signature({required int length, required int value}) {
  return List<int>.filled(length, value, growable: false);
}
