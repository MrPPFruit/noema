import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/series_appraisal.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_dialog.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';
import 'package:noema/core/widgets/noema_sort_icons.dart';
import 'package:noema/core/widgets/photo_wall_badges.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appraise/appraise_band.dart';
import 'package:noema/features/appraise/appraise_ai_client.dart';
import 'package:noema/features/appraise/appraise_ai_settings_store.dart';
import 'package:noema/features/appraise/appraise_image_bytes.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/observe/observe_photo_wall_layout.dart';
import 'package:noema/features/processing/photo_viewer_page.dart';

const _appraiseEase = Cubic(0.16, 1, 0.3, 1);
const _appraiseWallShadowGutter = 22.0;
const _appraiseWallTopPadding = 10.0;
const _appraiseWallBottomPadding = 132.0;
const _appraiseWallTopFadeHeight = 64.0;
const _appraiseWallBottomFadeHeight = 132.0;
const _appraiseThumbnailMaxSize = 640;
const _appraiseActionRowTop = NoemaSceneMetrics.bodyTop + 4.0;
const _appraiseContentTop = 128.0;
const _appraiseViewerSheetDefaultFraction = 0.75;
const _appraiseViewerSheetPeekFraction = 0.25;
const _appraiseViewerSheetHiddenFraction = 0.10;
const _appraiseViewerSheetChromeHeight = 78.0;
const _appraiseViewerSheetRadius = 34.0;
const _appraiseViewerSheetContentX = 28.0;
const _appraiseSvgIconRoot = 'assets/icons/svg/currentColor';
const _appraiseClarityIcon = '$_appraiseSvgIconRoot/clarity-sparkles.svg';
const _appraiseExposureIcon = '$_appraiseSvgIconRoot/exposure-sun.svg';
const _appraiseCameraIcon = '$_appraiseSvgIconRoot/camera-params.svg';
const _appraiseFavoriteIcon = '$_appraiseSvgIconRoot/favorite-heart.svg';
const _appraiseSectionDiamondIcon = '$_appraiseSvgIconRoot/section-diamond.svg';
const _appraiseThemeIcon = '$_appraiseSvgIconRoot/theme-target.svg';
const _appraiseTechIcon = '$_appraiseSvgIconRoot/tech-aperture.svg';
const _appraiseEmotionIcon = '$_appraiseSvgIconRoot/emotion-heart-circle.svg';
const _appraiseImaginationIcon = '$_appraiseSvgIconRoot/imagination-ring.svg';
const _appraiseExternalLinksChannel = MethodChannel('noema/external_links');
const _qwenBailianConsoleUrl = 'https://bailian.console.aliyun.com/';
const _qwenApiKeyHelpUrl =
    'https://help.aliyun.com/zh/model-studio/get-api-key';
const _qwenOpenAiHelpUrl =
    'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope';

enum _AppraiseBand { flaw, formed, fine, cherished }

enum _AppraiseSort { highToLow, lowToHigh }

enum _AppraiseSeriesConfirmAction { cancel, runSinglesFirst, runSeries }

