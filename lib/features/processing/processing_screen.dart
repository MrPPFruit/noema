import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/debug/noema_tune_exporter.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_dialog.dart';
import 'package:noema/core/widgets/noema_remove_assets_dialog.dart';
import 'package:noema/core/widgets/noema_sort_icons.dart';
import 'package:noema/core/widgets/photo_wall_badges.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/observe/observe_photo_wall_layout.dart';
import 'package:noema/features/processing/photo_viewer_page.dart';

const _observeEase = Cubic(0.16, 1, 0.3, 1);
const _observeWallShadowGutter = 10.0;
const _observeWallTopFadeHeight = 48.0;
const _observeWallBottomFadeHeight = 124.0;
const _observeWallTopPadding = 12.0;
const _observeWallBottomPadding = 142.0;
const _observeWallVisibleGutterFactor = 0.75;
const _observeWallVisibleGutterBase = 160.0;
const _observeWallScrollUpdateThreshold = 96.0;
const _observeExperienceDockBottom = 11.0;
const _observeExperienceIntentDockHeight = 116.0;
const _observeAppreciateDockCancelTopPadding = 48.0;
const _observeThumbnailMaxSize = 640;
const _observeReflowInputCooldown = Duration(milliseconds: 320);
const _observeWallReflowDuration = Duration(milliseconds: 360);
const _observeWallReflowSettleGrace = Duration(milliseconds: 80);
const _observeViewerPrecacheMaxWait = Duration(milliseconds: 320);
const _intentEntryThreshold = 0.45;
const _intentVerticalFollowLimit = 26.0;
const _intentViewDragLiftThreshold = 18.0;
const _intentInitialSnapDuration = Duration(milliseconds: 360);
const _intentInitialSnapCurve = Curves.easeInOutCubic;
const _intentInitialSnapMoveTolerance = 8.0;

enum _ObserveTimeSort { newestFirst, oldestFirst }

enum _ObserveSortMode { time, score }

enum _ObserveScoreSort { highToLow, lowToHigh }

enum _ObserveFilterMode { all, cherished }

enum ExperienceDockVariant {
  focus,
  lens,
  object,
  intent,
  intentRipple,
  intentSeal,
  intentTiles,
  intentRail,
  intentGate,
  quiet,
  orbit,
  rail,
  balanced,
}

ExperienceDockVariant experienceDockVariantFromQuery(String? value) {
  return switch (value) {
    'balanced' || 'classic' => ExperienceDockVariant.balanced,
    'lens' || 'mirror' => ExperienceDockVariant.lens,
    'object' || 'emerge' || 'field' => ExperienceDockVariant.object,
    'intent' || 'axis' => ExperienceDockVariant.intent,
    'intent-ripple' ||
    'ripple' ||
    'water' => ExperienceDockVariant.intentRipple,
    'intent-seal' ||
    'seal' ||
    'intent-mark' => ExperienceDockVariant.intentSeal,
    'intent-tiles' || 'tiles' => ExperienceDockVariant.intentTiles,
    'intent-rail' ||
    'intent-slate' ||
    'slate' => ExperienceDockVariant.intentRail,
    'intent-gate' || 'gate' => ExperienceDockVariant.intentGate,
    'quiet' || 'silent' => ExperienceDockVariant.quiet,
    'orbit' => ExperienceDockVariant.orbit,
    'rail' => ExperienceDockVariant.rail,
    'focus' => ExperienceDockVariant.focus,
    _ => ExperienceDockVariant.intentSeal,
  };
}

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.selectedCount,
    this.experienceDockVariant = ExperienceDockVariant.intentSeal,
    this.experienceDockTuning = false,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final int? selectedCount;
  final ExperienceDockVariant experienceDockVariant;
  final bool experienceDockTuning;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final GlobalKey<_ObservePhotoWallState> _photoWallKey =
      GlobalKey<_ObservePhotoWallState>();
  final ScrollController _wallScrollController = ScrollController();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final Set<String> _selectedPhotoIds = {};

  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;

  _ObserveTimeSort _timeSort = _ObserveTimeSort.newestFirst;
  _ObserveSortMode _sortMode = _ObserveSortMode.time;
  _ObserveScoreSort _scoreSort = _ObserveScoreSort.highToLow;
  _ObserveFilterMode _filterMode = _ObserveFilterMode.all;
  ObserveWallDensity _density = ObserveWallDensity.balanced;
  bool _isEditingName = false;
  bool _observeOptionsOpen = false;
  bool _showNameRequiredHint = false;
  bool _missingNoticeScheduled = false;
  bool _missingNoticeDialogOpen = false;
  bool _experienceDockPaused = false;
  String? _openingPreviewPhotoId;
  String? _appreciateDragTargetPhotoId;
  String? _observePreferencesWorkspaceId;
  int _openingPreviewGeneration = 0;
  double _scaleDelta = 1;
  double _scaleFocalY = 0;
  NoemaBackNavigationController? _backNavigationController;
  VoidCallback? _unregisterBackHandler;
  Timer? _observeReflowInputTimer;
  Timer? _experienceDockPauseTimer;

  bool get _selectingPhotos => _selectedPhotoIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    widget.workspaceController.addListener(_handleWorkspaceChanged);
    _applyObservePreferences(widget.workspaceController.workspace);
    _scheduleMissingAssetNotice();
  }

  @override
  void didUpdateWidget(covariant ProcessingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceController != widget.workspaceController) {
      oldWidget.workspaceController.removeListener(_handleWorkspaceChanged);
      widget.workspaceController.addListener(_handleWorkspaceChanged);
      _observePreferencesWorkspaceId = null;
      _applyObservePreferences(widget.workspaceController.workspace);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = NoemaBackNavigationScope.maybeOf(context);
    if (controller == _backNavigationController) {
      return;
    }
    _unregisterBackHandler?.call();
    _backNavigationController = controller;
    _unregisterBackHandler = controller?.registerLocalBackHandler(
      _handleLocalBackIntent,
    );
  }

  @override
  void dispose() {
    _unregisterBackHandler?.call();
    _observeReflowInputTimer?.cancel();
    _experienceDockPauseTimer?.cancel();
    widget.workspaceController.removeListener(_handleWorkspaceChanged);
    _wallScrollController.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
  }

  bool _handleLocalBackIntent() {
    if (_selectingPhotos) {
      setState(() => _selectedPhotoIds.clear());
      return true;
    }
    if (_isEditingName) {
      _cancelNameEdit();
      return true;
    }
    return false;
  }

  void _applyObservePreferences(ReviewWorkspace workspace) {
    final workspaceId = workspace.session.id;
    if (_observePreferencesWorkspaceId == workspaceId) {
      return;
    }
    _observePreferencesWorkspaceId = workspaceId;
    final preferences = workspace.observeViewPreferences;
    _timeSort = _observeTimeSortFromPreference(preferences.timeSort);
    _sortMode = _observeSortModeFromPreference(preferences.sortMode);
    _scoreSort = _observeScoreSortFromPreference(preferences.scoreSort);
    _filterMode = _observeFilterModeFromPreference(preferences.filterMode);
    _density = _observeDensityFromPreference(preferences.density);
  }

  void _persistObservePreferences() {
    widget.workspaceController.setObserveViewPreferences(
      ObserveViewPreferences(
        timeSort: _timeSort.name,
        sortMode: _sortMode.name,
        scoreSort: _scoreSort.name,
        filterMode: _filterMode.name,
        density: _density.name,
      ),
    );
  }

  void _handleWorkspaceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _applyObservePreferences(widget.workspaceController.workspace);
    });
    _scheduleMissingAssetNotice();
  }

  void _handleObserveInteractionBusy() {
    widget.workspaceController.deferBackgroundPreviewCaching();
    _experienceDockPauseTimer?.cancel();
    if (!_experienceDockPaused) {
      setState(() {
        _experienceDockPaused = true;
      });
    }
    // ponytail: hide the expensive glass dock only while scrolling; if users
    // need actions mid-scroll, replace this with a cheap non-blur dock variant.
    _experienceDockPauseTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _experienceDockPaused = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final palette = NoemaPalette.fromTone(
          _appearanceController.resolveTone(context),
        );
        final workspace = widget.workspaceController.workspace;
        final sceneLayout = NoemaSceneMetrics.layoutOf(context);
        final topBarTop = sceneLayout.topBarTop;
        final topShift = sceneLayout.topSafeShift;
        final sourceAssets = workspace.assets;
        final hasAppraisalScores = sourceAssets.any(
          (asset) => asset.photo.appraisalScore != null,
        );
        final hasCherishedAssets = sourceAssets.any(
          (asset) => asset.photo.isCherished,
        );
        final assets = _visibleAssets(sourceAssets);
        final missingIndexes = widget.workspaceController.missingAssetIndexes;
        final displayCount = assets.isNotEmpty
            ? assets.length
            : widget.selectedCount ?? workspace.session.totalCount;
        final dockExperimentMode =
            widget.experienceDockVariant != ExperienceDockVariant.intentSeal ||
            widget.experienceDockTuning;
        final appraiseAvailable = dockExperimentMode || assets.isNotEmpty;

        return Scaffold(
          body: NoemaSceneFrame(
            palette: palette,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: sceneLayout.markLeft,
                  top: NoemaSceneMetrics.markTop,
                  child: NoemaThemeMark(palette: palette, mark: '观'),
                ),
                Positioned(
                  left: sceneLayout.topBarInset,
                  right: sceneLayout.topBarInset,
                  top: topBarTop,
                  child: _ObserveTopBar(
                    palette: palette,
                    onBack: () => context.go(NoemaRoutes.home),
                  ),
                ),
                Positioned(
                  left: sceneLayout.sideInset,
                  right: sceneLayout.sideInset,
                  top: 84 + topShift,
                  bottom: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ObserveHeader(
                        palette: palette,
                        spaceName: workspace.session.name,
                        photoCount: displayCount,
                        sortMode: _effectiveSortMode(hasAppraisalScores),
                        timeSort: _timeSort,
                        scoreSort: _scoreSort,
                        filterMode: _effectiveFilterMode(hasCherishedAssets),
                        density: _density,
                        nameController: _nameController,
                        nameFocusNode: _nameFocusNode,
                        isEditingName: _isEditingName,
                        showNameRequiredHint: _showNameRequiredHint,
                        selectingPhotos: _selectingPhotos,
                        hasMissingAssets: missingIndexes.isNotEmpty,
                        optionsOpen: _observeOptionsOpen,
                        onStartEditingName: () =>
                            _startEditingName(workspace.session.name),
                        onNameChanged: _handleNameChanged,
                        onSaveName: _saveName,
                        onCancelNameEdit: _cancelNameEdit,
                        onClearPhotoSelection: _clearPhotoSelection,
                        onRemoveSelectedPhotos: _confirmRemoveSelectedPhotos,
                        onToggleOptions: _toggleObserveOptions,
                        onAddPhotos: () => context.go(appendImportRoute()),
                        onShowMissingAssets: () =>
                            _showMissingAssetNotice(missingIndexes),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: assets.isEmpty
                            ? _ObserveEmptyState(
                                palette: palette,
                                onAddPhotos: () =>
                                    context.go(appendImportRoute()),
                              )
                            : _ObservePhotoWall(
                                key: _photoWallKey,
                                palette: palette,
                                assets: assets,
                                density: _density,
                                showScoreBadges: hasAppraisalScores,
                                selectedIds: _selectedPhotoIds,
                                openingPhotoId: _openingPreviewPhotoId,
                                appreciateDragTargetPhotoId:
                                    _appreciateDragTargetPhotoId,
                                scrollController: _wallScrollController,
                                onInteractionBusy:
                                    _handleObserveInteractionBusy,
                                onOpenPreview: _openPhotoPreview,
                                onStartSelection: _startPhotoSelection,
                                onToggleSelection: _togglePhotoSelection,
                                onMetadataLoaded: widget
                                    .workspaceController
                                    .updateAssetMetadata,
                                onThumbnailLoaded: widget
                                    .workspaceController
                                    .updateAssetThumbnailPath,
                                onMissingAsset:
                                    widget.workspaceController.markAssetMissing,
                                onScaleStart: _handleScaleStart,
                                onScaleUpdate: _handleScaleUpdate,
                                onScaleEnd: _handleScaleEnd,
                              ),
                      ),
                    ],
                  ),
                ),
                if (_observeOptionsOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _closeObserveOptions,
                    ),
                  ),
                Positioned(
                  right: sceneLayout.sideInset,
                  top: 176 + topShift,
                  child: _ObserveOptionsSheet(
                    palette: palette,
                    open: _observeOptionsOpen,
                    sortMode: _effectiveSortMode(hasAppraisalScores),
                    timeSort: _timeSort,
                    scoreSort: _scoreSort,
                    filterMode: _effectiveFilterMode(hasCherishedAssets),
                    density: _density,
                    hasAppraisalScores: hasAppraisalScores,
                    hasCherishedAssets: hasCherishedAssets,
                    onSortModeSelected: _selectSortMode,
                    onCycleFilterMode: _cycleFilterMode,
                    onCycleDensity: () => _setDensity(_nextDensity(_density)),
                  ),
                ),
                if (assets.isNotEmpty)
                  Positioned(
                    left: 42,
                    right: 42,
                    bottom: _observeExperienceDockBottom,
                    child: AnimatedOpacity(
                      opacity: _selectingPhotos || _experienceDockPaused
                          ? 0
                          : 1,
                      duration: Duration(
                        milliseconds: _experienceDockPaused ? 80 : 140,
                      ),
                      child: IgnorePointer(
                        ignoring: _selectingPhotos || _experienceDockPaused,
                        child: _ExperienceDock(
                          palette: palette,
                          variant: widget.experienceDockVariant,
                          tuning: widget.experienceDockTuning,
                          cullAvailable: true,
                          appraiseAvailable: appraiseAvailable,
                          onCull: () => context.go(NoemaRoutes.reviewGroups),
                          onView: () => _openAppreciate(
                            hasAppraisalScores: hasAppraisalScores,
                          ),
                          onViewDragUpdate: _handleAppreciateDragUpdate,
                          onViewDragEnd: () => _finishAppreciateDrag(
                            hasAppraisalScores: hasAppraisalScores,
                          ),
                          onViewDragCancel: _clearAppreciateDragTarget,
                          onAppraise: () => context.go(appraiseRoute()),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<ReviewAsset> _visibleAssets(List<ReviewAsset> assets) {
    final filterMode = _effectiveFilterMode(
      assets.any((asset) => asset.photo.isCherished),
    );
    final visible = filterMode == _ObserveFilterMode.cherished
        ? assets.where((asset) => asset.photo.isCherished)
        : assets;
    return _orderedAssets(visible.toList(growable: false));
  }

  List<ReviewAsset> _orderedAssets(List<ReviewAsset> assets) {
    final hasScores = assets.any((asset) => asset.photo.appraisalScore != null);
    final sortMode = _effectiveSortMode(hasScores);
    final ordered = [...assets];
    ordered.sort((a, b) {
      if (sortMode == _ObserveSortMode.score) {
        final aScore = a.photo.appraisalScore;
        final bScore = b.photo.appraisalScore;
        if (aScore != null || bScore != null) {
          if (aScore == null) {
            return 1;
          }
          if (bScore == null) {
            return -1;
          }
          final scoreValue = aScore.compareTo(bScore);
          if (scoreValue != 0) {
            return _scoreSort == _ObserveScoreSort.highToLow
                ? -scoreValue
                : scoreValue;
          }
        }
      }
      return _compareByTime(a, b);
    });
    return ordered;
  }

  int _compareByTime(ReviewAsset a, ReviewAsset b) {
    return switch (_timeSort) {
      _ObserveTimeSort.newestFirst => b.photo.createdAt.compareTo(
        a.photo.createdAt,
      ),
      _ObserveTimeSort.oldestFirst => a.photo.createdAt.compareTo(
        b.photo.createdAt,
      ),
    };
  }

  _ObserveSortMode _effectiveSortMode(bool hasAppraisalScores) {
    if (_sortMode == _ObserveSortMode.score && !hasAppraisalScores) {
      return _ObserveSortMode.time;
    }
    return _sortMode;
  }

  _ObserveFilterMode _effectiveFilterMode(bool hasCherishedAssets) {
    if (_filterMode == _ObserveFilterMode.cherished && !hasCherishedAssets) {
      return _ObserveFilterMode.all;
    }
    return _filterMode;
  }

  void _toggleTimeSort() {
    if (!_startObserveReflowInputCooldown()) {
      return;
    }
    setState(() {
      _timeSort = switch (_timeSort) {
        _ObserveTimeSort.newestFirst => _ObserveTimeSort.oldestFirst,
        _ObserveTimeSort.oldestFirst => _ObserveTimeSort.newestFirst,
      };
    });
    _persistObservePreferences();
  }

  void _toggleScoreSort() {
    if (!_startObserveReflowInputCooldown()) {
      return;
    }
    setState(() {
      _scoreSort = switch (_scoreSort) {
        _ObserveScoreSort.highToLow => _ObserveScoreSort.lowToHigh,
        _ObserveScoreSort.lowToHigh => _ObserveScoreSort.highToLow,
      };
    });
    _persistObservePreferences();
  }

  void _selectSortMode(_ObserveSortMode sortMode) {
    if (sortMode == _ObserveSortMode.score &&
        !widget.workspaceController.workspace.assets.any(
          (asset) => asset.photo.appraisalScore != null,
        )) {
      return;
    }
    if (_sortMode == sortMode) {
      if (sortMode == _ObserveSortMode.time) {
        _toggleTimeSort();
      } else {
        _toggleScoreSort();
      }
      return;
    }
    if (!_startObserveReflowInputCooldown()) {
      return;
    }
    setState(() {
      _sortMode = sortMode;
    });
    _persistObservePreferences();
  }

  void _selectFilterMode(_ObserveFilterMode filterMode) {
    if (filterMode == _ObserveFilterMode.cherished &&
        !widget.workspaceController.workspace.assets.any(
          (asset) => asset.photo.isCherished,
        )) {
      return;
    }
    if (_filterMode == filterMode) {
      return;
    }
    if (!_startObserveReflowInputCooldown()) {
      return;
    }
    setState(() {
      _filterMode = filterMode;
    });
    _persistObservePreferences();
  }

  void _cycleFilterMode() {
    final hasCherishedAssets = widget.workspaceController.workspace.assets.any(
      (asset) => asset.photo.isCherished,
    );
    if (!hasCherishedAssets) {
      return;
    }
    final nextMode =
        _effectiveFilterMode(hasCherishedAssets) == _ObserveFilterMode.all
        ? _ObserveFilterMode.cherished
        : _ObserveFilterMode.all;
    _selectFilterMode(nextMode);
  }

  void _toggleObserveOptions() {
    setState(() {
      _observeOptionsOpen = !_observeOptionsOpen;
    });
  }

  void _closeObserveOptions() {
    if (!_observeOptionsOpen) {
      return;
    }
    setState(() {
      _observeOptionsOpen = false;
    });
  }

  void _setDensity(ObserveWallDensity density) {
    if (_density == density) {
      return;
    }
    if (!_startObserveReflowInputCooldown()) {
      return;
    }
    setState(() {
      _density = density;
    });
    _persistObservePreferences();
  }

  bool _startObserveReflowInputCooldown() {
    if (_observeReflowInputTimer?.isActive ?? false) {
      return false;
    }
    widget.workspaceController.deferBackgroundPreviewCaching();
    // ponytail: one shared reflow cooldown; queue the last tap only if UX needs it.
    _observeReflowInputTimer = Timer(_observeReflowInputCooldown, () {});
    return true;
  }

  void _startEditingName(String currentName) {
    setState(() {
      _isEditingName = true;
      _showNameRequiredHint = false;
      _nameController.text = currentName;
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocusNode.requestFocus();
      }
    });
  }

  void _handleNameChanged(String value) {
    if (!_isEditingName) {
      return;
    }
    setState(() {
      _showNameRequiredHint = false;
    });
  }

  void _cancelNameEdit() {
    setState(() {
      _isEditingName = false;
      _showNameRequiredHint = false;
      _nameController.clear();
    });
  }

  void _saveName() {
    final nextName = _nameController.text.trim();
    if (nextName.isEmpty) {
      setState(() {
        _showNameRequiredHint = true;
      });
      _nameFocusNode.requestFocus();
      return;
    }

    widget.workspaceController.renameWorkspace(nextName);
    setState(() {
      _isEditingName = false;
      _showNameRequiredHint = false;
      _nameController.clear();
    });
  }

  Future<void> _confirmRemoveSelectedPhotos() async {
    final palette = NoemaPalette.fromTone(
      _appearanceController.resolveTone(context),
    );
    final ids = Set<String>.from(_selectedPhotoIds);
    final choice = await showNoemaRemoveAssetsDialog(
      context: context,
      palette: palette,
      canDeleteSystemPhoto: widget.workspaceController
          .canDeleteSystemMediaForAssetIds(ids),
    );

    if (choice == null || !mounted) {
      return;
    }

    final removed = await removeNoemaAssetsWithChoice(
      context: context,
      workspaceController: widget.workspaceController,
      photoIds: ids,
      choice: choice,
    );
    if (removed && mounted) {
      setState(() {
        _selectedPhotoIds.clear();
      });
    }
  }

  void _scheduleMissingAssetNotice() {
    if (_missingNoticeScheduled || _missingNoticeDialogOpen) {
      return;
    }
    final indexes = widget.workspaceController.unnotifiedMissingAssetIndexes;
    if (indexes.isEmpty) {
      return;
    }

    _missingNoticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _missingNoticeScheduled = false;
      if (!mounted || _missingNoticeDialogOpen) {
        return;
      }
      final freshIndexes =
          widget.workspaceController.unnotifiedMissingAssetIndexes;
      if (freshIndexes.isEmpty) {
        return;
      }
      _showMissingAssetNotice(freshIndexes, markNotified: true);
    });
  }

  Future<void> _showMissingAssetNotice(
    List<MissingAssetIndex> indexes, {
    bool markNotified = false,
  }) async {
    if (indexes.isEmpty || _missingNoticeDialogOpen) {
      return;
    }

    final photoIds = {for (final index in indexes) index.photoId};
    if (markNotified) {
      widget.workspaceController.markMissingAssetIndexesNotified(photoIds);
    }

    _missingNoticeDialogOpen = true;
    final palette = NoemaPalette.fromTone(
      _appearanceController.resolveTone(context),
    );
    final clearIndexes = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (context) => _ObserveMissingAssetsDialog(
        palette: palette,
        indexes: indexes,
        onClose: () => Navigator.of(context).pop(false),
        onClear: () => Navigator.of(context).pop(true),
      ),
    );
    _missingNoticeDialogOpen = false;
    if (!mounted) {
      return;
    }
    if (clearIndexes == true) {
      widget.workspaceController.clearMissingAssetIndexes(photoIds);
    }
  }

  void _startPhotoSelection(ReviewAsset asset) {
    setState(() {
      _selectedPhotoIds.add(asset.photo.id);
    });
  }

  void _togglePhotoSelection(ReviewAsset asset) {
    setState(() {
      if (_selectedPhotoIds.contains(asset.photo.id)) {
        _selectedPhotoIds.remove(asset.photo.id);
      } else {
        _selectedPhotoIds.add(asset.photo.id);
      }
    });
  }

  void _clearPhotoSelection() {
    setState(() {
      _selectedPhotoIds.clear();
    });
  }

  Future<void> _openPhotoPreview(ReviewAsset asset) async {
    if (_openingPreviewPhotoId != null) {
      return;
    }
    final generation = _openingPreviewGeneration + 1;
    _openingPreviewGeneration = generation;
    setState(() {
      _openingPreviewPhotoId = asset.photo.id;
    });
    await _precachePhotoViewerFirstFrame(
      asset,
    ).timeout(_observeViewerPrecacheMaxWait, onTimeout: () {});
    if (!mounted || generation != _openingPreviewGeneration) {
      return;
    }
    context.push(
      observePhotoRoute(photoId: asset.photo.id, sort: _timeSort.name),
    );
    if (mounted) {
      setState(() {
        _openingPreviewPhotoId = null;
      });
    }
  }

  void _openAppreciate({
    required bool hasAppraisalScores,
    String? initialPhotoId,
  }) {
    context.push(
      observeAppreciateRoute(
        initialPhotoId: initialPhotoId,
        sortMode: _effectiveSortMode(hasAppraisalScores).name,
        timeSort: _timeSort.name,
        scoreSort: _scoreSort.name,
      ),
    );
  }

  void _handleAppreciateDragUpdate(Offset? globalPosition) {
    final targetPhotoId =
        globalPosition == null ||
            _appreciateDragInBottomCancelZone(globalPosition)
        ? null
        : _photoWallKey.currentState?.photoIdForGlobalPosition(globalPosition);
    if (_appreciateDragTargetPhotoId == targetPhotoId) {
      return;
    }
    setState(() {
      _appreciateDragTargetPhotoId = targetPhotoId;
    });
  }

  bool _appreciateDragInBottomCancelZone(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final appBottom = renderObject
        .localToGlobal(Offset(0, renderObject.size.height))
        .dy;
    return globalPosition.dy >=
        appBottom -
            _observeExperienceDockBottom -
            _observeExperienceIntentDockHeight -
            _observeAppreciateDockCancelTopPadding;
  }

  void _finishAppreciateDrag({required bool hasAppraisalScores}) {
    final targetPhotoId = _appreciateDragTargetPhotoId;
    _clearAppreciateDragTarget();
    if (targetPhotoId == null) {
      return;
    }
    _openAppreciate(
      hasAppraisalScores: hasAppraisalScores,
      initialPhotoId: targetPhotoId,
    );
  }

  void _clearAppreciateDragTarget() {
    if (_appreciateDragTargetPhotoId == null || !mounted) {
      return;
    }
    setState(() {
      _appreciateDragTargetPhotoId = null;
    });
  }

  Future<void> _precachePhotoViewerFirstFrame(ReviewAsset asset) async {
    final provider = photoViewerPrecacheImageProvider(context, asset);
    if (provider == null) {
      return;
    }
    try {
      await precacheImage(provider, context);
    } catch (_) {
      // The viewer still has its normal recover/error path; precache is only a
      // short first-frame warmup before navigation.
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _scaleDelta = 1;
    _scaleFocalY = details.localFocalPoint.dy;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    _scaleDelta = details.scale;
    _scaleFocalY = details.localFocalPoint.dy;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_scaleDelta > 1.08) {
      _setDensity(_largerDensity(_density));
    } else if (_scaleDelta < 0.92) {
      _setDensity(_smallerDensity(_density));
    }

    if (_wallScrollController.hasClients && _scaleFocalY > 0) {
      final currentOffset = _wallScrollController.offset;
      final target = math.max(0.0, currentOffset + (_scaleDelta - 1) * 42);
      _wallScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: _observeEase,
      );
    }
  }
}