class AppraiseScreen extends StatefulWidget {
  const AppraiseScreen({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.initialPhotoId,
    this.aiClient = const AppraiseAiClient(),
    this.aiSettingsStore,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final String? initialPhotoId;
  final AppraiseAiClient aiClient;
  final AppraiseAiSettingsStore? aiSettingsStore;

  @override
  State<AppraiseScreen> createState() => _AppraiseScreenState();
}

class _AppraiseScreenState extends State<AppraiseScreen> {
  final ScrollController _wallScrollController = ScrollController();
  final Set<String> _cherishedPhotoIds = {};
  final Map<String, AppraiseAiPhotoResult> _aiResults = {};
  final Set<String> _aiInFlightPhotoIds = {};
  final Set<String> _metadataHydrationPhotoIds = {};

  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;
  late final AppraiseAiSettingsStore _aiSettingsStore;

  _AppraiseBand _selectedBand = _AppraiseBand.formed;
  _AppraiseSort _sort = _AppraiseSort.highToLow;
  AppraiseAiSettingsLibrary _aiSettingsLibrary =
      AppraiseAiSettingsLibrary.defaults();
  AppraiseAiSettings _aiSettings = AppraiseAiSettings.defaults();
  AppraiseAiCheckResult? _lastAiCheckResult;
  bool _aiHintOpen = false;
  bool _aiCheckRunning = false;
  bool _aiBatchRunning = false;
  bool _aiBatchStopRequested = false;
  bool _aiBatchResumeRequested = false;
  List<_AppraiseRecord> _aiBatchResumeRecords = const [];
  int _aiBatchCompleted = 0;
  int _aiBatchTotal = 0;
  int _aiBatchRunSerial = 0;
  bool _seriesRunning = false;
  int _seriesCompleted = 0;
  int _seriesTotal = 0;
  String _seriesProgressLabel = '';
  PhotoSeriesAppraisal? _openSeriesAppraisal;
  List<_AppraiseRecord> _openSeriesRecords = const [];
  List<_AppraiseRecord> _openSeriesDisplayRecords = const [];
  String? _openedInitialPhotoId;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    _aiSettingsStore = widget.aiSettingsStore ?? AppraiseAiSettingsStore();
    widget.workspaceController.addListener(_handleWorkspaceChanged);
    _syncCherishedIdsWithWorkspace();
    _scheduleMissingExifHydration();
    unawaited(_restoreAiSettings());
  }

  @override
  void dispose() {
    widget.workspaceController.removeListener(_handleWorkspaceChanged);
    _wallScrollController.dispose();
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
  }

  void _handleWorkspaceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _syncCherishedIdsWithWorkspace();
    });
    _scheduleMissingExifHydration();
  }

  void _syncCherishedIdsWithWorkspace() {
    final activeIds = {
      for (final asset in widget.workspaceController.workspace.assets)
        asset.photo.id,
    };
    _metadataHydrationPhotoIds.removeWhere((id) => !activeIds.contains(id));
    _cherishedPhotoIds
      ..removeWhere((id) => !activeIds.contains(id))
      ..addAll(
        widget.workspaceController.workspace.assets
            .where((asset) => asset.photo.isCherished)
            .map((asset) => asset.photo.id),
      );
  }

  Future<void> _restoreAiSettings() async {
    final settingsLibrary = await _aiSettingsStore.readSettingsLibrary();
    if (!mounted) {
      return;
    }
    setState(() {
      _aiSettingsLibrary = settingsLibrary;
      _aiSettings = settingsLibrary.activeSettings;
      _lastAiCheckResult = null;
    });
  }

  void _handleAiSettingsChanged(AppraiseAiSettingsLibrary settingsLibrary) {
    setState(() {
      _aiSettingsLibrary = settingsLibrary;
      _aiSettings = settingsLibrary.activeSettings;
      _lastAiCheckResult = null;
    });
    unawaited(_aiSettingsStore.writeSettingsLibrary(settingsLibrary));
  }

  void _scheduleMissingExifHydration() {
    if (!NoemaMediaPicker.isAndroidSupported) {
      return;
    }
    const mediaPicker = NoemaMediaPicker();
    for (final asset in widget.workspaceController.workspace.assets) {
      final photo = asset.photo;
      final sourceUri = photo.sourceUri;
      if (sourceUri == null ||
          sourceUri.isEmpty ||
          photo.exif?.isNotEmpty == true ||
          !_metadataHydrationPhotoIds.add(photo.id)) {
        continue;
      }
      unawaited(_hydrateMissingExif(mediaPicker, photo.id, sourceUri));
    }
  }

  Future<void> _hydrateMissingExif(
    NoemaMediaPicker mediaPicker,
    String photoId,
    String sourceUri,
  ) async {
    try {
      final metadata = await mediaPicker.loadMetadata(uri: sourceUri);
      if (!mounted || metadata == null || metadata.exif?.isNotEmpty != true) {
        return;
      }
      widget.workspaceController.updateAssetMetadata(photoId, metadata);
    } catch (_) {
      // Metadata hydration is opportunistic; the existing sheet still works
      // without camera parameters when a provider strips EXIF.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final strings = NoemaStrings.of(context);
        final palette = NoemaPalette.fromTone(
          _appearanceController.resolveTone(context),
        );
        final workspace = widget.workspaceController.workspace;
        final records = _recordsFor(workspace);
        final visibleBands = _visibleBands(records);
        final selectedBand = visibleBands.contains(_selectedBand)
            ? _selectedBand
            : visibleBands.first;
        final selectedLaneRecords = _recordsForBand(records, selectedBand);
        final hasAiScore = selectedLaneRecords.any(_hasAppraisalScore);
        final laneRecords = _sortedRecords(selectedLaneRecords);
        final aiReviewedCount = laneRecords.where(_hasAppraisalScore).length;
        final aiPendingCount = laneRecords.length - aiReviewedCount;
        final selectedSeriesBand = _seriesBandFor(selectedBand);
        final seriesAppraisal = selectedSeriesBand == null
            ? null
            : workspace.seriesAppraisalFor(selectedSeriesBand);
        final seriesPhotoSetHash = _seriesPhotoSetHash(laneRecords);
        final seriesCanGenerate =
            selectedSeriesBand != null && laneRecords.length >= 2;
        final showSeries =
            selectedSeriesBand != null &&
            (seriesCanGenerate || seriesAppraisal != null);
        final seriesIsStale =
            seriesCanGenerate &&
            seriesAppraisal != null &&
            seriesAppraisal.photoSetHash != seriesPhotoSetHash;
        _scheduleInitialPreview(records);
        return Scaffold(
          body: NoemaSceneFrame(
            palette: palette,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: NoemaSceneMetrics.markLeft,
                  top: NoemaSceneMetrics.markTop,
                  child: NoemaThemeMark(palette: palette, mark: '鉴'),
                ),
                Positioned(
                  left: NoemaSceneMetrics.topBarInset,
                  right: NoemaSceneMetrics.topBarInset,
                  top: NoemaSceneMetrics.topBarTop,
                  child: _AppraiseTopBar(
                    palette: palette,
                    onBack: () => context.go(NoemaRoutes.observe),
                  ),
                ),
                Positioned(
                  right: 28,
                  top: _appraiseActionRowTop,
                  child: NoemaGlassIconButton(
                    palette: palette,
                    tooltip: strings.isZh ? 'AI 设置' : 'AI settings',
                    icon: Icons.settings_suggest_rounded,
                    surfaceOpacityScale: 0,
                    onPressed: _showAiHint,
                  ),
                ),
                Positioned(
                  left: NoemaSceneMetrics.sideInset,
                  right: NoemaSceneMetrics.sideInset,
                  top: _appraiseContentTop,
                  bottom: 0,
                  child: records.isEmpty
                      ? _AppraiseEmptyState(palette: palette)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AppraiseBandPicker(
                              palette: palette,
                              bands: visibleBands,
                              selectedBand: selectedBand,
                              records: records,
                              onSelect: (band) {
                                setState(() {
                                  _selectedBand = band;
                                });
                              },
                            ),
                            const SizedBox(height: 2),
                            _AppraiseToolRow(
                              palette: palette,
                              sort: _sort,
                              aiRunning: _aiBatchRunning,
                              aiCompleted: _aiBatchCompleted,
                              aiTotal: _aiBatchTotal,
                              aiReviewed: aiReviewedCount,
                              aiPending: aiPendingCount,
                              showSort: hasAiScore,
                              showSeries: showSeries,
                              seriesRunning: _seriesRunning,
                              seriesCompleted: _seriesCompleted,
                              seriesTotal: _seriesTotal,
                              seriesProgressLabel: _seriesProgressLabel,
                              seriesHasResult:
                                  seriesAppraisal != null && !seriesIsStale,
                              seriesIsStale: seriesIsStale,
                              onToggleSort: _toggleSort,
                              onRequestAi: () =>
                                  _requestAiForCurrentLane(laneRecords),
                              onStopAi: _stopAiBatch,
                              onRequestSeries: () => _handleSeriesAction(
                                laneRecords,
                                records,
                                selectedBand,
                                seriesAppraisal,
                                seriesPhotoSetHash,
                              ),
                            ),
                            Expanded(
                              child: _AppraisePhotoWall(
                                palette: palette,
                                records: laneRecords,
                                aiResults: _aiResults,
                                scrollController: _wallScrollController,
                                onOpen: (record) =>
                                    _openPreview(laneRecords, record),
                                onToggleCherished: _toggleCherished,
                                onThumbnailLoaded: widget
                                    .workspaceController
                                    .updateAssetThumbnailPath,
                              ),
                            ),
                          ],
                        ),
                ),
                if (_aiHintOpen)
                  Positioned.fill(
                    child: _AppraiseAiHintPanel(
                      palette: palette,
                      settingsLibrary: _aiSettingsLibrary,
                      initialCheckResult: _lastAiCheckResult,
                      onSettingsChanged: _handleAiSettingsChanged,
                      onCheck: _checkAiSettingsFor,
                      onClose: () => setState(() => _aiHintOpen = false),
                    ),
                  ),
                if (_openSeriesAppraisal != null)
                  Positioned.fill(
                    child: _AppraiseSeriesSheetOverlay(
                      palette: palette,
                      appraisal: _openSeriesAppraisal!,
                      records: _openSeriesDisplayRecords,
                      currentRecords: _openSeriesRecords,
                      onClose: _closeSeriesSheet,
                      onOpenPhoto: (record) =>
                          _openPreview(_openSeriesDisplayRecords, record),
                      onRegenerate: () => _regenerateOpenSeries(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleInitialPreview(List<_AppraiseRecord> records) {
    final initialPhotoId = widget.initialPhotoId;
    if (initialPhotoId == null ||
        initialPhotoId.isEmpty ||
        _openedInitialPhotoId == initialPhotoId ||
        records.isEmpty) {
      return;
    }
    final initialRecord = records
        .where((record) => record.asset.photo.id == initialPhotoId)
        .firstOrNull;
    if (initialRecord == null) {
      return;
    }
    _openedInitialPhotoId = initialPhotoId;
    final scopedRecords = _sortedRecords(
      _recordsForBand(records, initialRecord.band),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _openPreview(scopedRecords, initialRecord);
    });
  }

  List<_AppraiseRecord> _recordsFor(ReviewWorkspace workspace) {
    final analysisByPhotoId = {
      for (final result in workspace.analysisResults) result.photoId: result,
    };
    return [
      for (final asset in workspace.assets)
        if (asset.photo.availability == AssetAvailability.available)
          _recordFor(asset, analysisByPhotoId[asset.photo.id]),
    ];
  }

  _AppraiseRecord _recordFor(ReviewAsset asset, AnalysisResult? analysis) {
    final appraisal = _localAppraisalFor(asset, analysis);
    final cherished =
        asset.photo.isCherished || _cherishedPhotoIds.contains(asset.photo.id);
    final aiResult = _aiResultFor(asset.photo);
    return _AppraiseRecord(
      asset: asset,
      appraisal: appraisal,
      band: _resolvedBandFor(appraisal, aiResult),
      cherished: cherished,
    );
  }

  List<_AppraiseBand> _visibleBands(List<_AppraiseRecord> records) {
    final bands = <_AppraiseBand>[_AppraiseBand.flaw, _AppraiseBand.formed];
    if (records.any((record) => record.band == _AppraiseBand.fine)) {
      bands.add(_AppraiseBand.fine);
    }
    if (records.any((record) => record.cherished)) {
      bands.add(_AppraiseBand.cherished);
    }
    return bands;
  }

  List<_AppraiseRecord> _recordsForBand(
    List<_AppraiseRecord> records,
    _AppraiseBand band,
  ) {
    if (band == _AppraiseBand.cherished) {
      return records.where((record) => record.cherished).toList();
    }
    return records.where((record) => record.band == band).toList();
  }

  List<_AppraiseRecord> _sortedRecords(List<_AppraiseRecord> records) {
    final sorted = [...records];
    sorted.sort((a, b) {
      final aAiScore = _appraisalScoreFor(a);
      final bAiScore = _appraisalScoreFor(b);
      if (aAiScore != null || bAiScore != null) {
        if (aAiScore == null) {
          return 1;
        }
        if (bAiScore == null) {
          return -1;
        }
        final aiScore = aAiScore.compareTo(bAiScore);
        if (aiScore != 0) {
          return _sort == _AppraiseSort.highToLow ? -aiScore : aiScore;
        }
      }
      return b.asset.photo.createdAt.compareTo(a.asset.photo.createdAt);
    });
    return sorted;
  }

  int? _appraisalScoreFor(_AppraiseRecord record) {
    return _aiResultFor(record.asset.photo)?.totalScore ??
        record.asset.photo.appraisalScore;
  }

  AppraiseAiPhotoResult? _aiResultFor(PhotoAsset photo) {
    final liveResult = _aiResults[photo.id];
    if (liveResult != null) {
      return liveResult;
    }
    final appraisal = photo.appraisal;
    if (appraisal == null) {
      return null;
    }
    return AppraiseAiPhotoResult.fromPhotoAppraisal(appraisal);
  }

  bool _hasAppraisalScore(_AppraiseRecord record) {
    return _appraisalScoreFor(record) != null;
  }

  void _toggleSort() {
    setState(() {
      _sort = switch (_sort) {
        _AppraiseSort.highToLow => _AppraiseSort.lowToHigh,
        _AppraiseSort.lowToHigh => _AppraiseSort.highToLow,
      };
    });
  }

  void _toggleCherished(String photoId) {
    final current =
        _cherishedPhotoIds.contains(photoId) ||
        (widget.workspaceController.workspace
                .assetById(photoId)
                ?.photo
                .isCherished ??
            false);
    final next = !current;
    setState(() {
      if (next) {
        _cherishedPhotoIds.add(photoId);
      } else {
        _cherishedPhotoIds.remove(photoId);
      }
    });
    widget.workspaceController.setAssetCherished(photoId, next);
  }

  void _showAiHint() {
    setState(() {
      _aiHintOpen = true;
    });
  }

  void _showAiConfigPrompt() {
    _showAppraiseAiConfigPrompt(
      context: context,
      palette: NoemaPalette.fromTone(
        _appearanceController.resolveTone(context),
      ),
      onConfigure: _showAiHint,
    );
  }

  Future<void> _requestAiForCurrentLane(List<_AppraiseRecord> records) async {
    if (_aiBatchRunning) {
      return;
    }
    if (!_aiSettings.isReady) {
      _showAiConfigPrompt();
      return;
    }
    if (_aiInFlightPhotoIds.isNotEmpty) {
      _queueAiResume(records);
      return;
    }

    final pending = _pendingAiRecords(records);
    if (pending.isEmpty) {
      _showAppraiseNotice('当前分类已完成 AI 品鉴');
      return;
    }

    final runSerial = ++_aiBatchRunSerial;
    setState(() {
      _aiBatchRunning = true;
      _aiBatchStopRequested = false;
      _aiBatchCompleted = 0;
      _aiBatchTotal = pending.length;
    });
    try {
      var nextIndex = 0;
      var round = 0;
      while (nextIndex < pending.length) {
        if (!mounted) {
          return;
        }
        if (_aiBatchStopRequested || runSerial != _aiBatchRunSerial) {
          break;
        }
        final batchSize = _aiParallelSizeForRound(round);
        final batch = pending.skip(nextIndex).take(batchSize).toList();
        nextIndex += batch.length;
        round += 1;

        final errors = <Object>[];
        await Future.wait([
          for (final record in batch)
            () async {
              final error = await _runTrackedAiAppraisal(record);
              if (error != null) {
                errors.add(error);
              }
              if (mounted &&
                  runSerial == _aiBatchRunSerial &&
                  !_aiBatchStopRequested) {
                setState(() {
                  _aiBatchCompleted += 1;
                });
              }
            }(),
        ]);
        if (_aiBatchStopRequested || runSerial != _aiBatchRunSerial) {
          break;
        }
        if (errors.isNotEmpty) {
          throw errors.first;
        }
      }
      if (mounted && runSerial == _aiBatchRunSerial) {
        _showAppraiseNotice(_aiBatchStopRequested ? '已停止 AI 品鉴' : 'AI 品鉴完成');
      }
    } on Object catch (error) {
      if (mounted && runSerial == _aiBatchRunSerial) {
        _showAppraiseNotice('$error');
      }
    } finally {
      if (mounted && runSerial == _aiBatchRunSerial) {
        setState(() {
          _aiBatchRunning = false;
          _aiBatchStopRequested = false;
          _aiBatchCompleted = 0;
          _aiBatchTotal = 0;
        });
      }
    }
  }

  List<_AppraiseRecord> _pendingAiRecords(List<_AppraiseRecord> records) {
    return [
      for (final record in records)
        if (_aiResultFor(record.asset.photo) == null &&
            !_aiInFlightPhotoIds.contains(record.asset.photo.id))
          record,
    ];
  }

  Future<void> _handleSeriesAction(
    List<_AppraiseRecord> records,
    List<_AppraiseRecord> displaySourceRecords,
    _AppraiseBand band,
    PhotoSeriesAppraisal? existing,
    String photoSetHash,
  ) async {
    if (_seriesRunning) {
      return;
    }
    final seriesBand = _seriesBandFor(band);
    if (seriesBand == null) {
      return;
    }
    if (existing != null) {
      _openSeriesSheet(
        existing,
        records,
        displayRecords: _seriesDisplayRecordsForAppraisal(
          allRecords: displaySourceRecords,
          appraisal: existing,
        ),
      );
      return;
    }
    if (records.length < 2) {
      _showAppraiseNotice('当前分类至少需要两张照片才能进行系列品鉴');
      return;
    }
    if (!_aiSettings.isReady) {
      _showAiConfigPrompt();
      return;
    }
    final strings = NoemaStrings.of(context);
    final action = await _showAppraiseSeriesConfirmPrompt(
      context: context,
      palette: NoemaPalette.fromTone(
        _appearanceController.resolveTone(context),
      ),
      count: records.length,
      categoryLabel: _bandLabel(strings, band),
      replacingExisting: existing != null,
      pendingSingleCount: band == _AppraiseBand.formed
          ? _pendingAiRecords(records).length
          : 0,
    );
    if (!mounted || action == _AppraiseSeriesConfirmAction.cancel) {
      return;
    }
    if (action == _AppraiseSeriesConfirmAction.runSinglesFirst) {
      await _requestAiForCurrentLane(records);
      return;
    }
    await _runSeriesAppraisal(
      records: records,
      band: seriesBand,
      categoryLabel: _bandLabel(strings, band),
      photoSetHash: photoSetHash,
    );
  }

  Future<void> _regenerateOpenSeries() async {
    final appraisal = _openSeriesAppraisal;
    if (appraisal == null) {
      return;
    }
    if (_openSeriesRecords.length < 2) {
      _showAppraiseNotice('当前分类至少需要两张照片才能重新生成系列品鉴');
      return;
    }
    if (!_aiSettings.isReady) {
      _showAiConfigPrompt();
      return;
    }
    final action = await _showAppraiseSeriesConfirmPrompt(
      context: context,
      palette: NoemaPalette.fromTone(
        _appearanceController.resolveTone(context),
      ),
      count: _openSeriesRecords.length,
      categoryLabel: _seriesBandLabel(appraisal.band),
      replacingExisting: true,
      pendingSingleCount: appraisal.band == SeriesAppraisalBand.formed
          ? _pendingAiRecords(_openSeriesRecords).length
          : 0,
    );
    if (!mounted || action == _AppraiseSeriesConfirmAction.cancel) {
      return;
    }
    final records = List<_AppraiseRecord>.of(_openSeriesRecords);
    if (action == _AppraiseSeriesConfirmAction.runSinglesFirst) {
      _closeSeriesSheet();
      await _requestAiForCurrentLane(records);
      return;
    }
    _closeSeriesSheet();
    await _runSeriesAppraisal(
      records: records,
      band: appraisal.band,
      categoryLabel: _seriesBandLabel(appraisal.band),
      photoSetHash: _seriesPhotoSetHash(records),
    );
  }

  Future<void> _runSeriesAppraisal({
    required List<_AppraiseRecord> records,
    required SeriesAppraisalBand band,
    required String categoryLabel,
    required String photoSetHash,
  }) async {
    setState(() {
      _seriesRunning = true;
      _seriesCompleted = 0;
      _seriesTotal = records.length;
      _seriesProgressLabel = '准备素材';
    });
    try {
      final photos = <AppraiseAiSeriesPhoto>[];
      for (var index = 0; index < records.length; index += 1) {
        final record = records[index];
        final bytes = await appraiseImageBytesForAsset(record.asset);
        if (bytes == null || bytes.isEmpty) {
          throw AppraiseAiException(
            '“${record.asset.displayName}”没有可发送给 AI 的照片数据',
          );
        }
        photos.add(
          AppraiseAiSeriesPhoto(
            id: record.asset.photo.id,
            label: record.asset.displayName,
            imageBytes: bytes,
            mimeType: appraiseImageMimeTypeForAsset(record.asset),
            captureTime: record.asset.photo.createdAt,
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _seriesCompleted = index + 1;
        });
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _seriesProgressLabel = '分析';
      });
      final result = await widget.aiClient.appraiseSeries(
        settings: _aiSettings,
        photos: photos,
        categoryLabel: categoryLabel,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _seriesProgressLabel = progress.label;
            _seriesCompleted = progress.completed;
            _seriesTotal = progress.total;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _seriesProgressLabel = '保存结果';
        _seriesCompleted = 1;
        _seriesTotal = 1;
      });
      final now = DateTime.now();
      final range = _seriesCaptureRange(records);
      final appraisal = PhotoSeriesAppraisal(
        id: '${widget.workspaceController.workspace.session.id}-${band.name}-series',
        sessionId: widget.workspaceController.workspace.session.id,
        band: band,
        photoIds: [for (final record in records) record.asset.photo.id],
        photoSetHash: photoSetHash,
        captureStartAt: range.start,
        captureEndAt: range.end,
        createdAt:
            widget.workspaceController.workspace
                .seriesAppraisalFor(band)
                ?.createdAt ??
            now,
        updatedAt: now,
        provider: _aiSettings.provider,
        model: _aiSettings.model,
        promptVersion: 'series-v1',
        result: result,
      );
      widget.workspaceController.setSeriesAppraisal(appraisal);
      if (!mounted) {
        return;
      }
      _showAppraiseNotice('系列品鉴完成');
      _openSeriesSheet(appraisal, records);
    } on Object catch (error) {
      if (mounted) {
        _showAppraiseNotice('$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _seriesRunning = false;
          _seriesCompleted = 0;
          _seriesTotal = 0;
          _seriesProgressLabel = '';
        });
      }
    }
  }

  void _openSeriesSheet(
    PhotoSeriesAppraisal appraisal,
    List<_AppraiseRecord> records, {
    List<_AppraiseRecord>? displayRecords,
  }) {
    setState(() {
      _openSeriesAppraisal = appraisal;
      _openSeriesRecords = List<_AppraiseRecord>.of(records);
      _openSeriesDisplayRecords = List<_AppraiseRecord>.of(
        displayRecords ?? records,
      );
      _aiHintOpen = false;
    });
  }

  void _closeSeriesSheet() {
    setState(() {
      _openSeriesAppraisal = null;
      _openSeriesRecords = const [];
      _openSeriesDisplayRecords = const [];
    });
  }

  void _stopAiBatch() {
    if (!_aiBatchRunning) {
      return;
    }
    setState(() {
      _aiBatchRunSerial += 1;
      _aiBatchStopRequested = true;
      _aiBatchRunning = false;
      _aiBatchCompleted = 0;
      _aiBatchTotal = 0;
    });
  }

  void _queueAiResume(List<_AppraiseRecord> records) {
    _aiBatchResumeRequested = true;
    _aiBatchResumeRecords = List<_AppraiseRecord>.of(records);
  }

  void _resumeQueuedAiBatchIfReady() {
    if (!mounted ||
        !_aiBatchResumeRequested ||
        _aiBatchRunning ||
        _aiInFlightPhotoIds.isNotEmpty) {
      return;
    }
    final records = _aiBatchResumeRecords;
    _aiBatchResumeRequested = false;
    _aiBatchResumeRecords = const [];
    if (records.isEmpty) {
      return;
    }
    unawaited(_requestAiForCurrentLane(records));
  }

  void _showAppraiseNotice(String message) {
    final messageController = NoemaBackNavigationScope.maybeOf(
      context,
    )?.messageController;
    if (messageController != null) {
      messageController.show(message);
      return;
    }
    final palette = NoemaPalette.fromTone(
      _appearanceController.resolveTone(context),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.ink,
            fontFamily: 'LXGWWenKaiGB',
            fontFamilyFallback: const ['NoemaCjkFallback'],
          ),
        ),
        backgroundColor: palette.sheet.withValues(alpha: 0.94),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(34, 0, 34, 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.glassBorder),
        ),
      ),
    );
  }

  void _openPreview(List<_AppraiseRecord> records, _AppraiseRecord initial) {
    final scopedAssets = [for (final record in records) record.asset];
    final recordById = {
      for (final record in records) record.asset.photo.id: record,
    };
    final sheetInset = ValueNotifier<double>(
      _appraiseViewerSheetHiddenFraction,
    );

    final navigator = Navigator.of(context);
    VoidCallback? unregisterBackHandler;
    unregisterBackHandler = NoemaBackNavigationScope.maybeOf(context)
        ?.registerLocalBackHandler(() {
          if (navigator.canPop()) {
            navigator.pop();
            return true;
          }
          return false;
        });

    navigator
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.transparent,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) {
              return PhotoViewerPage(
                workspaceController: widget.workspaceController,
                appearanceController: _appearanceController,
                initialPhotoId: initial.asset.photo.id,
                assets: scopedAssets,
                imageBottomInsetFraction: _appraiseViewerSheetHiddenFraction,
                imageBottomInsetFractionListenable: sheetInset,
                overlayBuilder: (context, palette, asset, index, total) {
                  final record =
                      recordById[asset.photo.id] ??
                      _recordFor(asset, _analysisFor(asset.photo.id));
                  return _AppraiseViewerOverlay(
                    key: const ValueKey('appraise-viewer-overlay'),
                    palette: palette,
                    record: record.copyWith(
                      cherished: _cherishedPhotoIds.contains(asset.photo.id),
                    ),
                    index: index,
                    total: total,
                    aiSettingsLibrary: _aiSettingsLibrary,
                    aiSettings: _aiSettings,
                    aiCheckResult: _lastAiCheckResult,
                    initialAiResult: _aiResultFor(asset.photo),
                    onToggleCherished: () => _toggleCherished(asset.photo.id),
                    onAiSettingsChanged: _handleAiSettingsChanged,
                    onCheckAiSettings: _checkAiSettingsFor,
                    onRunAi: () => _runAiAppraisal(record),
                    onSheetFractionChanged: (fraction) {
                      sheetInset.value = fraction;
                    },
                  );
                },
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return child;
                },
          ),
        )
        .whenComplete(() {
          unregisterBackHandler?.call();
          sheetInset.dispose();
        });
  }

  AnalysisResult? _analysisFor(String photoId) {
    for (final result in widget.workspaceController.workspace.analysisResults) {
      if (result.photoId == photoId) {
        return result;
      }
    }
    return null;
  }

  Future<AppraiseAiCheckResult> _checkAiSettingsFor(
    AppraiseAiSettings settings,
  ) async {
    if (_aiCheckRunning) {
      return const AppraiseAiCheckResult(ok: false, message: '正在测试');
    }
    setState(() {
      _aiCheckRunning = true;
      _lastAiCheckResult = null;
    });
    final result = await widget.aiClient.checkVision(settings);
    if (!mounted) {
      return result;
    }
    setState(() {
      _aiSettingsLibrary = _aiSettingsLibrary.withActiveSettings(settings);
      _aiSettings = settings;
      _lastAiCheckResult = result;
      _aiCheckRunning = false;
    });
    return result;
  }

  Future<AppraiseAiPhotoResult> _runAiAppraisal(_AppraiseRecord record) async {
    final bytes = await appraiseImageBytesForAsset(record.asset);
    if (bytes == null || bytes.isEmpty) {
      throw const AppraiseAiException('没有可发送给 AI 的照片数据');
    }
    final result = await widget.aiClient.appraisePhoto(
      settings: _aiSettings,
      imageBytes: bytes,
      mimeType: appraiseImageMimeTypeForAsset(record.asset),
    );
    if (mounted) {
      setState(() {
        _aiResults[record.asset.photo.id] = result;
      });
      widget.workspaceController.setAssetAppraisal(
        record.asset.photo.id,
        result.toPhotoAppraisal(),
      );
    }
    return result;
  }

  Future<Object?> _runTrackedAiAppraisal(_AppraiseRecord record) async {
    final photoId = record.asset.photo.id;
    if (!_aiInFlightPhotoIds.add(photoId)) {
      return null;
    }
    try {
      await _runAiAppraisal(record);
      return null;
    } on Object catch (error) {
      return error;
    } finally {
      _aiInFlightPhotoIds.remove(photoId);
      if (_aiInFlightPhotoIds.isEmpty && _aiBatchResumeRequested) {
        scheduleMicrotask(_resumeQueuedAiBatchIfReady);
      }
    }
  }
}

class AppraiseSheetPhotoViewerPage extends StatefulWidget {
  const AppraiseSheetPhotoViewerPage({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.initialPhotoId,
    this.sort,
    this.aiClient = const AppraiseAiClient(),
    this.aiSettingsStore,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final String? initialPhotoId;
  final String? sort;
  final AppraiseAiClient aiClient;
  final AppraiseAiSettingsStore? aiSettingsStore;

  @override
  State<AppraiseSheetPhotoViewerPage> createState() =>
      _AppraiseSheetPhotoViewerPageState();
}

class _AppraiseSheetPhotoViewerPageState
    extends State<AppraiseSheetPhotoViewerPage> {
  final ValueNotifier<double> _sheetInset = ValueNotifier<double>(
    _appraiseViewerSheetHiddenFraction,
  );

  @override
  void dispose() {
    _sheetInset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PhotoViewerPage(
      workspaceController: widget.workspaceController,
      appearanceController: widget.appearanceController,
      initialPhotoId: widget.initialPhotoId,
      sort: widget.sort,
      imageBottomInsetFraction: _appraiseViewerSheetHiddenFraction,
      imageBottomInsetFractionListenable: _sheetInset,
      overlayBuilder: (context, palette, asset, index, total) {
        return _ObserveAppraiseViewerOverlay(
          key: const ValueKey('observe-appraise-viewer-overlay'),
          palette: palette,
          workspaceController: widget.workspaceController,
          aiClient: widget.aiClient,
          aiSettingsStore: widget.aiSettingsStore,
          asset: asset,
          index: index,
          total: total,
          onSheetFractionChanged: (fraction) {
            _sheetInset.value = fraction;
          },
        );
      },
    );
  }
}

class _ObserveAppraiseViewerOverlay extends StatefulWidget {
  const _ObserveAppraiseViewerOverlay({
    required this.palette,
    required this.workspaceController,
    required this.aiClient,
    required this.asset,
    required this.index,
    required this.total,
    required this.onSheetFractionChanged,
    super.key,
    this.aiSettingsStore,
  });

  final NoemaPalette palette;
  final ReviewWorkspaceController workspaceController;
  final AppraiseAiClient aiClient;
  final AppraiseAiSettingsStore? aiSettingsStore;
  final ReviewAsset asset;
  final int index;
  final int total;
  final ValueChanged<double> onSheetFractionChanged;

  @override
  State<_ObserveAppraiseViewerOverlay> createState() =>
      _ObserveAppraiseViewerOverlayState();
}

class _ObserveAppraiseViewerOverlayState
    extends State<_ObserveAppraiseViewerOverlay> {
  AppraiseAiSettingsLibrary _aiSettingsLibrary =
      AppraiseAiSettingsLibrary.defaults();
  AppraiseAiSettings _aiSettings = AppraiseAiSettings.defaults();
  AppraiseAiCheckResult? _aiCheckResult;
  late final AppraiseAiSettingsStore _aiSettingsStore;
  bool _aiCheckRunning = false;

  @override
  void initState() {
    super.initState();
    _aiSettingsStore = widget.aiSettingsStore ?? AppraiseAiSettingsStore();
    unawaited(_restoreAiSettings());
  }

  Future<void> _restoreAiSettings() async {
    final settingsLibrary = await _aiSettingsStore.readSettingsLibrary();
    if (!mounted) {
      return;
    }
    setState(() {
      _aiSettingsLibrary = settingsLibrary;
      _aiSettings = settingsLibrary.activeSettings;
      _aiCheckResult = null;
    });
  }

  void _handleAiSettingsChanged(AppraiseAiSettingsLibrary settingsLibrary) {
    setState(() {
      _aiSettingsLibrary = settingsLibrary;
      _aiSettings = settingsLibrary.activeSettings;
      _aiCheckResult = null;
    });
    unawaited(_aiSettingsStore.writeSettingsLibrary(settingsLibrary));
  }

  @override
  Widget build(BuildContext context) {
    final asset = _latestAsset();
    final record = _recordFor(asset);
    return _AppraiseViewerOverlay(
      palette: widget.palette,
      record: record,
      index: widget.index,
      total: widget.total,
      aiSettingsLibrary: _aiSettingsLibrary,
      aiSettings: _aiSettings,
      aiCheckResult: _aiCheckResult,
      initialAiResult: _aiResultFor(asset.photo),
      initialSheetFraction: _appraiseViewerSheetHiddenFraction,
      autoOpenSheetFraction: null,
      onToggleCherished: () {
        final current = _latestAsset().photo.isCherished;
        widget.workspaceController.setAssetCherished(asset.photo.id, !current);
      },
      onAiSettingsChanged: _handleAiSettingsChanged,
      onCheckAiSettings: _checkAiSettings,
      onRunAi: () => _runAiAppraisal(asset),
      onSheetFractionChanged: widget.onSheetFractionChanged,
    );
  }

  ReviewAsset _latestAsset() {
    return widget.workspaceController.workspace.assetById(
          widget.asset.photo.id,
        ) ??
        widget.asset;
  }

  _AppraiseRecord _recordFor(ReviewAsset asset) {
    final appraisal = _localAppraisalFor(asset, _analysisFor(asset.photo.id));
    final aiResult = _aiResultFor(asset.photo);
    return _AppraiseRecord(
      asset: asset,
      appraisal: appraisal,
      band: _resolvedBandFor(appraisal, aiResult),
      cherished: asset.photo.isCherished,
    );
  }

  AnalysisResult? _analysisFor(String photoId) {
    for (final result in widget.workspaceController.workspace.analysisResults) {
      if (result.photoId == photoId) {
        return result;
      }
    }
    return null;
  }

  AppraiseAiPhotoResult? _aiResultFor(PhotoAsset photo) {
    final appraisal = photo.appraisal;
    if (appraisal == null) {
      return null;
    }
    return AppraiseAiPhotoResult.fromPhotoAppraisal(appraisal);
  }

  Future<AppraiseAiCheckResult> _checkAiSettings(
    AppraiseAiSettings settings,
  ) async {
    if (_aiCheckRunning) {
      return const AppraiseAiCheckResult(ok: false, message: '正在测试');
    }
    setState(() {
      _aiCheckRunning = true;
      _aiCheckResult = null;
    });
    final result = await widget.aiClient.checkVision(settings);
    if (mounted) {
      setState(() {
        _aiSettingsLibrary = _aiSettingsLibrary.withActiveSettings(settings);
        _aiSettings = settings;
        _aiCheckResult = result;
        _aiCheckRunning = false;
      });
    }
    return result;
  }

  Future<AppraiseAiPhotoResult> _runAiAppraisal(ReviewAsset asset) async {
    final bytes = await appraiseImageBytesForAsset(asset);
    if (bytes == null || bytes.isEmpty) {
      throw const AppraiseAiException('没有可发送给 AI 的照片数据');
    }
    final result = await widget.aiClient.appraisePhoto(
      settings: _aiSettings,
      imageBytes: bytes,
      mimeType: appraiseImageMimeTypeForAsset(asset),
    );
    widget.workspaceController.setAssetAppraisal(
      asset.photo.id,
      result.toPhotoAppraisal(),
    );
    return result;
  }
}

class _AppraiseRecord {
  const _AppraiseRecord({
    required this.asset,
    required this.appraisal,
    required this.band,
    required this.cherished,
  });

  final ReviewAsset asset;
  final _LocalAppraisal appraisal;
  final _AppraiseBand band;
  final bool cherished;

  _AppraiseRecord copyWith({_AppraiseBand? band, bool? cherished}) {
    return _AppraiseRecord(
      asset: asset,
      appraisal: appraisal,
      band: band ?? this.band,
      cherished: cherished ?? this.cherished,
    );
  }
}

class _LocalAppraisal {
  const _LocalAppraisal({required this.gate, required this.signals});

  final AppraiseTechnicalGate gate;
  final List<_AppraiseSignal> signals;
}

class _AppraiseSignal {
  const _AppraiseSignal({required this.label, required this.value});

  final String label;
  final String value;
}

class _AppraiseTopBar extends StatelessWidget {
  const _AppraiseTopBar({required this.palette, required this.onBack});

  final NoemaPalette palette;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    return SizedBox(
      height: NoemaSceneMetrics.topBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: NoemaGlassIconButton(
              palette: palette,
              tooltip: strings.back,
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: onBack,
            ),
          ),
          NoemaWordmark(color: palette.ink, text: strings.appName),
        ],
      ),
    );
  }
}

class _AppraiseBandPicker extends StatelessWidget {
  const _AppraiseBandPicker({
    required this.palette,
    required this.bands,
    required this.selectedBand,
    required this.records,
    required this.onSelect,
  });

  final NoemaPalette palette;
  final List<_AppraiseBand> bands;
  final _AppraiseBand selectedBand;
  final List<_AppraiseRecord> records;
  final ValueChanged<_AppraiseBand> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: _appraiseEase,
        alignment: Alignment.center,
        child: Row(
          children: [
            for (final band in bands)
              Expanded(
                child: _AppraiseBandTab(
                  palette: palette,
                  band: band,
                  count: _recordCountForBand(records, band),
                  selected: selectedBand == band,
                  onTap: () => onSelect(band),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _recordCountForBand(List<_AppraiseRecord> records, _AppraiseBand band) {
  if (band == _AppraiseBand.cherished) {
    return records.where((record) => record.cherished).length;
  }
  return records.where((record) => record.band == band).length;
}

class _AppraiseBandTab extends StatelessWidget {
  const _AppraiseBandTab({
    required this.palette,
    required this.band,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final NoemaPalette palette;
  final _AppraiseBand band;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final label = _bandLabel(strings, band);
    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: _appraiseEase,
          padding: const EdgeInsets.only(top: 2),
          child: CustomPaint(
            painter: _AppraiseBandPainter(palette: palette, active: selected),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, selected ? -2 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.ink.withValues(
                          alpha: selected ? 0.92 : 0.58,
                        ),
                        fontFamily: noemaTitleCjkFontFamily,
                        fontFamilyFallback: const [
                          'LXGWWenKaiGB',
                          'NoemaCjkFallback',
                        ],
                        fontSize: selected ? 23 : 21,
                        height: 1,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 1, bottom: 1),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: palette.muted.withValues(alpha: 0.64),
                          fontFamily: 'NoemaDigits',
                          fontSize: selected ? 14 : 13,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppraiseBandPainter extends CustomPainter {
  const _AppraiseBandPainter({required this.palette, required this.active});

  final NoemaPalette palette;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 8;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final wash = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, y),
        const Offset(0, 6),
        [
          palette.glass.withValues(alpha: active ? 0.10 : 0.044),
          palette.glass.withValues(alpha: active ? 0.040 : 0.018),
          Colors.transparent,
        ],
        const [0, 0.58, 1],
      );
    canvas.drawRect(rect, wash);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = active ? 1.28 : 0.88
      ..shader = ui.Gradient.linear(
        Offset(0, y),
        Offset(size.width, y),
        [
          Colors.transparent,
          palette.ink.withValues(alpha: active ? 0.24 : 0.10),
          palette.ink.withValues(alpha: active ? 0.38 : 0.18),
          palette.ink.withValues(alpha: active ? 0.24 : 0.10),
          Colors.transparent,
        ],
        const [0, 0.22, 0.5, 0.78, 1],
      );
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
  }

  @override
  bool shouldRepaint(covariant _AppraiseBandPainter oldDelegate) {
    return oldDelegate.palette != palette || oldDelegate.active != active;
  }
}

class _AppraiseToolRow extends StatelessWidget {
  const _AppraiseToolRow({
    required this.palette,
    required this.sort,
    required this.aiRunning,
    required this.aiCompleted,
    required this.aiTotal,
    required this.aiReviewed,
    required this.aiPending,
    required this.showSort,
    required this.showSeries,
    required this.seriesRunning,
    required this.seriesCompleted,
    required this.seriesTotal,
    required this.seriesProgressLabel,
    required this.seriesHasResult,
    required this.seriesIsStale,
    required this.onToggleSort,
    required this.onRequestAi,
    required this.onStopAi,
    required this.onRequestSeries,
  });

  final NoemaPalette palette;
  final _AppraiseSort sort;
  final bool aiRunning;
  final int aiCompleted;
  final int aiTotal;
  final int aiReviewed;
  final int aiPending;
  final bool showSort;
  final bool showSeries;
  final bool seriesRunning;
  final int seriesCompleted;
  final int seriesTotal;
  final String seriesProgressLabel;
  final bool seriesHasResult;
  final bool seriesIsStale;
  final VoidCallback onToggleSort;
  final VoidCallback onRequestAi;
  final VoidCallback onStopAi;
  final VoidCallback onRequestSeries;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final aiCurrentLaneTotal = aiReviewed + aiPending;
    final progressLabel = '$aiReviewed/$aiCurrentLaneTotal';
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          NoemaGlassIconButton(
            palette: palette,
            tooltip: aiRunning
                ? (strings.isZh ? '停止 AI 品鉴' : 'Stop AI appraisal')
                : (strings.isZh ? 'AI 品鉴' : 'AI appraisal'),
            onPressed: aiRunning ? onStopAi : onRequestAi,
            child: aiRunning
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.ink.withValues(alpha: 0.72),
                        ),
                      ),
                      Icon(
                        Icons.stop_rounded,
                        size: 10,
                        color: palette.ink.withValues(alpha: 0.90),
                      ),
                    ],
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 22),
          ),
          Transform.translate(
            offset: const Offset(-4, 0),
            child: Tooltip(
              message: aiRunning && aiTotal > 0
                  ? (strings.isZh
                        ? '本轮 $aiCompleted/$aiTotal'
                        : 'This round $aiCompleted/$aiTotal')
                  : progressLabel,
              child: Text(
                progressLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted.withValues(alpha: 0.78),
                  fontFamily: 'NoemaDigits',
                  fontSize: 12,
                  height: 1.1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (showSeries) ...[
            const SizedBox(width: 8),
            _AppraiseToolChip(
              palette: palette,
              tooltip: seriesRunning
                  ? (strings.isZh ? '系列品鉴生成中' : 'Generating series appraisal')
                  : seriesHasResult
                  ? (strings.isZh ? '查看系列品鉴' : 'View series appraisal')
                  : seriesIsStale
                  ? (strings.isZh ? '重新生成系列品鉴' : 'Regenerate series appraisal')
                  : (strings.isZh ? '系列品鉴' : 'Series appraisal'),
              onPressed: seriesRunning ? null : onRequestSeries,
              icon: seriesRunning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.ink.withValues(alpha: 0.70),
                      ),
                    )
                  : Icon(
                      seriesHasResult
                          ? Icons.collections_bookmark_rounded
                          : Icons.dynamic_feed_rounded,
                      size: 18,
                    ),
              label: strings.isZh ? '系列品鉴' : 'Series',
              trailing: seriesRunning && seriesTotal > 0
                  ? '$seriesCompleted/$seriesTotal'
                  : null,
              attention: seriesIsStale,
              active: seriesHasResult || seriesIsStale,
              maxWidth: 124,
            ),
          ],
          const Spacer(),
          if (showSort)
            NoemaGlassIconButton(
              palette: palette,
              tooltip: sort == _AppraiseSort.highToLow
                  ? (strings.isZh ? '评分由高到低' : 'Score high to low')
                  : (strings.isZh ? '评分由低到高' : 'Score low to high'),
              onPressed: onToggleSort,
              child: NoemaScoreSortIcon(
                palette: palette,
                ascending: sort == _AppraiseSort.lowToHigh,
              ),
            ),
        ],
      ),
    );
  }
}

class _AppraiseToolChip extends StatelessWidget {
  const _AppraiseToolChip({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.attention = false,
    this.active = false,
    this.maxWidth,
  });

  final NoemaPalette palette;
  final String tooltip;
  final Widget icon;
  final String label;
  final String? trailing;
  final VoidCallback? onPressed;
  final bool attention;
  final bool active;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final enabled = onPressed != null;
    final foreground = enabled
        ? (active
              ? colors.accent.withValues(alpha: 0.82)
              : palette.muted.withValues(alpha: 0.82))
        : palette.muted.withValues(alpha: 0.52);
    final background = active
        ? colors.accentMuted.withValues(alpha: 0.18)
        : palette.glass.withValues(
            alpha: palette.tone == NoemaTone.dark ? 0.18 : 0.30,
          );

    final chip = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          constraints: BoxConstraints(minWidth: 74, maxWidth: maxWidth ?? 116),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: IconTheme(
            data: IconThemeData(color: foreground, size: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.82),
                      fontFamily: 'NoemaDigits',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (attention)
          Positioned(
            right: 6,
            top: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.36),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const SizedBox(width: 5, height: 5),
            ),
          ),
      ],
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(height: 36, child: Center(child: chip)),
        ),
      ),
    );
  }
}

void _showAppraiseAiConfigPrompt({
  required BuildContext context,
  required NoemaPalette palette,
  required VoidCallback onConfigure,
}) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (dialogContext) => _AppraiseAiConfigPrompt(
        palette: palette,
        onConfigure: () {
          Navigator.of(dialogContext).pop();
          onConfigure();
        },
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}

Future<_AppraiseSeriesConfirmAction> _showAppraiseSeriesConfirmPrompt({
  required BuildContext context,
  required NoemaPalette palette,
  required int count,
  required String categoryLabel,
  required bool replacingExisting,
  required int pendingSingleCount,
}) async {
  final result = await showDialog<_AppraiseSeriesConfirmAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (dialogContext) => _AppraiseSeriesConfirmPrompt(
      palette: palette,
      count: count,
      categoryLabel: categoryLabel,
      replacingExisting: replacingExisting,
      pendingSingleCount: pendingSingleCount,
      onRunSinglesFirst: () => Navigator.of(
        dialogContext,
      ).pop(_AppraiseSeriesConfirmAction.runSinglesFirst),
      onConfirm: () => Navigator.of(
        dialogContext,
      ).pop(_AppraiseSeriesConfirmAction.runSeries),
      onClose: () =>
          Navigator.of(dialogContext).pop(_AppraiseSeriesConfirmAction.cancel),
    ),
  );
  return result ?? _AppraiseSeriesConfirmAction.cancel;
}

class _AppraiseSeriesConfirmPrompt extends StatelessWidget {
  const _AppraiseSeriesConfirmPrompt({
    required this.palette,
    required this.count,
    required this.categoryLabel,
    required this.replacingExisting,
    required this.pendingSingleCount,
    required this.onRunSinglesFirst,
    required this.onConfirm,
    required this.onClose,
  });

  final NoemaPalette palette;
  final int count;
  final String categoryLabel;
  final bool replacingExisting;
  final int pendingSingleCount;
  final VoidCallback onRunSinglesFirst;
  final VoidCallback onConfirm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final showSingleFirst = pendingSingleCount > 0;
    final bodyText = showSingleFirst
        ? '将分析“$categoryLabel”中的 $count 张照片，判断主题、情绪、视觉语言和编排关系。'
              '其中 $pendingSingleCount 张还未完成单张品鉴；单张品鉴后，部分照片可能进入佳作，系列结果也可能需要更新。'
        : '将分析“$categoryLabel”中的 $count 张照片，判断主题、情绪、视觉语言和编排关系。'
              '这个过程会比单张品鉴更耗 token，也需要更长等待时间。';