class _ObserveTopBar extends StatelessWidget {
  const _ObserveTopBar({required this.palette, required this.onBack});

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
            child: _ObserveIconButton(
              visualKey: const ValueKey('observe-back-button-visual'),
              palette: palette,
              tooltip: strings.back,
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: onBack,
            ),
          ),
          Center(
            child: NoemaWordmark(color: palette.ink, text: strings.appName),
          ),
        ],
      ),
    );
  }
}

class _ObserveHeader extends StatelessWidget {
  const _ObserveHeader({
    required this.palette,
    required this.spaceName,
    required this.photoCount,
    required this.sortMode,
    required this.timeSort,
    required this.scoreSort,
    required this.filterMode,
    required this.density,
    required this.nameController,
    required this.nameFocusNode,
    required this.isEditingName,
    required this.showNameRequiredHint,
    required this.selectingPhotos,
    required this.hasMissingAssets,
    required this.optionsOpen,
    required this.onStartEditingName,
    required this.onNameChanged,
    required this.onSaveName,
    required this.onCancelNameEdit,
    required this.onClearPhotoSelection,
    required this.onRemoveSelectedPhotos,
    required this.onToggleOptions,
    required this.onAddPhotos,
    required this.onShowMissingAssets,
  });

  final NoemaPalette palette;
  final String spaceName;
  final int photoCount;
  final _ObserveSortMode sortMode;
  final _ObserveTimeSort timeSort;
  final _ObserveScoreSort scoreSort;
  final _ObserveFilterMode filterMode;
  final ObserveWallDensity density;
  final TextEditingController nameController;
  final FocusNode nameFocusNode;
  final bool isEditingName;
  final bool showNameRequiredHint;
  final bool selectingPhotos;
  final bool hasMissingAssets;
  final bool optionsOpen;
  final VoidCallback onStartEditingName;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onSaveName;
  final VoidCallback onCancelNameEdit;
  final VoidCallback onClearPhotoSelection;
  final VoidCallback onRemoveSelectedPhotos;
  final VoidCallback onToggleOptions;
  final VoidCallback onAddPhotos;
  final VoidCallback onShowMissingAssets;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: _observeEase,
          alignment: Alignment.topLeft,
          child: isEditingName
              ? _EditableSpaceName(
                  palette: palette,
                  controller: nameController,
                  focusNode: nameFocusNode,
                  showNameRequiredHint: showNameRequiredHint,
                  onChanged: onNameChanged,
                  onSave: onSaveName,
                  onCancel: onCancelNameEdit,
                )
              : _SpaceNameTitle(
                  palette: palette,
                  name: spaceName,
                  onEdit: onStartEditingName,
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: selectingPhotos
                ? _ObserveSelectionActionStrip(
                    key: const ValueKey('observe-selection-actions'),
                    palette: palette,
                    onClearSelection: onClearPhotoSelection,
                    onRemoveSelected: onRemoveSelectedPhotos,
                  )
                : Row(
                    key: const ValueKey('observe-tool-row'),
                    children: [
                      Text(
                        strings.observePhotoCount(photoCount),
                        style: TextStyle(
                          color: palette.muted,
                          fontFamily: _fontForText(
                            strings.observePhotoCount(photoCount),
                          ),
                          fontSize: 13,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: hasMissingAssets
                            ? Padding(
                                key: const ValueKey(
                                  'observe-missing-assets-warning',
                                ),
                                padding: const EdgeInsets.only(left: 6),
                                child: _HeaderMiniIconButton(
                                  palette: palette,
                                  tooltip: strings.observeMissingAssetsTooltip,
                                  icon: Icons.warning_amber_rounded,
                                  onPressed: onShowMissingAssets,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      _ObserveIconButton(
                        palette: palette,
                        tooltip: strings.importAddPhotos,
                        icon: Icons.add_photo_alternate_outlined,
                        onPressed: onAddPhotos,
                      ),
                      const SizedBox(width: 2),
                      _ObserveIconButton(
                        palette: palette,
                        tooltip: _observeOptionsTooltip(
                          strings,
                          sortMode: sortMode,
                          timeSort: timeSort,
                          scoreSort: scoreSort,
                          filterMode: filterMode,
                          density: density,
                        ),
                        icon: optionsOpen
                            ? Icons.tune_rounded
                            : Icons.tune_outlined,
                        onPressed: onToggleOptions,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ObserveOptionsSheet extends StatelessWidget {
  const _ObserveOptionsSheet({
    required this.palette,
    required this.open,
    required this.sortMode,
    required this.timeSort,
    required this.scoreSort,
    required this.filterMode,
    required this.density,
    required this.hasAppraisalScores,
    required this.hasCherishedAssets,
    required this.onSortModeSelected,
    required this.onCycleFilterMode,
    required this.onCycleDensity,
  });

  final NoemaPalette palette;
  final bool open;
  final _ObserveSortMode sortMode;
  final _ObserveTimeSort timeSort;
  final _ObserveScoreSort scoreSort;
  final _ObserveFilterMode filterMode;
  final ObserveWallDensity density;
  final bool hasAppraisalScores;
  final bool hasCherishedAssets;
  final ValueChanged<_ObserveSortMode> onSortModeSelected;
  final VoidCallback onCycleFilterMode;
  final VoidCallback onCycleDensity;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final groupLabelStyle = TextStyle(
      color: palette.muted.withValues(alpha: 0.82),
      fontFamily: 'LXGWWenKaiGB',
      fontSize: 11,
      height: 1,
      letterSpacing: 0,
    );
    return Visibility(
      visible: open,
      maintainState: true,
      maintainAnimation: true,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: Duration(milliseconds: open ? 160 : 120),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: open ? 1 : 0.985,
            alignment: const Alignment(0.78, -1),
            duration: Duration(milliseconds: open ? 160 : 120),
            curve: Curves.easeOut,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  key: const ValueKey('observe-options-sheet'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.sheet,
                    border: Border.all(color: palette.glassBorder),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 42,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ObserveOptionGroup(
                        label: strings.isZh ? '排序' : 'Sort',
                        labelStyle: groupLabelStyle,
                        children: [
                          _ObserveOptionPill(
                            palette: palette,
                            active: sortMode == _ObserveSortMode.time,
                            tooltip: _timeSortLabel(strings, timeSort),
                            onPressed: () =>
                                onSortModeSelected(_ObserveSortMode.time),
                            child: _TimeSortIcon(
                              palette: palette,
                              ascending:
                                  timeSort == _ObserveTimeSort.oldestFirst,
                            ),
                          ),
                          if (hasAppraisalScores) ...[
                            const SizedBox(width: 4),
                            _ObserveOptionPill(
                              palette: palette,
                              active: sortMode == _ObserveSortMode.score,
                              tooltip: _scoreSortLabel(strings, scoreSort),
                              onPressed: () =>
                                  onSortModeSelected(_ObserveSortMode.score),
                              child: NoemaScoreSortIcon(
                                palette: palette,
                                ascending:
                                    scoreSort == _ObserveScoreSort.lowToHigh,
                              ),
                            ),
                          ],
                        ],
                      ),
                      _ObserveOptionDivider(palette: palette),
                      _ObserveOptionGroup(
                        label: strings.isZh ? '筛选' : 'Filter',
                        labelStyle: groupLabelStyle,
                        children: [
                          _ObserveOptionPill(
                            palette: palette,
                            active: true,
                            enabled: hasCherishedAssets,
                            tooltip: hasCherishedAssets
                                ? _filterModeLabel(strings, filterMode)
                                : (strings.isZh
                                      ? '暂无珍藏照片'
                                      : 'No cherished photos'),
                            onPressed: onCycleFilterMode,
                            child: Icon(
                              filterMode == _ObserveFilterMode.cherished
                                  ? Icons.favorite_rounded
                                  : Icons.photo_library_outlined,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      _ObserveOptionDivider(palette: palette),
                      _ObserveOptionGroup(
                        label: strings.isZh ? '墙面' : 'Wall',
                        labelStyle: groupLabelStyle,
                        children: [
                          _ObserveOptionPill(
                            palette: palette,
                            active: true,
                            tooltip: strings.observeDensityTooltip(
                              _densityLabel(strings, density),
                            ),
                            onPressed: onCycleDensity,
                            child: Icon(_densityIcon(density), size: 20),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ObserveOptionGroup extends StatelessWidget {
  const _ObserveOptionGroup({
    required this.label,
    required this.labelStyle,
    required this.children,
  });

  final String label;
  final TextStyle labelStyle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 9),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

class _ObserveOptionDivider extends StatelessWidget {
  const _ObserveOptionDivider({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: palette.glassBorder.withValues(alpha: 0.72),
    );
  }
}

class _ObserveOptionPill extends StatelessWidget {
  const _ObserveOptionPill({
    required this.palette,
    required this.active,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.enabled = true,
  });

  final NoemaPalette palette;
  final bool active;
  final bool enabled;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (active ? palette.ink : palette.muted)
        : palette.muted.withValues(alpha: 0.42);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 42,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active && enabled
                  ? palette.glass.withValues(alpha: 0.9)
                  : Colors.transparent,
              border: Border.all(
                color: active && enabled
                    ? palette.glassBorder
                    : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: IconTheme(
              data: IconThemeData(color: color, size: 20),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceNameTitle extends StatelessWidget {
  const _SpaceNameTitle({
    required this.palette,
    required this.name,
    required this.onEdit,
  });

  final NoemaPalette palette;
  final String name;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontFamily: 'LXGWWenKaiGB',
                fontSize: 30,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
          ),
          _HeaderMiniIconButton(
            palette: palette,
            tooltip: strings.observeEditName,
            icon: Icons.edit_rounded,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _EditableSpaceName extends StatelessWidget {
  const _EditableSpaceName({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.showNameRequiredHint,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  final NoemaPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showNameRequiredHint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final count = controller.text.runes.length;

    return SizedBox(
      height: 58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('observe-name-field'),
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    maxLength: 10,
                    inputFormatters: [LengthLimitingTextInputFormatter(10)],
                    cursorColor: palette.ink,
                    style: TextStyle(
                      color: palette.ink,
                      fontFamily: 'LXGWWenKaiGB',
                      fontSize: 30,
                      height: 1.05,
                      letterSpacing: 0,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: onChanged,
                    onSubmitted: (_) => onSave(),
                  ),
                ),
                const SizedBox(width: 2),
                _HeaderMiniIconButton(
                  palette: palette,
                  tooltip: strings.observeSaveName,
                  icon: Icons.check_rounded,
                  onPressed: onSave,
                ),
                _HeaderMiniIconButton(
                  palette: palette,
                  tooltip: strings.observeCancelNameEdit,
                  icon: Icons.close_rounded,
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 18,
            child: Row(
              children: [
                Text(
                  '$count/10',
                  style: TextStyle(
                    color: palette.muted.withValues(alpha: 0.78),
                    fontFamily: 'NoemaDigits',
                    fontSize: 11,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedOpacity(
                  opacity: showNameRequiredHint ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    strings.nameRequiredTitle,
                    style: TextStyle(
                      color: palette.ink.withValues(alpha: 0.72),
                      fontFamily: 'LXGWWenKaiGB',
                      fontSize: 12,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMiniIconButton extends StatelessWidget {
  const _HeaderMiniIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      textStyle: _tooltipTextStyle(palette, tooltip),
      decoration: _tooltipDecoration(palette),
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 30,
            height: 34,
            child: Center(
              child: Icon(
                icon,
                size: 17,
                color: palette.ink.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ObserveSelectionActionStrip extends StatelessWidget {
  const _ObserveSelectionActionStrip({
    super.key,
    required this.palette,
    required this.onClearSelection,
    required this.onRemoveSelected,
  });

  final NoemaPalette palette;
  final VoidCallback onClearSelection;
  final VoidCallback onRemoveSelected;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ObserveSelectionIconButton(
          palette: palette,
          tooltip: strings.cancel,
          icon: Icons.close_rounded,
          onPressed: onClearSelection,
        ),
        _ObserveSelectionIconButton(
          palette: palette,
          tooltip: strings.remove,
          icon: Icons.delete_outline_rounded,
          danger: true,
          onPressed: onRemoveSelected,
        ),
      ],
    );
  }
}

class _ObserveSelectionIconButton extends StatelessWidget {
  const _ObserveSelectionIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final NoemaPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? (palette.tone == NoemaTone.dark
              ? const Color(0xFFE1A39B)
              : const Color(0xFF8D3028))
        : palette.ink;

    return Tooltip(
      message: tooltip,
      textStyle: _tooltipTextStyle(palette, tooltip),
      decoration: _tooltipDecoration(palette),
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: NoemaSceneMetrics.iconTapSize,
            height: NoemaSceneMetrics.iconTapSize,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.glass.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: NoemaSceneMetrics.iconVisualSize,
                  height: NoemaSceneMetrics.iconVisualSize,
                  child: Icon(icon, color: color, size: 25),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ObservePhotoWall extends StatefulWidget {
  const _ObservePhotoWall({
    super.key,
    required this.palette,
    required this.assets,
    required this.density,
    required this.showScoreBadges,
    required this.selectedIds,
    required this.openingPhotoId,
    required this.appreciateDragTargetPhotoId,
    required this.scrollController,
    required this.onInteractionBusy,
    required this.onOpenPreview,
    required this.onStartSelection,
    required this.onToggleSelection,
    required this.onMetadataLoaded,
    required this.onThumbnailLoaded,
    required this.onMissingAsset,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
  });

  final NoemaPalette palette;
  final List<ReviewAsset> assets;
  final ObserveWallDensity density;
  final bool showScoreBadges;
  final Set<String> selectedIds;
  final String? openingPhotoId;
  final String? appreciateDragTargetPhotoId;
  final ScrollController scrollController;
  final VoidCallback onInteractionBusy;
  final ValueChanged<ReviewAsset> onOpenPreview;
  final ValueChanged<ReviewAsset> onStartSelection;
  final ValueChanged<ReviewAsset> onToggleSelection;
  final void Function(String photoId, SelectedGalleryAsset metadata)
  onMetadataLoaded;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;
  final ValueChanged<String> onMissingAsset;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;

  @override
  State<_ObservePhotoWall> createState() => _ObservePhotoWallState();
}

class _ObservePhotoWallState extends State<_ObservePhotoWall> {
  double _scrollOffset = 0;
  Map<String, ObservePhotoWallRect> _lastRectById = const {};
  Map<String, ObservePhotoWallRect>? _reflowFromRectById;
  Timer? _reflowSettleTimer;
  double _lastViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _ObservePhotoWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
      _scrollOffset = widget.scrollController.hasClients
          ? widget.scrollController.offset
          : 0;
    }
    if (_wallReflowInputsChanged(oldWidget) && _lastRectById.isNotEmpty) {
      _beginReflowAnimationFromLastLayout();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    _reflowSettleTimer?.cancel();
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.scrollController.hasClients) {
      return;
    }
    widget.onInteractionBusy();
    final nextOffset = widget.scrollController.offset;
    // ponytail: coarse window updates reduce wall rebuilds; lower this if fast
    // fling reveals late tiles on larger libraries.
    if ((nextOffset - _scrollOffset).abs() <
        _observeWallScrollUpdateThreshold) {
      return;
    }
    setState(() {
      _scrollOffset = nextOffset;
    });
  }

  bool _wallReflowInputsChanged(_ObservePhotoWall oldWidget) {
    if (oldWidget.density != widget.density ||
        oldWidget.assets.length != widget.assets.length) {
      return true;
    }
    for (var index = 0; index < widget.assets.length; index += 1) {
      final oldAsset = oldWidget.assets[index];
      final asset = widget.assets[index];
      if (oldAsset.photo.id != asset.photo.id ||
          _assetAspectRatio(oldAsset) != _assetAspectRatio(asset)) {
        return true;
      }
    }
    return false;
  }

  String? photoIdForGlobalPosition(Offset? globalPosition) {
    if (globalPosition == null || !mounted) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final local = renderObject.globalToLocal(globalPosition);
    if (local.dx < 0 ||
        local.dx > renderObject.size.width ||
        local.dy < 0 ||
        local.dy > renderObject.size.height) {
      return null;
    }
    // ponytail: rendering can use throttled offset; hit testing needs the live
    // value or small scrolls will target the photo above the finger.
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : _scrollOffset;
    final contentPosition = Offset(
      local.dx,
      local.dy + scrollOffset - _observeWallTopPadding,
    );
    final visibleTop = math.max(0.0, scrollOffset - _observeWallTopPadding - 4);
    final visibleBottom = visibleTop + _lastViewportHeight;
    final visibleGutter =
        _lastViewportHeight * _observeWallVisibleGutterFactor +
        _observeWallVisibleGutterBase;

    for (final rect in _lastRectById.values) {
      if (!_rectNearViewport(
        rect,
        visibleTop: visibleTop,
        visibleBottom: visibleBottom,
        gutter: visibleGutter,
      )) {
        continue;
      }
      final hitRect = Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        rect.height,
      );
      if (hitRect.contains(contentPosition)) {
        return rect.id;
      }
    }
    return null;
  }

  void _beginReflowAnimationFromLastLayout() {
    _reflowFromRectById = Map<String, ObservePhotoWallRect>.from(_lastRectById);
    _reflowSettleTimer?.cancel();
    _reflowSettleTimer = Timer(
      _observeWallReflowDuration + _observeWallReflowSettleGrace,
      () {
        if (!mounted) {
          return;
        }
        setState(() {
          _reflowFromRectById = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wallWidth = constraints.maxWidth;
        _lastViewportHeight = constraints.maxHeight;
        final paintWidth = wallWidth + _observeWallShadowGutter * 2;
        final items = [
          for (final asset in widget.assets)
            ObservePhotoWallItem(
              id: asset.photo.id,
              aspectRatio: _assetAspectRatio(asset),
            ),
        ];
        final layout = buildObservePhotoWallLayout(
          items: items,
          width: wallWidth,
          density: widget.density,
        );
        final rectById = {for (final rect in layout.rects) rect.id: rect};
        final reflowFromRectById = _reflowFromRectById;
        final visibleTop = math.max(
          0.0,
          _scrollOffset - _observeWallTopPadding - 4,
        );
        final visibleBottom = visibleTop + constraints.maxHeight;
        final visibleGutter =
            constraints.maxHeight * _observeWallVisibleGutterFactor +
            _observeWallVisibleGutterBase;

        final wall = GestureDetector(
          onScaleStart: widget.onScaleStart,
          onScaleUpdate: widget.onScaleUpdate,
          onScaleEnd: widget.onScaleEnd,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: paintWidth,
            maxWidth: paintWidth,
            child: SizedBox(
              width: paintWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      key: const ValueKey('observe-photo-wall-scroll'),
                      controller: widget.scrollController,
                      clipBehavior: Clip.hardEdge,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(
                        top: _observeWallTopPadding,
                        bottom: _observeWallBottomPadding,
                      ),
                      child: SizedBox(
                        key: const ValueKey('observe-photo-wall'),
                        width: paintWidth,
                        height: layout.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (
                              var index = 0;
                              index < widget.assets.length;
                              index++
                            )
                              if (rectById[widget.assets[index].photo.id]
                                  case final rect?
                                  when _shouldRenderRect(
                                    rect,
                                    previousRect: reflowFromRectById?[rect.id],
                                    visibleTop: visibleTop,
                                    visibleBottom: visibleBottom,
                                    gutter: visibleGutter,
                                  ))
                                _ObservePositionedPhotoTile(
                                  key: ValueKey('observe-position-${rect.id}'),
                                  rect: rect,
                                  previousRect: reflowFromRectById?[rect.id],
                                  child: _ObservePhotoTile(
                                    key: ValueKey('observe-photo-${rect.id}'),
                                    palette: widget.palette,
                                    asset: widget.assets[index],
                                    showScoreBadge: widget.showScoreBadges,
                                    index: index,
                                    displayWidth: rect.width,
                                    displayHeight: rect.height,
                                    selected: widget.selectedIds.contains(
                                      widget.assets[index].photo.id,
                                    ),
                                    opening:
                                        widget.openingPhotoId ==
                                        widget.assets[index].photo.id,
                                    appreciateTarget:
                                        widget.appreciateDragTargetPhotoId ==
                                        widget.assets[index].photo.id,
                                    selecting: widget.selectedIds.isNotEmpty,
                                    onTap: () {
                                      if (widget.selectedIds.isNotEmpty) {
                                        widget.onToggleSelection(
                                          widget.assets[index],
                                        );
                                      } else {
                                        widget.onOpenPreview(
                                          widget.assets[index],
                                        );
                                      }
                                    },
                                    onLongPress: () => widget.onStartSelection(
                                      widget.assets[index],
                                    ),
                                    onMetadataLoaded: widget.onMetadataLoaded,
                                    onThumbnailLoaded: widget.onThumbnailLoaded,
                                    onMissingAsset: widget.onMissingAsset,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  NoemaScrollEdgeFade(
                    palette: widget.palette,
                    top: true,
                    height: _observeWallTopFadeHeight,
                  ),
                  NoemaScrollEdgeFade(
                    palette: widget.palette,
                    top: false,
                    height: _observeWallBottomFadeHeight,
                  ),
                ],
              ),
            ),
          ),
        );
        _lastRectById = rectById;
        return wall;
      },
    );
  }

  bool _shouldRenderRect(
    ObservePhotoWallRect rect, {
    required ObservePhotoWallRect? previousRect,
    required double visibleTop,
    required double visibleBottom,
    required double gutter,
  }) {
    return _rectNearViewport(
          rect,
          visibleTop: visibleTop,
          visibleBottom: visibleBottom,
          gutter: gutter,
        ) ||
        previousRect != null &&
            _rectNearViewport(
              previousRect,
              visibleTop: visibleTop,
              visibleBottom: visibleBottom,
              gutter: gutter,
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

class _ObservePositionedPhotoTile extends StatelessWidget {
  const _ObservePositionedPhotoTile({
    required super.key,
    required this.rect,
    required this.previousRect,
    required this.child,
  });

  final ObservePhotoWallRect rect;
  final ObservePhotoWallRect? previousRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final target = _observePositionRect(rect);
    final previous = previousRect;
    final begin = previous == null ? target : _observePositionRect(previous);
    final shouldAnimate = begin != target;

    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(begin: begin, end: target),
      duration: shouldAnimate ? _observeWallReflowDuration : Duration.zero,
      curve: _observeEase,
      child: child,
      builder: (context, value, child) {
        final effectiveRect = value ?? target;
        return Positioned(
          left: effectiveRect.left,
          top: effectiveRect.top,
          width: effectiveRect.width,
          height: effectiveRect.height,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

Rect _observePositionRect(ObservePhotoWallRect rect) {
  return Rect.fromLTWH(
    rect.left + _observeWallShadowGutter,
    rect.top,
    rect.width,
    rect.height,
  );
}

class _ObservePhotoTile extends StatefulWidget {
  const _ObservePhotoTile({
    super.key,
    required this.palette,
    required this.asset,
    required this.showScoreBadge,
    required this.index,
    required this.displayWidth,
    required this.displayHeight,
    required this.selected,
    required this.opening,
    required this.appreciateTarget,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMetadataLoaded,
    required this.onThumbnailLoaded,
    required this.onMissingAsset,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final bool showScoreBadge;
  final int index;
  final double displayWidth;
  final double displayHeight;
  final bool selected;
  final bool opening;
  final bool appreciateTarget;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(String photoId, SelectedGalleryAsset metadata)
  onMetadataLoaded;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;
  final ValueChanged<String> onMissingAsset;

  @override
  State<_ObservePhotoTile> createState() => _ObservePhotoTileState();
}

class _ObservePhotoTileState extends State<_ObservePhotoTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(9);
    final emphasized =
        widget.selected ||
        widget.opening ||
        widget.appreciateTarget ||
        _pressed;
    final selectedBorder = widget.selected
        ? Border.all(color: widget.palette.ink, width: 1.6)
        : null;
    Widget tile = Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: widget.palette.photoFallback,
        borderRadius: borderRadius,
      ),
      foregroundDecoration: selectedBorder == null
          ? null
          : BoxDecoration(borderRadius: borderRadius, border: selectedBorder),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ObserveAssetImage(
            palette: widget.palette,
            asset: widget.asset,
            index: widget.index,
            displayWidth: widget.displayWidth,
            displayHeight: widget.displayHeight,
            onMetadataLoaded: widget.onMetadataLoaded,
            onThumbnailLoaded: widget.onThumbnailLoaded,
            onMissingAsset: widget.onMissingAsset,
          ),
          if (!widget.selecting &&
              widget.showScoreBadge &&
              widget.asset.photo.appraisalScore != null)
            Positioned(
              top: 6,
              left: 6,
              child: NoemaPhotoWallScoreBadge(
                palette: widget.palette,
                score: widget.asset.photo.appraisalScore!,
              ),
            ),
          if (!widget.selecting && widget.asset.photo.isCherished)
            Positioned(
              top: 4,
              right: 4,
              child: NoemaPhotoWallHeartBadge(
                key: ValueKey('observe-photo-heart-${widget.asset.photo.id}'),
                palette: widget.palette,
                cherished: true,
              ),
            ),
          if (widget.selecting)
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              color: widget.selected
                  ? Colors.black.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.38),
            ),
          if (widget.opening)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color: Colors.black.withValues(alpha: 0.22),
            ),
          if (widget.appreciateTarget)
            AnimatedContainer(
              key: ValueKey(
                'observe-appreciate-target-${widget.asset.photo.id}',
              ),
              duration: const Duration(milliseconds: 140),
              curve: _observeEase,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: widget.palette.ink.withValues(alpha: 0.62),
                  width: 1.4,
                ),
                color: widget.palette.ink.withValues(
                  alpha: widget.palette.tone == NoemaTone.dark ? 0.10 : 0.06,
                ),
              ),
            ),
          if (widget.selected)
            Positioned(
              top: 5,
              right: 5,
              child: Icon(
                Icons.check_circle_rounded,
                color: widget.palette.ink,
                size: 19,
              ),
            ),
        ],
      ),
    );
    if (emphasized) {
      tile = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: widget.palette.cardShadow.withValues(alpha: 0.45),
              blurRadius: widget.palette.tone == NoemaTone.dark ? 14 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: tile,
      );
    }

    return Semantics(
      image: true,
      label: widget.asset.displayName,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          scale: widget.selected
              ? 0.955
              : widget.appreciateTarget
              ? 1.018
              : (widget.opening || _pressed ? 0.985 : 1),
          child: RepaintBoundary(child: tile),
        ),
      ),
    );
  }
}

class _ObserveAssetImage extends StatefulWidget {
  const _ObserveAssetImage({
    required this.palette,
    required this.asset,
    required this.index,
    required this.displayWidth,
    required this.displayHeight,
    required this.onMetadataLoaded,
    required this.onThumbnailLoaded,
    required this.onMissingAsset,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final int index;
  final double displayWidth;
  final double displayHeight;
  final void Function(String photoId, SelectedGalleryAsset metadata)
  onMetadataLoaded;
  final void Function(String photoId, String thumbnailPath) onThumbnailLoaded;
  final ValueChanged<String> onMissingAsset;

  @override
  State<_ObserveAssetImage> createState() => _ObserveAssetImageState();
}

class _ObserveAssetImageState extends State<_ObserveAssetImage> {
  int _metadataGeneration = 0;
  int _thumbnailGeneration = 0;
  String? _metadataRequestUri;
  String? _metadataHydratedUri;
  String? _thumbnailRequestUri;

  @override
  void initState() {
    super.initState();
    _prepareVisibleMedia();
  }

  @override
  void didUpdateWidget(covariant _ObserveAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.photo.id != widget.asset.photo.id ||
        oldWidget.asset.photo.sourceUri != widget.asset.photo.sourceUri ||
        oldWidget.asset.photo.dimensionsEstimated !=
            widget.asset.photo.dimensionsEstimated ||
        oldWidget.asset.photo.exif != widget.asset.photo.exif ||
        oldWidget.asset.photo.thumbnailPath !=
            widget.asset.photo.thumbnailPath) {
      _prepareVisibleMedia();
    }
  }

  void _prepareVisibleMedia() {
    final sourceUri = widget.asset.photo.sourceUri;
    if (sourceUri == null || sourceUri.isEmpty) {
      return;
    }

    const mediaPicker = NoemaMediaPicker();
    if ((widget.asset.photo.dimensionsEstimated ||
            widget.asset.photo.exif == null ||
            widget.asset.photo.exif!.isEmpty) &&
        _metadataHydratedUri != sourceUri &&
        _metadataRequestUri != sourceUri) {
      _metadataRequestUri = sourceUri;
      final generation = ++_metadataGeneration;
      unawaited(_loadMetadata(mediaPicker, sourceUri, generation));
    }
    if (widget.asset.photo.thumbnailPath == null &&
        _thumbnailRequestUri != sourceUri) {
      _thumbnailRequestUri = sourceUri;
      final generation = ++_thumbnailGeneration;
      unawaited(_loadThumbnail(mediaPicker, sourceUri, generation));
    }
  }

  Future<void> _loadMetadata(
    NoemaMediaPicker mediaPicker,
    String sourceUri,
    int generation,
  ) async {
    SelectedGalleryAsset? metadata;
    try {
      metadata = await mediaPicker.loadMetadata(uri: sourceUri);
    } catch (_) {
      metadata = null;
    }
    if (mounted && generation == _metadataGeneration) {
      _metadataRequestUri = null;
      _metadataHydratedUri = sourceUri;
    }
    if (!mounted || generation != _metadataGeneration || metadata == null) {
      return;
    }
    widget.onMetadataLoaded(widget.asset.photo.id, metadata);
  }

  Future<void> _loadThumbnail(
    NoemaMediaPicker mediaPicker,
    String sourceUri,
    int generation,
  ) async {
    String? thumbnailPath;
    try {
      thumbnailPath = await mediaPicker.createThumbnail(
        uri: sourceUri,
        maxSize: _observeThumbnailMaxSize,
      );
    } catch (_) {
      thumbnailPath = null;
    }
    if (mounted && generation == _thumbnailGeneration) {
      _thumbnailRequestUri = null;
    }
    if (!mounted || generation != _thumbnailGeneration) {
      return;
    }
    if (thumbnailPath == null || thumbnailPath.isEmpty) {
      widget.onMissingAsset(widget.asset.photo.id);
      return;
    }
    widget.onThumbnailLoaded(widget.asset.photo.id, thumbnailPath);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asset.photo.availability == AssetAvailability.unavailable) {
      return _ObserveUnavailableTile(
        palette: widget.palette,
        name: widget.asset.displayName,
      );
    }

    final fallback = _ObserveUnavailableTile(
      palette: widget.palette,
      name: widget.asset.displayName,
    );
    return _toneImage(
      NoemaRecoverableReviewImage(
        asset: widget.asset,
        fit: BoxFit.cover,
        // ponytail: density changes should move tiles, not create new image
        // provider keys; the wall source is already a bounded thumbnail.
        cacheWidth: _observeThumbnailMaxSize,
        cacheHeight: _observeThumbnailMaxSize,
        recoverKind: NoemaRecoverableImageKind.thumbnail,
        recoverMaxSize: _observeThumbnailMaxSize,
        allowAlternatePathFallback: false,
        revealOnFirstAvailable: true,
        onRecovered: widget.onThumbnailLoaded,
        onRecoveryFailed: widget.onMissingAsset,
        filterQuality: FilterQuality.low,
        fallback: fallback,
      ),
    );
  }

  Widget _toneImage(Widget image) {
    // ponytail: per-tile ColorFiltered created dozens of saveLayers per scroll
    // frame; keep Observe wall photos native and retint only if brand tone wins
    // over frame pacing.
    return image;
  }
}

class _ObserveUnavailableTile extends StatelessWidget {
  const _ObserveUnavailableTile({required this.palette, required this.name});

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
          padding: const EdgeInsets.all(8),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.muted.withValues(alpha: 0.8),
              fontSize: 10,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ObserveEmptyState extends StatelessWidget {
  const _ObserveEmptyState({required this.palette, required this.onAddPhotos});

  final NoemaPalette palette;
  final VoidCallback onAddPhotos;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return Align(
      alignment: const Alignment(0, -0.12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.observeEmptyTitle,
            style: TextStyle(
              color: palette.muted,
              fontFamily: 'LXGWWenKaiGB',
              fontSize: 18,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          NoemaFloatingActionButton(
            palette: palette,
            tooltip: strings.importAddPhotos,
            onPressed: onAddPhotos,
            child: const Icon(Icons.add_photo_alternate_outlined, size: 30),
          ),
        ],
      ),
    );
  }
}

class _ObserveMissingAssetsDialog extends StatelessWidget {
  const _ObserveMissingAssetsDialog({
    required this.palette,
    required this.indexes,
    required this.onClose,
    required this.onClear,
  });

  final NoemaPalette palette;
  final List<MissingAssetIndex> indexes;
  final VoidCallback onClose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return NoemaDialogPanel(
      panelKey: const ValueKey('observe-missing-assets-dialog-panel'),
      palette: palette,
      title: strings.observeMissingAssetsTitle(indexes.length),
      onClose: onClose,
      closeTooltip: strings.close,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoemaDialogText(
            palette: palette,
            text: strings.observeMissingAssetsBody,
            color: palette.muted,
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.glass.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.glassBorder.withValues(alpha: 0.72),
                ),
              ),
              child: ListView.separated(
                key: const ValueKey('observe-missing-assets-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: indexes.length,
                separatorBuilder: (context, index) => Divider(
                  height: 12,
                  thickness: 1,
                  color: palette.glassBorder.withValues(alpha: 0.45),
                ),
                itemBuilder: (context, index) {
                  final displayName = indexes[index].displayName;
                  return Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.ink.withValues(alpha: 0.82),
                      fontFamily: _fontForText(displayName),
                      fontSize: 13,
                      height: 1.2,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: NoemaDialogButton(
              palette: palette,
              label: strings.observeClearMissingIndexes,
              onPressed: onClear,
              tone: NoemaDialogButtonTone.primary,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ExperienceDockEntry { cull, view, appraise }

enum _IntentEffectStyle { mist, ripple, seal }

enum _IntentTuneTarget {
  line,
  leftDash,
  rightDash,
  cullMark,
  appraiseMark,
  cullFrame,
  appraiseFrame,
  cullSign,
  centerSign,
  appraiseSign,
  centerLeftEnd,
  centerRightEnd,
  caption,
}

extension _IntentTuneTargetText on _IntentTuneTarget {
  String get keyName {
    return switch (this) {
      _IntentTuneTarget.line => 'line',
      _IntentTuneTarget.leftDash => 'leftDash',
      _IntentTuneTarget.rightDash => 'rightDash',
      _IntentTuneTarget.cullMark => 'cullMark',
      _IntentTuneTarget.appraiseMark => 'appraiseMark',
      _IntentTuneTarget.cullFrame => 'cullFrame',
      _IntentTuneTarget.appraiseFrame => 'appraiseFrame',
      _IntentTuneTarget.cullSign => 'cullSign',
      _IntentTuneTarget.centerSign => 'centerSign',
      _IntentTuneTarget.appraiseSign => 'appraiseSign',
      _IntentTuneTarget.centerLeftEnd => 'centerLeftEnd',
      _IntentTuneTarget.centerRightEnd => 'centerRightEnd',
      _IntentTuneTarget.caption => 'caption',
    };
  }
}

Offset _intentSealAlignedOffset(_IntentTuneTarget target) {
  return switch (target) {
    _IntentTuneTarget.line => Offset.zero,
    _IntentTuneTarget.leftDash => const Offset(2, -9),
    _IntentTuneTarget.rightDash => const Offset(-2, -9),
    _IntentTuneTarget.cullMark => Offset.zero,
    _IntentTuneTarget.appraiseMark => Offset.zero,
    _IntentTuneTarget.cullFrame => const Offset(-26, -9),
    _IntentTuneTarget.appraiseFrame => const Offset(26, -9),
    _IntentTuneTarget.cullSign => const Offset(2, -9),
    _IntentTuneTarget.centerSign => const Offset(0, -9),
    _IntentTuneTarget.appraiseSign => const Offset(-2, -9),
    _IntentTuneTarget.centerLeftEnd => Offset.zero,
    _IntentTuneTarget.centerRightEnd => Offset.zero,
    _IntentTuneTarget.caption => Offset.zero,
  };
}

class _ExperienceDock extends StatefulWidget {
  const _ExperienceDock({
    required this.palette,
    required this.variant,
    this.tuning = false,
    this.cullAvailable = true,
    this.appraiseAvailable = true,
    this.onCull,
    this.onView,
    this.onViewDragUpdate,
    this.onViewDragEnd,
    this.onViewDragCancel,
    this.onAppraise,
  });

  final NoemaPalette palette;
  final ExperienceDockVariant variant;
  final bool tuning;
  final bool cullAvailable;
  final bool appraiseAvailable;
  final VoidCallback? onCull;
  final VoidCallback? onView;
  final ValueChanged<Offset?>? onViewDragUpdate;
  final VoidCallback? onViewDragEnd;
  final VoidCallback? onViewDragCancel;
  final VoidCallback? onAppraise;

  @override
  State<_ExperienceDock> createState() => _ExperienceDockState();
}

class _ExperienceDockState extends State<_ExperienceDock> {
  Timer? _objectDetectionTimer;
  Timer? _quietRevealTimer;
  Timer? _intentTriggerTimer;

  bool _lensExpanded = false;
  bool _objectDetected = false;
  bool _quietRevealed = false;
  bool _intentDragging = false;
  bool _intentInitialSnapAnimating = false;
  bool _viewDragActive = false;
  bool _viewDragWasActive = false;
  double _intentValue = 0;
  double _intentLift = 0;
  Offset? _intentInitialSnapOrigin;
  Offset? _viewDragLocalPosition;
  _ExperienceDockEntry? _intentGestureStartEntry;
  _ExperienceDockEntry? _intentTriggeredEntry;
  _ExperienceDockEntry? _intentFeedbackEntry;
  final Map<_IntentTuneTarget, Offset> _intentTuneOffsets = {
    for (final target in _IntentTuneTarget.values) target: Offset.zero,
  };

  NoemaPalette get palette => widget.palette;
  ExperienceDockVariant get variant => widget.variant;

  @override
  void initState() {
    super.initState();
    _scheduleObjectDetection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _exportIntentTuneOffsets();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ExperienceDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) {
      _objectDetectionTimer?.cancel();
      _quietRevealTimer?.cancel();
      setState(() {
        _lensExpanded = false;
        _objectDetected = false;
        _quietRevealed = false;
        _intentDragging = false;
        _intentInitialSnapAnimating = false;
        _viewDragActive = false;
        _viewDragWasActive = false;
        _intentValue = 0;
        _intentLift = 0;
        _intentInitialSnapOrigin = null;
        _viewDragLocalPosition = null;
        _intentGestureStartEntry = null;
        _intentTriggeredEntry = null;
      });
      _scheduleObjectDetection();
    }
    if (!oldWidget.tuning && widget.tuning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _logIntentTuneOffsets();
        }
      });
    }
  }

  @override
  void dispose() {
    _objectDetectionTimer?.cancel();
    _quietRevealTimer?.cancel();
    _intentTriggerTimer?.cancel();
    super.dispose();
  }

  void _scheduleObjectDetection() {
    if (widget.variant != ExperienceDockVariant.object) {
      return;
    }
    _objectDetectionTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || widget.variant != ExperienceDockVariant.object) {
        return;
      }
      setState(() {
        _objectDetected = true;
      });
    });
  }

  void _toggleLens() {
    setState(() {
      _lensExpanded = !_lensExpanded;
    });
  }

  void _toggleQuietReveal() {
    _quietRevealTimer?.cancel();
    setState(() {
      _quietRevealed = !_quietRevealed;
    });
    if (_quietRevealed) {
      _quietRevealTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _quietRevealed = false;
        });
      });
    }
  }

  void _setIntentValue(double value) {
    setState(() {
      _intentInitialSnapAnimating = false;
      _viewDragWasActive = false;
      _intentValue = value.clamp(-1.0, 1.0).toDouble();
      _intentLift = 0;
      _intentInitialSnapOrigin = null;
      _intentFeedbackEntry = null;
    });
  }

  void _setIntentFromPosition({
    required Offset localPosition,
    required Offset globalPosition,
    required double maxWidth,
    required double trackWidth,
    required double axisY,
    bool start = false,
  }) {
    final centerX = maxWidth / 2;
    final halfTrack = math.max(1.0, trackWidth / 2);
    final nextValue = ((localPosition.dx - centerX) / halfTrack)
        .clamp(-1.0, 1.0)
        .toDouble();
    final nextLift = (axisY - localPosition.dy)
        .clamp(0.0, _intentVerticalFollowLimit)
        .toDouble();
    final nextEntry = _intentEntryForValue(nextValue);
    final nextGestureStartEntry = start
        ? nextEntry
        : (_intentGestureStartEntry ?? nextEntry);
    final nextViewDragActive =
        nextGestureStartEntry == _ExperienceDockEntry.view &&
        nextLift >= _intentViewDragLiftThreshold;
    final snapOrigin = start ? localPosition : _intentInitialSnapOrigin;
    final keepInitialSnap =
        !start &&
        _intentInitialSnapAnimating &&
        snapOrigin != null &&
        (localPosition - snapOrigin).distance <=
            _intentInitialSnapMoveTolerance &&
        !nextViewDragActive;
    if (keepInitialSnap) {
      return;
    }
    final shouldFeedback =
        !nextViewDragActive &&
        nextEntry != _ExperienceDockEntry.view &&
        nextEntry != _intentFeedbackEntry;
    final nextFeedbackEntry = nextEntry == _ExperienceDockEntry.view
        ? null
        : nextEntry;
    _intentTriggerTimer?.cancel();
    setState(() {
      _intentDragging = true;
      _intentInitialSnapAnimating = start || keepInitialSnap;
      _intentTriggeredEntry = null;
      _intentValue = nextValue;
      _intentLift = nextLift;
      _intentFeedbackEntry = nextFeedbackEntry;
      _viewDragActive = nextViewDragActive;
      _viewDragWasActive = _viewDragWasActive || nextViewDragActive;
      _intentInitialSnapOrigin = start || keepInitialSnap ? snapOrigin : null;
      _viewDragLocalPosition = nextViewDragActive ? localPosition : null;
      _intentGestureStartEntry = nextGestureStartEntry;
    });
    widget.onViewDragUpdate?.call(nextViewDragActive ? globalPosition : null);
    if (shouldFeedback) {
      _playIntentFeedback();
    }
  }

  void _resetIntent({bool cancelViewDrag = true}) {
    if (cancelViewDrag) {
      widget.onViewDragCancel?.call();
    }
    setState(() {
      _intentDragging = false;
      _intentInitialSnapAnimating = false;
      _viewDragActive = false;
      _viewDragWasActive = false;
      _intentValue = 0;
      _intentLift = 0;
      _intentInitialSnapOrigin = null;
      _viewDragLocalPosition = null;
      _intentGestureStartEntry = null;
      _intentFeedbackEntry = null;
    });
  }

  void _finishIntentGesture() {
    if (_viewDragActive) {
      widget.onViewDragEnd?.call();
      _resetIntent(cancelViewDrag: false);
      return;
    }
    if (_viewDragWasActive) {
      _resetIntent();
      return;
    }
    final startEntry = _intentGestureStartEntry;
    if (startEntry != _ExperienceDockEntry.view &&
        _intentLift >= _intentViewDragLiftThreshold) {
      _resetIntent();
      return;
    }
    final entry = _intentEntry;
    if (entry != _ExperienceDockEntry.view && _intentEntryAvailable(entry)) {
      _triggerIntent(entry);
      return;
    }
    if (entry == _ExperienceDockEntry.view &&
        startEntry == _ExperienceDockEntry.view &&
        _intentValue.abs() < 0.36) {
      _triggerIntent(_ExperienceDockEntry.view);
      return;
    }
    _resetIntent();
  }

  void _triggerIntent(_ExperienceDockEntry entry) {
    if (!_intentEntryAvailable(entry)) {
      _resetIntent();
      return;
    }

    if (_intentFeedbackEntry != entry) {
      _playIntentFeedback();
    }
    final preserveTriggeredPosition =
        !widget.tuning && entry != _ExperienceDockEntry.view;
    final triggerValue = preserveTriggeredPosition
        ? (_intentEntry == entry ? _intentValue : _intentValueForEntry(entry))
        : 0.0;
    final triggerLift = preserveTriggeredPosition ? _intentLift : 0.0;
    _intentTriggerTimer?.cancel();
    setState(() {
      _intentTriggeredEntry = entry;
      _intentDragging = false;
      _intentInitialSnapAnimating = false;
      _viewDragActive = false;
      _viewDragWasActive = false;
      _intentValue = triggerValue;
      _intentLift = triggerLift;
      _intentInitialSnapOrigin = null;
      _viewDragLocalPosition = null;
      _intentGestureStartEntry = null;
      _intentFeedbackEntry = null;
    });
    _intentTriggerTimer = Timer(const Duration(milliseconds: 820), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _intentTriggeredEntry = null;
        _intentValue = 0;
        _intentLift = 0;
      });
    });
    if (!widget.tuning) {
      switch (entry) {
        case _ExperienceDockEntry.cull:
          widget.onCull?.call();
        case _ExperienceDockEntry.view:
          widget.onView?.call();
        case _ExperienceDockEntry.appraise:
          widget.onAppraise?.call();
      }
    }
  }

  bool _intentEntryAvailable(_ExperienceDockEntry entry) {
    return switch (entry) {
      _ExperienceDockEntry.cull => widget.cullAvailable,
      _ExperienceDockEntry.view => true,
      _ExperienceDockEntry.appraise => widget.appraiseAvailable,
    };
  }

  void _playIntentFeedback() {
    unawaited(HapticFeedback.lightImpact());
  }

  _ExperienceDockEntry? get _intentCaptionEntry {
    if (_intentTriggeredEntry != null) {
      return _intentTriggeredEntry;
    }

    final entry = _intentEntry;
    if (entry != _ExperienceDockEntry.view &&
        _intentEntryAvailable(entry) &&
        _intentValue.abs() >= _intentEntryThreshold) {
      return entry;
    }
    return null;
  }

  String _intentCaption(NoemaStrings strings, _ExperienceDockEntry entry) {
    if (strings.isZh) {
      return switch (entry) {
        _ExperienceDockEntry.cull => '甄别相似',
        _ExperienceDockEntry.view => '沉浸欣赏',
        _ExperienceDockEntry.appraise => '留下判断',
      };
    }
    return switch (entry) {
      _ExperienceDockEntry.cull => 'Find matches',
      _ExperienceDockEntry.view => 'Immerse',
      _ExperienceDockEntry.appraise => 'Mark value',
    };
  }

  _ExperienceDockEntry get _intentEntry {
    if (_viewDragActive) {
      return _ExperienceDockEntry.view;
    }
    return _intentEntryForValue(_intentValue);
  }

  _ExperienceDockEntry _intentEntryForValue(double value) {
    if (value < -_intentEntryThreshold &&
        _intentEntryAvailable(_ExperienceDockEntry.cull)) {
      return _ExperienceDockEntry.cull;
    }
    if (value > _intentEntryThreshold &&
        _intentEntryAvailable(_ExperienceDockEntry.appraise)) {
      return _ExperienceDockEntry.appraise;
    }
    return _ExperienceDockEntry.view;
  }

  double _intentValueForEntry(_ExperienceDockEntry entry) {
    return switch (entry) {
      _ExperienceDockEntry.cull => -1,
      _ExperienceDockEntry.view => 0,
      _ExperienceDockEntry.appraise => 1,
    };
  }

  void _resetIntentTuneOffsets() {
    setState(() {
      for (final target in _IntentTuneTarget.values) {
        _intentTuneOffsets[target] = Offset.zero;
      }
    });
    _logIntentTuneOffsets();
  }

  void _setIntentEndpointTune(_IntentTuneTarget target, double value) {
    if (target != _IntentTuneTarget.centerLeftEnd &&
        target != _IntentTuneTarget.centerRightEnd) {
      return;
    }
    setState(() {
      _intentTuneOffsets[target] = Offset(
        value.clamp(-180.0, 180.0).toDouble(),
        0,
      );
    });
    _exportIntentTuneOffsets();
  }

  void _logIntentTuneOffsets() {
    if (!widget.tuning) {
      return;
    }
    _exportIntentTuneOffsets();
    debugPrint('NoemaIntentSealTune=$_intentTunePayload');
  }

  void _exportIntentTuneOffsets() {
    if (!widget.tuning) {
      return;
    }
    exportNoemaTune('noema.intent_seal_tune.v1', _intentTunePayload);
  }

  String get _intentTunePayload {
    return jsonEncode({
      for (final target in _IntentTuneTarget.values)
        target.keyName: {
          'x': _roundTuneValue(_intentTuneOffsets[target]?.dx ?? 0),
          'y': _roundTuneValue(_intentTuneOffsets[target]?.dy ?? 0),
        },
    });
  }

  double _roundTuneValue(double value) {
    return double.parse(value.toStringAsFixed(1));
  }

  bool _intentEntryIsActive(_ExperienceDockEntry entry) {
    return _intentEntry == entry;
  }

  void _selectIntentEntry(_ExperienceDockEntry entry) {
    if (!_intentEntryAvailable(entry)) {
      return;
    }
    _setIntentValue(_intentValueForEntry(entry));
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return switch (variant) {
      ExperienceDockVariant.focus => _buildFocus(strings),
      ExperienceDockVariant.lens => _buildLens(strings),
      ExperienceDockVariant.object => _buildObject(strings),
      ExperienceDockVariant.intent => _buildIntent(
        strings,
        style: _IntentEffectStyle.mist,
      ),
      ExperienceDockVariant.intentRipple => _buildIntent(
        strings,
        style: _IntentEffectStyle.ripple,
      ),
      ExperienceDockVariant.intentSeal => _buildIntent(
        strings,
        style: _IntentEffectStyle.seal,
      ),
      ExperienceDockVariant.intentTiles => _buildIntentTiles(strings),
      ExperienceDockVariant.intentRail => _buildIntentRail(strings),
      ExperienceDockVariant.intentGate => _buildIntentGate(strings),
      ExperienceDockVariant.quiet => _buildQuiet(strings),
      ExperienceDockVariant.orbit => _buildOrbit(strings),
      ExperienceDockVariant.rail => _buildRail(strings),
      ExperienceDockVariant.balanced => _buildBalanced(strings),
    };
  }

  Widget _buildBalanced(NoemaStrings strings) {
    return SizedBox(
      height: 78,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _action(strings, _ExperienceDockEntry.cull),
          _action(strings, _ExperienceDockEntry.view),
          _action(strings, _ExperienceDockEntry.appraise),
        ],
      ),
    );
  }

  Widget _buildFocus(NoemaStrings strings) {
    return SizedBox(
      height: 96,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _action(
              strings,
              _ExperienceDockEntry.cull,
              cardSize: const Size(42, 58),
              hitSize: const Size(62, 76),
              cjkFontSize: 22,
              latinFontSize: 10,
              radius: 14,
              opacity: 0.78,
              glassScale: 0.72,
              strokeOpacity: 0.56,
              shadowScale: 0.48,
              motifOpacity: 0.62,
            ),
          ),
          const SizedBox(width: 18),
          _action(
            strings,
            _ExperienceDockEntry.view,
            cardSize: const Size(62, 78),
            hitSize: const Size(86, 92),
            cjkFontSize: 30,
            latinFontSize: 12,
            radius: 18,
            glassScale: 1.08,
            strokeOpacity: 0.88,
            shadowScale: 1.18,
          ),
          const SizedBox(width: 18),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _action(
              strings,
              _ExperienceDockEntry.appraise,
              cardSize: const Size(42, 58),
              hitSize: const Size(62, 76),
              cjkFontSize: 22,
              latinFontSize: 10,
              radius: 14,
              opacity: 0.78,
              glassScale: 0.72,
              strokeOpacity: 0.56,
              shadowScale: 0.48,
              motifOpacity: 0.62,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLens(NoemaStrings strings) {
    const motion = Duration(milliseconds: 220);

    return SizedBox(
      height: 102,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 16,
            child: _action(
              strings,
              _ExperienceDockEntry.view,
              cardSize: const Size(72, 72),
              hitSize: const Size(92, 92),
              cjkFontSize: 30,
              latinFontSize: 12,
              radius: 36,
              glassScale: 1.08,
              strokeOpacity: 0.9,
              shadowScale: 1.12,
              motifOpacity: 0,
              onPressed: _toggleLens,
            ),
          ),
          AnimatedPositioned(
            duration: motion,
            curve: _observeEase,
            left: _lensExpanded ? 82 : 132,
            bottom: _lensExpanded ? 28 : 24,
            child: IgnorePointer(
              ignoring: !_lensExpanded,
              child: AnimatedOpacity(
                duration: motion,
                opacity: _lensExpanded ? 1 : 0,
                child: _action(
                  strings,
                  _ExperienceDockEntry.cull,
                  cardSize: const Size(38, 38),
                  hitSize: const Size(58, 58),
                  cjkFontSize: 19,
                  latinFontSize: 9,
                  radius: 19,
                  opacity: 0.68,
                  glassScale: 0.62,
                  strokeOpacity: 0.46,
                  shadowScale: 0.32,
                  motifOpacity: 0,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: motion,
            curve: _observeEase,
            right: _lensExpanded ? 82 : 132,
            bottom: _lensExpanded ? 28 : 24,
            child: IgnorePointer(
              ignoring: !_lensExpanded,
              child: AnimatedOpacity(
                duration: motion,
                opacity: _lensExpanded ? 1 : 0,
                child: _action(
                  strings,
                  _ExperienceDockEntry.appraise,
                  cardSize: const Size(38, 38),
                  hitSize: const Size(58, 58),
                  cjkFontSize: 19,
                  latinFontSize: 9,
                  radius: 19,
                  opacity: 0.68,
                  glassScale: 0.62,
                  strokeOpacity: 0.46,
                  shadowScale: 0.32,
                  motifOpacity: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObject(NoemaStrings strings) {
    const motion = Duration(milliseconds: 260);

    return SizedBox(
      height: 106,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 24,
            child: IgnorePointer(
              ignoring: !_objectDetected,
              child: AnimatedOpacity(
                duration: motion,
                curve: Curves.easeOut,
                opacity: _objectDetected ? 1 : 0,
                child: AnimatedScale(
                  duration: motion,
                  curve: _observeEase,
                  scale: _objectDetected ? 1 : 0.86,
                  child: _ObjectSignal(
                    palette: palette,
                    tooltip: strings.observeDistill,
                    label: strings.observeDistill,
                    kind: _ObjectSignalKind.group,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 24,
            child: IgnorePointer(
              ignoring: !_objectDetected,
              child: AnimatedOpacity(
                duration: motion,
                curve: Curves.easeOut,
                opacity: _objectDetected ? 1 : 0,
                child: AnimatedScale(
                  duration: motion,
                  curve: _observeEase,
                  scale: _objectDetected ? 1 : 0.86,
                  child: _ObjectSignal(
                    palette: palette,
                    tooltip: strings.observeAppraise,
                    label: strings.observeAppraise,
                    kind: _ObjectSignalKind.single,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: _action(
                strings,
                _ExperienceDockEntry.view,
                cardSize: const Size(44, 44),
                hitSize: const Size(64, 64),
                cjkFontSize: 22,
                latinFontSize: 9,
                radius: 22,
                opacity: 0.72,
                glassScale: 0.72,
                strokeOpacity: 0.56,
                shadowScale: 0.42,
                motifOpacity: 0,
                onPressed: () {
                  setState(() {
                    _objectDetected = !_objectDetected;
                  });
                },
              ),
            ),
          ),
          Positioned(
            left: 72,
            right: 72,
            bottom: 42,
            child: AnimatedOpacity(
              duration: motion,
              opacity: _objectDetected ? 0 : 1,
              child: _ObjectScanningTrace(palette: palette),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntent(
    NoemaStrings strings, {
    required _IntentEffectStyle style,
  }) {
    const dockHeight = _observeExperienceIntentDockHeight;
    const intentAxisY = 58.0;
    const centerHitSize = Size(84, 92);
    const sideHitWidth = 56.0;
    const sideHitHeight = 68.0;
    const ambientHeight = 78.0;
    const captionWidth = 116.0;
    const tunePanelHeight = 74.0;

    double bottomFor(double height) => dockHeight - intentAxisY - height / 2;

    return SizedBox(
      height: dockHeight + (widget.tuning ? tunePanelHeight : 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawTrackWidth = math.min(
            300.0,
            math.max(190.0, constraints.maxWidth - 44),
          );
          final trackWidth = math
              .min(rawTrackWidth, constraints.maxWidth)
              .toDouble();
          final trackLeft = (constraints.maxWidth - trackWidth) / 2;
          final cullAvailable = _intentEntryAvailable(
            _ExperienceDockEntry.cull,
          );
          final appraiseAvailable = _intentEntryAvailable(
            _ExperienceDockEntry.appraise,
          );
          final sideSelectionValue = _viewDragActive ? 0.0 : _intentValue;
          final cullBias = cullAvailable
              ? math.max(
                  math.max(0.0, -sideSelectionValue),
                  _intentTriggeredEntry == _ExperienceDockEntry.cull
                      ? 1.0
                      : 0.0,
                )
              : 0.0;
          final appraiseBias = appraiseAvailable
              ? math.max(
                  math.max(0.0, sideSelectionValue),
                  _intentTriggeredEntry == _ExperienceDockEntry.appraise
                      ? 1.0
                      : 0.0,
                )
              : 0.0;
          final maxSideLeft = math.max(
            0.0,
            constraints.maxWidth - sideHitWidth,
          );
          final cullLeft = (trackLeft - sideHitWidth / 2)
              .clamp(0.0, maxSideLeft)
              .toDouble();
          final appraiseLeft = (trackLeft + trackWidth - sideHitWidth / 2)
              .clamp(0.0, maxSideLeft)
              .toDouble();
          final sealStyle = style == _IntentEffectStyle.seal;

          Offset tuneOffset(_IntentTuneTarget target) {
            final alignedOffset = sealStyle
                ? _intentSealAlignedOffset(target)
                : Offset.zero;
            if (!widget.tuning) {
              return alignedOffset;
            }
            return alignedOffset + (_intentTuneOffsets[target] ?? Offset.zero);
          }

          double tuneLeft(double left, _IntentTuneTarget target) {
            return left + tuneOffset(target).dx;
          }

          double tuneBottom(double bottom, _IntentTuneTarget target) {
            return bottom - tuneOffset(target).dy;
          }

          final sideCueWidth = sealStyle ? 112.0 : 76.0;
          final maxCueLeft = math.max(0.0, constraints.maxWidth - sideCueWidth);
          final cullCueLeft = sealStyle
              ? (trackLeft - sideCueWidth / 2).clamp(0.0, maxCueLeft).toDouble()
              : cullLeft - 10;
          final appraiseCueLeft = sealStyle
              ? (trackLeft + trackWidth - sideCueWidth / 2)
                    .clamp(0.0, maxCueLeft)
                    .toDouble()
              : appraiseLeft - 6;
          final centerBaseX = constraints.maxWidth / 2;
          final centerOffsetX = tuneOffset(_IntentTuneTarget.centerSign).dx;
          final cullSignCenterX =
              cullLeft +
              sideHitWidth / 2 +
              tuneOffset(_IntentTuneTarget.cullSign).dx;
          final appraiseSignCenterX =
              appraiseLeft +
              sideHitWidth / 2 +
              tuneOffset(_IntentTuneTarget.appraiseSign).dx;
          final cullFrameCenterX =
              cullCueLeft +
              sideCueWidth / 2 +
              tuneOffset(_IntentTuneTarget.cullFrame).dx;
          final appraiseFrameCenterX =
              appraiseCueLeft +
              sideCueWidth / 2 +
              tuneOffset(_IntentTuneTarget.appraiseFrame).dx;
          final cullTargetCenterX = sealStyle
              ? cullFrameCenterX +
                    tuneOffset(_IntentTuneTarget.centerLeftEnd).dx
              : cullSignCenterX;
          final appraiseTargetCenterX = sealStyle
              ? appraiseFrameCenterX +
                    tuneOffset(_IntentTuneTarget.centerRightEnd).dx
              : appraiseSignCenterX;
          final followCenterX = centerBaseX + _intentValue * (trackWidth / 2);
          final centerTargetX = followCenterX - centerOffsetX;
          final minCenterLeft = sealStyle ? -centerHitSize.width / 2 : 0.0;
          final maxCenterLeft = math.max(
            minCenterLeft,
            sealStyle
                ? constraints.maxWidth - centerHitSize.width / 2
                : constraints.maxWidth - centerHitSize.width,
          );
          final centerLeft = (centerTargetX - centerHitSize.width / 2)
              .clamp(minCenterLeft, maxCenterLeft)
              .toDouble();
          final sideCueHeight = sealStyle ? 100.0 : 84.0;
          final ambientBottom = bottomFor(ambientHeight);
          final cueBottom = bottomFor(sideCueHeight);
          final sideBottom = bottomFor(sideHitHeight);
          final centerBottom = bottomFor(centerHitSize.height);
          final captionEntry = _intentCaptionEntry;
          final captionText = captionEntry == null
              ? ''
              : _intentCaption(strings, captionEntry);
          final captionCenterX = switch (captionEntry) {
            _ExperienceDockEntry.cull => cullTargetCenterX,
            _ExperienceDockEntry.appraise => appraiseTargetCenterX,
            _ExperienceDockEntry.view => centerBaseX,
            null => centerBaseX,
          };
          final minCaptionLeft = sealStyle ? -captionWidth / 2 : 0.0;
          final maxCaptionLeft = math.max(
            minCaptionLeft,
            sealStyle
                ? constraints.maxWidth - captionWidth / 2
                : constraints.maxWidth - captionWidth,
          );
          final captionLeft = (captionCenterX - captionWidth / 2)
              .clamp(minCaptionLeft, maxCaptionLeft)
              .toDouble();
          final baseAmbientLeft = trackLeft - 18;
          final ambientWidth = trackWidth + 36;
          final tunedAmbientLeft = tuneLeft(
            baseAmbientLeft,
            _IntentTuneTarget.line,
          );
          final tunedAmbientBottom = tuneBottom(
            ambientBottom,
            _IntentTuneTarget.line,
          );
          final tunedCullCueLeft = tuneLeft(
            cullCueLeft,
            _IntentTuneTarget.cullFrame,
          );
          final tunedCullCueBottom = tuneBottom(
            cueBottom,
            _IntentTuneTarget.cullFrame,
          );
          final tunedAppraiseCueLeft = tuneLeft(
            appraiseCueLeft,
            _IntentTuneTarget.appraiseFrame,
          );
          final tunedAppraiseCueBottom = tuneBottom(
            cueBottom,
            _IntentTuneTarget.appraiseFrame,
          );
          final tunedCullLeft = tuneLeft(cullLeft, _IntentTuneTarget.cullSign);
          final tunedCullBottom = tuneBottom(
            sideBottom,
            _IntentTuneTarget.cullSign,
          );
          final tunedAppraiseLeft = tuneLeft(
            appraiseLeft,
            _IntentTuneTarget.appraiseSign,
          );
          final tunedAppraiseBottom = tuneBottom(
            sideBottom,
            _IntentTuneTarget.appraiseSign,
          );
          final tunedCaptionLeft = tuneLeft(
            captionLeft,
            _IntentTuneTarget.caption,
          );
          final tunedCaptionBottom = tuneBottom(116, _IntentTuneTarget.caption);
          final tunedCenterLeft = tuneLeft(
            centerLeft,
            _IntentTuneTarget.centerSign,
          );
          final tunedCenterBottom = tuneBottom(
            centerBottom + _intentLift,
            _IntentTuneTarget.centerSign,
          );
          final viewDragLocalPosition = _viewDragLocalPosition;
          final viewDragFloating =
              _viewDragActive && viewDragLocalPosition != null;
          // ponytail: the same dock listener keeps pointer ownership after the
          // finger leaves the dock, so a local floating seal is enough here.
          final floatingCenterLeft = viewDragFloating
              ? (viewDragLocalPosition.dx - centerHitSize.width / 2)
                    .clamp(minCenterLeft, maxCenterLeft)
                    .toDouble()
              : tunedCenterLeft;
          final floatingCenterBottom = viewDragFloating
              ? dockHeight - viewDragLocalPosition.dy - centerHitSize.height / 2
              : tunedCenterBottom;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: dockHeight,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _setIntentFromPosition(
                    localPosition: event.localPosition,
                    globalPosition: event.position,
                    maxWidth: constraints.maxWidth,
                    trackWidth: trackWidth,
                    axisY: intentAxisY,
                    start: true,
                  ),
                  onPointerMove: (event) => _setIntentFromPosition(
                    localPosition: event.localPosition,
                    globalPosition: event.position,
                    maxWidth: constraints.maxWidth,
                    trackWidth: trackWidth,
                    axisY: intentAxisY,
                  ),
                  onPointerUp: (_) => _finishIntentGesture(),
                  onPointerCancel: (_) => _resetIntent(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned(
                        left: tunedAmbientLeft,
                        bottom: tunedAmbientBottom,
                        child: _IntentAmbientField(
                          palette: palette,
                          style: style,
                          width: ambientWidth,
                          cullAvailable: cullAvailable,
                          appraiseAvailable: appraiseAvailable,
                          cullBias: cullBias,
                          appraiseBias: appraiseBias,
                          leftDashOffset: tuneOffset(
                            _IntentTuneTarget.leftDash,
                          ),
                          rightDashOffset: tuneOffset(
                            _IntentTuneTarget.rightDash,
                          ),
                          cullMarkOffset: tuneOffset(
                            _IntentTuneTarget.cullMark,
                          ),
                          appraiseMarkOffset: tuneOffset(
                            _IntentTuneTarget.appraiseMark,
                          ),
                        ),
                      ),
                      if (cullAvailable)
                        Positioned(
                          left: tunedCullCueLeft,
                          bottom: tunedCullCueBottom,
                          child: _IntentSideCue(
                            palette: palette,
                            style: style,
                            enabled: cullAvailable,
                            leading: true,
                            activeBias: cullBias,
                          ),
                        ),
                      if (appraiseAvailable)
                        Positioned(
                          left: tunedAppraiseCueLeft,
                          bottom: tunedAppraiseCueBottom,
                          child: _IntentSideCue(
                            palette: palette,
                            style: style,
                            enabled: appraiseAvailable,
                            leading: false,
                            activeBias: appraiseBias,
                          ),
                        ),
                      if (cullAvailable)
                        Positioned(
                          left: tunedCullLeft,
                          bottom: tunedCullBottom,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              opacity: 0.78 + cullBias * 0.2,
                              child: _intentGhostSign(
                                strings,
                                _ExperienceDockEntry.cull,
                                activeBias: cullBias,
                                borderless: sealStyle,
                              ),
                            ),
                          ),
                        ),
                      if (appraiseAvailable)
                        Positioned(
                          left: tunedAppraiseLeft,
                          bottom: tunedAppraiseBottom,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              opacity: 0.78 + appraiseBias * 0.2,
                              child: _intentGhostSign(
                                strings,
                                _ExperienceDockEntry.appraise,
                                activeBias: appraiseBias,
                                borderless: sealStyle,
                              ),
                            ),
                          ),
                        ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 180),
                        curve: _observeEase,
                        left: tunedCaptionLeft,
                        bottom: tunedCaptionBottom,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 180),
                          curve: _observeEase,
                          scale: captionEntry == null ? 1.08 : 1,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            opacity: captionEntry == null ? 0 : 1,
                            child: _IntentCaption(
                              palette: palette,
                              text: captionText,
                            ),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration:
                            (_intentDragging && !_intentInitialSnapAnimating) ||
                                viewDragFloating
                            ? Duration.zero
                            : _intentInitialSnapAnimating
                            ? _intentInitialSnapDuration
                            : const Duration(milliseconds: 240),
                        curve: _intentInitialSnapAnimating
                            ? _intentInitialSnapCurve
                            : _observeEase,
                        left: floatingCenterLeft,
                        bottom: floatingCenterBottom,
                        child: _action(
                          strings,
                          _intentEntry,
                          actionKey: const ValueKey(
                            'observe-experience-intent',
                          ),
                          cardSize: const Size(58, 74),
                          hitSize: centerHitSize,
                          cjkFontSize: 29,
                          latinFontSize: 12,
                          radius: 18,
                          glassScale: 1.22,
                          strokeOpacity: sealStyle ? 0.98 : 0.96,
                          shadowScale: 1.3,
                          motifOpacity: 1,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.tuning)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _IntentTuneReadout(
                    palette: palette,
                    leftEndpointValue: _roundTuneValue(
                      _intentTuneOffsets[_IntentTuneTarget.centerLeftEnd]?.dx ??
                          0,
                    ),
                    rightEndpointValue: _roundTuneValue(
                      _intentTuneOffsets[_IntentTuneTarget.centerRightEnd]
                              ?.dx ??
                          0,
                    ),
                    onLeftEndpointChanged: (value) => _setIntentEndpointTune(
                      _IntentTuneTarget.centerLeftEnd,
                      value,
                    ),
                    onRightEndpointChanged: (value) => _setIntentEndpointTune(
                      _IntentTuneTarget.centerRightEnd,
                      value,
                    ),
                    onReset: _resetIntentTuneOffsets,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntentTiles(NoemaStrings strings) {
    const entries = [
      _ExperienceDockEntry.cull,
      _ExperienceDockEntry.view,
      _ExperienceDockEntry.appraise,
    ];

    return SizedBox(
      height: 104,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _setIntentValue(_intentValue + details.delta.dx / 96);
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: 76,
              right: 76,
              bottom: 42,
              child: _IntentHairline(palette: palette),
            ),
            Positioned(
              bottom: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in entries) ...[
                    _intentTileAction(strings, entry),
                    if (entry != entries.last) const SizedBox(width: 22),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntentRail(NoemaStrings strings) {
    const entries = [
      _ExperienceDockEntry.cull,
      _ExperienceDockEntry.view,
      _ExperienceDockEntry.appraise,
    ];

    return SizedBox(
      height: 100,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _setIntentValue(_intentValue + details.delta.dx / 104);
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: palette.glassBorder.withValues(alpha: 0.42),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          palette.glass.withValues(
                            alpha: palette.tone == NoemaTone.dark ? 0.1 : 0.42,
                          ),
                          palette.glass.withValues(
                            alpha: palette.tone == NoemaTone.dark ? 0.18 : 0.58,
                          ),
                        ],
                      ),
                    ),
                    child: const SizedBox(width: 236, height: 56),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in entries) ...[
                    _intentTileAction(
                      strings,
                      entry,
                      compact: !_intentEntryIsActive(entry),
                      activeLift: 12,
                    ),
                    if (entry != entries.last) const SizedBox(width: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntentGate(NoemaStrings strings) {
    final activeEntry = _intentEntry;
    final previousEntry = switch (activeEntry) {
      _ExperienceDockEntry.cull => _ExperienceDockEntry.appraise,
      _ExperienceDockEntry.view => _ExperienceDockEntry.cull,
      _ExperienceDockEntry.appraise => _ExperienceDockEntry.view,
    };
    final nextEntry = switch (activeEntry) {
      _ExperienceDockEntry.cull => _ExperienceDockEntry.view,
      _ExperienceDockEntry.view => _ExperienceDockEntry.appraise,
      _ExperienceDockEntry.appraise => _ExperienceDockEntry.cull,
    };

    return SizedBox(
      height: 104,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          _setIntentValue(_intentValue + details.delta.dx / 108);
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: 96,
              bottom: 28,
              child: _intentTileAction(
                strings,
                previousEntry,
                compact: true,
                ghost: true,
              ),
            ),
            Positioned(
              right: 96,
              bottom: 28,
              child: _intentTileAction(
                strings,
                nextEntry,
                compact: true,
                ghost: true,
              ),
            ),
            Positioned(
              bottom: 4,
              child: _intentTileAction(
                strings,
                activeEntry,
                forceActive: true,
                activeLift: 0,
              ),
            ),
            Positioned(
              bottom: 7,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: palette.ink.withValues(alpha: 0.18),
                  ),
                  child: const SizedBox(width: 18, height: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuiet(NoemaStrings strings) {
    return SizedBox(
      height: 78,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleQuietReveal,
              child: Tooltip(
                message: strings.observeAppreciate,
                textStyle: _tooltipTextStyle(
                  palette,
                  strings.observeAppreciate,
                ),
                decoration: _tooltipDecoration(palette),
                child: Semantics(
                  button: true,
                  label: strings.observeAppreciate,
                  child: SizedBox(
                    key: const ValueKey('observe-experience-view'),
                    width: 104,
                    height: 36,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.ink.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: palette.tone == NoemaTone.dark
                                    ? 0.24
                                    : 0.07,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const SizedBox(width: 34, height: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 58,
            bottom: _quietRevealed ? 42 : 34,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _quietRevealed ? 1 : 0.36,
              child: _QuietMark(
                palette: palette,
                tooltip: strings.observeDistill,
                label: strings.observeDistill,
                valueKey: const ValueKey('observe-experience-cull'),
              ),
            ),
          ),
          Positioned(
            right: 58,
            bottom: _quietRevealed ? 42 : 34,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _quietRevealed ? 1 : 0.36,
              child: _QuietMark(
                palette: palette,
                tooltip: strings.observeAppraise,
                label: strings.observeAppraise,
                valueKey: const ValueKey('observe-experience-appraise'),
              ),
            ),
          ),
          Positioned(
            bottom: _quietRevealed ? 18 : 28,
            child: IgnorePointer(
              ignoring: !_quietRevealed,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _quietRevealed ? 1 : 0,
                child: _action(
                  strings,
                  _ExperienceDockEntry.view,
                  cardSize: const Size(46, 46),
                  hitSize: const Size(64, 56),
                  cjkFontSize: 22,
                  latinFontSize: 9,
                  radius: 23,
                  glassScale: 0.74,
                  strokeOpacity: 0.58,
                  shadowScale: 0.42,
                  motifOpacity: 0,
                  actionKey: const ValueKey('observe-experience-view-revealed'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbit(NoemaStrings strings) {
    const sideHitWidth = 62.0;

    return SizedBox(
      height: 100,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final centerX = constraints.maxWidth / 2;
          final sideOffset = math.min(112.0, constraints.maxWidth * 0.23);
          final maxLeft = math.max(0.0, constraints.maxWidth - sideHitWidth);
          final cullLeft = (centerX - sideOffset - sideHitWidth / 2)
              .clamp(0.0, maxLeft)
              .toDouble();
          final appraiseLeft = (centerX + sideOffset - sideHitWidth / 2)
              .clamp(0.0, maxLeft)
              .toDouble();

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: _action(
                  strings,
                  _ExperienceDockEntry.view,
                  cardSize: const Size(60, 76),
                  hitSize: const Size(86, 92),
                  cjkFontSize: 30,
                  latinFontSize: 12,
                  radius: 18,
                  glassScale: 1.08,
                  strokeOpacity: 0.86,
                  shadowScale: 1.12,
                ),
              ),
              Positioned(
                left: cullLeft,
                bottom: 24,
                child: Transform.rotate(
                  angle: -0.08,
                  child: _action(
                    strings,
                    _ExperienceDockEntry.cull,
                    cardSize: const Size(40, 54),
                    hitSize: const Size(sideHitWidth, 72),
                    cjkFontSize: 21,
                    latinFontSize: 10,
                    radius: 14,
                    opacity: 0.72,
                    glassScale: 0.68,
                    strokeOpacity: 0.52,
                    shadowScale: 0.42,
                    motifOpacity: 0.56,
                  ),
                ),
              ),
              Positioned(
                left: appraiseLeft,
                bottom: 24,
                child: Transform.rotate(
                  angle: 0.08,
                  child: _action(
                    strings,
                    _ExperienceDockEntry.appraise,
                    cardSize: const Size(40, 54),
                    hitSize: const Size(sideHitWidth, 72),
                    cjkFontSize: 21,
                    latinFontSize: 10,
                    radius: 14,
                    opacity: 0.72,
                    glassScale: 0.68,
                    strokeOpacity: 0.52,
                    shadowScale: 0.42,
                    motifOpacity: 0.56,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRail(NoemaStrings strings) {
    return SizedBox(
      height: 88,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: _action(
              strings,
              _ExperienceDockEntry.cull,
              cardSize: const Size(56, 40),
              hitSize: const Size(70, 64),
              cjkFontSize: 22,
              latinFontSize: 10,
              radius: 20,
              opacity: 0.76,
              glassScale: 0.66,
              strokeOpacity: 0.52,
              shadowScale: 0.36,
              motifOpacity: 0,
            ),
          ),
          const SizedBox(width: 18),
          _action(
            strings,
            _ExperienceDockEntry.view,
            cardSize: const Size(58, 72),
            hitSize: const Size(82, 88),
            cjkFontSize: 29,
            latinFontSize: 12,
            radius: 18,
            glassScale: 1.06,
            strokeOpacity: 0.84,
            shadowScale: 1.08,
          ),
          const SizedBox(width: 18),
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: _action(
              strings,
              _ExperienceDockEntry.appraise,
              cardSize: const Size(56, 40),
              hitSize: const Size(70, 64),
              cjkFontSize: 22,
              latinFontSize: 10,
              radius: 20,
              opacity: 0.76,
              glassScale: 0.66,
              strokeOpacity: 0.52,
              shadowScale: 0.36,
              motifOpacity: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _intentTileAction(
    NoemaStrings strings,
    _ExperienceDockEntry entry, {
    bool compact = false,
    bool ghost = false,
    bool forceActive = false,
    double activeLift = 0,
  }) {
    final active = forceActive || _intentEntryIsActive(entry);
    final cardWidth = active ? 58.0 : (compact ? 38.0 : 42.0);
    final cardHeight = active ? 74.0 : (compact ? 54.0 : 58.0);
    final hitWidth = active ? 76.0 : 58.0;
    final hitHeight = active ? 88.0 : 72.0;

    return Padding(
      padding: EdgeInsets.only(bottom: active ? activeLift : 0),
      child: _action(
        strings,
        entry,
        cardSize: Size(cardWidth, cardHeight),
        hitSize: Size(hitWidth, hitHeight),
        cjkFontSize: active ? 29 : 20,
        latinFontSize: active ? 12 : 9,
        radius: active ? 18 : 15,
        opacity: ghost ? 0.36 : (active ? 1 : 0.72),
        glassScale: active ? 1.06 : 0.66,
        strokeOpacity: active ? 0.88 : 0.48,
        shadowScale: active ? 1.02 : 0.34,
        motifOpacity: active ? 0.82 : 0.42,
        onPressed: () => _selectIntentEntry(entry),
      ),
    );
  }

  Widget _intentGhostSign(
    NoemaStrings strings,
    _ExperienceDockEntry entry, {
    required double activeBias,
    bool borderless = false,
  }) {
    return _action(
      strings,
      entry,
      cardSize: Size(42 + activeBias * 8, 58 + activeBias * 6),
      hitSize: const Size(56, 68),
      cjkFontSize: 21 + activeBias * 2,
      latinFontSize: 11.5 + activeBias,
      radius: 14,
      opacity: 1,
      glassScale: 0.88 + activeBias * 0.12,
      strokeOpacity: borderless
          ? 0.44 + activeBias * 0.2
          : 0.5 + activeBias * 0.18,
      shadowScale: 0.54 + activeBias * 0.16,
      motifOpacity: 0.64,
      onPressed: () => _selectIntentEntry(entry),
    );
  }

  Widget _action(
    NoemaStrings strings,
    _ExperienceDockEntry entry, {
    Size cardSize = const Size(52, 68),
    Size hitSize = const Size(72, 78),
    double cjkFontSize = 26,
    double latinFontSize = 12,
    double radius = 16,
    double opacity = 1,
    double glassScale = 1,
    double strokeOpacity = 0.76,
    double shadowScale = 1,
    double motifOpacity = 1,
    Key? actionKey,
    VoidCallback? onPressed,
  }) {
    final label = switch (entry) {
      _ExperienceDockEntry.cull => strings.observeDistill,
      _ExperienceDockEntry.view => strings.observeAppreciate,
      _ExperienceDockEntry.appraise => strings.observeAppraise,
    };

    return _ExperienceAction(
      palette: palette,
      tooltip: label,
      label: label,
      actionKey: actionKey ?? ValueKey('observe-experience-${entry.name}'),
      cardSize: cardSize,
      hitSize: hitSize,
      cjkFontSize: cjkFontSize,
      latinFontSize: latinFontSize,
      radius: radius,
      opacity: opacity,
      glassScale: glassScale,
      strokeOpacity: strokeOpacity,
      shadowScale: shadowScale,
      motifOpacity: motifOpacity,
      onPressed: onPressed ?? () => _triggerIntent(entry),
    );
  }
}

enum _ObjectSignalKind { group, single }

class _IntentHairline extends StatelessWidget {
  const _IntentHairline({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: LinearGradient(
          colors: [
            palette.ink.withValues(alpha: 0),
            palette.ink.withValues(
              alpha: palette.tone == NoemaTone.dark ? 0.3 : 0.18,
            ),
            palette.ink.withValues(alpha: 0),
          ],
        ),
      ),
      child: const SizedBox(height: 1),
    );
  }
}

class _IntentCaption extends StatelessWidget {
  const _IntentCaption({required this.palette, required this.text});

  final NoemaPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isCjk = _containsCjk(text);

    return SizedBox(
      width: 116,
      height: 18,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.ink.withValues(
              alpha: palette.tone == NoemaTone.dark ? 0.62 : 0.56,
            ),
            fontFamily: _fontForText(text),
            fontSize: isCjk ? 10.5 : 9.5,
            height: 1,
            letterSpacing: 0,
            shadows: [
              Shadow(
                color: palette.sheet.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntentTuneReadout extends StatelessWidget {
  const _IntentTuneReadout({
    required this.palette,
    required this.leftEndpointValue,
    required this.rightEndpointValue,
    required this.onLeftEndpointChanged,
    required this.onRightEndpointChanged,
    required this.onReset,
  });

  final NoemaPalette palette;
  final double leftEndpointValue;
  final double rightEndpointValue;
  final ValueChanged<double> onLeftEndpointChanged;
  final ValueChanged<double> onRightEndpointChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final darkTone = palette.tone == NoemaTone.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.sheet.withValues(alpha: darkTone ? 0.68 : 0.84),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: palette.ink.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: SizedBox(
            key: const ValueKey('observe-intent-tune-readout'),
            height: 54,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Text(
                  '赏终点',
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.78),
                    fontFamily: _fontForText('赏终点'),
                    fontSize: 11,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                _EndpointTuneField(
                  fieldKey: const ValueKey('observe-intent-left-endpoint'),
                  palette: palette,
                  label: '左',
                  value: leftEndpointValue,
                  onChanged: onLeftEndpointChanged,
                ),
                const SizedBox(width: 6),
                _EndpointTuneField(
                  fieldKey: const ValueKey('observe-intent-right-endpoint'),
                  palette: palette,
                  label: '右',
                  value: rightEndpointValue,
                  onChanged: onRightEndpointChanged,
                ),
                const Spacer(),
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.ink.withValues(alpha: 0.74),
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '归零',
                    style: TextStyle(
                      fontFamily: _fontForText('归零'),
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndpointTuneField extends StatefulWidget {
  const _EndpointTuneField({
    required this.fieldKey,
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final NoemaPalette palette;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_EndpointTuneField> createState() => _EndpointTuneFieldState();
}

class _EndpointTuneFieldState extends State<_EndpointTuneField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatEndpointTune(widget.value),
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _EndpointTuneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _formatEndpointTune(widget.value);
    if (!_focusNode.hasFocus && _controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTone = widget.palette.tone == NoemaTone.dark;

    return SizedBox(
      width: 82,
      height: 32,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        cursorColor: widget.palette.ink.withValues(alpha: 0.78),
        style: TextStyle(
          color: widget.palette.ink.withValues(alpha: 0.86),
          fontFamily: 'NoemaDigits',
          fontSize: 11,
          height: 1,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: widget.palette.ink.withValues(
            alpha: darkTone ? 0.055 : 0.045,
          ),
          prefixText: '${widget.label} ',
          suffixText: 'px',
          prefixStyle: TextStyle(
            color: widget.palette.ink.withValues(alpha: 0.62),
            fontFamily: _fontForText(widget.label),
            fontSize: 10,
            height: 1,
            letterSpacing: 0,
          ),
          suffixStyle: TextStyle(
            color: widget.palette.ink.withValues(alpha: 0.48),
            fontFamily: 'NoemaLatin',
            fontSize: 9,
            height: 1,
            letterSpacing: 0,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(
              color: widget.palette.ink.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(
              color: widget.palette.ink.withValues(alpha: 0.36),
              width: 0.8,
            ),
          ),
        ),
        onChanged: (source) {
          final parsed = double.tryParse(source.trim());
          if (parsed == null) {
            return;
          }
          widget.onChanged(parsed);
        },
      ),
    );
  }
}

String _formatEndpointTune(double value) {
  final rounded = double.parse(value.toStringAsFixed(1));
  if (rounded == rounded.roundToDouble()) {
    return rounded.toStringAsFixed(0);
  }
  return rounded.toStringAsFixed(1);
}

class _IntentAmbientField extends StatelessWidget {
  const _IntentAmbientField({
    required this.palette,
    required this.style,
    required this.width,
    required this.cullAvailable,
    required this.appraiseAvailable,
    required this.cullBias,
    required this.appraiseBias,
    this.leftDashOffset = Offset.zero,
    this.rightDashOffset = Offset.zero,
    this.cullMarkOffset = Offset.zero,
    this.appraiseMarkOffset = Offset.zero,
  });

  final NoemaPalette palette;
  final _IntentEffectStyle style;
  final double width;
  final bool cullAvailable;
  final bool appraiseAvailable;
  final double cullBias;
  final double appraiseBias;
  final Offset leftDashOffset;
  final Offset rightDashOffset;
  final Offset cullMarkOffset;
  final Offset appraiseMarkOffset;

  @override
  Widget build(BuildContext context) {
    final pull = math.max(cullBias, appraiseBias);
    final darkTone = palette.tone == NoemaTone.dark;

    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: 78,
        child: switch (style) {
          _IntentEffectStyle.mist => Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (cullAvailable)
                Positioned(
                  left: 0,
                  right: width * 0.54,
                  bottom: 4,
                  child: _IntentMistPool(
                    palette: palette,
                    opacity: 0.24 + cullBias * 0.18,
                    leading: true,
                  ),
                ),
              if (appraiseAvailable)
                Positioned(
                  left: width * 0.54,
                  right: 0,
                  bottom: 4,
                  child: _IntentMistPool(
                    palette: palette,
                    opacity: 0.24 + appraiseBias * 0.18,
                    leading: false,
                  ),
                ),
            ],
          ),
          _IntentEffectStyle.ripple => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: width * (0.52 + pull * 0.16),
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: RadialGradient(
                      radius: 1.22,
                      colors: [
                        palette.ink.withValues(
                          alpha: darkTone ? 0.09 + pull * 0.02 : 0.05,
                        ),
                        palette.ink.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: width * 0.18,
                right: width * 0.18,
                bottom: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        palette.ink.withValues(alpha: 0),
                        palette.ink.withValues(alpha: 0.06 + pull * 0.03),
                        palette.ink.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: const SizedBox(height: 1),
                ),
              ),
            ],
          ),
          _IntentEffectStyle.seal => Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 18,
                right: 18,
                bottom: 0,
                child: _IntentSealPath(
                  palette: palette,
                  pull: pull,
                  cullAvailable: cullAvailable,
                  appraiseAvailable: appraiseAvailable,
                  leftDashOffset: leftDashOffset,
                  rightDashOffset: rightDashOffset,
                ),
              ),
              if (cullAvailable)
                Positioned(
                  left: -2,
                  bottom: 23,
                  child: Transform.translate(
                    offset: cullMarkOffset,
                    child: _IntentRegisterMark(
                      palette: palette,
                      opacity: 0.18 + cullBias * 0.18,
                      leading: true,
                    ),
                  ),
                ),
              if (appraiseAvailable)
                Positioned(
                  right: -2,
                  bottom: 23,
                  child: Transform.translate(
                    offset: appraiseMarkOffset,
                    child: _IntentRegisterMark(
                      palette: palette,
                      opacity: 0.18 + appraiseBias * 0.18,
                      leading: false,
                    ),
                  ),
                ),
            ],
          ),
        },
      ),
    );
  }
}

class _IntentSideCue extends StatelessWidget {
  const _IntentSideCue({
    required this.palette,
    required this.style,
    required this.enabled,
    required this.leading,
    required this.activeBias,
  });

  final NoemaPalette palette;
  final _IntentEffectStyle style;
  final bool enabled;
  final bool leading;
  final double activeBias;

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? (0.74 + activeBias * 0.22) : 0.0;

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: SizedBox(
          width: style == _IntentEffectStyle.seal ? 112 : 76,
          height: style == _IntentEffectStyle.seal ? 100 : 84,
          child: switch (style) {
            _IntentEffectStyle.mist => _IntentMistCue(
              palette: palette,
              leading: leading,
              activeBias: activeBias,
            ),
            _IntentEffectStyle.ripple => _IntentRippleCue(
              palette: palette,
              leading: leading,
              activeBias: activeBias,
            ),
            _IntentEffectStyle.seal => _IntentSealCue(
              palette: palette,
              leading: leading,
              activeBias: activeBias,
            ),
          },
        ),
      ),
    );
  }
}

class _IntentSealPath extends StatefulWidget {
  const _IntentSealPath({
    required this.palette,
    required this.pull,
    required this.cullAvailable,
    required this.appraiseAvailable,
    required this.leftDashOffset,
    required this.rightDashOffset,
  });

  final NoemaPalette palette;
  final double pull;
  final bool cullAvailable;
  final bool appraiseAvailable;
  final Offset leftDashOffset;
  final Offset rightDashOffset;

  @override
  State<_IntentSealPath> createState() => _IntentSealPathState();
}

class _IntentSealPathState extends State<_IntentSealPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _IntentSealPathPainter(
              palette: widget.palette,
              progress: _controller.value,
              pull: widget.pull,
              cullAvailable: widget.cullAvailable,
              appraiseAvailable: widget.appraiseAvailable,
              leftDashOffset: widget.leftDashOffset,
              rightDashOffset: widget.rightDashOffset,
            ),
          );
        },
      ),
    );
  }
}

class _IntentSealPathPainter extends CustomPainter {
  const _IntentSealPathPainter({
    required this.palette,
    required this.progress,
    required this.pull,
    required this.cullAvailable,
    required this.appraiseAvailable,
    required this.leftDashOffset,
    required this.rightDashOffset,
  });

  final NoemaPalette palette;
  final double progress;
  final double pull;
  final bool cullAvailable;
  final bool appraiseAvailable;
  final Offset leftDashOffset;
  final Offset rightDashOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final center = size.width / 2;
    final leftStart = center - 30;
    final leftEnd = 0.0;
    final rightStart = center + 30;
    final rightEnd = size.width;
    final baseAlpha = palette.tone == NoemaTone.dark ? 0.12 : 0.08;
    final dashPaint = Paint()
      ..color = palette.ink.withValues(alpha: baseAlpha + pull * 0.03)
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;

    final leftEndOffset = Offset(leftEnd, y) + leftDashOffset;
    final leftStartOffset = Offset(leftStart, y) + leftDashOffset;
    final rightStartOffset = Offset(rightStart, y) + rightDashOffset;
    final rightEndOffset = Offset(rightEnd, y) + rightDashOffset;

    if (cullAvailable) {
      _drawDashedLine(canvas, leftEndOffset, leftStartOffset, dashPaint);
    }
    if (appraiseAvailable) {
      _drawDashedLine(canvas, rightStartOffset, rightEndOffset, dashPaint);
    }

    final pulseAlpha = 0.2 + pull * 0.08;
    final pulsePaint = Paint()
      ..color = palette.ink.withValues(alpha: pulseAlpha)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final pulseGlowPaint = Paint()
      ..color = palette.ink.withValues(alpha: pulseAlpha * 0.18)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    final leftPulseX =
        leftStartOffset.dx + (leftEndOffset.dx - leftStartOffset.dx) * progress;
    final leftPulseY =
        leftStartOffset.dy + (leftEndOffset.dy - leftStartOffset.dy) * progress;
    final rightPulseX =
        rightStartOffset.dx +
        (rightEndOffset.dx - rightStartOffset.dx) * progress;
    final rightPulseY =
        rightStartOffset.dy +
        (rightEndOffset.dy - rightStartOffset.dy) * progress;

    if (cullAvailable) {
      _drawPulse(canvas, Offset(leftPulseX, leftPulseY), -1, pulseGlowPaint);
      _drawPulse(canvas, Offset(leftPulseX, leftPulseY), -1, pulsePaint);
    }
    if (appraiseAvailable) {
      _drawPulse(canvas, Offset(rightPulseX, rightPulseY), 1, pulseGlowPaint);
      _drawPulse(canvas, Offset(rightPulseX, rightPulseY), 1, pulsePaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final total = (end - start).distance;
    if (total <= 0) {
      return;
    }
    final direction = (end - start) / total;
    var distance = 0.0;
    const dash = 5.0;
    const gap = 7.0;
    while (distance < total) {
      final segmentStart = start + direction * distance;
      final segmentEnd = start + direction * math.min(distance + dash, total);
      canvas.drawLine(segmentStart, segmentEnd, paint);
      distance += dash + gap;
    }
  }

  void _drawPulse(Canvas canvas, Offset center, int direction, Paint paint) {
    const length = 16.0;
    canvas.drawLine(
      center,
      Offset(center.dx + length * direction, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IntentSealPathPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pull != pull ||
        oldDelegate.cullAvailable != cullAvailable ||
        oldDelegate.appraiseAvailable != appraiseAvailable ||
        oldDelegate.leftDashOffset != leftDashOffset ||
        oldDelegate.rightDashOffset != rightDashOffset ||
        oldDelegate.palette != palette;
  }
}

class _IntentMistPool extends StatelessWidget {
  const _IntentMistPool({
    required this.palette,
    required this.opacity,
    required this.leading,
  });

  final NoemaPalette palette;
  final double opacity;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: RadialGradient(
          center: leading ? Alignment.centerLeft : Alignment.centerRight,
          radius: 0.9,
          colors: [
            palette.ink.withValues(alpha: opacity * 0.18),
            palette.ink.withValues(alpha: 0),
          ],
        ),
      ),
      child: const SizedBox(height: 42),
    );
  }
}

class _IntentMistCue extends StatelessWidget {
  const _IntentMistCue({
    required this.palette,
    required this.leading,
    required this.activeBias,
  });

  final NoemaPalette palette;
  final bool leading;
  final double activeBias;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: RadialGradient(
                center: leading ? Alignment.centerLeft : Alignment.centerRight,
                radius: 0.82,
                colors: [
                  palette.ink.withValues(alpha: 0.13 + activeBias * 0.06),
                  palette.ink.withValues(alpha: 0.02),
                  palette.ink.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: leading ? Alignment.centerLeft : Alignment.centerRight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border(
                left: leading
                    ? BorderSide(
                        color: palette.ink.withValues(
                          alpha: 0.12 + activeBias * 0.08,
                        ),
                      )
                    : BorderSide.none,
                right: !leading
                    ? BorderSide(
                        color: palette.ink.withValues(
                          alpha: 0.12 + activeBias * 0.08,
                        ),
                      )
                    : BorderSide.none,
              ),
            ),
            child: const SizedBox(width: 42, height: 70),
          ),
        ),
      ],
    );
  }
}

class _IntentRippleCue extends StatelessWidget {
  const _IntentRippleCue({
    required this.palette,
    required this.leading,
    required this.activeBias,
  });

  final NoemaPalette palette;
  final bool leading;
  final double activeBias;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 7,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: RadialGradient(
                radius: 1.05,
                colors: [
                  palette.ink.withValues(alpha: 0.14 + activeBias * 0.08),
                  palette.ink.withValues(alpha: 0),
                ],
              ),
            ),
            child: const SizedBox(width: 64, height: 30),
          ),
        ),
        Positioned(
          left: leading ? 14 : null,
          right: leading ? null : 14,
          top: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.ink.withValues(alpha: 0.1 + activeBias * 0.08),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const SizedBox(width: 1, height: 28),
          ),
        ),
      ],
    );
  }
}

class _IntentSealCue extends StatefulWidget {
  const _IntentSealCue({
    required this.palette,
    required this.leading,
    required this.activeBias,
  });

  final NoemaPalette palette;
  final bool leading;
  final double activeBias;

  @override
  State<_IntentSealCue> createState() => _IntentSealCueState();
}

class _IntentSealCueState extends State<_IntentSealCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final edgePulse = phase < 0.76
            ? 0.0
            : math.sin(((phase - 0.76) / 0.24).clamp(0.0, 1.0) * math.pi);
        return CustomPaint(
          painter: _IntentSealCuePainter(
            palette: widget.palette,
            leading: widget.leading,
            activeBias: widget.activeBias,
            pulse: edgePulse,
          ),
        );
      },
    );
  }
}

class _IntentSealCuePainter extends CustomPainter {
  const _IntentSealCuePainter({
    required this.palette,
    required this.leading,
    required this.activeBias,
    required this.pulse,
  });

  final NoemaPalette palette;
  final bool leading;
  final double activeBias;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = 42 + activeBias * 48 + pulse * 12;
    final frameHeight = 56 + activeBias * 30 + pulse * 8;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: frameWidth.clamp(42.0, size.width),
      height: frameHeight.clamp(56.0, size.height),
    );
    final baseAlpha = 0.28 + activeBias * 0.16;
    final pulseAlpha = pulse * 0.16;
    final paint = Paint()
      ..color = palette.ink.withValues(alpha: baseAlpha + pulseAlpha)
      ..strokeWidth = 0.95
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = palette.ink.withValues(alpha: 0.02 + pulseAlpha * 0.18)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
    final hLength = 13 + activeBias * 12 + pulse * 10;
    final vLength = 11 + activeBias * 14 + pulse * 10;

    _drawCorners(canvas, rect, hLength, vLength, glowPaint);
    _drawCorners(canvas, rect, hLength, vLength, paint);
  }

  void _drawCorners(
    Canvas canvas,
    Rect rect,
    double hLength,
    double vLength,
    Paint paint,
  ) {
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(hLength, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, vLength), paint);
    canvas.drawLine(rect.topRight, rect.topRight - Offset(hLength, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, vLength), paint);
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(hLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft - Offset(0, vLength),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - Offset(hLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight - Offset(0, vLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IntentSealCuePainter oldDelegate) {
    return oldDelegate.palette != palette ||
        oldDelegate.leading != leading ||
        oldDelegate.activeBias != activeBias ||
        oldDelegate.pulse != pulse;
  }
}

class _IntentRegisterMark extends StatelessWidget {
  const _IntentRegisterMark({
    required this.palette,
    required this.opacity,
    required this.leading,
  });

  final NoemaPalette palette;
  final double opacity;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 32,
      child: Stack(
        children: [
          Positioned(
            left: leading ? 0 : null,
            right: leading ? null : 0,
            top: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  colors: [
                    palette.ink.withValues(alpha: opacity),
                    palette.ink.withValues(alpha: 0),
                  ],
                  begin: leading ? Alignment.centerLeft : Alignment.centerRight,
                  end: leading ? Alignment.centerRight : Alignment.centerLeft,
                ),
              ),
              child: const SizedBox(width: 34, height: 1),
            ),
          ),
          Positioned(
            left: leading ? 0 : null,
            right: leading ? null : 0,
            top: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: opacity * 0.72),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const SizedBox(width: 1, height: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectScanningTrace extends StatelessWidget {
  const _ObjectScanningTrace({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: LinearGradient(
          colors: [
            palette.ink.withValues(alpha: 0),
            palette.ink.withValues(alpha: 0.22),
            palette.ink.withValues(alpha: 0),
          ],
        ),
      ),
      child: const SizedBox(height: 1),
    );
  }
}

class _ObjectSignal extends StatelessWidget {
  const _ObjectSignal({
    required this.palette,
    required this.tooltip,
    required this.label,
    required this.kind,
  });

  final NoemaPalette palette;
  final String tooltip;
  final String label;
  final _ObjectSignalKind kind;

  @override
  Widget build(BuildContext context) {
    final labelFont = _fontForText(label) ?? 'NoemaLatin';
    final darkTone = palette.tone == NoemaTone.dark;

    return Tooltip(
      message: tooltip,
      textStyle: _tooltipTextStyle(palette, tooltip),
      decoration: _tooltipDecoration(palette),
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SizedBox(
            key: ValueKey(
              kind == _ObjectSignalKind.group
                  ? 'observe-experience-cull'
                  : 'observe-experience-appraise',
            ),
            width: 92,
            height: 62,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: palette.glass.withValues(
                      alpha: darkTone ? 0.2 : 0.54,
                    ),
                    border: Border.all(
                      color: palette.glassBorder.withValues(alpha: 0.46),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: darkTone ? 0.12 : 0.04,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (kind == _ObjectSignalKind.group)
                        Positioned(
                          left: 16,
                          child: _MiniPhotoCluster(palette: palette),
                        )
                      else
                        Positioned(
                          left: 17,
                          child: Transform.rotate(
                            angle: math.pi / 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: palette.ink.withValues(alpha: 0.38),
                                ),
                              ),
                              child: const SizedBox(width: 19, height: 19),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 18,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: palette.ink.withValues(alpha: 0.76),
                            fontFamily: labelFont,
                            fontSize: _containsCjk(label) ? 21 : 10,
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
      ),
    );
  }
}

class _MiniPhotoCluster extends StatelessWidget {
  const _MiniPhotoCluster({required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 32,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 9,
            child: _MiniPhotoTile(palette: palette, opacity: 0.3),
          ),
          Positioned(
            left: 7,
            top: 4,
            child: _MiniPhotoTile(palette: palette, opacity: 0.44),
          ),
          Positioned(
            left: 14,
            top: 0,
            child: _MiniPhotoTile(palette: palette, opacity: 0.58),
          ),
        ],
      ),
    );
  }
}

class _MiniPhotoTile extends StatelessWidget {
  const _MiniPhotoTile({required this.palette, required this.opacity});

  final NoemaPalette palette;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const SizedBox(width: 14, height: 22),
    );
  }
}

class _QuietMark extends StatelessWidget {
  const _QuietMark({
    required this.palette,
    required this.tooltip,
    required this.label,
    required this.valueKey,
  });

  final NoemaPalette palette;
  final String tooltip;
  final String label;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final labelFont = _fontForText(label) ?? 'NoemaLatin';

    return Tooltip(
      message: tooltip,
      textStyle: _tooltipTextStyle(palette, tooltip),
      decoration: _tooltipDecoration(palette),
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SizedBox(
            key: valueKey,
            width: 32,
            height: 32,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: palette.ink.withValues(alpha: 0.32),
                  fontFamily: labelFont,
                  fontSize: _containsCjk(label) ? 16 : 8,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceAction extends StatelessWidget {
  const _ExperienceAction({
    required this.palette,
    required this.tooltip,
    required this.label,
    required this.onPressed,
    required this.actionKey,
    this.cardSize = const Size(52, 68),
    this.hitSize = const Size(72, 78),
    this.cjkFontSize = 26,
    this.latinFontSize = 12,
    this.radius = 16,
    this.opacity = 1,
    this.glassScale = 1,
    this.strokeOpacity = 0.76,
    this.shadowScale = 1,
    this.motifOpacity = 1,
  });

  final NoemaPalette palette;
  final String tooltip;
  final String label;
  final VoidCallback onPressed;
  final Key actionKey;
  final Size cardSize;
  final Size hitSize;
  final double cjkFontSize;
  final double latinFontSize;
  final double radius;
  final double opacity;
  final double glassScale;
  final double strokeOpacity;
  final double shadowScale;
  final double motifOpacity;

  @override
  Widget build(BuildContext context) {
    return NoemaSquareActionButton(
      palette: palette,
      tooltip: tooltip,
      label: label,
      onPressed: onPressed,
      actionKey: actionKey,
      cardSize: cardSize,
      hitSize: hitSize,
      cjkFontSize: cjkFontSize,
      latinFontSize: latinFontSize,
      radius: radius,
      opacity: opacity,
      glassScale: glassScale,
      strokeOpacity: strokeOpacity,
      shadowScale: shadowScale,
      motifOpacity: motifOpacity,
    );
  }
}

class _ObserveIconButton extends StatelessWidget {
  const _ObserveIconButton({
    required this.palette,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.visualKey,
  });

  final NoemaPalette palette;
  final String tooltip;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Key? visualKey;

  @override
  Widget build(BuildContext context) {
    return NoemaGlassIconButton(
      palette: palette,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      visualKey: visualKey,
    );
  }
}

class _TimeSortIcon extends StatelessWidget {
  const _TimeSortIcon({required this.palette, required this.ascending});

  final NoemaPalette palette;
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, color: palette.ink, size: 16),
            Transform.translate(
              offset: const Offset(-1, 0),
              child: Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: palette.ink,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _densityIcon(ObserveWallDensity density) {
  return switch (density) {
    ObserveWallDensity.compact => Icons.grid_on_rounded,
    ObserveWallDensity.balanced => Icons.grid_view_rounded,
    ObserveWallDensity.spacious => Icons.view_comfy_alt_rounded,
  };
}

ObserveWallDensity _nextDensity(ObserveWallDensity density) {
  return switch (density) {
    ObserveWallDensity.compact => ObserveWallDensity.balanced,
    ObserveWallDensity.balanced => ObserveWallDensity.spacious,
    ObserveWallDensity.spacious => ObserveWallDensity.compact,
  };
}

ObserveWallDensity _largerDensity(ObserveWallDensity density) {
  return switch (density) {
    ObserveWallDensity.compact => ObserveWallDensity.balanced,
    ObserveWallDensity.balanced => ObserveWallDensity.spacious,
    ObserveWallDensity.spacious => ObserveWallDensity.spacious,
  };
}

ObserveWallDensity _smallerDensity(ObserveWallDensity density) {
  return switch (density) {
    ObserveWallDensity.compact => ObserveWallDensity.compact,
    ObserveWallDensity.balanced => ObserveWallDensity.compact,
    ObserveWallDensity.spacious => ObserveWallDensity.balanced,
  };
}

_ObserveTimeSort _observeTimeSortFromPreference(String value) {
  return switch (value) {
    'oldestFirst' => _ObserveTimeSort.oldestFirst,
    _ => _ObserveTimeSort.newestFirst,
  };
}

_ObserveSortMode _observeSortModeFromPreference(String value) {
  return switch (value) {
    'score' => _ObserveSortMode.score,
    _ => _ObserveSortMode.time,
  };
}

_ObserveScoreSort _observeScoreSortFromPreference(String value) {
  return switch (value) {
    'lowToHigh' => _ObserveScoreSort.lowToHigh,
    _ => _ObserveScoreSort.highToLow,
  };
}

_ObserveFilterMode _observeFilterModeFromPreference(String value) {
  return switch (value) {
    'cherished' => _ObserveFilterMode.cherished,
    _ => _ObserveFilterMode.all,
  };
}

ObserveWallDensity _observeDensityFromPreference(String value) {
  return switch (value) {
    'compact' => ObserveWallDensity.compact,
    'spacious' => ObserveWallDensity.spacious,
    _ => ObserveWallDensity.balanced,
  };
}

String _timeSortLabel(NoemaStrings strings, _ObserveTimeSort sort) {
  return switch (sort) {
    _ObserveTimeSort.newestFirst => strings.observeSortTimeDescending,
    _ObserveTimeSort.oldestFirst => strings.observeSortTimeAscending,
  };
}

String _scoreSortLabel(NoemaStrings strings, _ObserveScoreSort sort) {
  return switch (sort) {
    _ObserveScoreSort.highToLow =>
      strings.isZh ? '评分由高到低' : 'Score high to low',
    _ObserveScoreSort.lowToHigh =>
      strings.isZh ? '评分由低到高' : 'Score low to high',
  };
}

String _filterModeLabel(NoemaStrings strings, _ObserveFilterMode mode) {
  return switch (mode) {
    _ObserveFilterMode.all => strings.isZh ? '全部照片' : 'All photos',
    _ObserveFilterMode.cherished => strings.isZh ? '只看珍藏' : 'Cherished only',
  };
}

String _observeOptionsTooltip(
  NoemaStrings strings, {
  required _ObserveSortMode sortMode,
  required _ObserveTimeSort timeSort,
  required _ObserveScoreSort scoreSort,
  required _ObserveFilterMode filterMode,
  required ObserveWallDensity density,
}) {
  final sortLabel = sortMode == _ObserveSortMode.score
      ? _scoreSortLabel(strings, scoreSort)
      : _timeSortLabel(strings, timeSort);
  return strings.isZh
      ? '查看选项：$sortLabel，${_filterModeLabel(strings, filterMode)}，${_densityLabel(strings, density)}'
      : 'View options: $sortLabel, ${_filterModeLabel(strings, filterMode)}, ${_densityLabel(strings, density)}';
}

String _densityLabel(NoemaStrings strings, ObserveWallDensity density) {
  return switch (density) {
    ObserveWallDensity.compact => strings.observeDensityCompact,
    ObserveWallDensity.balanced => strings.observeDensityBalanced,
    ObserveWallDensity.spacious => strings.observeDensitySpacious,
  };
}

double _assetAspectRatio(ReviewAsset asset) {
  final width = asset.photo.width;
  final height = asset.photo.height;
  if (width <= 0 || height <= 0) {
    return 1;
  }
  return width / height;
}

TextStyle _tooltipTextStyle(NoemaPalette palette, String text) {
  return TextStyle(
    color: palette.ink,
    fontFamily: _fontForText(text),
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0,
  );
}

Decoration _tooltipDecoration(NoemaPalette palette) {
  return BoxDecoration(
    color: palette.sheet.withValues(
      alpha: palette.tone == NoemaTone.dark ? 0.94 : 0.98,
    ),
    border: Border.all(color: palette.glassBorder),
    borderRadius: BorderRadius.circular(8),
  );
}

String? _fontForText(String text) {
  return _containsCjk(text) ? 'LXGWWenKaiGB' : null;
}

bool _containsCjk(String text) {
  return text.runes.any((rune) => rune >= 0x4E00 && rune <= 0x9FFF);
}