    return NoemaDialogPanel(
      panelKey: const ValueKey('appraise-series-confirm-prompt'),
      palette: palette,
      title: replacingExisting ? '重新生成系列品鉴' : '生成系列品鉴',
      accentColor: colors.accent,
      surfaceColor: colors.mid.withValues(alpha: 0.98),
      borderColor: colors.chipBorder.withValues(alpha: 0.9),
      onClose: onClose,
      body: NoemaDialogText(
        palette: palette,
        text: bodyText,
        color: colors.textPrimary,
      ),
      actions: showSingleFirst
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NoemaDialogButton(
                        palette: palette,
                        label: '先品鉴单张',
                        onPressed: onRunSinglesFirst,
                        tone: NoemaDialogButtonTone.primary,
                        accentColor: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NoemaDialogButton(
                        palette: palette,
                        label: '仍生成系列',
                        onPressed: onConfirm,
                        accentColor: colors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NoemaDialogButton(
                  palette: palette,
                  label: replacingExisting ? '重新生成' : '确认生成',
                  onPressed: onConfirm,
                  tone: NoemaDialogButtonTone.primary,
                  accentColor: colors.accent,
                ),
              ],
            ),
    );
  }
}

class _AppraiseAiConfigPrompt extends StatelessWidget {
  const _AppraiseAiConfigPrompt({
    required this.palette,
    required this.onConfigure,
    required this.onClose,
  });

  final NoemaPalette palette;
  final VoidCallback onConfigure;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final colors = _appraiseSheetStageColors(palette);
    final title = strings.isZh ? '启用 AI 品鉴' : 'Enable AI appraisal';
    final body = strings.isZh
        ? '需要先配置大模型提供商和密钥。配置完成后，AI 会从主题、技术、情感、联想四个维度生成点评。'
        : 'Set up a model provider and API key first. Then AI can appraise the photo across theme, technique, emotion, and association.';
    return NoemaDialogPanel(
      panelKey: const ValueKey('appraise-ai-config-prompt'),
      palette: palette,
      title: title,
      accentColor: colors.accent,
      surfaceColor: colors.mid.withValues(alpha: 0.98),
      borderColor: colors.chipBorder.withValues(alpha: 0.9),
      onClose: onClose,
      closeTooltip: strings.isZh ? '关闭' : 'Close',
      body: NoemaDialogText(
        palette: palette,
        text: body,
        color: colors.textPrimary.withValues(alpha: 0.86),
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          NoemaDialogButton(
            palette: palette,
            label: strings.isZh ? '去配置' : 'Set up',
            onPressed: onConfigure,
            tone: NoemaDialogButtonTone.primary,
            accentColor: colors.accent,
          ),
        ],
      ),
    );
  }
}

class _AppraisePhotoWall extends StatefulWidget {
  const _AppraisePhotoWall({
    required this.palette,
    required this.records,
    required this.aiResults,
    required this.scrollController,
    required this.onOpen,
    required this.onToggleCherished,
    required this.onThumbnailLoaded,
  });

  final NoemaPalette palette;
  final List<_AppraiseRecord> records;
  final Map<String, AppraiseAiPhotoResult> aiResults;
  final ScrollController scrollController;
  final ValueChanged<_AppraiseRecord> onOpen;
  final ValueChanged<String> onToggleCherished;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;

  @override
  State<_AppraisePhotoWall> createState() => _AppraisePhotoWallState();
}

class _AppraisePhotoWallState extends State<_AppraisePhotoWall> {
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _AppraisePhotoWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
      _scrollOffset = widget.scrollController.hasClients
          ? widget.scrollController.offset
          : 0;
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final nextOffset = widget.scrollController.offset;
    if ((nextOffset - _scrollOffset).abs() < 28) {
      return;
    }
    setState(() {
      _scrollOffset = nextOffset;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return _AppraiseLaneEmpty(palette: widget.palette);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wallWidth = constraints.maxWidth;
        final paintWidth = wallWidth + _appraiseWallShadowGutter * 2;
        final layout = buildObservePhotoWallLayout(
          items: [
            for (final record in widget.records)
              ObservePhotoWallItem(
                id: record.asset.photo.id,
                aspectRatio: _assetAspectRatio(record.asset),
              ),
          ],
          width: wallWidth,
          density: ObserveWallDensity.balanced,
        );
        final rectById = {for (final rect in layout.rects) rect.id: rect};
        final visibleTop = math.max(
          0.0,
          _scrollOffset - _appraiseWallTopPadding - 4,
        );
        final visibleBottom = visibleTop + constraints.maxHeight;
        final visibleGutter = constraints.maxHeight * 1.25 + 240;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: paintWidth,
                maxWidth: paintWidth,
                child: SizedBox(
                  width: paintWidth,
                  child: SingleChildScrollView(
                    key: const ValueKey('appraise-photo-wall-scroll'),
                    controller: widget.scrollController,
                    clipBehavior: Clip.hardEdge,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(
                      top: _appraiseWallTopPadding,
                      bottom: _appraiseWallBottomPadding,
                    ),
                    child: SizedBox(
                      key: const ValueKey('appraise-photo-wall'),
                      width: paintWidth,
                      height: layout.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (
                            var index = 0;
                            index < widget.records.length;
                            index++
                          )
                            if (rectById[widget.records[index].asset.photo.id]
                                case final rect?
                                when _rectNearViewport(
                                  rect,
                                  visibleTop: visibleTop,
                                  visibleBottom: visibleBottom,
                                  gutter: visibleGutter,
                                ))
                              AnimatedPositioned(
                                key: ValueKey('appraise-position-${rect.id}'),
                                duration: const Duration(milliseconds: 360),
                                curve: _appraiseEase,
                                left: rect.left + _appraiseWallShadowGutter,
                                top: rect.top,
                                width: rect.width,
                                height: rect.height,
                                child: _AppraisePhotoTile(
                                  key: ValueKey('appraise-photo-${rect.id}'),
                                  palette: widget.palette,
                                  record: widget.records[index],
                                  aiResult:
                                      widget.aiResults[widget
                                          .records[index]
                                          .asset
                                          .photo
                                          .id],
                                  displayWidth: rect.width,
                                  displayHeight: rect.height,
                                  onOpen: () =>
                                      widget.onOpen(widget.records[index]),
                                  onToggleCherished: () =>
                                      widget.onToggleCherished(
                                        widget.records[index].asset.photo.id,
                                      ),
                                  onThumbnailLoaded: widget.onThumbnailLoaded,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              NoemaScrollEdgeFade(
                palette: widget.palette,
                top: true,
                height: _appraiseWallTopFadeHeight,
              ),
              NoemaScrollEdgeFade(
                palette: widget.palette,
                top: false,
                height: _appraiseWallBottomFadeHeight,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _rectNearViewport(
    ObservePhotoWallRect rect, {
    required double visibleTop,
    required double visibleBottom,
    required double gutter,
  }) {
    return rect.top + rect.height >= visibleTop - gutter &&
        rect.top <= visibleBottom + gutter;
  }
}

class _AppraisePhotoTile extends StatefulWidget {
  const _AppraisePhotoTile({
    super.key,
    required this.palette,
    required this.record,
    required this.aiResult,
    required this.displayWidth,
    required this.displayHeight,
    required this.onOpen,
    required this.onToggleCherished,
    required this.onThumbnailLoaded,
  });

  final NoemaPalette palette;
  final _AppraiseRecord record;
  final AppraiseAiPhotoResult? aiResult;
  final double displayWidth;
  final double displayHeight;
  final VoidCallback onOpen;
  final VoidCallback onToggleCherished;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;

  @override
  State<_AppraisePhotoTile> createState() => _AppraisePhotoTileState();
}

class _AppraisePhotoTileState extends State<_AppraisePhotoTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final score =
        widget.aiResult?.totalScore ?? widget.record.asset.photo.appraisalScore;
    return Semantics(
      image: true,
      label: widget.record.asset.displayName,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          scale: _pressed ? 0.985 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: widget.palette.cardShadow.withValues(alpha: 0.72),
                  blurRadius: widget.palette.tone == NoemaTone.dark ? 24 : 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.palette.photoFallback,
                  border: Border.all(
                    color: widget.palette.cardBorder.withValues(alpha: 0.62),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AppraiseAssetImage(
                      palette: widget.palette,
                      asset: widget.record.asset,
                      displayWidth: widget.displayWidth,
                      displayHeight: widget.displayHeight,
                      onThumbnailLoaded: widget.onThumbnailLoaded,
                    ),
                    if (score case final score?)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: NoemaPhotoWallScoreBadge(
                          palette: widget.palette,
                          score: score,
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: NoemaPhotoWallHeartBadge(
                        key: ValueKey(
                          'appraise-photo-heart-${widget.record.asset.photo.id}',
                        ),
                        palette: widget.palette,
                        cherished: widget.record.cherished,
                        onTap: widget.onToggleCherished,
                        tooltip: widget.record.cherished ? '取消珍藏' : '珍藏',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppraiseAssetImage extends StatelessWidget {
  const _AppraiseAssetImage({
    required this.palette,
    required this.asset,
    required this.displayWidth,
    required this.displayHeight,
    required this.onThumbnailLoaded,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final double displayWidth;
  final double displayHeight;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;

  @override
  Widget build(BuildContext context) {
    final cacheSize = noemaImageCacheSize(
      context,
      width: displayWidth,
      height: displayHeight,
      maxExtent: _appraiseThumbnailMaxSize,
    );
    final fallback = _AppraiseImageFallback(
      palette: palette,
      name: asset.displayName,
    );
    if (asset.photo.availability == AssetAvailability.unavailable) {
      return fallback;
    }
    return ColorFiltered(
      colorFilter: palette.photoFilter,
      child: NoemaRecoverableReviewImage(
        asset: asset,
        fit: BoxFit.cover,
        cacheWidth: cacheSize.width,
        cacheHeight: cacheSize.height,
        recoverKind: NoemaRecoverableImageKind.thumbnail,
        recoverMaxSize: _appraiseThumbnailMaxSize,
        allowAlternatePathFallback: false,
        revealOnFirstAvailable: true,
        onRecovered: onThumbnailLoaded,
        filterQuality: FilterQuality.low,
        fallback: fallback,
      ),
    );
  }
}

class _AppraiseImageFallback extends StatelessWidget {
  const _AppraiseImageFallback({required this.palette, required this.name});

  final NoemaPalette palette;
  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.photoFallback, palette.photoFallbackAlt],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.muted.withValues(alpha: 0.74),
              fontSize: 11,
              height: 1.16,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

Color _appraiseScoreColor(NoemaPalette palette, int score) {
  final normalized = score.clamp(0, 100);
  if (palette.tone == NoemaTone.light) {
    if (normalized >= 80) {
      return const Color(0xFF4F7A4E);
    }
    if (normalized >= 70) {
      return const Color(0xFF9A6A2E);
    }
    if (normalized >= 60) {
      return const Color(0xFFA97832);
    }
    return const Color(0xFFB5634B);
  }
  if (normalized >= 80) {
    return const Color(0xFFA8D49A);
  }
  if (normalized >= 70) {
    return const Color(0xFFD8A85A);
  }
  if (normalized >= 60) {
    return const Color(0xFFE2B66E);
  }
  return const Color(0xFFE49278);
}

class _AppraiseViewerOverlay extends StatefulWidget {
  const _AppraiseViewerOverlay({
    required this.palette,
    required this.record,
    required this.index,
    required this.total,
    required this.aiSettingsLibrary,
    required this.aiSettings,
    required this.aiCheckResult,
    required this.initialAiResult,
    required this.onToggleCherished,
    required this.onAiSettingsChanged,
    required this.onCheckAiSettings,
    required this.onRunAi,
    required this.onSheetFractionChanged,
    super.key,
    this.initialSheetFraction = _appraiseViewerSheetHiddenFraction,
    this.autoOpenSheetFraction = _appraiseViewerSheetDefaultFraction,
  });

  final NoemaPalette palette;
  final _AppraiseRecord record;
  final int index;
  final int total;
  final AppraiseAiSettingsLibrary aiSettingsLibrary;
  final AppraiseAiSettings aiSettings;
  final AppraiseAiCheckResult? aiCheckResult;
  final AppraiseAiPhotoResult? initialAiResult;
  final VoidCallback onToggleCherished;
  final ValueChanged<AppraiseAiSettingsLibrary> onAiSettingsChanged;
  final Future<AppraiseAiCheckResult> Function(AppraiseAiSettings)
  onCheckAiSettings;
  final Future<AppraiseAiPhotoResult> Function() onRunAi;
  final ValueChanged<double> onSheetFractionChanged;
  final double initialSheetFraction;
  final double? autoOpenSheetFraction;

  @override
  State<_AppraiseViewerOverlay> createState() => _AppraiseViewerOverlayState();
}

class _AppraiseViewerOverlayState extends State<_AppraiseViewerOverlay>
    with SingleTickerProviderStateMixin {
  final ScrollController _sheetBodyScrollController = ScrollController();
  late final AnimationController _sheetAnimationController;
  Animation<double>? _sheetAnimation;
  bool _cherishedOverride = false;
  bool _aiRunning = false;
  bool _settingsOpen = false;
  late double _sheetFraction;
  String? _aiError;
  AppraiseAiPhotoResult? _aiResult;
  late AppraiseAiSettingsLibrary _aiSettingsLibrary;
  late AppraiseAiSettings _aiSettings;
  AppraiseAiCheckResult? _aiCheckResult;

  bool get _cherished => widget.record.cherished || _cherishedOverride;
  bool get _sheetContentVisible =>
      _sheetFraction > _appraiseViewerSheetHiddenFraction + 0.035;

  @override
  void initState() {
    super.initState();
    _sheetAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(_handleSheetAnimationChanged);
    _sheetFraction = widget.initialSheetFraction.clamp(
      _appraiseViewerSheetHiddenFraction,
      _appraiseViewerSheetDefaultFraction,
    );
    _aiResult = widget.initialAiResult;
    _aiSettingsLibrary = widget.aiSettingsLibrary;
    _aiSettings = widget.aiSettings;
    _aiCheckResult = widget.aiCheckResult;
    widget.onSheetFractionChanged(_sheetFraction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final autoOpenSheetFraction = widget.autoOpenSheetFraction;
      if (autoOpenSheetFraction == null) {
        return;
      }
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 90), () {
          if (!mounted) {
            return;
          }
          _animateSheetTo(
            autoOpenSheetFraction,
            duration: const Duration(milliseconds: 420),
          );
        }),
      );
    });
  }

  @override
  void dispose() {
    _sheetAnimationController.dispose();
    _sheetBodyScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AppraiseViewerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.asset.photo.id != widget.record.asset.photo.id) {
      _aiResult = widget.initialAiResult;
      _aiError = null;
      _aiRunning = false;
      _cherishedOverride = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sheetBodyScrollController.hasClients) {
          _sheetBodyScrollController.jumpTo(0);
        }
      });
    }
    if (oldWidget.aiSettingsLibrary != widget.aiSettingsLibrary ||
        oldWidget.aiSettings != widget.aiSettings) {
      _aiSettingsLibrary = widget.aiSettingsLibrary;
      _aiSettings = widget.aiSettings;
    }
    if (oldWidget.aiCheckResult != widget.aiCheckResult) {
      _aiCheckResult = widget.aiCheckResult;
    }
  }

  void _handleSheetAnimationChanged() {
    final animation = _sheetAnimation;
    if (animation == null) {
      return;
    }
    _setSheetFraction(animation.value);
  }

  void _setSheetFraction(double value) {
    final next = value.clamp(
      _appraiseViewerSheetHiddenFraction,
      _appraiseViewerSheetDefaultFraction,
    );
    if ((next - _sheetFraction).abs() < 0.002) {
      return;
    }
    setState(() {
      _sheetFraction = next;
    });
    widget.onSheetFractionChanged(next);
  }

  void _handleSheetChromeDragUpdate(DragUpdateDetails details) {
    _sheetAnimationController.stop();
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final delta = details.primaryDelta ?? 0;
    _setSheetFraction(_sheetFraction - delta / viewportHeight);
  }

  void _handleSheetChromeDragEnd(DragEndDetails details) {
    _animateSheetTo(_nearestAppraiseSheetFraction(_sheetFraction));
  }

  void _animateSheetTo(double target, {Duration? duration}) {
    _sheetAnimationController.stop();
    _sheetAnimation = Tween<double>(begin: _sheetFraction, end: target).animate(
      CurvedAnimation(parent: _sheetAnimationController, curve: _appraiseEase),
    );
    _sheetAnimationController.duration =
        duration ?? const Duration(milliseconds: 220);
    _sheetAnimationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetFraction = _sheetFraction;
    final contentVisible = _sheetContentVisible;
    final result = _aiResult;
    final metrics = result == null
        ? const <_VisibleAppraiseMetric>[]
        : _visibleMetrics(result);
    final localBasisSignals = _appraiseLocalBasisSignals(widget.record);
    final strings = NoemaStrings.of(context);
    final categoryLabel = _appraiseCategoryLabel(
      strings,
      widget.record,
      result,
    );
    final sheetScrollBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        ...ScrollConfiguration.of(context).dragDevices,
        PointerDeviceKind.mouse,
      },
      scrollbars: false,
    );
    return Stack(
      children: [
        Positioned(
          right: NoemaSceneMetrics.sideInset + 2,
          bottom: viewportHeight * sheetFraction + 12,
          child: _AppraiseViewerIndex(index: widget.index, total: widget.total),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: viewportHeight * sheetFraction,
          child: ScrollConfiguration(
            behavior: sheetScrollBehavior,
            child: KeyedSubtree(
              key: const ValueKey('appraise-viewer-sheet'),
              child: _AppraiseSheetSurface(
                palette: palette,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: _appraiseViewerSheetContentX,
                      top: 26,
                      child: _AppraiseSheetWatermark(
                        palette: palette,
                        label: categoryLabel,
                      ),
                    ),
                    ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                        ],
                        stops: [0, 0.085, 0.135, 1],
                      ).createShader(bounds),
                      child: CustomScrollView(
                        key: const ValueKey('appraise-viewer-sheet-scroll'),
                        controller: _sheetBodyScrollController,
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          if (contentVisible)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  _appraiseViewerSheetContentX,
                                  _appraiseViewerSheetChromeHeight,
                                  _appraiseViewerSheetContentX,
                                  42,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _AppraiseSheetHeader(
                                      palette: palette,
                                      record: widget.record,
                                    ),
                                    const SizedBox(height: 14),
                                    _AppraiseLocalBasis(
                                      palette: palette,
                                      signals: localBasisSignals,
                                    ),
                                    SizedBox(
                                      height: localBasisSignals.isEmpty
                                          ? 22
                                          : 28,
                                    ),
                                    if (result case final review?) ...[
                                      _AppraiseSectionTitle(
                                        palette: palette,
                                        label: '初见',
                                        ornament: true,
                                      ),
                                      _AppraiseBodyText(
                                        palette: palette,
                                        text: review.initial,
                                      ),
                                      _AppraiseSectionBreak(palette: palette),
                                      _AppraiseSectionTitle(
                                        palette: palette,
                                        label: '四维',
                                        trailing: '${review.totalScore}/100',
                                        trailingColor: _appraiseScoreColor(
                                          palette,
                                          review.totalScore,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      for (
                                        var metricIndex = 0;
                                        metricIndex < metrics.length;
                                        metricIndex += 1
                                      )
                                        _AppraiseMetricRow(
                                          palette: palette,
                                          label: metrics[metricIndex].label,
                                          value: metrics[metricIndex].value,
                                          maxValue:
                                              metrics[metricIndex].maxValue,
                                          scoreColor: _appraiseScoreColor(
                                            palette,
                                            review.totalScore,
                                          ),
                                          text: metrics[metricIndex].text,
                                          isLast:
                                              metricIndex == metrics.length - 1,
                                        ),
                                      const SizedBox(height: 22),
                                      _AppraiseSectionTitle(
                                        palette: palette,
                                        label: '总观',
                                      ),
                                      _AppraiseBodyText(
                                        palette: palette,
                                        text: review.overall,
                                      ),
                                      _AppraiseSectionBreak(palette: palette),
                                      _AppraiseSectionTitle(
                                        palette: palette,
                                        label: '打磨',
                                      ),
                                      _AppraiseBodyText(
                                        palette: palette,
                                        text: review.refine,
                                      ),
                                      _AppraiseSectionBreak(palette: palette),
                                      _AppraiseSectionTitle(
                                        palette: palette,
                                        label: '自问',
                                      ),
                                      _AppraiseQuestion(
                                        palette: palette,
                                        text: review.question,
                                      ),
                                      const SizedBox(height: 18),
                                    ],
                                    _AppraiseAiInlineAction(
                                      palette: palette,
                                      running: _aiRunning,
                                      error: _aiError,
                                      hasResult: _aiResult != null,
                                      aiReady: _aiSettings.isReady,
                                      onOpenSettings: _showAiConfigPrompt,
                                      onPressed: _runAi,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      height: _appraiseViewerSheetChromeHeight,
                      child: _AppraiseSheetChrome(
                        palette: palette,
                        cherished: _cherished,
                        onDragUpdate: _handleSheetChromeDragUpdate,
                        onDragEnd: _handleSheetChromeDragEnd,
                        onToggleCherished: () {
                          widget.onToggleCherished();
                          setState(() {
                            _cherishedOverride = !_cherishedOverride;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_settingsOpen)
          Positioned.fill(
            child: _AppraiseAiHintPanel(
              palette: palette,
              settingsLibrary: _aiSettingsLibrary,
              initialCheckResult: _aiCheckResult,
              onSettingsChanged: _handleAiSettingsChanged,
              onCheck: _checkAiSettings,
              onClose: () => setState(() => _settingsOpen = false),
            ),
          ),
      ],
    );
  }

  List<_VisibleAppraiseMetric> _visibleMetrics(AppraiseAiPhotoResult result) {
    return [
      for (final metric in result.metrics)
        _VisibleAppraiseMetric(
          label: metric.label,
          value: metric.value,
          maxValue: 25,
          text: metric.text,
        ),
    ];
  }

  Future<void> _runAi() async {
    if (_aiRunning) {
      return;
    }
    setState(() {
      _aiRunning = true;
      _aiError = null;
    });
    try {
      final result = await widget.onRunAi();
      if (!mounted) {
        return;
      }
      setState(() {
        _aiResult = result;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _aiError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _aiRunning = false;
        });
      }
    }
  }

  void _handleAiSettingsChanged(AppraiseAiSettingsLibrary settingsLibrary) {
    setState(() {
      _aiSettingsLibrary = settingsLibrary;
      _aiSettings = settingsLibrary.activeSettings;
      _aiCheckResult = null;
    });
    widget.onAiSettingsChanged(settingsLibrary);
  }

  Future<AppraiseAiCheckResult> _checkAiSettings(
    AppraiseAiSettings settings,
  ) async {
    final result = await widget.onCheckAiSettings(settings);
    if (mounted) {
      setState(() {
        _aiSettingsLibrary = _aiSettingsLibrary.withActiveSettings(settings);
        _aiSettings = settings;
        _aiCheckResult = result;
      });
    }
    return result;
  }

  void _showAiConfigPrompt() {
    _showAppraiseAiConfigPrompt(
      context: context,
      palette: widget.palette,
      onConfigure: () => setState(() => _settingsOpen = true),
    );
  }
}

class _VisibleAppraiseMetric {
  const _VisibleAppraiseMetric({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.text,
  });

  final String label;
  final int value;
  final int maxValue;
  final String text;
}

class _AppraiseViewerIndex extends StatelessWidget {
  const _AppraiseViewerIndex({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '${index + 1}/$total',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.76),
            fontFamily: 'NoemaDigits',
            fontSize: 11,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _AppraiseSheetTopFade extends StatelessWidget {
  const _AppraiseSheetTopFade({
    required this.palette,
    super.key,
    this.height = 28,
  });

  final NoemaPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    final darkTone = palette.tone == NoemaTone.dark;
    final colors = _appraiseSheetStageColors(palette);
    final base = colors.top;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base,
                base.withValues(alpha: darkTone ? 0.98 : 0.96),
                base.withValues(alpha: darkTone ? 0.74 : 0.78),
                base.withValues(alpha: 0),
              ],
              stops: const [0, 0.48, 0.72, 1],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AppraiseSheetChrome extends StatelessWidget {
  const _AppraiseSheetChrome({
    required this.palette,
    required this.cherished,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onToggleCherished,
  });

  final NoemaPalette palette;
  final bool cherished;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onToggleCherished;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _appraiseViewerSheetChromeHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 44,
            child: _AppraiseSheetTopFade(
              key: const ValueKey('appraise-viewer-sheet-chrome-fade'),
              palette: palette,
              height: 44,
            ),
          ),
          _AppraiseSheetHandle(palette: palette),
          Positioned(
            left: 0,
            top: 0,
            right: _appraiseViewerSheetContentX + 48,
            height: _appraiseViewerSheetChromeHeight,
            child: GestureDetector(
              key: const ValueKey('appraise-viewer-sheet-handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: _appraiseViewerSheetContentX,
            top: 28,
            child: _AppraiseSheetHeartButton(
              palette: palette,
              cherished: cherished,
              onTap: onToggleCherished,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppraiseSheetWatermark extends StatelessWidget {
  const _AppraiseSheetWatermark({required this.palette, required this.label});

  final NoemaPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final longLabel = label.runes.length > 2;
    return ExcludeSemantics(
      child: Text(
        label,
        style: TextStyle(
          color: colors.watermark,
          fontFamily: noemaTitleCjkFontFamily,
          fontFamilyFallback: const ['LXGWWenKaiGB', 'NoemaCjkFallback'],
          fontSize: longLabel ? 86 : 108,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: longLabel ? 0 : 5,
        ),
      ),
    );
  }
}

class _AppraiseSheetHandle extends StatelessWidget {
  const _AppraiseSheetHandle({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return SizedBox(
      height: 31,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.handle,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const SizedBox(width: 48, height: 5),
        ),
      ),
    );
  }
}

class _AppraiseSeriesSheetOverlay extends StatefulWidget {
  const _AppraiseSeriesSheetOverlay({
    required this.palette,
    required this.appraisal,
    required this.records,
    required this.currentRecords,
    required this.onClose,
    required this.onOpenPhoto,
    required this.onRegenerate,
  });

  final NoemaPalette palette;
  final PhotoSeriesAppraisal appraisal;
  final List<_AppraiseRecord> records;
  final List<_AppraiseRecord> currentRecords;
  final VoidCallback onClose;
  final ValueChanged<_AppraiseRecord> onOpenPhoto;
  final VoidCallback onRegenerate;

  @override
  State<_AppraiseSeriesSheetOverlay> createState() =>
      _AppraiseSeriesSheetOverlayState();
}

class _AppraiseSeriesSheetOverlayState
    extends State<_AppraiseSeriesSheetOverlay> {
  double _dragOffset = 0;

  void _handleChromeDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = math.max(0, _dragOffset + delta);
    });
  }

  void _handleChromeDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 92 || velocity > 700) {
      widget.onClose();
      return;
    }
    setState(() {
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = viewportHeight * 0.82;
    final colors = _appraiseSheetStageColors(widget.palette);
    final recordById = {
      for (final record in widget.records) record.asset.photo.id: record,
    };
    final orderedRecords = _seriesOrderedRecordsForAppraisal(
      widget.records,
      widget.appraisal.photoIds,
    );
    final indexByPhotoId = _seriesIndexByPhotoId(orderedRecords);
    final canRegenerateSeries = widget.currentRecords.length >= 2;
    final updateAvailable =
        canRegenerateSeries &&
        _seriesPhotoSetHash(widget.currentRecords) !=
            widget.appraisal.photoSetHash;
    final sheetScrollBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        ...ScrollConfiguration.of(context).dragDevices,
        PointerDeviceKind.mouse,
      },
      scrollbars: false,
    );
    final barrierAlpha = widget.palette.tone == NoemaTone.dark ? 0.74 : 0.50;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: _appraiseEase,
      builder: (context, value, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: barrierAlpha * value),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: sheetHeight,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 34 + _dragOffset),
                child: Opacity(
                  opacity: value,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: _AppraiseSheetSurface(
                      palette: widget.palette,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: _appraiseViewerSheetContentX,
                            top: 26,
                            child: _AppraiseSheetWatermark(
                              palette: widget.palette,
                              label: '系列',
                            ),
                          ),
                          ScrollConfiguration(
                            behavior: sheetScrollBehavior,
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (bounds) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black,
                                  Colors.black,
                                ],
                                stops: [0, 0.055, 0.115, 1],
                              ).createShader(bounds),
                              child: CustomScrollView(
                                key: const ValueKey(
                                  'appraise-series-sheet-scroll',
                                ),
                                physics: const BouncingScrollPhysics(),
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        _appraiseViewerSheetContentX,
                                        _appraiseViewerSheetChromeHeight,
                                        _appraiseViewerSheetContentX,
                                        42,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _AppraiseSeriesHeader(
                                            palette: widget.palette,
                                            appraisal: widget.appraisal,
                                          ),
                                          if (updateAvailable) ...[
                                            const SizedBox(height: 12),
                                            _AppraiseSeriesUpdateButton(
                                              palette: widget.palette,
                                              onPressed: widget.onRegenerate,
                                            ),
                                          ],
                                          const SizedBox(height: 16),
                                          _AppraiseSeriesThumbnailStrip(
                                            palette: widget.palette,
                                            records: orderedRecords,
                                            onOpenPhoto: widget.onOpenPhoto,
                                          ),
                                          const SizedBox(height: 24),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '总观',
                                            trailing:
                                                '${widget.appraisal.result.scores.total}/100',
                                            trailingColor: _appraiseScoreColor(
                                              widget.palette,
                                              widget
                                                  .appraisal
                                                  .result
                                                  .scores
                                                  .total,
                                            ),
                                          ),
                                          _AppraiseBodyText(
                                            palette: widget.palette,
                                            text: _seriesDisplayText(
                                              widget.appraisal.result.overall,
                                              indexByPhotoId,
                                            ),
                                            highlightPhotoRefs: true,
                                          ),
                                          _AppraiseSectionBreak(
                                            palette: widget.palette,
                                          ),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '主题线',
                                          ),
                                          _AppraiseBodyText(
                                            palette: widget.palette,
                                            text: _seriesDisplayText(
                                              widget.appraisal.result.themeLine,
                                              indexByPhotoId,
                                            ),
                                            highlightPhotoRefs: true,
                                          ),
                                          _AppraiseSectionBreak(
                                            palette: widget.palette,
                                          ),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '组内关系',
                                          ),
                                          const SizedBox(height: 12),
                                          for (
                                            var index = 0;
                                            index <
                                                widget
                                                    .appraisal
                                                    .result
                                                    .relationships
                                                    .length;
                                            index += 1
                                          ) ...[
                                            _AppraiseSeriesRelationshipBlock(
                                              relationshipIndex: index,
                                              palette: widget.palette,
                                              relationship: widget
                                                  .appraisal
                                                  .result
                                                  .relationships[index],
                                              records: _seriesRecordsForIds(
                                                recordById,
                                                widget
                                                    .appraisal
                                                    .result
                                                    .relationships[index]
                                                    .photoIds,
                                              ),
                                              indexByPhotoId: indexByPhotoId,
                                              onOpenPhoto: widget.onOpenPhoto,
                                            ),
                                            if (index !=
                                                widget
                                                        .appraisal
                                                        .result
                                                        .relationships
                                                        .length -
                                                    1)
                                              const SizedBox(height: 18),
                                          ],
                                          _AppraiseSectionBreak(
                                            palette: widget.palette,
                                          ),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '编排',
                                          ),
                                          const SizedBox(height: 12),
                                          _AppraiseSeriesInlineThumbnails(
                                            palette: widget.palette,
                                            records: _seriesRecordsForIds(
                                              recordById,
                                              widget
                                                  .appraisal
                                                  .result
                                                  .sequence
                                                  .suggestedPhotoIds,
                                            ),
                                            indexByPhotoId: indexByPhotoId,
                                            onOpenPhoto: widget.onOpenPhoto,
                                          ),
                                          _AppraiseBodyText(
                                            palette: widget.palette,
                                            text: _seriesDisplayText(
                                              widget
                                                  .appraisal
                                                  .result
                                                  .sequence
                                                  .text,
                                              indexByPhotoId,
                                            ),
                                            highlightPhotoRefs: true,
                                          ),
                                          _AppraiseSectionBreak(
                                            palette: widget.palette,
                                          ),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '打磨',
                                          ),
                                          _AppraiseBodyText(
                                            palette: widget.palette,
                                            text: _seriesDisplayText(
                                              widget.appraisal.result.refine,
                                              indexByPhotoId,
                                            ),
                                            highlightPhotoRefs: true,
                                          ),
                                          _AppraiseSectionBreak(
                                            palette: widget.palette,
                                          ),
                                          _AppraiseSectionTitle(
                                            palette: widget.palette,
                                            label: '自问',
                                          ),
                                          _AppraiseQuestion(
                                            palette: widget.palette,
                                            text: _seriesDisplayText(
                                              widget.appraisal.result.question,
                                              indexByPhotoId,
                                            ),
                                            highlightPhotoRefs: true,
                                          ),
                                          if (canRegenerateSeries) ...[
                                            const SizedBox(height: 22),
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                key: const ValueKey(
                                                  'appraise-series-regenerate',
                                                ),
                                                onPressed: widget.onRegenerate,
                                                icon: Icon(
                                                  Icons.refresh_rounded,
                                                  size: 18,
                                                  color: colors.accent,
                                                ),
                                                label: Text(
                                                  '重新生成系列品鉴',
                                                  style: TextStyle(
                                                    color: colors.accent,
                                                    fontFamily: 'LXGWWenKaiGB',
                                                    fontSize: 14.5,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(
                                                    color: colors.chipBorder,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            right: 0,
                            height: _appraiseViewerSheetChromeHeight,
                            child: _AppraiseSeriesSheetChrome(
                              palette: widget.palette,
                              onDragUpdate: _handleChromeDragUpdate,
                              onDragEnd: _handleChromeDragEnd,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppraiseSeriesSheetChrome extends StatelessWidget {
  const _AppraiseSeriesSheetChrome({
    required this.palette,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final NoemaPalette palette;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: 44,
          child: _AppraiseSheetTopFade(
            key: const ValueKey('appraise-series-sheet-chrome-fade'),
            palette: palette,
            height: 44,
          ),
        ),
        _AppraiseSheetHandle(palette: palette),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _appraiseViewerSheetChromeHeight,
          child: GestureDetector(
            key: const ValueKey('appraise-series-sheet-handle'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _AppraiseSeriesUpdateButton extends StatelessWidget {
  const _AppraiseSeriesUpdateButton({
    required this.palette,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('appraise-series-update'),
        onPressed: onPressed,
        icon: Icon(Icons.refresh_rounded, size: 16, color: colors.accent),
        label: Text(
          '更新系列品鉴',
          style: TextStyle(
            color: colors.accent,
            fontFamily: 'LXGWWenKaiGB',
            fontSize: 13.5,
            height: 1,
          ),
        ),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: colors.chipBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }
}

class _AppraiseSeriesHeader extends StatelessWidget {
  const _AppraiseSeriesHeader({required this.palette, required this.appraisal});

  final NoemaPalette palette;
  final PhotoSeriesAppraisal appraisal;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appraisal.result.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.accent,
            fontFamily: 'LXGWWenKaiGB',
            fontSize: 27,
            fontWeight: FontWeight.w600,
            height: 1.24,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        _AppraiseSheetMetaLine(
          palette: palette,
          meta: (
            time: _seriesTimeRangeLabel(
              appraisal.captureStartAt,
              appraisal.captureEndAt,
            ),
            location:
                '${_seriesBandLabel(appraisal.band)}   ${appraisal.photoIds.length} 张',
          ),
        ),
        const SizedBox(height: 12),
        _AppraiseSheetMetaRule(palette: palette),
      ],
    );
  }
}

class _AppraiseSeriesThumbnailStrip extends StatelessWidget {
  const _AppraiseSeriesThumbnailStrip({
    required this.palette,
    required this.records,
    required this.onOpenPhoto,
  });

  final NoemaPalette palette;
  final List<_AppraiseRecord> records;
  final ValueChanged<_AppraiseRecord> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: records.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _AppraiseSeriesThumbnail(
            palette: palette,
            record: records[index],
            size: 58,
            index: index + 1,
            onTap: () => onOpenPhoto(records[index]),
          );
        },
      ),
    );
  }
}

class _AppraiseSeriesRelationshipBlock extends StatelessWidget {
  const _AppraiseSeriesRelationshipBlock({
    required this.relationshipIndex,
    required this.palette,
    required this.relationship,
    required this.records,
    required this.indexByPhotoId,
    required this.onOpenPhoto,
  });

  final int relationshipIndex;
  final NoemaPalette palette;
  final PhotoSeriesRelationship relationship;
  final List<_AppraiseRecord> records;
  final Map<String, int> indexByPhotoId;
  final ValueChanged<_AppraiseRecord> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return Column(
      key: ValueKey('appraise-series-relationship-$relationshipIndex'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          relationship.role,
          style: TextStyle(
            color: colors.accent,
            fontFamily: 'LXGWWenKaiGB',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0.2,
          ),
        ),
        if (records.isNotEmpty) ...[
          const SizedBox(height: 10),
          _AppraiseSeriesInlineThumbnails(
            palette: palette,
            records: records,
            indexByPhotoId: indexByPhotoId,
            onOpenPhoto: onOpenPhoto,
          ),
        ],
        _AppraiseBodyText(
          palette: palette,
          text: _seriesDisplayText(relationship.text, indexByPhotoId),
          highlightPhotoRefs: true,
        ),
      ],
    );
  }
}

class _AppraiseSeriesInlineThumbnails extends StatelessWidget {
  const _AppraiseSeriesInlineThumbnails({
    required this.palette,
    required this.records,
    required this.indexByPhotoId,
    required this.onOpenPhoto,
  });

  final NoemaPalette palette;
  final List<_AppraiseRecord> records;
  final Map<String, int> indexByPhotoId;
  final ValueChanged<_AppraiseRecord> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < records.length; index += 1)
          _AppraiseSeriesThumbnail(
            palette: palette,
            record: records[index],
            size: 52,
            index: indexByPhotoId[records[index].asset.photo.id],
            onTap: () => onOpenPhoto(records[index]),
          ),
      ],
    );
  }
}

class _AppraiseSeriesThumbnail extends StatelessWidget {
  const _AppraiseSeriesThumbnail({
    required this.palette,
    required this.record,
    required this.size,
    required this.index,
    required this.onTap,
  });

  final NoemaPalette palette;
  final _AppraiseRecord record;
  final double size;
  final int? index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return GestureDetector(
      key: ValueKey('appraise-series-thumbnail-${record.asset.photo.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AppraiseAssetImage(
                palette: palette,
                asset: record.asset,
                displayWidth: size,
                displayHeight: size,
                onThumbnailLoaded: (_, _) {},
              ),
              if (index case final value?)
                Positioned(
                  left: 5,
                  top: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.bottom.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.52),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      child: Text(
                        '$value',
                        style: TextStyle(
                          color: colors.accent,
                          fontFamily: 'NoemaDigits',
                          fontSize: 10,
                          height: 1,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_AppraiseRecord> _seriesRecordsForIds(
  Map<String, _AppraiseRecord> recordById,
  Iterable<String> photoIds,
) {
  final result = <_AppraiseRecord>[];
  for (final photoId in photoIds) {
    final record = recordById[photoId];
    if (record != null) {
      result.add(record);
    }
  }
  return result;
}

List<_AppraiseRecord> _seriesDisplayRecordsForAppraisal({
  required List<_AppraiseRecord> allRecords,
  required PhotoSeriesAppraisal appraisal,
}) {
  final recordById = {
    for (final record in allRecords) record.asset.photo.id: record,
  };
  final usedPhotoIds = <String>{};
  final displayRecords = <_AppraiseRecord>[];
  for (final photoId in appraisal.photoIds) {
    final record = recordById[photoId];
    if (record != null && usedPhotoIds.add(photoId)) {
      displayRecords.add(record);
    }
  }
  return displayRecords;
}

List<_AppraiseRecord> _seriesOrderedRecordsForAppraisal(
  List<_AppraiseRecord> records,
  Iterable<String> photoIds,
) {
  final recordById = {
    for (final record in records) record.asset.photo.id: record,
  };
  final usedPhotoIds = <String>{};
  final ordered = <_AppraiseRecord>[];
  for (final photoId in photoIds) {
    final record = recordById[photoId];
    if (record == null) {
      continue;
    }
    usedPhotoIds.add(photoId);
    ordered.add(record);
  }
  for (final record in records) {
    if (usedPhotoIds.add(record.asset.photo.id)) {
      ordered.add(record);
    }
  }
  return ordered;
}

Map<String, int> _seriesIndexByPhotoId(List<_AppraiseRecord> records) {
  return {
    for (var index = 0; index < records.length; index += 1)
      records[index].asset.photo.id: index + 1,
  };
}

String _seriesDisplayText(String text, Map<String, int> indexByPhotoId) {
  if (text.isEmpty || indexByPhotoId.isEmpty) {
    return text;
  }
  var result = text;
  for (final entry in indexByPhotoId.entries) {
    result = result.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
      '照片${entry.value}',
    );
  }
  return result.replaceAllMapped(
    RegExp(r'\bphoto[-_ ]?(\d+)\b', caseSensitive: false),
    (match) {
      final index = indexByPhotoId['photo-${match.group(1)}'];
      return index == null ? '这张照片' : '照片$index';
    },
  );
}

String _seriesTimeRangeLabel(DateTime start, DateTime end) {
  String two(int number) => number.toString().padLeft(2, '0');
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final startDate = '${start.year}.${two(start.month)}.${two(start.day)}';
  final startTime = '${two(start.hour)}:${two(start.minute)}';
  final endDate = '${end.year}.${two(end.month)}.${two(end.day)}';
  final endTime = '${two(end.hour)}:${two(end.minute)}';
  if (sameDay) {
    return '$startDate $startTime-$endTime';
  }
  return '$startDate $startTime - $endDate $endTime';
}

class _AppraiseSheetSurface extends StatelessWidget {
  const _AppraiseSheetSurface({required this.palette, required this.child});

  final NoemaPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final darkTone = palette.tone == NoemaTone.dark;
    final colors = _appraiseSheetStageColors(palette);
    const radius = BorderRadius.vertical(
      top: Radius.circular(_appraiseViewerSheetRadius),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: darkTone ? 0.38 : 0.16),
            blurRadius: 44,
            offset: const Offset(0, -18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.top, colors.mid, colors.bottom],
              stops: const [0, 0.44, 1],
            ),
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AppraiseSheetHeader extends StatelessWidget {
  const _AppraiseSheetHeader({required this.palette, required this.record});

  final NoemaPalette palette;
  final _AppraiseRecord record;

  @override
  Widget build(BuildContext context) {
    final meta = _appraisePhotoMeta(record);
    final height = meta.isEmpty ? 0.0 : (meta.hasBoth ? 116.0 : 93.0);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!meta.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppraiseSheetMetaLine(palette: palette, meta: meta),
                  const SizedBox(height: 12),
                  _AppraiseSheetMetaRule(palette: palette),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _appraiseCategoryLabel(
  NoemaStrings strings,
  _AppraiseRecord record,
  AppraiseAiPhotoResult? aiResult,
) {
  if (record.cherished) {
    return _bandLabel(strings, _AppraiseBand.cherished);
  }
  return _bandLabel(strings, _resolvedBandFor(record.appraisal, aiResult));
}

({String? time, String? location}) _appraisePhotoMeta(_AppraiseRecord record) {
  final time = _appraiseTimeLabel(record.asset.photo.createdAt);
  return (time: time, location: _appraiseLocationLabel(record));
}

extension on ({String? time, String? location}) {
  bool get isEmpty =>
      (time == null || time!.isEmpty) &&
      (location == null || location!.isEmpty);

  bool get hasBoth =>
      time != null &&
      time!.isNotEmpty &&
      location != null &&
      location!.isNotEmpty;
}

class _AppraiseSheetMetaLine extends StatelessWidget {
  const _AppraiseSheetMetaLine({required this.palette, required this.meta});

  final NoemaPalette palette;
  final ({String? time, String? location}) meta;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final timeStyle = TextStyle(
      color: colors.accent,
      fontFamily: 'NoemaDigits',
      fontFamilyFallback: const ['LXGWWenKaiGB', 'NoemaCjkFallback'],
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 25 / 18,
      letterSpacing: 0,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final detailStyle = timeStyle.copyWith(
      color: colors.accent.withValues(alpha: 0.88),
      fontSize: 15.5,
      height: 21 / 15.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (meta.time case final time? when time.isNotEmpty)
          _AppraiseMetaText(
            key: const ValueKey('appraise-sheet-meta-time'),
            text: time,
            style: timeStyle,
          ),
        if (meta.location case final location? when location.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: meta.time?.isNotEmpty == true ? 2 : 0,
            ),
            child: _AppraiseMetaText(
              key: const ValueKey('appraise-sheet-meta-detail'),
              text: location,
              style: detailStyle,
            ),
          ),
      ],
    );
  }
}

class _AppraiseMetaText extends StatelessWidget {
  const _AppraiseMetaText({required this.text, required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, softWrap: false, style: style),
      ),
    );
  }
}

class _AppraiseSheetMetaRule extends StatelessWidget {
  const _AppraiseSheetMetaRule({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return SizedBox(
      width: double.infinity,
      height: 7,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 3,
            bottom: 3,
            child: ColoredBox(color: colors.line),
          ),
          Transform.rotate(
            angle: math.pi / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
              child: const SizedBox(width: 7, height: 7),
            ),
          ),
        ],
      ),
    );
  }
}

String? _appraiseLocationLabel(_AppraiseRecord record) {
  // ponytail: PhotoAsset does not store location yet; wire this to EXIF/GPS once
  // the import model has a real location field.
  return null;
}

String _appraiseTimeLabel(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}.${two(value.month)}.${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _AppraiseSheetHeartButton extends StatelessWidget {
  const _AppraiseSheetHeartButton({
    required this.palette,
    required this.cherished,
    required this.onTap,
  });

  final NoemaPalette palette;
  final bool cherished;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final color = cherished
        ? colors.accent
        : colors.accentSoft.withValues(alpha: 0.78);
    return Tooltip(
      message: cherished ? '取消珍藏' : '珍藏',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          key: const ValueKey('appraise-viewer-sheet-heart'),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: cherished
                ? colors.accent.withValues(alpha: 0.15)
                : colors.top.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: cherished ? colors.accent : colors.chipBorder,
            ),
          ),
          child: Center(
            child: cherished
                ? Icon(Icons.favorite_rounded, size: 17, color: color)
                : _AppraiseSvgIcon(
                    asset: _appraiseFavoriteIcon,
                    size: 16,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
}

class _AppraiseSvgIcon extends StatelessWidget {
  const _AppraiseSvgIcon({
    required this.asset,
    required this.size,
    required this.color,
  });

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        asset,
        key: ValueKey('appraise-svg-$asset'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        excludeFromSemantics: true,
      ),
    );
  }
}

class _AppraiseSheetStageColors {
  const _AppraiseSheetStageColors({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.border,
    required this.accent,
    required this.handle,
    required this.accentSoft,
    required this.accentMuted,
    required this.line,
    required this.chipBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.watermark,
    required this.quoteBg,
  });

  final Color top;
  final Color mid;
  final Color bottom;
  final Color border;
  final Color accent;
  final Color handle;
  final Color accentSoft;
  final Color accentMuted;
  final Color line;
  final Color chipBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color watermark;
  final Color quoteBg;
}

_AppraiseSheetStageColors _appraiseSheetStageColors(NoemaPalette palette) {
  if (palette.tone == NoemaTone.dark) {
    return const _AppraiseSheetStageColors(
      top: Color(0xFF101313),
      mid: Color(0xFF0B0D0D),
      bottom: Color(0xFF060707),
      border: Color(0x1FFFFFFF),
      accent: Color(0xFFD8A85A),
      handle: Color(0x52F7F1E5),
      accentSoft: Color(0xFFD8A85A),
      accentMuted: Color(0x1FD8A85A),
      line: Color(0x47D8A85A),
      chipBorder: Color(0x85D8A85A),
      textPrimary: Color(0xE6F7F1E5),
      textSecondary: Color(0xA3F7F1E5),
      textTertiary: Color(0x8AF7F1E5),
      watermark: Color(0x0EF7F1E5),
      quoteBg: Color(0x0EFFFFFF),
    );
  }
  return const _AppraiseSheetStageColors(
    top: Color(0xFFFAF6EF),
    mid: Color(0xFFFAF6EF),
    bottom: Color(0xFFF5EDE1),
    border: Color(0x1F9A6A2E),
    accent: Color(0xFF9A6A2E),
    handle: Color(0x4D211C16),
    accentSoft: Color(0xFF9A6A2E),
    accentMuted: Color(0x1F9A6A2E),
    line: Color(0x389A6A2E),
    chipBorder: Color(0x759A6A2E),
    textPrimary: Color(0xE6211C16),
    textSecondary: Color(0x9E211C16),
    textTertiary: Color(0x85211C16),
    watermark: Color(0x0E644B30),
    quoteBg: Color(0x119A6A2E),
  );
}

class _AppraiseSectionTitle extends StatelessWidget {
  const _AppraiseSectionTitle({
    required this.palette,
    required this.label,
    this.trailing,
    this.trailingColor,
    this.ornament = false,
  });

  final NoemaPalette palette;
  final String label;
  final String? trailing;
  final Color? trailingColor;
  final bool ornament;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.accent,
            fontFamily: 'LXGWWenKaiGB',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 32 / 24,
            letterSpacing: 0.48,
          ),
        ),
        if (ornament) ...[
          const SizedBox(width: 14),
          Baseline(
            baseline: 21,
            baselineType: TextBaseline.alphabetic,
            child: _AppraiseSvgIcon(
              asset: _appraiseSectionDiamondIcon,
              size: 11,
              color: colors.accent,
            ),
          ),
        ],
        if (trailing case final value? when value.isNotEmpty) ...[
          const SizedBox(width: 12),
          _AppraiseScoreText(
            value: value,
            activeColor: trailingColor ?? colors.textSecondary,
            restColor: colors.textSecondary,
          ),
        ],
      ],
    );
  }
}

class _AppraiseScoreText extends StatelessWidget {
  const _AppraiseScoreText({
    required this.value,
    required this.activeColor,
    required this.restColor,
  });

  final String value;
  final Color activeColor;
  final Color restColor;

  @override
  Widget build(BuildContext context) {
    final slashIndex = value.indexOf('/');
    final active = slashIndex == -1 ? value : value.substring(0, slashIndex);
    final rest = slashIndex == -1 ? '' : value.substring(slashIndex);
    const baseStyle = TextStyle(
      fontFamily: 'NoemaDigits',
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 24 / 17,
      letterSpacing: 0,
      fontFeatures: [ui.FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: active,
            style: baseStyle.copyWith(color: activeColor),
          ),
          if (rest.isNotEmpty)
            TextSpan(
              text: rest,
              style: baseStyle.copyWith(color: restColor),
            ),
        ],
      ),
    );
  }
}

class _AppraiseSectionBreak extends StatelessWidget {
  const _AppraiseSectionBreak({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 22),
      child: ColoredBox(
        color: colors.line,
        child: const SizedBox(width: double.infinity, height: 1),
      ),
    );
  }
}

class _AppraiseBodyText extends StatelessWidget {
  const _AppraiseBodyText({
    required this.palette,
    required this.text,
    this.highlightPhotoRefs = false,
  });

  final NoemaPalette palette;
  final String text;
  final bool highlightPhotoRefs;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final baseStyle = _appraiseBodyTextStyle(colors);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: highlightPhotoRefs
          ? Text.rich(
              TextSpan(
                style: baseStyle,
                children: _appraisePhotoReferenceSpans(
                  text: text,
                  highlightStyle: _appraisePhotoReferenceStyle(colors),
                ),
              ),
            )
          : Text(text, style: baseStyle),
    );
  }
}

TextStyle _appraiseBodyTextStyle(_AppraiseSheetStageColors colors) {
  return TextStyle(
    color: colors.textPrimary,
    fontFamily: 'LXGWWenKaiGB',
    fontSize: 15.5,
    fontWeight: FontWeight.w400,
    height: 1.75,
    letterSpacing: 0.2,
  );
}

TextStyle _appraisePhotoReferenceStyle(_AppraiseSheetStageColors colors) {
  return _appraiseBodyTextStyle(
    colors,
  ).copyWith(color: colors.accent, fontWeight: FontWeight.w600);
}

List<InlineSpan> _appraisePhotoReferenceSpans({
  required String text,
  required TextStyle highlightStyle,
}) {
  final pattern = RegExp(r'照片[0-9一二三四五六七八九十百]+');
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: highlightStyle));
    start = match.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

class _AppraiseMetricRow extends StatelessWidget {
  const _AppraiseMetricRow({
    required this.palette,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.scoreColor,
    required this.text,
    required this.isLast,
  });

  final NoemaPalette palette;
  final String label;
  final int value;
  final int maxValue;
  final Color scoreColor;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final safeMaxValue = math.max(1, maxValue);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.line),
          bottom: isLast ? BorderSide(color: colors.line) : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.accent),
                  ),
                  child: SizedBox.square(
                    key: ValueKey('appraise-metric-icon-$label'),
                    dimension: 36,
                    child: Center(
                      child: _AppraiseSvgIcon(
                        asset: _appraiseMetricIcon(label),
                        size: 20,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  key: ValueKey('appraise-metric-label-$label'),
                  style: TextStyle(
                    color: colors.accent,
                    fontFamily: 'LXGWWenKaiGB',
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    height: 24 / 19,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$value',
                  style: TextStyle(
                    color: scoreColor,
                    fontFamily: 'NoemaDigits',
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 24 / 17,
                    letterSpacing: 0,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '/$safeMaxValue',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontFamily: 'NoemaDigits',
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    height: 24 / 17,
                    letterSpacing: 0,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  text,
                  key: ValueKey('appraise-metric-body-$label'),
                  style: _appraiseBodyTextStyle(colors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _appraiseMetricIcon(String label) {
  return switch (label) {
    '主题' => _appraiseThemeIcon,
    '技术' => _appraiseTechIcon,
    '情感' => _appraiseEmotionIcon,
    '联想' => _appraiseImaginationIcon,
    _ => _appraiseSectionDiamondIcon,
  };
}

class _AppraiseLocalBasis extends StatelessWidget {
  const _AppraiseLocalBasis({required this.palette, required this.signals});

  final NoemaPalette palette;
  final List<_AppraiseSignal> signals;

  @override
  Widget build(BuildContext context) {
    if (signals.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return _AppraiseSignalGrid(
          palette: palette,
          maxWidth: constraints.maxWidth,
          signals: signals,
        );
      },
    );
  }
}

List<_AppraiseSignal> _appraiseLocalBasisSignals(_AppraiseRecord record) {
  return [...record.appraisal.signals, ..._appraiseExifSignals(record)];
}

enum _AppraiseSignalChipMode { stacked, inline, camera }

class _AppraiseSignalGrid extends StatelessWidget {
  const _AppraiseSignalGrid({
    required this.palette,
    required this.maxWidth,
    required this.signals,
  });

  final NoemaPalette palette;
  final double maxWidth;
  final List<_AppraiseSignal> signals;

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    final cameraSignals = [
      for (final signal in signals)
        if (signal.label == '参数') signal,
    ];
    final basicSignals = [
      for (final signal in signals)
        if (signal.label != '参数') signal,
    ];
    final camera = cameraSignals.firstOrNull;
    final visibleSignals = [...basicSignals.take(2), ?camera];

    if (visibleSignals.isEmpty) {
      return const SizedBox.shrink();
    }

    if (camera != null && basicSignals.length >= 2) {
      return Row(
        children: [
          Expanded(
            flex: 100,
            child: _AppraiseSignalChip(
              palette: palette,
              signal: basicSignals[0],
              mode: _AppraiseSignalChipMode.stacked,
            ),
          ),
          const SizedBox(width: spacing),
          Expanded(
            flex: 100,
            child: _AppraiseSignalChip(
              palette: palette,
              signal: basicSignals[1],
              mode: _AppraiseSignalChipMode.stacked,
            ),
          ),
          const SizedBox(width: spacing),
          Expanded(
            flex: 155,
            child: _AppraiseSignalChip(
              palette: palette,
              signal: camera,
              mode: _AppraiseSignalChipMode.camera,
            ),
          ),
        ],
      );
    }

    if (visibleSignals.length == 2) {
      return Row(
        children: [
          for (var index = 0; index < visibleSignals.length; index += 1) ...[
            if (index > 0) const SizedBox(width: spacing),
            Expanded(
              child: _AppraiseSignalChip(
                palette: palette,
                signal: visibleSignals[index],
                mode: _AppraiseSignalChipMode.inline,
              ),
            ),
          ],
        ],
      );
    }

    return _AppraiseSignalChip(
      palette: palette,
      signal: visibleSignals.single,
      mode: _AppraiseSignalChipMode.inline,
    );
  }
}

class _AppraiseSignalChip extends StatelessWidget {
  const _AppraiseSignalChip({
    required this.palette,
    required this.signal,
    required this.mode,
  });

  final NoemaPalette palette;
  final _AppraiseSignal signal;
  final _AppraiseSignalChipMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final inline = mode == _AppraiseSignalChipMode.inline;
    final camera = mode == _AppraiseSignalChipMode.camera;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.026),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.chipBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            camera ? 16 : 10,
            camera ? 7 : 8,
            10,
            camera ? 7 : 8,
          ),
          child: camera
              ? _AppraiseSignalCameraText(colors: colors, signal: signal)
              : inline
              ? _AppraiseSignalInlineText(colors: colors, signal: signal)
              : _AppraiseSignalStackedText(colors: colors, signal: signal),
        ),
      ),
    );
  }
}

class _AppraiseSignalStackedText extends StatelessWidget {
  const _AppraiseSignalStackedText({
    required this.colors,
    required this.signal,
  });

  final _AppraiseSheetStageColors colors;
  final _AppraiseSignal signal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppraiseSignalIcon(colors: colors, label: signal.label),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  signal.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontFamily: 'LXGWWenKaiGB',
                    fontFamilyFallback: const ['NoemaCjkFallback'],
                    fontSize: 13,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  signal.value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontFamily: 'LXGWWenKaiGB',
                    fontFamilyFallback: const ['NoemaCjkFallback'],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 22 / 16,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppraiseSignalInlineText extends StatelessWidget {
  const _AppraiseSignalInlineText({required this.colors, required this.signal});

  final _AppraiseSheetStageColors colors;
  final _AppraiseSignal signal;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AppraiseSignalIcon(colors: colors, label: signal.label),
          const SizedBox(width: 7),
          Text(
            signal.label,
            style: TextStyle(
              color: colors.textSecondary,
              fontFamily: 'LXGWWenKaiGB',
              fontFamilyFallback: const ['NoemaCjkFallback'],
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 22 / 16,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              signal.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontFamily: 'LXGWWenKaiGB',
                fontFamilyFallback: const ['NoemaCjkFallback'],
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 22 / 16,
                letterSpacing: 0,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppraiseSignalCameraText extends StatelessWidget {
  const _AppraiseSignalCameraText({required this.colors, required this.signal});

  final _AppraiseSheetStageColors colors;
  final _AppraiseSignal signal;

  @override
  Widget build(BuildContext context) {
    final lines = signal.value.split('\n').where((line) => line.isNotEmpty);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AppraiseSignalIcon(colors: colors, label: signal.label),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line,
                      maxLines: 1,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontFamily: 'NoemaDigits',
                        fontFamilyFallback: const [
                          'LXGWWenKaiGB',
                          'NoemaCjkFallback',
                        ],
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 22 / 16,
                        letterSpacing: 0,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppraiseSignalIcon extends StatelessWidget {
  const _AppraiseSignalIcon({required this.colors, required this.label});

  final _AppraiseSheetStageColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: _AppraiseSvgIcon(
        asset: _appraiseSignalIcon(label),
        size: 20,
        color: colors.accent,
      ),
    );
  }
}

String _appraiseSignalIcon(String label) {
  return switch (label) {
    '清晰度' => _appraiseClarityIcon,
    '曝光' => _appraiseExposureIcon,
    '参数' => _appraiseCameraIcon,
    _ => _appraiseSectionDiamondIcon,
  };
}

List<_AppraiseSignal> _appraiseExifSignals(_AppraiseRecord record) {
  final exif = record.asset.photo.exif;
  if (exif == null || exif.isEmpty) {
    return const [];
  }
  final firstLine = [
    if (exif.iso case final iso?) 'ISO $iso',
    if (exif.shutterSpeed case final shutter? when shutter.isNotEmpty) shutter,
    if (exif.aperture case final aperture?)
      'f/${_appraiseExifNumber(aperture)}',
  ].join('  ');
  final secondLine = [
    if (exif.focalLengthMm case final focal?) '${_appraiseExifNumber(focal)}mm',
    if (exif.whiteBalance case final whiteBalance? when whiteBalance.isNotEmpty)
      whiteBalance,
  ].join('  ');
  final value = [
    if (firstLine.isNotEmpty) firstLine,
    if (secondLine.isNotEmpty) secondLine,
  ].join('\n');
  if (value.isEmpty) {
    return const [];
  }
  return [_AppraiseSignal(label: '参数', value: value)];
}

String _appraiseExifNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

class _AppraiseQuestion extends StatelessWidget {
  const _AppraiseQuestion({
    required this.palette,
    required this.text,
    this.highlightPhotoRefs = false,
  });

  final NoemaPalette palette;
  final String text;
  final bool highlightPhotoRefs;

  @override
  Widget build(BuildContext context) {
    final colors = _appraiseSheetStageColors(palette);
    final textStyle = _appraiseBodyTextStyle(colors);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.quoteBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: highlightPhotoRefs
                ? Text.rich(
                    TextSpan(
                      style: textStyle,
                      children: _appraisePhotoReferenceSpans(
                        text: text,
                        highlightStyle: _appraisePhotoReferenceStyle(colors),
                      ),
                    ),
                  )
                : Text(text, style: textStyle),
          ),
        ),
      ),
    );
  }
}

class _AppraiseAiInlineAction extends StatelessWidget {
  const _AppraiseAiInlineAction({
    required this.palette,
    required this.running,
    required this.hasResult,
    required this.aiReady,
    required this.error,
    required this.onOpenSettings,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final bool running;
  final bool hasResult;
  final bool aiReady;
  final String? error;
  final VoidCallback onOpenSettings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = palette.ink;
    final colors = _appraiseSheetStageColors(palette);
    final errorText = error?.trim();
    if (hasResult && (errorText == null || errorText.isEmpty)) {
      return const SizedBox.shrink();
    }
    final primaryLabel = running
        ? '品鉴中'
        : aiReady
        ? 'AI 品鉴'
        : '启用 AI 品鉴';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              disabledForegroundColor: color.withValues(alpha: 0.48),
              backgroundColor: colors.accentMuted,
              side: BorderSide(color: colors.chipBorder.withValues(alpha: 0.9)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              minimumSize: const Size.fromHeight(46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontFamily: 'LXGWWenKaiGB',
                fontFamilyFallback: ['NoemaCjkFallback'],
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1,
                letterSpacing: 0,
              ),
            ),
            onPressed: running
                ? null
                : aiReady
                ? onPressed
                : onOpenSettings,
            icon: running
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color.withValues(alpha: 0.62),
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 19),
            label: Text(primaryLabel),
          ),
        ),
        if (errorText case final message? when message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: const Color(0xFFE9B7AF).withValues(alpha: 0.86),
              fontFamily: 'LXGWWenKaiGB',
              fontFamilyFallback: const ['NoemaCjkFallback'],
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _AppraiseAiHintPanel extends StatefulWidget {
  const _AppraiseAiHintPanel({
    required this.palette,
    required this.settingsLibrary,
    required this.initialCheckResult,
    required this.onSettingsChanged,
    required this.onCheck,
    required this.onClose,
  });

  final NoemaPalette palette;
  final AppraiseAiSettingsLibrary settingsLibrary;
  final AppraiseAiCheckResult? initialCheckResult;
  final ValueChanged<AppraiseAiSettingsLibrary> onSettingsChanged;
  final Future<AppraiseAiCheckResult> Function(AppraiseAiSettings) onCheck;
  final VoidCallback onClose;

  @override
  State<_AppraiseAiHintPanel> createState() => _AppraiseAiHintPanelState();
}

class _AppraiseAiHintPanelState extends State<_AppraiseAiHintPanel> {
  late AppraiseAiSettingsLibrary _settingsLibrary;
  late AppraiseAiSettings _settings;
  AppraiseAiCheckResult? _checkResult;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _settingsLibrary = widget.settingsLibrary;
    _settings = widget.settingsLibrary.activeSettings;
    _checkResult = widget.initialCheckResult;
  }

  @override
  void didUpdateWidget(covariant _AppraiseAiHintPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsLibrary != widget.settingsLibrary &&
        _settings == oldWidget.settingsLibrary.activeSettings) {
      _settingsLibrary = widget.settingsLibrary;
      _settings = widget.settingsLibrary.activeSettings;
      _checkResult = widget.initialCheckResult;
    }
  }

  void _updateSettings(AppraiseAiSettings settings) {
    setState(() {
      _settingsLibrary = _settingsLibrary.withActiveSettings(settings);
      _settings = _settingsLibrary.activeSettings;
      _checkResult = null;
    });
  }

  void _saveAndClose() {
    final shouldAutoEnable = _settings.apiKey.trim().isNotEmpty;
    final nextLibrary = _settingsLibrary.withActiveSettings(
      shouldAutoEnable ? _settings.copyWith(enabled: true) : _settings,
    );
    widget.onSettingsChanged(nextLibrary);
    widget.onClose();
  }

  void _selectProvider(String value) {
    setState(() {
      _settingsLibrary = _settingsLibrary.selectProvider(value);
      _settings = _settingsLibrary.activeSettings;
      _checkResult = null;
    });
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      await _appraiseExternalLinksChannel.invokeMethod<void>('openUrl', {
        'url': url,
      });
    } on PlatformException catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('无法打开浏览器'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: widget.palette.sheet.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: widget.palette.glassBorder),
          ),
        ),
      );
    }
  }

  void _showQwenBailianGuide() {
    unawaited(
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.46),
        builder: (dialogContext) => _QwenBailianGuideDialog(
          palette: widget.palette,
          onClose: () => Navigator.of(dialogContext).pop(),
          onOpenConsole: () {
            Navigator.of(dialogContext).pop();
            unawaited(_openExternalUrl(_qwenBailianConsoleUrl));
          },
          onOpenApiKeyHelp: () =>
              unawaited(_openExternalUrl(_qwenApiKeyHelpUrl)),
          onOpenOpenAiHelp: () =>
              unawaited(_openExternalUrl(_qwenOpenAiHelpUrl)),
        ),
      ),
    );
  }

  Future<void> _check() async {
    if (_checking) {
      return;
    }
    final shouldAutoEnable = _settings.apiKey.trim().isNotEmpty;
    final settingsForCheck = shouldAutoEnable
        ? _settings.copyWith(enabled: true)
        : _settings;
    final settingsLibraryForCheck = _settingsLibrary.withActiveSettings(
      settingsForCheck,
    );
    setState(() {
      _settingsLibrary = settingsLibraryForCheck;
      _settings = settingsForCheck;
      _checking = true;
      _checkResult = null;
    });
    final result = await widget.onCheck(settingsForCheck);
    if (!mounted) {
      return;
    }
    setState(() {
      _checkResult = result;
      _checking = false;
    });
    if (result.ok) {
      widget.onSettingsChanged(settingsLibraryForCheck);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final strings = NoemaStrings.of(context);
    final providerOption = appraiseAiProviderOptionFor(_settings.provider);
    return Theme(
      data: _appraiseSettingsMaterialTheme(context, palette),
      child: Material(
        color: Colors.transparent,
        child: NoemaSceneFrame(
          palette: palette,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: NoemaSceneMetrics.markLeft,
                top: NoemaSceneMetrics.markTop,
                child: NoemaThemeMark(palette: palette, mark: '赋'),
              ),
              Positioned(
                left: NoemaSceneMetrics.topBarInset,
                right: NoemaSceneMetrics.topBarInset,
                top: NoemaSceneMetrics.topBarTop,
                child: _AppraiseAiSettingsTopBar(
                  palette: palette,
                  onBack: widget.onClose,
                ),
              ),
              Positioned(
                left: NoemaSceneMetrics.sideInset,
                right: NoemaSceneMetrics.sideInset,
                top: 116,
                bottom: 0,
                child: Stack(
                  children: [
                    ListView(
                      key: const ValueKey('appraise-ai-settings-page'),
                      padding: const EdgeInsets.fromLTRB(0, 18, 0, 46),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'AI 设置',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontFamily: 'LXGWWenKaiGB',
                                  fontSize: 30,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: strings.isZh ? '保存' : 'Save',
                              child: TextButton(
                                onPressed: _saveAndClose,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(96, 42),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 10,
                                  ),
                                  foregroundColor: palette.ink.withValues(
                                    alpha: 0.90,
                                  ),
                                  backgroundColor: palette.glass.withValues(
                                    alpha: palette.tone == NoemaTone.dark
                                        ? 0.20
                                        : 0.36,
                                  ),
                                  shape: const StadiumBorder(),
                                  side: BorderSide(
                                    color: palette.ink.withValues(alpha: 0.16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                  ),
                                ),
                                child: Text(strings.isZh ? '保存' : 'Save'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '配置用于品鉴照片的视觉模型。',
                          style: TextStyle(
                            color: palette.muted.withValues(alpha: 0.78),
                            fontSize: 13,
                            height: 1.48,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '启用 AI 品鉴',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontFamily: 'LXGWWenKaiGB',
                                  fontSize: 20,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            Switch(
                              value: _settings.enabled,
                              activeThumbColor: palette.ink,
                              activeTrackColor: palette.ink.withValues(
                                alpha: 0.28,
                              ),
                              inactiveThumbColor: palette.muted.withValues(
                                alpha: 0.62,
                              ),
                              inactiveTrackColor: palette.glass.withValues(
                                alpha: 0.44,
                              ),
                              onChanged: (enabled) => _updateSettings(
                                _settings.copyWith(enabled: enabled),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _AppraiseSettingsLabel(
                          palette: palette,
                          text: 'Provider',
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'appraise-ai-provider-${providerOption.id}',
                          ),
                          initialValue: providerOption.id,
                          items: [
                            for (final option in appraiseAiProviderOptions)
                              DropdownMenuItem(
                                value: option.id,
                                child: Text(option.label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _selectProvider(value);
                            }
                          },
                          dropdownColor: _appraiseSettingsMenuSurface(palette),
                          iconEnabledColor: palette.ink.withValues(alpha: 0.72),
                          iconDisabledColor: palette.muted.withValues(
                            alpha: 0.42,
                          ),
                          style: _appraiseSettingsInputTextStyle(palette),
                          decoration: _appraiseSettingsInputDecoration(palette),
                        ),
                        if (providerOption.id == 'qwen') ...[
                          const SizedBox(height: 10),
                          _QwenBailianRecommendation(
                            palette: palette,
                            onOpenGuide: _showQwenBailianGuide,
                          ),
                        ],
                        if (providerOption.allowCustomBaseUrl) ...[
                          const SizedBox(height: 14),
                          _AppraiseSettingsLabel(
                            palette: palette,
                            text: 'Base URL',
                          ),
                          TextFormField(
                            key: ValueKey(
                              'appraise-ai-base-url-${providerOption.id}',
                            ),
                            initialValue: _settings.baseUrl,
                            keyboardType: TextInputType.url,
                            onChanged: (value) => _updateSettings(
                              _settings.copyWith(baseUrl: value),
                            ),
                            cursorColor: palette.ink,
                            style: _appraiseSettingsInputTextStyle(palette),
                            decoration: _appraiseSettingsInputDecoration(
                              palette,
                              hintText: providerOption.baseUrl,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _AppraiseSettingsLabel(palette: palette, text: '模型'),
                        TextFormField(
                          key: ValueKey(
                            'appraise-ai-model-${providerOption.id}-${_settings.model}',
                          ),
                          initialValue: _settings.model,
                          onChanged: (value) =>
                              _updateSettings(_settings.copyWith(model: value)),
                          cursorColor: palette.ink,
                          style: _appraiseSettingsInputTextStyle(palette),
                          decoration: _appraiseSettingsInputDecoration(
                            palette,
                            hintText: providerOption.defaultModel,
                          ),
                        ),
                        if (providerOption.models.length > 1) ...[
                          const SizedBox(height: 8),
                          _AppraiseModelSuggestionRow(
                            palette: palette,
                            models: providerOption.models,
                            selectedModel: _settings.model,
                            onModelSelected: (model) => _updateSettings(
                              _settings.copyWith(model: model),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _AppraiseSettingsLabel(
                          palette: palette,
                          text: 'API Key',
                        ),
                        TextFormField(
                          key: ValueKey(
                            'appraise-ai-api-key-field-${providerOption.id}',
                          ),
                          initialValue: '',
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          onChanged: (value) => _updateSettings(
                            _settings.copyWith(apiKey: value),
                          ),
                          cursorColor: palette.ink,
                          style: _appraiseSettingsInputTextStyle(palette),
                          decoration: _appraiseSettingsInputDecoration(
                            palette,
                            hintText: _settings.apiKey.trim().isEmpty
                                ? providerOption.apiKeyHint
                                : '已填写，可重新输入',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'API Key 保存在设备安全存储中，重新输入会替换旧密钥。',
                          style: TextStyle(
                            color: palette.muted.withValues(alpha: 0.70),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        if (_checkResult case final result?) ...[
                          const SizedBox(height: 14),
                          _AppraiseAiCheckLine(
                            palette: palette,
                            result: result,
                          ),
                        ],
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: palette.ink.withValues(
                                alpha: 0.86,
                              ),
                              disabledForegroundColor: palette.muted.withValues(
                                alpha: 0.58,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 10,
                              ),
                            ),
                            onPressed: _checking ? null : _check,
                            icon: _checking
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.ink.withValues(
                                        alpha: 0.72,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.fact_check_outlined,
                                    size: 18,
                                  ),
                            label: Text(_checking ? '测试中' : '测试'),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: NoemaScrollEdgeFade(
                        palette: palette,
                        top: false,
                        height: 62,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppraiseAiSettingsTopBar extends StatelessWidget {
  const _AppraiseAiSettingsTopBar({
    required this.palette,
    required this.onBack,
  });

  final NoemaPalette palette;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    return SizedBox(
      height: NoemaSceneMetrics.topBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: NoemaGlassIconButton(
              palette: palette,
              tooltip: strings.back,
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: onBack,
            ),
          ),
          NoemaWordmark(color: palette.ink, text: strings.appName),
        ],
      ),
    );
  }
}

class _QwenBailianRecommendation extends StatelessWidget {
  const _QwenBailianRecommendation({
    required this.palette,
    required this.onOpenGuide,
  });

  final NoemaPalette palette;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final accent = palette.ink.withValues(alpha: 0.80);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '千问可通过阿里云百炼平台接入，新用户拥有免费额度。',
                style: TextStyle(
                  color: palette.muted.withValues(alpha: 0.78),
                  fontSize: 12.5,
                  height: 1.42,
                  letterSpacing: 0,
                ),
              ),
              TextButton(
                onPressed: onOpenGuide,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontFamily: 'LXGWWenKaiGB',
                    fontFamilyFallback: ['NoemaCjkFallback'],
                    fontSize: 12.5,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                child: const Text('查看获取 API Key 的方式'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QwenBailianGuideDialog extends StatelessWidget {
  const _QwenBailianGuideDialog({
    required this.palette,
    required this.onClose,
    required this.onOpenConsole,
    required this.onOpenApiKeyHelp,
    required this.onOpenOpenAiHelp,
  });

  final NoemaPalette palette;
  final VoidCallback onClose;
  final VoidCallback onOpenConsole;
  final VoidCallback onOpenApiKeyHelp;
  final VoidCallback onOpenOpenAiHelp;

  @override
  Widget build(BuildContext context) {
    return NoemaDialogPanel(
      palette: palette,
      title: '阿里云百炼配置指引',
      onClose: onClose,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoemaDialogText(
            palette: palette,
            text:
                '千问可通过阿里云百炼平台接入，新用户拥有免费额度。打开浏览器后，注册并创建 API Key，再回到 Noema 填入即可。',
            color: palette.ink.withValues(alpha: 0.86),
          ),
          const SizedBox(height: 12),
          _QwenGuideStep(text: '1. 登录阿里云百炼控制台', palette: palette),
          _QwenGuideStep(text: '2. 查看免费额度并创建 API Key', palette: palette),
          _QwenGuideStep(text: '3. 回到 Noema 粘贴 API Key', palette: palette),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _QwenGuideLink(
                palette: palette,
                label: 'API Key 说明',
                onPressed: onOpenApiKeyHelp,
              ),
              _QwenGuideLink(
                palette: palette,
                label: '接口兼容说明',
                onPressed: onOpenOpenAiHelp,
              ),
            ],
          ),
        ],
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          NoemaDialogButton(
            palette: palette,
            label: '打开百炼控制台',
            icon: Icons.open_in_browser_rounded,
            onPressed: onOpenConsole,
            tone: NoemaDialogButtonTone.primary,
          ),
        ],
      ),
    );
  }
}

class _QwenGuideStep extends StatelessWidget {
  const _QwenGuideStep({required this.text, required this.palette});

  final String text;
  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          color: palette.muted.withValues(alpha: 0.82),
          fontSize: 12.5,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _QwenGuideLink extends StatelessWidget {
  const _QwenGuideLink({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.open_in_new_rounded, size: 13),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: palette.ink.withValues(alpha: 0.66),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, height: 1.2, letterSpacing: 0),
      ),
    );
  }
}

class _AppraiseModelSuggestionRow extends StatelessWidget {
  const _AppraiseModelSuggestionRow({
    required this.palette,
    required this.models,
    required this.selectedModel,
    required this.onModelSelected,
  });

  final NoemaPalette palette;
  final List<String> models;
  final String selectedModel;
  final ValueChanged<String> onModelSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final model in models)
          Builder(
            builder: (context) {
              final selected = model == selectedModel;
              return ChoiceChip(
                label: Text(
                  model,
                  style: TextStyle(
                    color: selected
                        ? palette.ink.withValues(alpha: 0.92)
                        : palette.muted.withValues(alpha: 0.86),
                    fontSize: 12,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => onModelSelected(model),
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _appraiseSettingsControlSelectedFill(palette);
                  }
                  return _appraiseSettingsControlFill(palette);
                }),
                side: BorderSide(
                  color: _appraiseSettingsControlBorder(palette),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _AppraiseSettingsLabel extends StatelessWidget {
  const _AppraiseSettingsLabel({required this.palette, required this.text});

  final NoemaPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          color: palette.ink.withValues(alpha: 0.72),
          fontSize: 12,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AppraiseAiCheckLine extends StatelessWidget {
  const _AppraiseAiCheckLine({required this.palette, required this.result});

  final NoemaPalette palette;
  final AppraiseAiCheckResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.ok
        ? palette.ink.withValues(alpha: 0.76)
        : const Color(0xFFE9B7AF).withValues(alpha: 0.86);
    return Row(
      children: [
        Icon(
          result.ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            result.message,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _appraiseSettingsInputDecoration(
  NoemaPalette palette, {
  String? hintText,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: _appraiseSettingsControlBorder(palette)),
  );
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: TextStyle(color: palette.muted.withValues(alpha: 0.60)),
    filled: true,
    fillColor: _appraiseSettingsControlFill(palette),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: palette.tone == NoemaTone.light
            ? const Color(0xFF9A6A2E).withValues(alpha: 0.42)
            : palette.ink.withValues(alpha: 0.28),
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  );
}

ThemeData _appraiseSettingsMaterialTheme(
  BuildContext context,
  NoemaPalette palette,
) {
  final base = Theme.of(context);
  final brightness = palette.tone == NoemaTone.light
      ? Brightness.light
      : Brightness.dark;
  return base.copyWith(
    brightness: brightness,
    canvasColor: _appraiseSettingsMenuSurface(palette),
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: palette.ink,
      surface: _appraiseSettingsMenuSurface(palette),
      onSurface: palette.ink,
      outline: _appraiseSettingsControlBorder(palette),
    ),
    focusColor: palette.ink.withValues(alpha: 0.08),
    highlightColor: palette.ink.withValues(alpha: 0.08),
    hoverColor: palette.ink.withValues(alpha: 0.06),
    splashColor: palette.ink.withValues(alpha: 0.08),
    textSelectionTheme: TextSelectionThemeData(cursorColor: palette.ink),
  );
}

TextStyle _appraiseSettingsInputTextStyle(NoemaPalette palette) {
  return TextStyle(
    color: palette.ink.withValues(alpha: 0.90),
    fontSize: 15,
    height: 1.2,
    letterSpacing: 0,
  );
}

Color _appraiseSettingsMenuSurface(NoemaPalette palette) {
  if (palette.tone == NoemaTone.light) {
    return const Color(0xFFFBF6EC);
  }
  return const Color(0xFF141413);
}

Color _appraiseSettingsControlFill(NoemaPalette palette) {
  if (palette.tone == NoemaTone.light) {
    return const Color(0xFFF7F1E8);
  }
  return palette.ink.withValues(alpha: 0.045);
}

Color _appraiseSettingsControlSelectedFill(NoemaPalette palette) {
  if (palette.tone == NoemaTone.light) {
    return const Color(0xFFE9DDCB);
  }
  return palette.ink.withValues(alpha: 0.14);
}

Color _appraiseSettingsControlBorder(NoemaPalette palette) {
  if (palette.tone == NoemaTone.light) {
    return const Color(0x3324211D);
  }
  return palette.ink.withValues(alpha: 0.11);
}

class _AppraiseEmptyState extends StatelessWidget {
  const _AppraiseEmptyState({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '此境还没有可鉴的照片',
        style: TextStyle(
          color: palette.muted.withValues(alpha: 0.82),
          fontFamily: 'LXGWWenKaiGB',
          fontSize: 18,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AppraiseLaneEmpty extends StatelessWidget {
  const _AppraiseLaneEmpty({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '这一档暂时没有照片',
        style: TextStyle(
          color: palette.muted.withValues(alpha: 0.72),
          fontFamily: 'LXGWWenKaiGB',
          fontSize: 16,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

_AppraiseBand _resolvedBandFor(
  _LocalAppraisal appraisal,
  AppraiseAiPhotoResult? aiResult,
) {
  final band = aiResult == null
      ? appraiseBandForTechnicalGate(appraisal.gate)
      : appraiseBandForScore(aiResult.totalScore);
  return _appraiseBandFromShared(band);
}

_AppraiseBand _appraiseBandFromShared(AppraisePhotoBand band) {
  return switch (band) {
    AppraisePhotoBand.flaw => _AppraiseBand.flaw,
    AppraisePhotoBand.formed => _AppraiseBand.formed,
    AppraisePhotoBand.fine => _AppraiseBand.fine,
  };
}

int _aiParallelSizeForRound(int round) {
  if (round < 2) {
    return 3;
  }
  return math.min(5, round + 2);
}

SeriesAppraisalBand? _seriesBandFor(_AppraiseBand band) {
  return switch (band) {
    _AppraiseBand.formed => SeriesAppraisalBand.formed,
    _AppraiseBand.fine => SeriesAppraisalBand.fine,
    _AppraiseBand.cherished => SeriesAppraisalBand.cherished,
    _AppraiseBand.flaw => null,
  };
}

String _seriesPhotoSetHash(List<_AppraiseRecord> records) {
  final ids = [for (final record in records) record.asset.photo.id]..sort();
  return ids.join('|');
}

({DateTime start, DateTime end}) _seriesCaptureRange(
  List<_AppraiseRecord> records,
) {
  final times = [for (final record in records) record.asset.photo.createdAt]
    ..sort();
  final fallback = DateTime.now();
  return (
    start: times.isEmpty ? fallback : times.first,
    end: times.isEmpty ? fallback : times.last,
  );
}

String _seriesBandLabel(SeriesAppraisalBand band) {
  return switch (band) {
    SeriesAppraisalBand.formed => '成片',
    SeriesAppraisalBand.fine => '佳作',
    SeriesAppraisalBand.cherished => '珍藏',
  };
}

double _nearestAppraiseSheetFraction(double fraction) {
  const stages = [
    _appraiseViewerSheetHiddenFraction,
    _appraiseViewerSheetPeekFraction,
    _appraiseViewerSheetDefaultFraction,
  ];
  return stages.reduce((best, stage) {
    final bestDistance = (best - fraction).abs();
    final stageDistance = (stage - fraction).abs();
    return stageDistance < bestDistance ? stage : best;
  });
}

String _bandLabel(NoemaStrings strings, _AppraiseBand band) {
  if (!strings.isZh) {
    return switch (band) {
      _AppraiseBand.flaw => 'Minor flaw',
      _AppraiseBand.formed => 'Finished',
      _AppraiseBand.fine => 'Fine',
      _AppraiseBand.cherished => 'Loved',
    };
  }
  return switch (band) {
    _AppraiseBand.flaw => '微瑕',
    _AppraiseBand.formed => '成片',
    _AppraiseBand.fine => '佳作',
    _AppraiseBand.cherished => '珍藏',
  };
}

_LocalAppraisal _localAppraisalFor(
  ReviewAsset asset,
  AnalysisResult? analysis,
) {
  final clarity = (analysis?.blurScore ?? 0.78).clamp(0.0, 1.0);
  final exposureFlag = analysis?.exposureFlag ?? ExposureFlag.normal;
  final gate = appraiseTechnicalGateFor(analysis);
  final canShowAnalysisSignals =
      analysis != null &&
      !analysis.qualityFlags.contains(QualityFlag.unavailable) &&
      !analysis.qualityFlags.contains(QualityFlag.unsupportedType);
  return _LocalAppraisal(
    gate: gate,
    signals: canShowAnalysisSignals
        ? [
            _AppraiseSignal(label: '清晰度', value: _claritySignal(clarity)),
            _AppraiseSignal(label: '曝光', value: _exposureSignal(exposureFlag)),
          ]
        : const [],
  );
}

String _claritySignal(double clarity) {
  if (clarity >= 0.72) {
    return '清楚';
  }
  if (clarity >= 0.5) {
    return '略糊';
  }
  return '模糊';
}

String _exposureSignal(ExposureFlag exposureFlag) {
  return switch (exposureFlag) {
    ExposureFlag.normal => '正常',
    ExposureFlag.dark => '偏暗',
    ExposureFlag.overexposed => '过亮',
    ExposureFlag.highlightRisk => '高光风险',
  };
}

double _assetAspectRatio(ReviewAsset asset) {
  final width = asset.photo.width;
  final height = asset.photo.height;
  if (width <= 0 || height <= 0) {
    return 1;
  }
  return (width / height).clamp(0.58, 2.05).toDouble();
}
