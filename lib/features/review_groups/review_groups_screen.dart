import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:image/image.dart' as img;
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/similar_group.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';
import 'package:noema/core/widgets/noema_remove_assets_dialog.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/import_image_source.dart';

const _cullEase = Cubic(0.16, 1, 0.3, 1);
const _cullStageTop = 62.0;
const _cullStageBottom = 72.0;
const _cullModeContentTop = 104.0;
const _cullModeContentBottom = 28.0;
const _cullUpperBoundaryFactor = 0.18;
const _cullLowerBoundaryFactor = 0.82;
const _modeLabelHeight = 58.0;
const _modeLabelBoundaryGap = 64.0;
const _fastTargetLabelCenterGap = 42.0;
const _fastDecisionQueueHeight = 58.0;
const _fastQueueIconWidth = 28.0;
const _fastQueueThumbSize = 48.0;
const _fastQueueThumbGap = 8.0;
const _fastQueueVisibleThumbs = 5;
const _fastQueueMaxStripWidth =
    _fastQueueThumbSize * _fastQueueVisibleThumbs +
    _fastQueueThumbGap * (_fastQueueVisibleThumbs - 1);
const _cullTriggerDragDistance = 112.0;
const _cullGroupSwitchDragDistance = 56.0;
const _cullProgressSealHeight = 26.0;
const _cullProgressSealCardGap = 14.0;
const _cullProgressSealBoundaryGap = 12.0;
const _cullPageIndicatorHeight = 18.0;
const _cullPageIndicatorCardGap = 12.0;
const _cullPageIndicatorBoundaryGap = 12.0;
const _fastCardExitDistance = 340.0;
const _fastCommitAnimationDuration = Duration(milliseconds: 280);
const _fastQueueShiftDuration = Duration(milliseconds: 300);
const _compareTriggerDragDistance = 72.0;
const _compareCardExitDistance = 210.0;
const _previewOpenEase = Cubic(0.18, 1, 0.22, 1);
const _comparePreviewOpenEase = Cubic(0.2, 0, 0, 1);
const _comparePreviewOpenDuration = Duration(milliseconds: 640);
const _singlePreviewOpenDuration = Duration(milliseconds: 460);
const _previewZoomDuration = Duration(milliseconds: 230);
const _singlePreviewMaxScale = 4.0;
const _singlePreviewMinInteractionScale = 0.82;
const _singlePreviewDismissScale = 0.96;
const _singlePreviewDoubleTapScale = 2.4;
const _compareLeftAccent = Color(0xFFBFDCE8);
const _compareRightAccent = Color(0xFFE7D1AA);
const _cullPageSwitchDuration = Duration(milliseconds: 430);
const _cullPageSwitchEase = Cubic(0.19, 1, 0.22, 1);

enum _CullStatus { keep, out, pending, revisit }

enum _CullMode { fast, compare }

enum _CullGroupReviewState { waiting, inProgress, complete }

void _playCullHapticFeedback() {
  unawaited(HapticFeedback.lightImpact());
}

class ReviewGroupsScreen extends StatefulWidget {
  const ReviewGroupsScreen({
    required this.workspaceController,
    super.key,
    this.appearanceController,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;

  @override
  State<ReviewGroupsScreen> createState() => _ReviewGroupsScreenState();
}

class _ReviewGroupsScreenState extends State<ReviewGroupsScreen> {
  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;
  final Map<String, _CullStatus> _statusOverrides = {};

  int _selectedIndex = 0;
  String? _initialSelectionWorkspaceId;
  bool _detailOpen = false;
  bool _clearConfirmOpen = false;
  bool _clearCompletedConfirmOpen = false;
  _CullMode? _activeMode;
  _CullPhotoView? _previewPhoto;
  Offset _dragOffset = Offset.zero;
  NoemaBackNavigationController? _backNavigationController;
  VoidCallback? _unregisterBackHandler;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    widget.workspaceController.addListener(_handleWorkspaceChanged);
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
    widget.workspaceController.removeListener(_handleWorkspaceChanged);
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
  }

  void _handleWorkspaceChanged() {
    if (mounted) {
      setState(() {
        final activePhotoIds = {
          for (final asset in widget.workspaceController.workspace.assets)
            asset.photo.id,
        };
        _statusOverrides.removeWhere(
          (photoId, _) => !activePhotoIds.contains(photoId),
        );
        final groups = _groupsFor(widget.workspaceController.workspace);
        if (_clearCompletedConfirmOpen && _completedOutPhotos(groups).isEmpty) {
          _clearCompletedConfirmOpen = false;
        }
      });
    }
  }

  bool _handleLocalBackIntent() {
    if (_previewPhoto != null) {
      setState(() => _previewPhoto = null);
      return true;
    }
    if (_clearCompletedConfirmOpen) {
      setState(() => _clearCompletedConfirmOpen = false);
      return true;
    }
    if (_clearConfirmOpen) {
      setState(() => _clearConfirmOpen = false);
      return true;
    }
    if (_detailOpen) {
      setState(() => _detailOpen = false);
      return true;
    }
    if (_activeMode != null) {
      setState(() => _activeMode = null);
      return true;
    }
    return false;
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
        final sceneLayout = NoemaSceneMetrics.layoutOf(context);
        final topBarTop = sceneLayout.topBarTop;
        final topShift = sceneLayout.topSafeShift;
        final workspace = widget.workspaceController.workspace;
        final groups = _groupsFor(workspace);
        final hasGroups = groups.isNotEmpty;
        if (_initialSelectionWorkspaceId != workspace.session.id) {
          _initialSelectionWorkspaceId = workspace.session.id;
          _selectedIndex = _preferredInitialGroupIndex(groups) ?? 0;
        }
        final selectedIndex = hasGroups
            ? _selectedIndex.clamp(0, groups.length - 1)
            : 0;
        if (selectedIndex != _selectedIndex) {
          _selectedIndex = selectedIndex;
        }
        final group = hasGroups ? groups[selectedIndex] : null;
        final completedOutPhotos = _completedOutPhotos(groups);
        final nextIncompleteIndex = hasGroups
            ? _nextIncompleteGroupIndex(groups, selectedIndex)
            : null;

        return PopScope<Object?>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _handleLocalBackIntent();
            }
          },
          child: Scaffold(
            body: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: NoemaSceneFrame(
                    palette: palette,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: sceneLayout.markLeft,
                          top: NoemaSceneMetrics.markTop,
                          child: NoemaThemeMark(palette: palette, mark: '甄'),
                        ),
                        Positioned(
                          left: sceneLayout.topBarInset,
                          right: sceneLayout.topBarInset,
                          top: topBarTop,
                          child: _CullTopBar(
                            palette: palette,
                            onBack: () => context.go(NoemaRoutes.observe),
                          ),
                        ),
                        Positioned(
                          left: sceneLayout.sideInset,
                          right: sceneLayout.sideInset,
                          top: _cullModeContentTop + topShift,
                          bottom: _cullModeContentBottom,
                          child: hasGroups
                              ? _CullHome(
                                  palette: palette,
                                  groups: groups,
                                  selectedIndex: selectedIndex,
                                  dragOffset: _dragOffset,
                                  onPageChanged: (index) {
                                    setState(() {
                                      _selectedIndex = index;
                                      _detailOpen = false;
                                      _clearConfirmOpen = false;
                                      _clearCompletedConfirmOpen = false;
                                    });
                                  },
                                  onTapGroup: () => setState(() {
                                    _detailOpen = true;
                                    _clearCompletedConfirmOpen = false;
                                  }),
                                  onDragUpdate: (delta) => setState(() {
                                    _dragOffset = Offset(
                                      (_dragOffset.dx + delta.dx)
                                          .clamp(-132, 132)
                                          .toDouble(),
                                      (_dragOffset.dy + delta.dy)
                                          .clamp(-178, 178)
                                          .toDouble(),
                                    );
                                  }),
                                  onDragCancel: () =>
                                      setState(() => _dragOffset = Offset.zero),
                                  onModeSelected: (mode) {
                                    setState(() {
                                      _activeMode = mode;
                                      _dragOffset = Offset.zero;
                                      _detailOpen = false;
                                      _clearCompletedConfirmOpen = false;
                                    });
                                  },
                                )
                              : _CullEmptyState(
                                  palette: palette,
                                  strings: strings,
                                ),
                        ),
                        if (group != null)
                          _CullDetailPanel(
                            palette: palette,
                            strings: strings,
                            group: group,
                            open: _detailOpen,
                            clearConfirmOpen: _clearConfirmOpen,
                            onClose: () => setState(() {
                              _detailOpen = false;
                              _clearConfirmOpen = false;
                              _clearCompletedConfirmOpen = false;
                            }),
                            onPreviewPhoto: (photo) => setState(() {
                              _previewPhoto = photo;
                              _clearConfirmOpen = false;
                              _clearCompletedConfirmOpen = false;
                            }),
                            onOpenClearConfirm: () =>
                                setState(() => _clearConfirmOpen = true),
                            onCloseClearConfirm: () =>
                                setState(() => _clearConfirmOpen = false),
                            onClearOutPhotos: (photos, choice) =>
                                _clearOutPhotos(photos, choice: choice),
                          ),
                        if (_activeMode != null && group != null)
                          _CullModeOverlay(
                            palette: palette,
                            strings: strings,
                            mode: _activeMode!,
                            group: group,
                            onClose: () => setState(() => _activeMode = null),
                            onOpenNextIncomplete: nextIncompleteIndex == null
                                ? null
                                : () => _openNextIncompleteGroup(
                                    nextIncompleteIndex,
                                  ),
                            onSetStatus: _setStatus,
                            onPreviewPhoto: (photo) => setState(() {
                              _previewPhoto = photo;
                              _clearConfirmOpen = false;
                              _clearCompletedConfirmOpen = false;
                            }),
                          ),
                        if (_previewPhoto != null)
                          _CullPreviewOverlay(
                            palette: palette,
                            photo: _previewPhoto!,
                            onClose: () => setState(() => _previewPhoto = null),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasGroups &&
                    _activeMode == null &&
                    !_detailOpen &&
                    _previewPhoto == null)
                  Positioned(
                    right: sceneLayout.sideInset,
                    top: NoemaSceneMetrics.bodyTop + 18,
                    height: NoemaSceneMetrics.topBarHeight,
                    child: Center(
                      child: NoemaGlassIconButton(
                        key: const ValueKey(
                          'review-groups-clear-completed-out-button',
                        ),
                        palette: palette,
                        tooltip: strings.cullClearCompletedOut,
                        icon: Icons.delete_outline_rounded,
                        onPressed: () => setState(() {
                          _clearCompletedConfirmOpen = true;
                          _clearConfirmOpen = false;
                          _detailOpen = false;
                          _previewPhoto = null;
                        }),
                      ),
                    ),
                  ),
                if (_clearCompletedConfirmOpen)
                  _CompletedOutConfirmOverlay(
                    palette: palette,
                    strings: strings,
                    photos: completedOutPhotos,
                    onCancel: () =>
                        setState(() => _clearCompletedConfirmOpen = false),
                    onConfirm: (choice) => _clearCompletedOutPhotos(
                      completedOutPhotos,
                      choice: choice,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_CullGroupView> _groupsFor(ReviewWorkspace workspace) {
    final groups = workspace.groups;
    if (groups.isEmpty) {
      if (kIsWeb && kDebugMode && workspace.assets.isEmpty) {
        return _sampleGroups();
      }
      return const [];
    }

    final visibleGroups = <_CullGroupView>[];
    for (final group in groups) {
      final groupIndex = visibleGroups.length;
      final photos = group.photoIds
          .map(workspace.assetById)
          .nonNulls
          .toList(growable: false)
          .asMap()
          .entries
          .map((photoEntry) {
            final asset = photoEntry.value;
            return _CullPhotoView(
              id: asset.photo.id,
              name: asset.displayName,
              asset: asset,
              status:
                  _statusOverrides[asset.photo.id] ??
                  _statusFromDecision(asset.photo.id),
              aspectRatio: _assetAspectRatio(asset.photo),
              seed: groupIndex * 17 + photoEntry.key,
            );
          })
          .toList(growable: false);
      if (photos.length < 2) {
        continue;
      }

      visibleGroups.add(
        _CullGroupView(
          id: group.id,
          title: _groupTitle(group.groupReason, groupIndex),
          photos: photos,
          seed: groupIndex,
        ),
      );
    }

    return visibleGroups;
  }

  double _assetAspectRatio(PhotoAsset asset) {
    if (asset.width > 0 && asset.height > 0) {
      return asset.width / asset.height;
    }
    return 1;
  }

  _CullStatus _statusFromDecision(String photoId) {
    final decision = widget.workspaceController.decisions[photoId]?.decision;
    return switch (decision) {
      Decision.keep => _CullStatus.keep,
      Decision.reviewForRemoval => _CullStatus.out,
      Decision.maybe => _CullStatus.revisit,
      null => _CullStatus.pending,
    };
  }

  String _groupTitle(GroupReason reason, int index) {
    final order = '${index + 1}'.padLeft(2, '0');
    return switch (reason) {
      GroupReason.burst => '连拍 $order',
      GroupReason.nearDuplicate => '相近 $order',
      GroupReason.timeCluster => '时刻 $order',
      GroupReason.needsAttention => '待看 $order',
    };
  }

  List<_CullGroupView> _sampleGroups() {
    const sizes = [5, 4, 7, 3, 6];
    return sizes
        .asMap()
        .entries
        .map((entry) {
          final groupIndex = entry.key;
          final count = entry.value;
          return _CullGroupView(
            id: 'sample-group-$groupIndex',
            title: '相近 ${(groupIndex + 1).toString().padLeft(2, '0')}',
            seed: groupIndex,
            photos: List.generate(count, (photoIndex) {
              final id = 'sample-$groupIndex-$photoIndex';
              return _CullPhotoView(
                id: id,
                name: 'Photo ${photoIndex + 1}',
                status: _statusOverrides[id] ?? _CullStatus.pending,
                aspectRatio:
                    _sampleAspectRatios[(groupIndex + photoIndex) %
                        _sampleAspectRatios.length],
                seed: groupIndex * 11 + photoIndex,
              );
            }),
          );
        })
        .toList(growable: false);
  }

  void _setStatus(_CullPhotoView photo, _CullStatus status) {
    setState(() => _statusOverrides[photo.id] = status);
    final decision = _decisionFromStatus(status);
    if (decision == null) {
      widget.workspaceController.clearDecision(photo.id);
    } else {
      widget.workspaceController.recordDecision(photo.id, decision);
    }
  }

  Decision? _decisionFromStatus(_CullStatus status) {
    return switch (status) {
      _CullStatus.keep => Decision.keep,
      _CullStatus.out => Decision.reviewForRemoval,
      _CullStatus.revisit => Decision.maybe,
      _CullStatus.pending => null,
    };
  }

  int? _nextIncompleteGroupIndex(List<_CullGroupView> groups, int fromIndex) {
    if (groups.length <= 1) {
      return null;
    }
    for (var offset = 1; offset < groups.length; offset += 1) {
      final index = (fromIndex + offset) % groups.length;
      if (groups[index].reviewState != _CullGroupReviewState.complete) {
        return index;
      }
    }
    return null;
  }

  int? _preferredInitialGroupIndex(List<_CullGroupView> groups) {
    for (var index = 0; index < groups.length; index += 1) {
      if (groups[index].reviewState == _CullGroupReviewState.inProgress) {
        return index;
      }
    }
    for (var index = 0; index < groups.length; index += 1) {
      if (groups[index].reviewState == _CullGroupReviewState.waiting) {
        return index;
      }
    }
    return groups.isEmpty ? null : 0;
  }

  void _openNextIncompleteGroup(int index) {
    setState(() {
      _selectedIndex = index;
      _detailOpen = false;
      _clearConfirmOpen = false;
      _clearCompletedConfirmOpen = false;
      _previewPhoto = null;
      _dragOffset = Offset.zero;
    });
  }

  List<_CullPhotoView> _completedOutPhotos(List<_CullGroupView> groups) {
    final photosById = <String, _CullPhotoView>{};
    for (final group in groups) {
      if (group.reviewState != _CullGroupReviewState.complete) {
        continue;
      }
      for (final photo in group.photos) {
        if (photo.status == _CullStatus.out) {
          photosById.putIfAbsent(photo.id, () => photo);
        }
      }
    }
    return photosById.values.toList(growable: false);
  }

  Future<void> _clearOutPhotos(
    List<_CullPhotoView> photos, {
    required NoemaRemoveChoice choice,
  }) async {
    final ids = {for (final photo in photos) photo.id};
    if (ids.isEmpty) {
      setState(() => _clearConfirmOpen = false);
      return;
    }
    final removed = await removeNoemaAssetsWithChoice(
      context: context,
      workspaceController: widget.workspaceController,
      photoIds: ids,
      choice: choice,
    );
    if (!removed || !mounted) {
      return;
    }
    setState(() {
      _clearConfirmOpen = false;
      _detailOpen = false;
      _clearCompletedConfirmOpen = false;
      _previewPhoto = null;
      _statusOverrides.removeWhere((photoId, _) => ids.contains(photoId));
    });
  }

  Future<void> _clearCompletedOutPhotos(
    List<_CullPhotoView> photos, {
    required NoemaRemoveChoice choice,
  }) async {
    final ids = {for (final photo in photos) photo.id};
    if (ids.isEmpty) {
      setState(() => _clearCompletedConfirmOpen = false);
      return;
    }
    final removed = await removeNoemaAssetsWithChoice(
      context: context,
      workspaceController: widget.workspaceController,
      photoIds: ids,
      choice: choice,
    );
    if (!removed || !mounted) {
      return;
    }
    setState(() {
      _clearCompletedConfirmOpen = false;
      _clearConfirmOpen = false;
      _detailOpen = false;
      _previewPhoto = null;
      _statusOverrides.removeWhere((photoId, _) => ids.contains(photoId));
    });
  }
}

class _CullGroupView {
  const _CullGroupView({
    required this.id,
    required this.title,
    required this.photos,
    required this.seed,
  });

  final String id;
  final String title;
  final List<_CullPhotoView> photos;
  final int seed;

  int get doneCount =>
      photos.where((photo) => photo.status != _CullStatus.pending).length;

  int get outCount =>
      photos.where((photo) => photo.status == _CullStatus.out).length;

  double get reviewProgress {
    if (photos.isEmpty) {
      return 0;
    }
    return doneCount / photos.length;
  }

  _CullGroupReviewState get reviewState {
    if (doneCount == 0) {
      return _CullGroupReviewState.waiting;
    }
    if (doneCount == photos.length) {
      return _CullGroupReviewState.complete;
    }
    return _CullGroupReviewState.inProgress;
  }
}

class _CullPhotoView {
  const _CullPhotoView({
    required this.id,
    required this.name,
    required this.status,
    required this.aspectRatio,
    required this.seed,
    this.asset,
  });

  final String id;
  final String name;
  final _CullStatus status;
  final double aspectRatio;
  final int seed;
  final ReviewAsset? asset;
}

const _sampleAspectRatios = [0.74, 1.46, 0.82, 1.62, 1.0, 0.68, 1.28];

class _CullTopBar extends StatelessWidget {
  const _CullTopBar({required this.palette, required this.onBack});

  final NoemaPalette palette;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NoemaSceneMetrics.topBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: NoemaGlassIconButton(
              palette: palette,
              tooltip: NoemaStrings.of(context).back,
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: onBack,
            ),
          ),
          NoemaWordmark(color: palette.ink),
        ],
      ),
    );
  }
}

class _CullEmptyState extends StatelessWidget {
  const _CullEmptyState({required this.palette, required this.strings});

  final NoemaPalette palette;
  final NoemaStrings strings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageHeight =
            constraints.maxHeight - _cullStageTop - _cullStageBottom;
        final upperBoundaryY =
            _cullStageTop + stageHeight * _cullUpperBoundaryFactor;
        final lowerBoundaryY =
            _cullStageTop + stageHeight * _cullLowerBoundaryFactor;
        final upperLabelTop =
            upperBoundaryY - _modeLabelBoundaryGap - _modeLabelHeight / 2;
        final lowerLabelTop =
            lowerBoundaryY + _modeLabelBoundaryGap - _modeLabelHeight / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: _cullStageTop,
              bottom: _cullStageBottom,
              child: _FloatingCullField(
                key: const ValueKey('review-group-floating-field'),
                palette: palette,
                upperBias: 0,
                lowerBias: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: upperLabelTop,
              height: _modeLabelHeight,
              child: _ModeLabel(
                palette: palette,
                text: strings.cullFastMode,
                activeBias: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: lowerLabelTop,
              height: _modeLabelHeight,
              child: _ModeLabel(
                palette: palette,
                text: strings.cullCompareMode,
                activeBias: 0,
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_motion_rounded,
                      color: palette.ink.withValues(alpha: 0.24),
                      size: 34,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.noCullGroups,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.ink.withValues(alpha: 0.56),
                        fontFamily: 'LXGWWenKaiGB',
                        fontFamilyFallback: const ['NoemaCjkFallback'],
                        fontSize: 14,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CullHome extends StatefulWidget {
  const _CullHome({
    required this.palette,
    required this.groups,
    required this.selectedIndex,
    required this.dragOffset,
    required this.onPageChanged,
    required this.onTapGroup,
    required this.onDragUpdate,
    required this.onDragCancel,
    required this.onModeSelected,
  });

  final NoemaPalette palette;
  final List<_CullGroupView> groups;
  final int selectedIndex;
  final Offset dragOffset;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapGroup;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragCancel;
  final ValueChanged<_CullMode> onModeSelected;

  @override
  State<_CullHome> createState() => _CullHomeState();
}

class _CullHomeState extends State<_CullHome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pageSwitchController;
  late final Animation<double> _pageSwitchProgress;
  int? _previousSelectedIndex;
  int _switchDirection = 1;
  Offset _gestureDragOffset = Offset.zero;
  _CullMode? _modeFeedbackTarget;

  @override
  void initState() {
    super.initState();
    _pageSwitchController = AnimationController(
      vsync: this,
      duration: _cullPageSwitchDuration,
    );
    _pageSwitchProgress = CurvedAnimation(
      parent: _pageSwitchController,
      curve: _cullPageSwitchEase,
    );
    _pageSwitchController.addListener(() => setState(() {}));
    _pageSwitchController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _previousSelectedIndex = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CullHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dragOffset == Offset.zero &&
        oldWidget.dragOffset != Offset.zero) {
      _gestureDragOffset = Offset.zero;
      _modeFeedbackTarget = null;
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _previousSelectedIndex = oldWidget.selectedIndex;
      _switchDirection = widget.selectedIndex > oldWidget.selectedIndex
          ? 1
          : -1;
      _pageSwitchController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pageSwitchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final upperBias = math
        .max(0.0, -widget.dragOffset.dy / 142)
        .clamp(0.0, 1.0)
        .toDouble();
    final lowerBias = math
        .max(0.0, widget.dragOffset.dy / 142)
        .clamp(0.0, 1.0)
        .toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageHeight =
            constraints.maxHeight - _cullStageTop - _cullStageBottom;
        final upperBoundaryY =
            _cullStageTop + stageHeight * _cullUpperBoundaryFactor;
        final lowerBoundaryY =
            _cullStageTop + stageHeight * _cullLowerBoundaryFactor;
        final upperLabelTop =
            upperBoundaryY - _modeLabelBoundaryGap - _modeLabelHeight / 2;
        final lowerLabelTop =
            lowerBoundaryY + _modeLabelBoundaryGap - _modeLabelHeight / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: upperLabelTop,
              height: _modeLabelHeight,
              child: _ModeLabel(
                palette: widget.palette,
                text: strings.cullFastMode,
                activeBias: upperBias,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: lowerLabelTop,
              height: _modeLabelHeight,
              child: _ModeLabel(
                palette: widget.palette,
                text: strings.cullCompareMode,
                activeBias: lowerBias,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _cullStageTop,
              bottom: _cullStageBottom,
              child: _FloatingCullStage(
                palette: widget.palette,
                groups: widget.groups,
                selectedIndex: widget.selectedIndex,
                dragOffset: widget.dragOffset,
                upperBias: upperBias,
                lowerBias: lowerBias,
                previousIndex: reduceMotion ? null : _previousSelectedIndex,
                switchDirection: _switchDirection,
                switchProgress: reduceMotion ? 1 : _pageSwitchProgress.value,
                onTapGroup: widget.onTapGroup,
                onDragUpdate: _handleDragUpdate,
                onDragEnd: _settleDrag,
                onDragCancel: _cancelDrag,
                onPreviousGroup: widget.selectedIndex > 0
                    ? () => _switchGroupFromEdge(-1)
                    : null,
                onNextGroup: widget.selectedIndex < widget.groups.length - 1
                    ? () => _switchGroupFromEdge(1)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleDragUpdate(Offset delta) {
    _gestureDragOffset += delta;
    _updateModeFeedback(_modeTargetForOffset(_gestureDragOffset));
    widget.onDragUpdate(delta);
  }

  void _cancelDrag() {
    _gestureDragOffset = Offset.zero;
    _modeFeedbackTarget = null;
    widget.onDragCancel();
  }

  void _settleDrag() {
    final dragOffset = _gestureDragOffset.distance >= widget.dragOffset.distance
        ? _gestureDragOffset
        : widget.dragOffset;
    final horizontalIntent = dragOffset.dx.abs() > dragOffset.dy.abs() * 1.18;
    _gestureDragOffset = Offset.zero;
    _modeFeedbackTarget = null;
    if (dragOffset.dy < -_cullTriggerDragDistance) {
      widget.onModeSelected(_CullMode.fast);
    } else if (dragOffset.dy > _cullTriggerDragDistance) {
      widget.onModeSelected(_CullMode.compare);
    } else if (horizontalIntent &&
        dragOffset.dx > _cullGroupSwitchDragDistance &&
        widget.selectedIndex > 0) {
      widget.onPageChanged(widget.selectedIndex - 1);
      widget.onDragCancel();
    } else if (horizontalIntent &&
        dragOffset.dx < -_cullGroupSwitchDragDistance &&
        widget.selectedIndex < widget.groups.length - 1) {
      widget.onPageChanged(widget.selectedIndex + 1);
      widget.onDragCancel();
    } else {
      widget.onDragCancel();
    }
  }

  void _switchGroupFromEdge(int delta) {
    final nextIndex = widget.selectedIndex + delta;
    if (nextIndex < 0 || nextIndex >= widget.groups.length) {
      return;
    }
    widget.onPageChanged(nextIndex);
    widget.onDragCancel();
  }

  _CullMode? _modeTargetForOffset(Offset offset) {
    if (offset.dy < -_cullTriggerDragDistance) {
      return _CullMode.fast;
    }
    if (offset.dy > _cullTriggerDragDistance) {
      return _CullMode.compare;
    }
    return null;
  }

  void _updateModeFeedback(_CullMode? target) {
    if (target == _modeFeedbackTarget) {
      return;
    }
    _modeFeedbackTarget = target;
    if (target != null) {
      _playCullHapticFeedback();
    }
  }
}

class _FloatingCullStage extends StatelessWidget {
  const _FloatingCullStage({
    required this.palette,
    required this.groups,
    required this.selectedIndex,
    required this.dragOffset,
    required this.upperBias,
    required this.lowerBias,
    required this.previousIndex,
    required this.switchDirection,
    required this.switchProgress,
    required this.onTapGroup,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onPreviousGroup,
    required this.onNextGroup,
  });

  final NoemaPalette palette;
  final List<_CullGroupView> groups;
  final int selectedIndex;
  final Offset dragOffset;
  final double upperBias;
  final double lowerBias;
  final int? previousIndex;
  final int switchDirection;
  final double switchProgress;
  final VoidCallback onTapGroup;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final VoidCallback? onPreviousGroup;
  final VoidCallback? onNextGroup;

  @override
  Widget build(BuildContext context) {
    final selected = groups[selectedIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerX = width / 2;
        final centerY = height / 2 + 4;
        final upperBoundaryY = height * _cullUpperBoundaryFactor;
        final lowerBoundaryY = height * _cullLowerBoundaryFactor;
        Size frameSizeFor(_CullGroupView group) {
          final cover = group.photos.firstOrNull;
          return _floatingFrameSize(
            cover?.aspectRatio ?? 0.78,
            constraints.biggest,
          );
        }

        final frameSize = frameSizeFor(selected);
        final switching =
            previousIndex != null &&
            previousIndex != selectedIndex &&
            previousIndex! >= 0 &&
            previousIndex! < groups.length &&
            switchProgress < 1;
        final previous = switching ? groups[previousIndex!] : null;
        final switchDistance = math.min(
          width * 0.42,
          math.max(96.0, frameSize.width * 0.78 + 28),
        );
        final dragging = dragOffset.distance > 0.5;
        final triggerBias =
            ((dragOffset.dy.abs() - _cullTriggerDragDistance) / 44)
                .clamp(0.0, 1.0)
                .toDouble();
        final cardTop = centerY - frameSize.height / 2;
        final cardBottom = centerY + frameSize.height / 2;
        final progressSealTop = _floatingControlTop(
          preferredTop:
              cardTop - _cullProgressSealHeight - _cullProgressSealCardGap,
          minTop: upperBoundaryY + _cullProgressSealBoundaryGap,
          maxTop: cardTop - _cullProgressSealHeight - 8,
          stageHeight: height,
          controlHeight: _cullProgressSealHeight,
        );
        final pageIndicatorTop = _floatingControlTop(
          preferredTop: cardBottom + _cullPageIndicatorCardGap,
          minTop: cardBottom + 8,
          maxTop:
              lowerBoundaryY -
              _cullPageIndicatorHeight -
              _cullPageIndicatorBoundaryGap,
          stageHeight: height,
          controlHeight: _cullPageIndicatorHeight,
        );

        Widget cardLayer({
          required _CullGroupView group,
          required Size localFrameSize,
          required Offset switchOffset,
          required double switchRotation,
          required double switchScale,
          required double opacity,
          required bool interactive,
        }) {
          final cardWidth = math.max(localFrameSize.width, 118.0);
          final rotation =
              (dragOffset.dx / 260).clamp(-0.055, 0.055).toDouble() +
              (dragOffset.dy / 420).clamp(-0.018, 0.018).toDouble() +
              switchRotation;
          final effectiveOffset = dragOffset + switchOffset;
          final card = _SealGroupCard(
            palette: palette,
            group: group,
            selected: true,
            frameSize: localFrameSize,
            triggerBias: triggerBias,
          );
          final content = Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(
              scale: switchScale,
              child: IgnorePointer(
                ignoring: !interactive,
                child: GestureDetector(
                  key: ValueKey('review-group-card-${group.id}'),
                  behavior: HitTestBehavior.translucent,
                  onTap: onTapGroup,
                  onPanUpdate: (details) => onDragUpdate(details.delta),
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: onDragCancel,
                  child: card,
                ),
              ),
            ),
          );

          return Positioned(
            key: ValueKey('review-group-layer-${group.id}'),
            left: centerX - cardWidth / 2,
            top: centerY - localFrameSize.height / 2,
            child: AnimatedContainer(
              duration: dragging || switching
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: _cullEase,
              transform: Matrix4.identity()
                ..translateByDouble(
                  effectiveOffset.dx,
                  effectiveOffset.dy,
                  0,
                  1,
                )
                ..rotateZ(rotation),
              transformAlignment: Alignment.center,
              child: content,
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _FloatingCullField(
                key: const ValueKey('review-group-floating-field'),
                palette: palette,
                upperBias: upperBias,
                lowerBias: lowerBias,
              ),
            ),
            Positioned.fill(
              child: _CullEdgeSwitchZones(
                palette: palette,
                onPrevious: onPreviousGroup,
                onNext: onNextGroup,
              ),
            ),
            if (selectedIndex > 0)
              Positioned(
                left: -frameSize.width * 0.16 + dragOffset.dx * 0.1,
                top: centerY - frameSize.height * 0.36,
                child: _NeighborGhost(
                  palette: palette,
                  group: groups[selectedIndex - 1],
                  baseSize: frameSize,
                  side: -1,
                  opacity: switching ? 0.24 : 0.36,
                ),
              ),
            if (selectedIndex < groups.length - 1)
              Positioned(
                right: -frameSize.width * 0.16 - dragOffset.dx * 0.1,
                top: centerY - frameSize.height * 0.36,
                child: _NeighborGhost(
                  palette: palette,
                  group: groups[selectedIndex + 1],
                  baseSize: frameSize,
                  side: 1,
                  opacity: switching ? 0.24 : 0.36,
                ),
              ),
            if (previous != null)
              cardLayer(
                group: previous,
                localFrameSize: frameSizeFor(previous),
                switchOffset: Offset(
                  -switchDirection * switchDistance * switchProgress,
                  0,
                ),
                switchRotation: -switchDirection * 0.055 * switchProgress,
                switchScale: 1 - 0.055 * switchProgress,
                opacity: 1 - switchProgress,
                interactive: false,
              ),
            cardLayer(
              group: selected,
              localFrameSize: frameSize,
              switchOffset: switching
                  ? Offset(
                      switchDirection * switchDistance * (1 - switchProgress),
                      0,
                    )
                  : Offset.zero,
              switchRotation: switching
                  ? switchDirection * 0.055 * (1 - switchProgress)
                  : 0,
              switchScale: switching ? 0.94 + 0.06 * switchProgress : 1,
              opacity: switching ? 0.72 + 0.28 * switchProgress : 1,
              interactive: !switching || switchProgress > 0.72,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: progressSealTop,
              height: _cullProgressSealHeight,
              child: IgnorePointer(
                child: Center(
                  key: const ValueKey('review-group-progress-seal'),
                  child: _CullGroupProgressSeal(
                    palette: palette,
                    group: selected,
                    selected: true,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: pageIndicatorTop,
              height: _cullPageIndicatorHeight,
              child: IgnorePointer(
                child: _CullGroupPageIndicator(
                  palette: palette,
                  groups: groups,
                  selectedIndex: selectedIndex,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CullEdgeSwitchZones extends StatelessWidget {
  const _CullEdgeSwitchZones({
    required this.palette,
    required this.onPrevious,
    required this.onNext,
  });

  final NoemaPalette palette;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CullEdgeSwitchZone(
          key: const ValueKey('review-group-edge-previous'),
          palette: palette,
          alignment: Alignment.centerLeft,
          enabled: onPrevious != null,
          onTap: onPrevious,
        ),
        const Spacer(),
        _CullEdgeSwitchZone(
          key: const ValueKey('review-group-edge-next'),
          palette: palette,
          alignment: Alignment.centerRight,
          enabled: onNext != null,
          onTap: onNext,
        ),
      ],
    );
  }
}

double _floatingControlTop({
  required double preferredTop,
  required double minTop,
  required double maxTop,
  required double stageHeight,
  required double controlHeight,
}) {
  final safeTop = math.max(0.0, stageHeight - controlHeight);
  if (minTop <= maxTop) {
    return preferredTop.clamp(minTop, maxTop).clamp(0.0, safeTop).toDouble();
  }
  return preferredTop.clamp(0.0, safeTop).toDouble();
}

class _CullEdgeSwitchZone extends StatelessWidget {
  const _CullEdgeSwitchZone({
    super.key,
    required this.palette,
    required this.alignment,
    required this.enabled,
    required this.onTap,
  });

  final NoemaPalette palette;
  final Alignment alignment;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final right = alignment.x > 0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 62,
        height: double.infinity,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0,
          child: Align(
            alignment: alignment,
            child: Container(
              width: 34,
              height: 118,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: right ? Alignment.centerRight : Alignment.centerLeft,
                  end: right ? Alignment.centerLeft : Alignment.centerRight,
                  colors: [
                    palette.glass.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(right ? 18 : 0),
                  right: Radius.circular(right ? 0 : 18),
                ),
              ),
              child: Icon(
                right
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 23,
                color: palette.ink.withValues(alpha: 0.28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingCullField extends StatelessWidget {
  const _FloatingCullField({
    required this.palette,
    required this.upperBias,
    required this.lowerBias,
    super.key,
  });

  final NoemaPalette palette;
  final double upperBias;
  final double lowerBias;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FloatingFieldPainter(
        palette: palette,
        upperBias: upperBias,
        lowerBias: lowerBias,
      ),
    );
  }
}

class _FloatingFieldPainter extends CustomPainter {
  const _FloatingFieldPainter({
    required this.palette,
    required this.upperBias,
    required this.lowerBias,
  });

  final NoemaPalette palette;
  final double upperBias;
  final double lowerBias;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBoundary(canvas, size, top: true, bias: upperBias);
    _drawBoundary(canvas, size, top: false, bias: lowerBias);
  }

  void _drawBoundary(
    Canvas canvas,
    Size size, {
    required bool top,
    required double bias,
  }) {
    final y =
        size.height *
        (top ? _cullUpperBoundaryFactor : _cullLowerBoundaryFactor);
    final bend = size.height * 0.04 * (top ? 1 : -1);
    final path = Path()
      ..moveTo(-size.width * 0.08, y)
      ..quadraticBezierTo(size.width / 2, y + bend, size.width * 1.08, y);
    final washPath = Path.from(path)
      ..lineTo(size.width * 1.08, top ? -20 : size.height + 20)
      ..lineTo(-size.width * 0.08, top ? -20 : size.height + 20)
      ..close();
    final washRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final fill = Paint()
      ..shader = ui.Gradient.linear(
        top ? washRect.topCenter : washRect.bottomCenter,
        top
            ? Offset(size.width / 2, y + bend)
            : Offset(size.width / 2, y + bend),
        [
          palette.glass.withValues(alpha: 0.045 + bias * 0.08),
          palette.glass.withValues(alpha: 0.012 + bias * 0.025),
          Colors.transparent,
        ],
        [0, 0.68, 1],
      );
    canvas.drawPath(washPath, fill);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9 + bias * 5
      ..color = palette.ink.withValues(alpha: 0.026 + bias * 0.052);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1 + bias * 0.55
      ..shader = ui.Gradient.linear(
        Offset(0, y),
        Offset(size.width, y),
        [
          Colors.transparent,
          palette.ink.withValues(alpha: 0.105 + bias * 0.2),
          palette.ink.withValues(alpha: 0.13 + bias * 0.26),
          palette.ink.withValues(alpha: 0.105 + bias * 0.2),
          Colors.transparent,
        ],
        [0, 0.22, 0.5, 0.78, 1],
      );

    canvas.drawPath(path, glow);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _FloatingFieldPainter oldDelegate) {
    return oldDelegate.palette != palette ||
        oldDelegate.upperBias != upperBias ||
        oldDelegate.lowerBias != lowerBias;
  }
}

class _NeighborGhost extends StatelessWidget {
  const _NeighborGhost({
    required this.palette,
    required this.group,
    required this.baseSize,
    required this.side,
    required this.opacity,
  });

  final NoemaPalette palette;
  final _CullGroupView group;
  final Size baseSize;
  final int side;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final cover = group.photos.firstOrNull;
    final width = math.max(54.0, baseSize.width * 0.58);
    final height = math.max(72.0, baseSize.height * 0.62);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.rotate(
          angle: side * 0.025,
          child: SizedBox(
            key: ValueKey('review-group-neighbor-${group.id}'),
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: cover == null
                        ? _CullPhotoFallback(
                            palette: palette,
                            seed: group.seed,
                            name: '',
                          )
                        : _CullPhotoImage(
                            palette: palette,
                            photo: cover,
                            fit: BoxFit.contain,
                            cacheHeadroom: 1.35,
                            cacheMaxExtent: 1200,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.sheet.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: palette.ink.withValues(alpha: 0.34),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: side > 0 ? 8 : null,
                  left: side < 0 ? 8 : null,
                  child: _CountBadge(
                    palette: palette,
                    count: group.photos.length,
                    compact: true,
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

Size _floatingFrameSize(double aspectRatio, Size viewport) {
  final ratio = aspectRatio.clamp(0.54, 1.78).toDouble();
  final maxWidth = math.min(228.0, viewport.width * 0.7);
  final maxHeight = math.min(238.0, viewport.height * 0.58);
  if (ratio >= 1.14) {
    final width = maxWidth;
    final height = _clampFrameDimension(width / ratio, 118.0, maxHeight);
    return Size(width, height);
  }
  if (ratio <= 0.86) {
    final height = maxHeight;
    final width = _clampFrameDimension(height * ratio, 126.0, maxWidth);
    return Size(width, height);
  }
  final side = math.min(188.0, math.min(maxWidth, maxHeight));
  return Size(side, side);
}

double _clampFrameDimension(double value, double min, double max) {
  final safeMax = math.max(0.0, max);
  if (safeMax < min) {
    return safeMax;
  }
  return value.clamp(min, safeMax).toDouble();
}

class _ModeLabel extends StatefulWidget {
  const _ModeLabel({
    required this.palette,
    required this.text,
    required this.activeBias,
    super.key,
    this.activeShiftY,
  });

  final NoemaPalette palette;
  final String text;
  final double activeBias;
  final double? activeShiftY;

  @override
  State<_ModeLabel> createState() => _ModeLabelState();
}

class _ModeLabelState extends State<_ModeLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shineController;

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bias = widget.activeBias.clamp(0.0, 1.0).toDouble();
    final baseColor = widget.palette.ink.withValues(alpha: 0.4 + bias * 0.18);
    final shineColor = Color.lerp(
      widget.palette.ink,
      Colors.white,
      0.82,
    )!.withValues(alpha: 0.98);
    final glowColor = widget.palette.ink.withValues(alpha: 0.18 + bias * 0.18);
    final textStyle = TextStyle(
      color: baseColor,
      fontFamily: 'LXGWWenKaiGB',
      fontFamilyFallback: const ['NoemaCjkFallback'],
      fontSize: 38,
      height: 1,
      letterSpacing: 0,
    );
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: 0.78 + bias * 0.2,
        child: Transform.translate(
          offset: Offset(
            0,
            bias * (widget.activeShiftY ?? (widget.text.length > 2 ? -5 : 5)),
          ),
          child: Transform.scale(
            scale: 1 + bias * 0.045,
            child: RepaintBoundary(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      widget.text,
                      style: textStyle.copyWith(
                        color: glowColor,
                        shadows: [
                          Shadow(color: glowColor, blurRadius: 18 + bias * 8),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _shineController,
                      builder: (context, child) {
                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (rect) {
                            final sweep = rect.width * 1.28;
                            final dx =
                                rect.left -
                                sweep +
                                (rect.width + sweep * 2) *
                                    _shineController.value;
                            return ui.Gradient.linear(
                              Offset(dx, rect.top),
                              Offset(dx + sweep, rect.bottom),
                              [
                                baseColor,
                                baseColor,
                                shineColor,
                                baseColor,
                                baseColor,
                              ],
                              const [0, 0.32, 0.5, 0.68, 1],
                            );
                          },
                          child: child,
                        );
                      },
                      child: Text(widget.text, style: textStyle),
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

class _SealGroupCard extends StatelessWidget {
  const _SealGroupCard({
    required this.palette,
    required this.group,
    required this.selected,
    required this.frameSize,
    required this.triggerBias,
  });

  final NoemaPalette palette;
  final _CullGroupView group;
  final bool selected;
  final Size frameSize;
  final double triggerBias;

  @override
  Widget build(BuildContext context) {
    final cover = group.photos.firstOrNull;
    final cardWidth = math.max(frameSize.width, 118.0);
    final armed = triggerBias > 0;
    final glowAlpha = triggerBias.clamp(0.0, 1.0).toDouble();
    final glowColor = Color.lerp(palette.ink, Colors.white, 0.72)!;
    return SizedBox(
      width: cardWidth,
      child: SizedBox(
        width: frameSize.width,
        height: frameSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: selected ? 0.34 : 0.16,
                      ),
                      blurRadius: selected ? 42 : 24,
                      offset: const Offset(0, 20),
                    ),
                    if (armed)
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.18 * glowAlpha),
                        blurRadius: 26 + glowAlpha * 18,
                        spreadRadius: 1.5 + glowAlpha * 2.5,
                      ),
                    if (armed)
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.11 * glowAlpha),
                        blurRadius: 52,
                        spreadRadius: 8,
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover == null
                      ? _CullPhotoFallback(
                          palette: palette,
                          seed: group.seed,
                          name: group.title,
                        )
                      : _CullPhotoImage(
                          palette: palette,
                          photo: cover,
                          fit: BoxFit.contain,
                          cacheHeadroom: 1.6,
                          cacheMaxExtent: 1600,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.glass.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.22),
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(
                      palette.ink.withValues(alpha: selected ? 0.42 : 0.2),
                      glowColor.withValues(alpha: 0.9),
                      glowAlpha,
                    )!,
                    width: 1 + glowAlpha * 1.2,
                  ),
                ),
              ),
            ),
            if (armed)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SealTriggerGlowPainter(
                      color: glowColor.withValues(alpha: 0.62 * glowAlpha),
                      progress: glowAlpha,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 9,
              right: 9,
              child: _CountBadge(palette: palette, count: group.photos.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _SealTriggerGlowPainter extends CustomPainter {
  const _SealTriggerGlowPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 + progress * 5
      ..color = color.withValues(alpha: 0.14 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2 + progress
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          Colors.transparent,
          color.withValues(alpha: 0.34 * progress),
          color,
          color.withValues(alpha: 0.34 * progress),
          Colors.transparent,
        ],
        const [0, 0.25, 0.5, 0.75, 1],
      );

    canvas.drawRRect(rrect, halo);
    canvas.drawRRect(rrect, edge);
  }

  @override
  bool shouldRepaint(covariant _SealTriggerGlowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.progress != progress;
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.palette,
    required this.count,
    this.compact = false,
  });

  final NoemaPalette palette;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badgeSize = compact ? const Size(36, 21) : const Size(52, 28);
    final radius = compact ? 7.0 : 10.0;
    return Semantics(
      label: '$count 张照片',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sheet.withValues(alpha: compact ? 0.56 : 0.68),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: palette.ink.withValues(alpha: compact ? 0.16 : 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: compact ? 0.08 : 0.18),
              blurRadius: compact ? 8 : 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: badgeSize.width,
          height: badgeSize.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: Size(compact ? 9.5 : 12, compact ? 10.5 : 13),
                painter: _PhotoStackGlyphPainter(palette: palette),
              ),
              SizedBox(width: compact ? 3 : 4),
              Text(
                '$count',
                style: TextStyle(
                  color: palette.ink.withValues(alpha: 0.88),
                  fontFamily: 'LXGWWenKaiGB',
                  fontFamilyFallback: const ['NoemaCjkFallback'],
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  fontSize: compact ? 11.5 : 15,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoStackGlyphPainter extends CustomPainter {
  const _PhotoStackGlyphPainter({required this.palette});

  final NoemaPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.0;
    final inset = strokeWidth / 2;
    final glyphSize = Size(
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );
    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset + glyphSize.width * 0.2,
        inset,
        glyphSize.width * 0.7,
        glyphSize.height * 0.72,
      ),
      const Radius.circular(2),
    );
    final front = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset + glyphSize.height * 0.24,
        glyphSize.width * 0.78,
        glyphSize.height * 0.72,
      ),
      const Radius.circular(2),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = palette.ink.withValues(alpha: 0.44);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.ink.withValues(alpha: 0.08);

    canvas.drawRRect(back, stroke);
    canvas.drawRRect(front, fill);
    canvas.drawRRect(front, stroke);
  }

  @override
  bool shouldRepaint(covariant _PhotoStackGlyphPainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class _CullGroupProgressSeal extends StatelessWidget {
  const _CullGroupProgressSeal({
    required this.palette,
    required this.group,
    required this.selected,
  });

  final NoemaPalette palette;
  final _CullGroupView group;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final progress = group.reviewProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    final alpha = selected ? 0.88 : 0.48;
    final icon = switch (group.reviewState) {
      _CullGroupReviewState.waiting => Icons.hourglass_empty_rounded,
      _CullGroupReviewState.inProgress => Icons.autorenew_rounded,
      _CullGroupReviewState.complete => Icons.check_rounded,
    };
    final semanticLabel = switch (group.reviewState) {
      _CullGroupReviewState.waiting => '待甄',
      _CullGroupReviewState.inProgress => '甄选中',
      _CullGroupReviewState.complete => '已完成',
    };

    return Semantics(
      label: '$semanticLabel $percent%',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ReviewProgressRing(
            palette: palette,
            progress: progress,
            icon: icon,
            alpha: alpha,
          ),
          if (group.doneCount > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$percent%',
              style: TextStyle(
                color: palette.ink.withValues(alpha: alpha),
                fontFamily: 'LXGWWenKaiGB',
                fontFamilyFallback: const ['NoemaCjkFallback'],
                fontFeatures: const [ui.FontFeature.tabularFigures()],
                fontSize: selected ? 15 : 12,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewProgressRing extends StatelessWidget {
  const _ReviewProgressRing({
    required this.palette,
    required this.progress,
    required this.icon,
    required this.alpha,
  });

  final NoemaPalette palette;
  final double progress;
  final IconData icon;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(26),
            painter: _ReviewProgressRingPainter(
              palette: palette,
              progress: progress,
              alpha: alpha,
            ),
          ),
          Icon(
            icon,
            size: 12,
            color: palette.ink.withValues(alpha: alpha * 0.92),
          ),
        ],
      ),
    );
  }
}

class _ReviewProgressRingPainter extends CustomPainter {
  const _ReviewProgressRingPainter({
    required this.palette,
    required this.progress,
    required this.alpha,
  });

  final NoemaPalette palette;
  final double progress;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 1.35;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = palette.ink.withValues(alpha: alpha * 0.18);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 0.35
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.sweep(
        rect.center,
        [
          palette.ink.withValues(alpha: 0.3 * alpha),
          Colors.white.withValues(alpha: 0.82 * alpha),
          palette.ink.withValues(alpha: 0.38 * alpha),
        ],
        const [0, 0.62, 1],
      );

    canvas.drawOval(arcRect, base);
    if (progress > 0) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        active,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReviewProgressRingPainter oldDelegate) {
    return oldDelegate.palette != palette ||
        oldDelegate.progress != progress ||
        oldDelegate.alpha != alpha;
  }
}

class _CullGroupPageIndicator extends StatelessWidget {
  const _CullGroupPageIndicator({
    required this.palette,
    required this.groups,
    required this.selectedIndex,
  });

  final NoemaPalette palette;
  final List<_CullGroupView> groups;
  final int selectedIndex;

  static const _slotCount = 7;
  static const _centerSlot = 3;
  static const _slotWidth = 18.0;
  static const _slotGap = 6.0;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }
    final safeSelectedIndex = selectedIndex.clamp(0, groups.length - 1).toInt();
    final slots = _indicatorSlots(safeSelectedIndex);
    return Center(
      child: SizedBox(
        key: const ValueKey('review-group-page-indicator-window'),
        width: _slotCount * _slotWidth + (_slotCount - 1) * _slotGap,
        height: 18,
        child: Row(
          key: const ValueKey('review-group-page-indicator'),
          children: [
            for (final entry in slots.asMap().entries) ...[
              _CullGroupPageIndicatorSlot(
                key: ValueKey('review-group-page-indicator-slot-${entry.key}'),
                palette: palette,
                slot: entry.value,
              ),
              if (entry.key != slots.length - 1)
                const SizedBox(width: _slotGap),
            ],
          ],
        ),
      ),
    );
  }

  List<_CullGroupPageIndicatorSlotData> _indicatorSlots(int selected) {
    return [
      for (var slot = 0; slot < _slotCount; slot += 1)
        _indicatorSlotForOffset(slot - _centerSlot, selected),
    ];
  }

  _CullGroupPageIndicatorSlotData _indicatorSlotForOffset(
    int offset,
    int selected,
  ) {
    if (offset == 0) {
      return _CullGroupPageIndicatorSlotData.group(
        groups[selected],
        current: true,
      );
    }

    final targetIndex = selected + offset;
    if (targetIndex < 0 || targetIndex >= groups.length) {
      return const _CullGroupPageIndicatorSlotData.placeholder();
    }

    if (offset == -_centerSlot && targetIndex > 0) {
      return const _CullGroupPageIndicatorSlotData.ellipsis(leading: true);
    }
    if (offset == _centerSlot && targetIndex < groups.length - 1) {
      return const _CullGroupPageIndicatorSlotData.ellipsis(leading: false);
    }

    return _CullGroupPageIndicatorSlotData.group(groups[targetIndex]);
  }
}

class _CullGroupPageIndicatorSlotData {
  const _CullGroupPageIndicatorSlotData._({
    required this.kind,
    this.group,
    this.current = false,
    this.leading = false,
  });

  const _CullGroupPageIndicatorSlotData.placeholder()
    : this._(kind: _CullGroupPageIndicatorSlotKind.placeholder);

  const _CullGroupPageIndicatorSlotData.ellipsis({required bool leading})
    : this._(kind: _CullGroupPageIndicatorSlotKind.ellipsis, leading: leading);

  const _CullGroupPageIndicatorSlotData.group(
    _CullGroupView group, {
    bool current = false,
  }) : this._(
         kind: _CullGroupPageIndicatorSlotKind.group,
         group: group,
         current: current,
       );

  final _CullGroupPageIndicatorSlotKind kind;
  final _CullGroupView? group;
  final bool current;
  final bool leading;
}

enum _CullGroupPageIndicatorSlotKind { placeholder, ellipsis, group }

class _CullGroupPageIndicatorSlot extends StatelessWidget {
  const _CullGroupPageIndicatorSlot({
    super.key,
    required this.palette,
    required this.slot,
  });

  final NoemaPalette palette;
  final _CullGroupPageIndicatorSlotData slot;

  @override
  Widget build(BuildContext context) {
    final child = switch (slot.kind) {
      _CullGroupPageIndicatorSlotKind.placeholder => const SizedBox.shrink(),
      _CullGroupPageIndicatorSlotKind.ellipsis => _CullGroupPageOverflowDot(
        key: ValueKey(
          slot.leading
              ? 'review-group-page-indicator-ellipsis-leading'
              : 'review-group-page-indicator-ellipsis-trailing',
        ),
        palette: palette,
      ),
      _CullGroupPageIndicatorSlotKind.group => _CullGroupPageIndicatorSegment(
        key: slot.current
            ? const ValueKey('review-group-page-indicator-current')
            : ValueKey('review-group-page-indicator-group-${slot.group!.id}'),
        palette: palette,
        complete: slot.group!.reviewState == _CullGroupReviewState.complete,
        current: slot.current,
      ),
    };

    return SizedBox(
      width: _CullGroupPageIndicator._slotWidth,
      height: 18,
      child: Center(child: child),
    );
  }
}

class _CullGroupPageOverflowDot extends StatelessWidget {
  const _CullGroupPageOverflowDot({super.key, required this.palette});

  final NoemaPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: 0.26),
        shape: BoxShape.circle,
      ),
      child: const SizedBox(width: 4, height: 4),
    );
  }
}

class _CullGroupPageIndicatorSegment extends StatelessWidget {
  const _CullGroupPageIndicatorSegment({
    super.key,
    required this.palette,
    required this.complete,
    required this.current,
  });

  final NoemaPalette palette;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? const Color(0xFF73D99A).withValues(alpha: current ? 0.96 : 0.72)
        : Colors.white.withValues(alpha: current ? 0.82 : 0.42);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: _cullEase,
      width: current ? 8 : 15,
      height: current ? 8 : 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(current ? 99 : 3),
        boxShadow: [
          BoxShadow(
            color: (complete ? const Color(0xFF73D99A) : palette.ink)
                .withValues(alpha: current ? 0.18 : 0.06),
            blurRadius: current ? 10 : 5,
          ),
        ],
      ),
    );
  }
}

class _CullDetailPanel extends StatelessWidget {
  const _CullDetailPanel({
    required this.palette,
    required this.strings,
    required this.group,
    required this.open,
    required this.clearConfirmOpen,
    required this.onClose,
    required this.onPreviewPhoto,
    required this.onOpenClearConfirm,
    required this.onCloseClearConfirm,
    required this.onClearOutPhotos,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final _CullGroupView group;
  final bool open;
  final bool clearConfirmOpen;
  final VoidCallback onClose;
  final ValueChanged<_CullPhotoView> onPreviewPhoto;
  final VoidCallback onOpenClearConfirm;
  final VoidCallback onCloseClearConfirm;
  final void Function(List<_CullPhotoView> photos, NoemaRemoveChoice choice)
  onClearOutPhotos;

  @override
  Widget build(BuildContext context) {
    final outPhotos = group.photos
        .where((photo) => photo.status == _CullStatus.out)
        .toList(growable: false);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: _cullEase,
                  opacity: open ? 1 : 0,
                  child: ColoredBox(
                    key: const ValueKey('review-group-detail-barrier'),
                    color: Colors.black.withValues(
                      alpha: palette.tone == NoemaTone.dark ? 0.32 : 0.2,
                    ),
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final sheetHeight = math
                    .min(
                      constraints.maxHeight * 0.76,
                      math.max(420.0, constraints.maxHeight * 0.68),
                    )
                    .toDouble();
                final hiddenOffset = sheetHeight + 28;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: _cullEase,
                    transform: Matrix4.translationValues(
                      0,
                      open ? 0 : hiddenOffset,
                      0,
                    ),
                    width: double.infinity,
                    height: sheetHeight,
                    child: _GlassPanel(
                      key: const ValueKey('review-group-detail-sheet'),
                      palette: palette,
                      radius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              18,
                              10,
                              18,
                              16 + MediaQuery.paddingOf(context).bottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DetailSheetHeader(
                                  palette: palette,
                                  strings: strings,
                                  title: group.title,
                                  hasOutPhotos: outPhotos.isNotEmpty,
                                  onClose: onClose,
                                  onOpenClearConfirm: onOpenClearConfirm,
                                ),
                                const SizedBox(height: 18),
                                Expanded(
                                  child: GridView.builder(
                                    key: const ValueKey(
                                      'review-group-detail-grid',
                                    ),
                                    physics: const BouncingScrollPhysics(),
                                    clipBehavior: Clip.hardEdge,
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 4,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                        ),
                                    itemCount: group.photos.length,
                                    itemBuilder: (context, index) {
                                      final photo = group.photos[index];
                                      return _DetailPhotoTile(
                                        palette: palette,
                                        photo: photo,
                                        onPreview: () => onPreviewPhoto(photo),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (clearConfirmOpen)
                            _ClearConfirmSheet(
                              palette: palette,
                              strings: strings,
                              outPhotos: outPhotos,
                              onCancel: onCloseClearConfirm,
                              onConfirm: (choice) =>
                                  onClearOutPhotos(outPhotos, choice),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSheetHeader extends StatelessWidget {
  const _DetailSheetHeader({
    required this.palette,
    required this.strings,
    required this.title,
    required this.hasOutPhotos,
    required this.onClose,
    required this.onOpenClearConfirm,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final String title;
  final bool hasOutPhotos;
  final VoidCallback onClose;
  final VoidCallback onOpenClearConfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 260) {
          onClose();
        }
      },
      child: Column(
        children: [
          Center(
            child: Container(
              key: const ValueKey('review-group-detail-handle'),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.9),
                    fontFamily: 'LXGWWenKaiGB',
                    fontFamilyFallback: const ['NoemaCjkFallback'],
                    fontSize: 16,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (hasOutPhotos)
                NoemaGlassIconButton(
                  palette: palette,
                  tooltip: strings.cullClearOut,
                  icon: Icons.delete_outline_rounded,
                  onPressed: onOpenClearConfirm,
                ),
              const SizedBox(width: 4),
              NoemaGlassIconButton(
                palette: palette,
                tooltip: strings.close,
                icon: Icons.close_rounded,
                onPressed: onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailPhotoTile extends StatelessWidget {
  const _DetailPhotoTile({
    required this.palette,
    required this.photo,
    required this.onPreview,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final statusColor = _detailStatusColor(photo.status, palette);
    final isPending = photo.status == _CullStatus.pending;
    return GestureDetector(
      key: ValueKey('review-photo-tile-${photo.id}'),
      onTap: onPreview,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: _cullEase,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: statusColor.withValues(alpha: isPending ? 0.16 : 0.64),
            width: isPending ? 1 : 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CullPhotoImage(
                palette: palette,
                photo: photo,
                fit: BoxFit.cover,
                cacheHeadroom: 1.65,
                cacheMaxExtent: 1800,
                filterQuality: FilterQuality.medium,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 5,
                right: 5,
                child: _DetailStatusBadge(
                  palette: palette,
                  status: photo.status,
                  color: statusColor,
                  muted: isPending,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailStatusBadge extends StatelessWidget {
  const _DetailStatusBadge({
    required this.palette,
    required this.status,
    required this.color,
    required this.muted,
  });

  final NoemaPalette palette;
  final _CullStatus status;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      _CullStatus.keep => Icons.check_rounded,
      _CullStatus.out => Icons.delete_outline_rounded,
      _CullStatus.pending => Icons.radio_button_unchecked_rounded,
      _CullStatus.revisit => Icons.change_circle_outlined,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.sheet.withValues(alpha: 0.56),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: muted ? 0.32 : 0.72),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Icon(
          icon,
          size: 15,
          color: color.withValues(alpha: muted ? 0.52 : 0.94),
        ),
      ),
    );
  }
}

bool _canDeleteSystemPhotos(List<_CullPhotoView> photos) {
  return photos.isNotEmpty &&
      photos.every((photo) {
        final sourceUri = photo.asset?.photo.sourceUri;
        return sourceUri != null && sourceUri.trim().isNotEmpty;
      });
}

Color _detailStatusColor(_CullStatus status, NoemaPalette palette) {
  return switch (status) {
    _CullStatus.keep => const Color(0xFF73D99A),
    _CullStatus.out => const Color(0xFFD98C73),
    _CullStatus.revisit => const Color(0xFFE2C264),
    _CullStatus.pending => palette.ink,
  };
}

class _ClearConfirmSheet extends StatelessWidget {
  const _ClearConfirmSheet({
    required this.palette,
    required this.strings,
    required this.outPhotos,
    required this.onCancel,
    required this.onConfirm,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final List<_CullPhotoView> outPhotos;
  final VoidCallback onCancel;
  final ValueChanged<NoemaRemoveChoice> onConfirm;

  @override
  Widget build(BuildContext context) {
    final canDeleteSystemPhoto = _canDeleteSystemPhotos(outPhotos);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCancel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 304),
                child: NoemaRemoveAssetsDialog(
                  palette: palette,
                  bodyText: canDeleteSystemPhoto
                      ? strings.cullClearConfirm(outPhotos.length)
                      : strings.removeSystemPhotoUnavailable,
                  canDeleteSystemPhoto: canDeleteSystemPhoto,
                  onCancel: onCancel,
                  onRemoveFromSpace: () =>
                      onConfirm(NoemaRemoveChoice.indexOnly),
                  onRemoveAndDeleteSystemPhoto: () =>
                      onConfirm(NoemaRemoveChoice.deleteSystemPhoto),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedOutConfirmOverlay extends StatelessWidget {
  const _CompletedOutConfirmOverlay({
    required this.palette,
    required this.strings,
    required this.photos,
    required this.onCancel,
    required this.onConfirm,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final List<_CullPhotoView> photos;
  final VoidCallback onCancel;
  final ValueChanged<NoemaRemoveChoice> onConfirm;

  @override
  Widget build(BuildContext context) {
    final count = photos.length;
    final canDeleteSystemPhoto = _canDeleteSystemPhotos(photos);
    final hasPhotos = count > 0;
    if (hasPhotos) {
      return Positioned.fill(
        key: const ValueKey('review-groups-completed-clear-confirm-overlay'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: palette.tone == NoemaTone.dark ? 0.32 : 0.24,
              ),
            ),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 318),
                  child: NoemaRemoveAssetsDialog(
                    palette: palette,
                    bodyText: canDeleteSystemPhoto
                        ? strings.cullClearCompletedConfirm(count)
                        : strings.removeSystemPhotoUnavailable,
                    canDeleteSystemPhoto: canDeleteSystemPhoto,
                    onCancel: onCancel,
                    onRemoveFromSpace: () =>
                        onConfirm(NoemaRemoveChoice.indexOnly),
                    onRemoveAndDeleteSystemPhoto: () =>
                        onConfirm(NoemaRemoveChoice.deleteSystemPhoto),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      key: const ValueKey('review-groups-completed-clear-confirm-overlay'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCancel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: palette.tone == NoemaTone.dark ? 0.32 : 0.24,
            ),
          ),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 318),
                child: _GlassPanel(
                  palette: palette,
                  radius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                strings.cullClearCompletedOut,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontFamily: 'LXGWWenKaiGB',
                                  fontFamilyFallback: const [
                                    'NoemaCjkFallback',
                                  ],
                                  fontSize: 17,
                                  letterSpacing: 0,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            NoemaGlassIconButton(
                              palette: palette,
                              tooltip: strings.close,
                              icon: Icons.close_rounded,
                              onPressed: onCancel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.cullClearCompletedEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.ink.withValues(alpha: 0.9),
                            fontFamily: 'LXGWWenKaiGB',
                            fontFamilyFallback: const ['NoemaCjkFallback'],
                            fontSize: 13,
                            letterSpacing: 0,
                            height: 1.4,
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
      ),
    );
  }
}

class _CullModeOverlay extends StatefulWidget {
  const _CullModeOverlay({
    required this.palette,
    required this.strings,
    required this.mode,
    required this.group,
    required this.onClose,
    required this.onOpenNextIncomplete,
    required this.onSetStatus,
    required this.onPreviewPhoto,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final _CullMode mode;
  final _CullGroupView group;
  final VoidCallback onClose;
  final VoidCallback? onOpenNextIncomplete;
  final void Function(_CullPhotoView photo, _CullStatus status) onSetStatus;
  final ValueChanged<_CullPhotoView> onPreviewPhoto;

  @override
  State<_CullModeOverlay> createState() => _CullModeOverlayState();
}

class _CullModeOverlayState extends State<_CullModeOverlay> {
  @override
  Widget build(BuildContext context) {
    final sceneLayout = NoemaSceneMetrics.layoutOf(context);
    final topBarTop = sceneLayout.topBarTop;
    final topShift = sceneLayout.topSafeShift;
    final fast = widget.mode == _CullMode.fast;
    final modeContent = fast
        ? _FastCullMode(
            palette: widget.palette,
            group: widget.group,
            onClose: widget.onClose,
            onOpenNextIncomplete: widget.onOpenNextIncomplete,
            onSetStatus: widget.onSetStatus,
            onPreviewPhoto: widget.onPreviewPhoto,
          )
        : _CompareCullMode(
            palette: widget.palette,
            strings: widget.strings,
            group: widget.group,
            onClose: widget.onClose,
            onOpenNextIncomplete: widget.onOpenNextIncomplete,
            onSetStatus: widget.onSetStatus,
          );

    return Positioned.fill(
      child: NoemaSceneSurface(
        palette: widget.palette,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: sceneLayout.markLeft,
              top: NoemaSceneMetrics.markTop,
              child: NoemaThemeMark(palette: widget.palette, mark: '甄'),
            ),
            Positioned(
              left: sceneLayout.topBarInset,
              right: sceneLayout.topBarInset,
              top: topBarTop,
              child: _CullTopBar(
                palette: widget.palette,
                onBack: widget.onClose,
              ),
            ),
            Positioned(
              left: sceneLayout.sideInset,
              right: sceneLayout.sideInset,
              top: _cullModeContentTop + topShift,
              bottom: _cullModeContentBottom,
              child: modeContent,
            ),
          ],
        ),
      ),
    );
  }
}

class _FastCullMode extends StatefulWidget {
  const _FastCullMode({
    required this.palette,
    required this.group,
    required this.onClose,
    required this.onOpenNextIncomplete,
    required this.onSetStatus,
    required this.onPreviewPhoto,
  });

  final NoemaPalette palette;
  final _CullGroupView group;
  final VoidCallback onClose;
  final VoidCallback? onOpenNextIncomplete;
  final void Function(_CullPhotoView photo, _CullStatus status) onSetStatus;
  final ValueChanged<_CullPhotoView> onPreviewPhoto;

  @override
  State<_FastCullMode> createState() => _FastCullModeState();
}

class _FastCullModeState extends State<_FastCullMode> {
  final List<String> _pendingIds = [];
  final List<String> _keptIds = [];
  final List<String> _discardedIds = [];
  Offset _dragOffset = Offset.zero;
  String? _currentId;
  _CullPhotoView? _exitingPhoto;
  _CullStatus? _targetFeedbackStatus;
  bool _commitInFlight = false;

  @override
  void initState() {
    super.initState();
    _resetForGroup();
  }

  @override
  void didUpdateWidget(covariant _FastCullMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _resetForGroup();
      return;
    }
    _reconcilePhotos();
  }

  Map<String, _CullPhotoView> get _photosById => {
    for (final photo in widget.group.photos) photo.id: photo,
  };

  _CullPhotoView? get _currentPhoto {
    final id = _currentId;
    if (id == null) {
      return null;
    }
    return _photosById[id];
  }

  void _resetForGroup() {
    _pendingIds.clear();
    _keptIds.clear();
    _discardedIds.clear();
    _exitingPhoto = null;
    _targetFeedbackStatus = null;
    _commitInFlight = false;
    for (final photo in widget.group.photos) {
      switch (photo.status) {
        case _CullStatus.keep:
          _keptIds.add(photo.id);
        case _CullStatus.out:
          _discardedIds.add(photo.id);
        case _CullStatus.pending:
        case _CullStatus.revisit:
          _pendingIds.add(photo.id);
      }
    }
    _currentId = _pendingIds.isEmpty ? null : _pendingIds.removeAt(0);
    _dragOffset = Offset.zero;
  }

  void _reconcilePhotos() {
    if (_commitInFlight) {
      return;
    }
    final validIds = {for (final photo in widget.group.photos) photo.id};
    _pendingIds.removeWhere((id) => !validIds.contains(id));
    _keptIds.removeWhere((id) => !validIds.contains(id));
    _discardedIds.removeWhere((id) => !validIds.contains(id));
    if (_currentId != null && !validIds.contains(_currentId)) {
      _currentId = null;
    }

    final knownIds = {
      ..._pendingIds,
      ..._keptIds,
      ..._discardedIds,
      ?_currentId,
    };
    for (final photo in widget.group.photos) {
      if (knownIds.contains(photo.id)) {
        continue;
      }
      switch (photo.status) {
        case _CullStatus.keep:
          _keptIds.add(photo.id);
        case _CullStatus.out:
          _discardedIds.add(photo.id);
        case _CullStatus.pending:
        case _CullStatus.revisit:
          _pendingIds.add(photo.id);
      }
    }

    if (_currentId == null && _pendingIds.isNotEmpty) {
      _currentId = _pendingIds.removeAt(0);
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_commitInFlight) {
      return;
    }
    final nextOffset = Offset(
      (_dragOffset.dx + details.delta.dx).clamp(-132, 132).toDouble(),
      (_dragOffset.dy + details.delta.dy).clamp(-244, 244).toDouble(),
    );
    setState(() {
      _dragOffset = nextOffset;
    });
    _updateTargetFeedback(_targetForOffset(nextOffset));
  }

  void _handleDragEnd() {
    if (_commitInFlight) {
      return;
    }
    final photo = _currentPhoto;
    if (photo == null) {
      _resetDrag();
      return;
    }
    if (_dragOffset.dy <= -_cullTriggerDragDistance) {
      _commitCurrent(photo, _CullStatus.out);
      return;
    }
    if (_dragOffset.dy >= _cullTriggerDragDistance) {
      _commitCurrent(photo, _CullStatus.keep);
      return;
    }
    _resetDrag();
  }

  void _resetDrag() {
    if (_commitInFlight) {
      return;
    }
    setState(() {
      _dragOffset = Offset.zero;
      _targetFeedbackStatus = null;
    });
  }

  void _commitCurrent(_CullPhotoView photo, _CullStatus status) {
    if (_commitInFlight) {
      return;
    }
    final exitY = status == _CullStatus.keep
        ? _fastCardExitDistance
        : -_fastCardExitDistance;
    setState(() {
      _removeFromLocalBuckets(photo.id);
      if (status == _CullStatus.keep) {
        _keptIds.insert(0, photo.id);
      } else {
        _discardedIds.insert(0, photo.id);
      }
      _exitingPhoto = photo;
      _targetFeedbackStatus = null;
      _commitInFlight = true;
      _dragOffset = Offset(_dragOffset.dx.clamp(-84, 84).toDouble(), exitY);
    });
    widget.onSetStatus(photo, status);
    Future<void>.delayed(_fastCommitAnimationDuration, () {
      if (!mounted || _exitingPhoto?.id != photo.id) {
        return;
      }
      setState(() {
        _currentId = _pendingIds.isEmpty ? null : _pendingIds.removeAt(0);
        _exitingPhoto = null;
        _commitInFlight = false;
        _dragOffset = Offset.zero;
      });
    });
  }

  void _recallPhoto(_CullPhotoView photo) {
    if (_commitInFlight) {
      return;
    }
    setState(() {
      _removeFromLocalBuckets(photo.id);
      final currentId = _currentId;
      if (currentId != null) {
        _pendingIds.insert(0, currentId);
      }
      _currentId = photo.id;
      _dragOffset = Offset.zero;
      _targetFeedbackStatus = null;
    });
    widget.onSetStatus(photo, _CullStatus.pending);
  }

  void _removeFromLocalBuckets(String id) {
    _pendingIds.remove(id);
    _keptIds.remove(id);
    _discardedIds.remove(id);
    if (_currentId == id) {
      _currentId = null;
    }
  }

  _CullStatus? _targetForOffset(Offset offset) {
    if (offset.dy <= -_cullTriggerDragDistance) {
      return _CullStatus.out;
    }
    if (offset.dy >= _cullTriggerDragDistance) {
      return _CullStatus.keep;
    }
    return null;
  }

  void _updateTargetFeedback(_CullStatus? status) {
    if (status == _targetFeedbackStatus) {
      return;
    }
    _targetFeedbackStatus = status;
    if (status != null) {
      _playCullHapticFeedback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final photoById = _photosById;
    final current = _exitingPhoto ?? _currentPhoto;
    final discardBias = math
        .max(0.0, -_dragOffset.dy / _cullTriggerDragDistance)
        .clamp(0.0, 1.0)
        .toDouble();
    final keepBias = math
        .max(0.0, _dragOffset.dy / _cullTriggerDragDistance)
        .clamp(0.0, 1.0)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final upperBoundaryY = constraints.maxHeight * _cullUpperBoundaryFactor;
        final lowerBoundaryY = constraints.maxHeight * _cullLowerBoundaryFactor;
        final upperLabelTop =
            upperBoundaryY - _fastTargetLabelCenterGap - _modeLabelHeight / 2;
        final lowerLabelTop =
            lowerBoundaryY + _fastTargetLabelCenterGap - _modeLabelHeight / 2;
        final labelTopMax = math.max(
          0,
          constraints.maxHeight - _modeLabelHeight,
        );
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: _FloatingCullField(
                key: const ValueKey('fast-cull-boundary-field'),
                palette: widget.palette,
                upperBias: discardBias,
                lowerBias: keepBias,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: upperLabelTop.clamp(0.0, labelTopMax).toDouble(),
              height: _modeLabelHeight,
              child: _ModeLabel(
                key: const ValueKey('fast-cull-discard-label'),
                palette: widget.palette,
                text: strings.cullDiscardTarget,
                activeBias: math.max(0.22, discardBias),
                activeShiftY: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: lowerLabelTop.clamp(0.0, labelTopMax).toDouble(),
              height: _modeLabelHeight,
              child: _ModeLabel(
                key: const ValueKey('fast-cull-keep-label'),
                palette: widget.palette,
                text: strings.cullKeepTarget,
                activeBias: math.max(0.22, keepBias),
                activeShiftY: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 74,
              bottom: 74,
              child: current == null
                  ? _FastCullComplete(
                      palette: widget.palette,
                      strings: strings,
                      totalCount: widget.group.photos.length,
                      onClose: widget.onClose,
                      onOpenNextIncomplete: widget.onOpenNextIncomplete,
                    )
                  : _FastPhotoStack(
                      palette: widget.palette,
                      current: current,
                      pendingPhotos: [
                        for (final id in _pendingIds.take(5))
                          if (photoById[id] != null) photoById[id]!,
                      ],
                      dragOffset: _dragOffset,
                      discardBias: discardBias,
                      keepBias: keepBias,
                      committing: _commitInFlight,
                      onTapCurrent: () => widget.onPreviewPhoto(current),
                      onDragUpdate: _handleDragUpdate,
                      onDragEnd: _handleDragEnd,
                      onDragCancel: _resetDrag,
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _fastDecisionQueueHeight,
              child: _FastDecisionQueue(
                palette: widget.palette,
                icon: Icons.delete_outline_rounded,
                ids: _discardedIds,
                photoById: photoById,
                onRecall: _recallPhoto,
                queueKeyPrefix: 'fast-cull-discard',
                contentAlignment: Alignment.topLeft,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _fastDecisionQueueHeight,
              child: _FastDecisionQueue(
                palette: widget.palette,
                icon: Icons.check_rounded,
                ids: _keptIds,
                photoById: photoById,
                onRecall: _recallPhoto,
                queueKeyPrefix: 'fast-cull-keep',
                contentAlignment: Alignment.bottomLeft,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FastDecisionQueue extends StatefulWidget {
  const _FastDecisionQueue({
    required this.palette,
    required this.icon,
    required this.ids,
    required this.photoById,
    required this.onRecall,
    required this.queueKeyPrefix,
    required this.contentAlignment,
  });

  final NoemaPalette palette;
  final IconData icon;
  final List<String> ids;
  final Map<String, _CullPhotoView> photoById;
  final ValueChanged<_CullPhotoView> onRecall;
  final String queueKeyPrefix;
  final Alignment contentAlignment;

  @override
  State<_FastDecisionQueue> createState() => _FastDecisionQueueState();
}

class _FastDecisionQueueState extends State<_FastDecisionQueue> {
  late final ScrollController _scrollController;
  String? _leadingId;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _leadingId = widget.ids.firstOrNull;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FastDecisionQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    final leadingId = widget.ids.firstOrNull;
    if (leadingId != _leadingId) {
      _leadingId = leadingId;
      if (leadingId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: _fastQueueShiftDuration,
              curve: _cullPageSwitchEase,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = widget.contentAlignment.y < 0
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    final visiblePhotos = [
      for (final id in widget.ids)
        if (widget.photoById[id] != null) widget.photoById[id]!,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = math.min(
          _fastQueueMaxStripWidth,
          math.max(
            0.0,
            constraints.maxWidth - _fastQueueIconWidth - _fastQueueThumbGap,
          ),
        );
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            SizedBox(
              width: _fastQueueIconWidth,
              height: _fastDecisionQueueHeight,
              child: Align(
                alignment: widget.contentAlignment,
                child: Icon(
                  widget.icon,
                  size: 24,
                  color: widget.palette.ink.withValues(alpha: 0.52),
                ),
              ),
            ),
            if (visiblePhotos.isNotEmpty) ...[
              const SizedBox(width: _fastQueueThumbGap),
              Align(
                alignment: widget.contentAlignment,
                child: SizedBox(
                  width: stripWidth,
                  height: _fastQueueThumbSize,
                  child: _FastQueueStrip(
                    palette: widget.palette,
                    photos: visiblePhotos,
                    queueKeyPrefix: widget.queueKeyPrefix,
                    scrollController: _scrollController,
                    onRecall: widget.onRecall,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FastQueueStrip extends StatelessWidget {
  const _FastQueueStrip({
    required this.palette,
    required this.photos,
    required this.queueKeyPrefix,
    required this.scrollController,
    required this.onRecall,
  });

  final NoemaPalette palette;
  final List<_CullPhotoView> photos;
  final String queueKeyPrefix;
  final ScrollController scrollController;
  final ValueChanged<_CullPhotoView> onRecall;

  @override
  Widget build(BuildContext context) {
    final contentWidth = math.max(
      _fastQueueMaxStripWidth,
      photos.length * _fastQueueThumbSize +
          math.max(0, photos.length - 1) * _fastQueueThumbGap,
    );
    return ClipRect(
      child: SingleChildScrollView(
        key: ValueKey('$queueKeyPrefix-queue-scroll'),
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          width: contentWidth,
          height: _fastQueueThumbSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final entry in photos.asMap().entries)
                AnimatedPositioned(
                  key: ValueKey('$queueKeyPrefix-position-${entry.value.id}'),
                  duration: _fastQueueShiftDuration,
                  curve: _cullPageSwitchEase,
                  left: entry.key * (_fastQueueThumbSize + _fastQueueThumbGap),
                  top: 0,
                  width: _fastQueueThumbSize,
                  height: _fastQueueThumbSize,
                  child: _FastQueueThumb(
                    palette: palette,
                    photo: entry.value,
                    queueKey: ValueKey('$queueKeyPrefix-${entry.value.id}'),
                    onTap: () => onRecall(entry.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FastQueueThumb extends StatefulWidget {
  const _FastQueueThumb({
    required this.palette,
    required this.photo,
    required this.queueKey,
    required this.onTap,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final Key queueKey;
  final VoidCallback onTap;

  @override
  State<_FastQueueThumb> createState() => _FastQueueThumbState();
}

class _FastQueueThumbState extends State<_FastQueueThumb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _enter;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _enter = CurvedAnimation(parent: _enterController, curve: _cullEase);
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: widget.queueKey,
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final progress = _enter.value;
          return Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset((1 - progress) * -14, 0),
              child: Transform.scale(
                scale: 0.86 + progress * 0.14,
                child: child,
              ),
            ),
          );
        },
        child: SizedBox(
          width: _fastQueueThumbSize,
          height: _fastQueueThumbSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _CullPhotoImage(
                palette: widget.palette,
                photo: widget.photo,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FastPhotoStack extends StatelessWidget {
  const _FastPhotoStack({
    required this.palette,
    required this.current,
    required this.pendingPhotos,
    required this.dragOffset,
    required this.discardBias,
    required this.keepBias,
    required this.committing,
    required this.onTapCurrent,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final NoemaPalette palette;
  final _CullPhotoView current;
  final List<_CullPhotoView> pendingPhotos;
  final Offset dragOffset;
  final double discardBias;
  final double keepBias;
  final bool committing;
  final VoidCallback onTapCurrent;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );
        final currentSize = _fastCullFrameSize(
          current.aspectRatio,
          constraints.biggest,
        );
        final topGlow = discardBias > keepBias ? discardBias : keepBias;
        final activeBias = topGlow.clamp(0.0, 1.0).toDouble();

        return Stack(
          alignment: Alignment.center,
          children: [
            for (
              var depth = math.min(4, pendingPhotos.length) - 1;
              depth >= 0;
              depth -= 1
            )
              _FastStackLayer(
                palette: palette,
                photo: pendingPhotos[depth],
                center: center,
                baseSize: currentSize,
                depth: depth + 1,
              ),
            Positioned(
              left: center.dx - currentSize.width / 2,
              top: center.dy - currentSize.height / 2,
              child: IgnorePointer(
                ignoring: committing,
                child: GestureDetector(
                  key: const ValueKey('fast-cull-current-photo'),
                  behavior: HitTestBehavior.translucent,
                  onTap: onTapCurrent,
                  onPanUpdate: onDragUpdate,
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: onDragCancel,
                  child: AnimatedOpacity(
                    duration: committing
                        ? _fastCommitAnimationDuration
                        : const Duration(milliseconds: 180),
                    curve: committing ? Curves.easeOutCubic : _cullEase,
                    opacity: committing ? 0 : 1,
                    child: AnimatedContainer(
                      duration: committing
                          ? _fastCommitAnimationDuration
                          : dragOffset.distance > 0.5
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      curve: committing ? Curves.easeInCubic : _cullEase,
                      transform: Matrix4.identity()
                        ..translateByDouble(dragOffset.dx, dragOffset.dy, 0, 1)
                        ..rotateZ(
                          (dragOffset.dx / 260).clamp(-0.06, 0.06).toDouble(),
                        ),
                      transformAlignment: Alignment.center,
                      child: _FastPhotoCard(
                        palette: palette,
                        photo: current,
                        size: currentSize,
                        activeBias: activeBias,
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

class _FastStackLayer extends StatelessWidget {
  const _FastStackLayer({
    required this.palette,
    required this.photo,
    required this.center,
    required this.baseSize,
    required this.depth,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final Offset center;
  final Size baseSize;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final scale = 1 - depth * 0.045;
    final size = Size(baseSize.width * scale, baseSize.height * scale);
    final dx = (depth.isOdd ? 1 : -1) * depth * 7.0;
    final dy = depth * 10.0;
    return Positioned(
      left: center.dx - size.width / 2 + dx,
      top: center.dy - size.height / 2 + dy,
      child: IgnorePointer(
        child: Opacity(
          opacity: (0.36 - depth * 0.055).clamp(0.12, 0.36).toDouble(),
          child: Transform.rotate(
            angle: (depth.isOdd ? 1 : -1) * 0.022,
            child: _FastPhotoCard(
              palette: palette,
              photo: photo,
              size: size,
              activeBias: 0,
              subdued: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _FastPhotoCard extends StatelessWidget {
  const _FastPhotoCard({
    required this.palette,
    required this.photo,
    required this.size,
    required this.activeBias,
    this.subdued = false,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final Size size;
  final double activeBias;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final glowColor = Color.lerp(palette.ink, Colors.white, 0.74)!;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: subdued ? 0.16 : 0.32),
              blurRadius: subdued ? 18 : 34,
              offset: Offset(0, subdued ? 10 : 19),
            ),
            if (activeBias > 0)
              BoxShadow(
                color: glowColor.withValues(alpha: 0.18 * activeBias),
                blurRadius: 28 + activeBias * 16,
                spreadRadius: 1 + activeBias * 2,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CullPhotoImage(
                palette: palette,
                photo: photo,
                fit: BoxFit.cover,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color.lerp(
                        palette.ink.withValues(alpha: subdued ? 0.12 : 0.38),
                        glowColor.withValues(alpha: 0.82),
                        activeBias,
                      )!,
                      width: 1 + activeBias,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.glass.withValues(alpha: subdued ? 0.03 : 0.06),
                        Colors.black.withValues(alpha: subdued ? 0.12 : 0.2),
                      ],
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

class _FastCullComplete extends StatelessWidget {
  const _FastCullComplete({
    required this.palette,
    required this.strings,
    required this.totalCount,
    required this.onClose,
    required this.onOpenNextIncomplete,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final int totalCount;
  final VoidCallback onClose;
  final VoidCallback? onOpenNextIncomplete;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 268),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_rounded,
              size: 34,
              color: palette.ink.withValues(alpha: 0.58),
            ),
            const SizedBox(height: 12),
            Text(
              strings.cullGroupComplete,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.ink.withValues(alpha: 0.62),
                fontFamily: 'LXGWWenKaiGB',
                fontFamilyFallback: const ['NoemaCjkFallback'],
                fontSize: 17,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$totalCount',
              style: TextStyle(
                color: palette.ink.withValues(alpha: 0.34),
                fontFamily: 'LXGWWenKaiGB',
                fontFamilyFallback: const ['NoemaCjkFallback'],
                fontFeatures: const [ui.FontFeature.tabularFigures()],
                fontSize: 18,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            _CullCompletionActionButton(
              palette: palette,
              text: strings.cullReturnToGroups,
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: onClose,
            ),
            const SizedBox(height: 10),
            _CullCompletionActionButton(
              palette: palette,
              text: onOpenNextIncomplete == null
                  ? strings.cullAllGroupsComplete
                  : strings.cullNextUnfinished,
              icon: Icons.skip_next_rounded,
              onPressed: onOpenNextIncomplete,
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CullCompletionActionButton extends StatelessWidget {
  const _CullCompletionActionButton({
    required this.palette,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final NoemaPalette palette;
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final backgroundAlpha = emphasized ? 0.18 : 0.1;
    final borderAlpha = emphasized ? 0.32 : 0.18;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.glass.withValues(alpha: backgroundAlpha),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.ink.withValues(alpha: borderAlpha),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: emphasized ? 0.14 : 0.08),
                blurRadius: emphasized ? 18 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: palette.ink.withValues(alpha: enabled ? 0.78 : 0.42),
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: enabled ? 0.78 : 0.42),
                    fontFamily: 'LXGWWenKaiGB',
                    fontFamilyFallback: const ['NoemaCjkFallback'],
                    fontSize: 14,
                    letterSpacing: 0,
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

Size _fastCullFrameSize(double aspectRatio, Size viewport) {
  final ratio = aspectRatio.clamp(0.48, 2.05).toDouble();
  final maxWidth = math.min(248.0, viewport.width * 0.72);
  final maxHeight = math.min(360.0, viewport.height * 0.58);
  if (ratio >= 1) {
    var width = maxWidth;
    var height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    return Size(width, math.max(132.0, height));
  }

  var height = maxHeight;
  var width = height * ratio;
  if (width > maxWidth) {
    width = maxWidth;
    height = width / ratio;
  }
  return Size(math.max(132.0, width), height);
}

Size _compareSingleFrameSize(double aspectRatio, Size viewport) {
  final ratio = aspectRatio.clamp(0.42, 2.4).toDouble();
  final maxWidth = math.min(304.0, viewport.width * 0.88);
  final maxHeight = math.min(430.0, viewport.height * 0.76);
  if (ratio >= 1) {
    var width = maxWidth;
    var height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    return Size(width, math.max(132.0, height));
  }

  var height = maxHeight;
  var width = height * ratio;
  if (width > maxWidth) {
    width = maxWidth;
    height = width / ratio;
  }
  return Size(math.max(132.0, width), height);
}

enum _CompareSlot { left, right }

class _CompareExitingPhoto {
  const _CompareExitingPhoto({required this.photo, required this.slot});

  final _CullPhotoView photo;
  final _CompareSlot slot;
}

class _CompareCullMode extends StatefulWidget {
  const _CompareCullMode({
    required this.palette,
    required this.strings,
    required this.group,
    required this.onClose,
    required this.onOpenNextIncomplete,
    required this.onSetStatus,
  });

  final NoemaPalette palette;
  final NoemaStrings strings;
  final _CullGroupView group;
  final VoidCallback onClose;
  final VoidCallback? onOpenNextIncomplete;
  final void Function(_CullPhotoView photo, _CullStatus status) onSetStatus;

  @override
  State<_CompareCullMode> createState() => _CompareCullModeState();
}

class _CompareCullModeState extends State<_CompareCullMode> {
  final List<String> _pendingIds = [];
  final List<String> _keptIds = [];
  final List<String> _discardedIds = [];
  final Map<_CompareSlot, Offset> _slotOffsets = {
    _CompareSlot.left: Offset.zero,
    _CompareSlot.right: Offset.zero,
  };
  final Map<_CompareSlot, _CullStatus?> _slotFeedbackTargets = {
    _CompareSlot.left: null,
    _CompareSlot.right: null,
  };

  String? _leftId;
  String? _rightId;
  _CompareExitingPhoto? _exiting;
  bool _commitInFlight = false;
  bool _previewOpen = false;

  @override
  void initState() {
    super.initState();
    _resetForGroup();
  }

  @override
  void didUpdateWidget(covariant _CompareCullMode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _resetForGroup();
      return;
    }
    _reconcilePhotos();
  }

  Map<String, _CullPhotoView> get _photosById => {
    for (final photo in widget.group.photos) photo.id: photo,
  };

  void _resetForGroup() {
    _pendingIds.clear();
    _keptIds.clear();
    _discardedIds.clear();
    _leftId = null;
    _rightId = null;
    _exiting = null;
    _commitInFlight = false;
    _previewOpen = false;
    _slotOffsets[_CompareSlot.left] = Offset.zero;
    _slotOffsets[_CompareSlot.right] = Offset.zero;
    _slotFeedbackTargets[_CompareSlot.left] = null;
    _slotFeedbackTargets[_CompareSlot.right] = null;

    for (final photo in widget.group.photos) {
      switch (photo.status) {
        case _CullStatus.keep:
          _keptIds.add(photo.id);
        case _CullStatus.out:
          _discardedIds.add(photo.id);
        case _CullStatus.pending:
        case _CullStatus.revisit:
          _pendingIds.add(photo.id);
      }
    }
    _fillOpenSlots();
  }

  void _reconcilePhotos() {
    if (_commitInFlight) {
      return;
    }
    final validIds = {for (final photo in widget.group.photos) photo.id};
    _pendingIds.removeWhere((id) => !validIds.contains(id));
    _keptIds.removeWhere((id) => !validIds.contains(id));
    _discardedIds.removeWhere((id) => !validIds.contains(id));
    if (_leftId != null && !validIds.contains(_leftId)) {
      _leftId = null;
    }
    if (_rightId != null && !validIds.contains(_rightId)) {
      _rightId = null;
    }

    final knownIds = {
      ..._pendingIds,
      ..._keptIds,
      ..._discardedIds,
      ?_leftId,
      ?_rightId,
    };
    for (final photo in widget.group.photos) {
      if (knownIds.contains(photo.id)) {
        continue;
      }
      switch (photo.status) {
        case _CullStatus.keep:
          _keptIds.add(photo.id);
        case _CullStatus.out:
          _discardedIds.add(photo.id);
        case _CullStatus.pending:
        case _CullStatus.revisit:
          _pendingIds.add(photo.id);
      }
    }
    _fillOpenSlots();
    if (_previewOpen && _leftPhoto == null && _rightPhoto == null) {
      _previewOpen = false;
    }
  }

  _CullPhotoView? get _leftPhoto => _photoForSlot(_CompareSlot.left);

  _CullPhotoView? get _rightPhoto => _photoForSlot(_CompareSlot.right);

  _CullPhotoView? _photoForSlot(_CompareSlot slot) {
    final exiting = _exiting;
    if (exiting != null && exiting.slot == slot) {
      return exiting.photo;
    }
    final id = switch (slot) {
      _CompareSlot.left => _leftId,
      _CompareSlot.right => _rightId,
    };
    if (id == null) {
      return null;
    }
    return _photosById[id];
  }

  void _fillOpenSlots() {
    if (_leftId == null && _rightId != null) {
      _leftId = _rightId;
      _rightId = null;
    }
    if (_leftId == null && _pendingIds.isNotEmpty) {
      _leftId = _pendingIds.removeAt(0);
    }
    if (_rightId == null && _pendingIds.isNotEmpty) {
      _rightId = _pendingIds.removeAt(0);
    }
  }

  void _handleDragUpdate(_CompareSlot slot, DragUpdateDetails details) {
    if (_commitInFlight || _photoForSlot(slot) == null) {
      return;
    }
    final previous = _slotOffsets[slot] ?? Offset.zero;
    final nextOffset = Offset(
      (previous.dx + details.delta.dx).clamp(-108, 108).toDouble(),
      (previous.dy + details.delta.dy).clamp(-132, 132).toDouble(),
    );
    setState(() {
      _slotOffsets[slot] = nextOffset;
    });
    _updateSlotFeedback(slot, _targetForOffset(nextOffset));
  }

  void _handleDragEnd(_CompareSlot slot) {
    if (_commitInFlight) {
      return;
    }
    final offset = _slotOffsets[slot] ?? Offset.zero;
    if (offset.dy <= -_compareTriggerDragDistance) {
      _commitSlot(slot, _CullStatus.out);
      return;
    }
    if (offset.dy >= _compareTriggerDragDistance) {
      _commitSlot(slot, _CullStatus.keep);
      return;
    }
    _resetSlotDrag(slot);
  }

  void _resetSlotDrag(_CompareSlot slot) {
    if (_commitInFlight) {
      return;
    }
    setState(() {
      _slotOffsets[slot] = Offset.zero;
      _slotFeedbackTargets[slot] = null;
    });
  }

  void _commitSlot(_CompareSlot slot, _CullStatus status) {
    final photo = _photoForSlot(slot);
    if (_commitInFlight || photo == null) {
      return;
    }
    final exitY = status == _CullStatus.keep
        ? _compareCardExitDistance
        : -_compareCardExitDistance;
    setState(() {
      _removeFromLocalBuckets(photo.id);
      if (status == _CullStatus.keep) {
        _keptIds.insert(0, photo.id);
      } else {
        _discardedIds.insert(0, photo.id);
      }
      _exiting = _CompareExitingPhoto(photo: photo, slot: slot);
      _commitInFlight = true;
      final currentOffset = _slotOffsets[slot] ?? Offset.zero;
      _slotOffsets[slot] = Offset(
        currentOffset.dx.clamp(-72, 72).toDouble(),
        exitY,
      );
      _slotFeedbackTargets[slot] = null;
      _previewOpen = false;
    });
    widget.onSetStatus(photo, status);
    Future<void>.delayed(_fastCommitAnimationDuration, () {
      if (!mounted || _exiting?.photo.id != photo.id) {
        return;
      }
      setState(() {
        _exiting = null;
        _slotOffsets[slot] = Offset.zero;
        _fillOpenSlots();
        _commitInFlight = false;
      });
    });
  }

  void _recallPhoto(_CullPhotoView photo) {
    if (_commitInFlight) {
      return;
    }
    setState(() {
      _removeFromLocalBuckets(photo.id);
      if (_rightId == null) {
        _rightId = photo.id;
      } else if (_leftId == null) {
        _leftId = photo.id;
      } else {
        _pendingIds.insert(0, _rightId!);
        _rightId = photo.id;
      }
      _slotOffsets[_CompareSlot.left] = Offset.zero;
      _slotOffsets[_CompareSlot.right] = Offset.zero;
      _slotFeedbackTargets[_CompareSlot.left] = null;
      _slotFeedbackTargets[_CompareSlot.right] = null;
      _previewOpen = false;
    });
    widget.onSetStatus(photo, _CullStatus.pending);
  }

  void _removeFromLocalBuckets(String id) {
    _pendingIds.remove(id);
    _keptIds.remove(id);
    _discardedIds.remove(id);
    if (_leftId == id) {
      _leftId = null;
    }
    if (_rightId == id) {
      _rightId = null;
    }
  }

  _CullStatus? _targetForOffset(Offset offset) {
    if (offset.dy <= -_compareTriggerDragDistance) {
      return _CullStatus.out;
    }
    if (offset.dy >= _compareTriggerDragDistance) {
      return _CullStatus.keep;
    }
    return null;
  }

  void _updateSlotFeedback(_CompareSlot slot, _CullStatus? status) {
    if (_slotFeedbackTargets[slot] == status) {
      return;
    }
    _slotFeedbackTargets[slot] = status;
    if (status != null) {
      _playCullHapticFeedback();
    }
  }

  void _openPreview() {
    if (_leftPhoto == null && _rightPhoto == null) {
      return;
    }
    if (_previewOpen) {
      return;
    }
    final leftPhoto = _leftPhoto;
    final rightPhoto = _rightPhoto;
    final singlePhoto = leftPhoto != null && rightPhoto == null
        ? leftPhoto
        : leftPhoto == null && rightPhoto != null
        ? rightPhoto
        : null;
    setState(() => _previewOpen = true);
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, _) {
        return Material(
          type: MaterialType.transparency,
          child: singlePhoto == null
              ? _ComparePairPreviewOverlay(
                  palette: widget.palette,
                  leftPhoto: leftPhoto,
                  rightPhoto: rightPhoto,
                  onClose: () => Navigator.of(dialogContext).pop(),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _CullPreviewOverlay(
                      palette: widget.palette,
                      photo: singlePhoto,
                      onClose: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        setState(() => _previewOpen = false);
      }
    });
  }

  double _slotActiveBias(Offset offset) {
    return math
            .max(math.max(0.0, -offset.dy), math.max(0.0, offset.dy))
            .clamp(0.0, _compareTriggerDragDistance) /
        _compareTriggerDragDistance;
  }

  bool _slotIsExiting(_CompareSlot slot) {
    return _exiting?.slot == slot && _commitInFlight;
  }

  Widget _buildComparePhotoPane({
    required _CompareSlot slot,
    required _CullPhotoView? photo,
    required Offset offset,
  }) {
    final left = slot == _CompareSlot.left;
    return _ComparePhotoPane(
      palette: widget.palette,
      photo: photo,
      slotKey: left ? 'compare-cull-left-photo' : 'compare-cull-right-photo',
      accentColor: left ? _compareLeftAccent : _compareRightAccent,
      offset: offset,
      activeBias: _slotActiveBias(offset),
      exiting: _slotIsExiting(slot),
      committing: _commitInFlight,
      onTap: _openPreview,
      onDragUpdate: (details) => _handleDragUpdate(slot, details),
      onDragEnd: () => _handleDragEnd(slot),
      onDragCancel: () => _resetSlotDrag(slot),
    );
  }

  Widget _buildCurrentPhotoStage({
    required BoxConstraints constraints,
    required _CullPhotoView? leftPhoto,
    required _CullPhotoView? rightPhoto,
    required Offset leftOffset,
    required Offset rightOffset,
  }) {
    if (leftPhoto == null && rightPhoto == null) {
      return _FastCullComplete(
        palette: widget.palette,
        strings: widget.strings,
        totalCount: widget.group.photos.length,
        onClose: widget.onClose,
        onOpenNextIncomplete: widget.onOpenNextIncomplete,
      );
    }

    final singleSlot = leftPhoto != null && rightPhoto == null
        ? _CompareSlot.left
        : leftPhoto == null && rightPhoto != null
        ? _CompareSlot.right
        : null;
    if (singleSlot != null) {
      final photo = singleSlot == _CompareSlot.left ? leftPhoto! : rightPhoto!;
      final offset = singleSlot == _CompareSlot.left ? leftOffset : rightOffset;
      final frameSize = _compareSingleFrameSize(
        photo.aspectRatio,
        constraints.biggest,
      );
      return Center(
        child: SizedBox(
          width: frameSize.width,
          height: frameSize.height,
          child: _buildComparePhotoPane(
            slot: singleSlot,
            photo: photo,
            offset: offset,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _buildComparePhotoPane(
            slot: _CompareSlot.left,
            photo: leftPhoto,
            offset: leftOffset,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildComparePhotoPane(
            slot: _CompareSlot.right,
            photo: rightPhoto,
            offset: rightOffset,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final leftPhoto = _leftPhoto;
    final rightPhoto = _rightPhoto;
    final leftOffset = _slotOffsets[_CompareSlot.left] ?? Offset.zero;
    final rightOffset = _slotOffsets[_CompareSlot.right] ?? Offset.zero;
    final discardBias =
        math
            .max(0.0, math.max(-leftOffset.dy, -rightOffset.dy))
            .clamp(0.0, _compareTriggerDragDistance)
            .toDouble() /
        _compareTriggerDragDistance;
    final keepBias =
        math
            .max(0.0, math.max(leftOffset.dy, rightOffset.dy))
            .clamp(0.0, _compareTriggerDragDistance)
            .toDouble() /
        _compareTriggerDragDistance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final upperBoundaryY = constraints.maxHeight * _cullUpperBoundaryFactor;
        final lowerBoundaryY = constraints.maxHeight * _cullLowerBoundaryFactor;
        final upperLabelTop =
            upperBoundaryY - _fastTargetLabelCenterGap - _modeLabelHeight / 2;
        final lowerLabelTop =
            lowerBoundaryY + _fastTargetLabelCenterGap - _modeLabelHeight / 2;
        final labelTopMax = math.max(
          0,
          constraints.maxHeight - _modeLabelHeight,
        );
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: _FloatingCullField(
                key: const ValueKey('compare-cull-boundary-field'),
                palette: widget.palette,
                upperBias: discardBias,
                lowerBias: keepBias,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: upperLabelTop.clamp(0.0, labelTopMax).toDouble(),
              height: _modeLabelHeight,
              child: _ModeLabel(
                key: const ValueKey('compare-cull-discard-label'),
                palette: widget.palette,
                text: widget.strings.cullDiscardTarget,
                activeBias: math.max(0.22, discardBias),
                activeShiftY: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 74,
              bottom: 74,
              child: LayoutBuilder(
                builder: (context, photoConstraints) {
                  return _buildCurrentPhotoStage(
                    constraints: photoConstraints,
                    leftPhoto: leftPhoto,
                    rightPhoto: rightPhoto,
                    leftOffset: leftOffset,
                    rightOffset: rightOffset,
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: lowerLabelTop.clamp(0.0, labelTopMax).toDouble(),
              height: _modeLabelHeight,
              child: _ModeLabel(
                key: const ValueKey('compare-cull-keep-label'),
                palette: widget.palette,
                text: widget.strings.cullKeepTarget,
                activeBias: math.max(0.22, keepBias),
                activeShiftY: 0,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _fastDecisionQueueHeight,
              child: _FastDecisionQueue(
                palette: widget.palette,
                icon: Icons.delete_outline_rounded,
                ids: _discardedIds,
                photoById: _photosById,
                onRecall: _recallPhoto,
                queueKeyPrefix: 'compare-cull-discard',
                contentAlignment: Alignment.topLeft,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _fastDecisionQueueHeight,
              child: _FastDecisionQueue(
                palette: widget.palette,
                icon: Icons.check_rounded,
                ids: _keptIds,
                photoById: _photosById,
                onRecall: _recallPhoto,
                queueKeyPrefix: 'compare-cull-keep',
                contentAlignment: Alignment.bottomLeft,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ComparePhotoPane extends StatefulWidget {
  const _ComparePhotoPane({
    required this.palette,
    required this.photo,
    required this.slotKey,
    required this.accentColor,
    required this.offset,
    required this.activeBias,
    required this.exiting,
    required this.committing,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final NoemaPalette palette;
  final _CullPhotoView? photo;
  final String slotKey;
  final Color accentColor;
  final Offset offset;
  final double activeBias;
  final bool exiting;
  final bool committing;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  State<_ComparePhotoPane> createState() => _ComparePhotoPaneState();
}

class _ComparePhotoPaneState extends State<_ComparePhotoPane> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  String? _imageIdentity;
  double? _resolvedAspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageAspectRatioIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ComparePhotoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIdentity = _comparePhotoImageIdentity(widget.photo);
    if (nextIdentity != _imageIdentity) {
      _resolvedAspectRatio = null;
      _clearImageStream();
      _resolveImageAspectRatioIfNeeded();
    }
  }

  @override
  void dispose() {
    _clearImageStream();
    super.dispose();
  }

  void _clearImageStream() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  void _resolveImageAspectRatioIfNeeded() {
    final photo = widget.photo;
    final identity = _comparePhotoImageIdentity(photo);
    if (identity == null ||
        identity == _imageIdentity && _imageStream != null) {
      _imageIdentity = identity;
      return;
    }

    _clearImageStream();
    _imageIdentity = identity;
    if (_comparePhotoCanUseMetadataAspectRatio(photo)) {
      return;
    }

    final previewBytesRatio = _comparePhotoPreviewBytesAspectRatio(photo);
    if (previewBytesRatio != null) {
      _resolvedAspectRatio = previewBytesRatio;
      return;
    }

    final provider = _comparePhotoImageProvider(photo);
    if (provider == null) {
      return;
    }

    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((imageInfo, _) {
      final width = imageInfo.image.width;
      final height = imageInfo.image.height;
      if (!mounted || width <= 0 || height <= 0) {
        return;
      }
      final ratio = width / height;
      if (!ratio.isFinite) {
        return;
      }
      setState(() => _resolvedAspectRatio = ratio);
    });
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    if (photo == null) {
      return _CompareEmptyPane(
        palette: widget.palette,
        slotKey: widget.slotKey,
      );
    }
    final glowColor = Color.lerp(widget.palette.ink, Colors.white, 0.76)!;
    final paneAspectRatio = (_resolvedAspectRatio ?? photo.aspectRatio)
        .clamp(0.45, 2.2)
        .toDouble();
    final hasRenderableImage = _comparePhotoImageProvider(photo) != null;
    return IgnorePointer(
      ignoring: widget.committing && !widget.exiting,
      child: GestureDetector(
        key: ValueKey(widget.slotKey),
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        onPanUpdate: widget.onDragUpdate,
        onPanEnd: (_) => widget.onDragEnd(),
        onPanCancel: widget.onDragCancel,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final photoFrame = AnimatedOpacity(
                duration: widget.exiting
                    ? _fastCommitAnimationDuration
                    : const Duration(milliseconds: 160),
                curve: widget.exiting ? Curves.easeOutCubic : _cullEase,
                opacity: widget.exiting ? 0 : 1,
                child: AnimatedContainer(
                  key: ValueKey('${widget.slotKey}-${photo.id}'),
                  duration: widget.exiting
                      ? _fastCommitAnimationDuration
                      : widget.offset.distance > 0.5
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: widget.exiting ? Curves.easeInCubic : _cullEase,
                  transform: Matrix4.identity()
                    ..translateByDouble(
                      widget.offset.dx,
                      widget.offset.dy,
                      0,
                      1,
                    )
                    ..rotateZ(
                      (widget.offset.dx / 360).clamp(-0.035, 0.035).toDouble(),
                    ),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasRenderableImage
                        ? Colors.transparent
                        : Colors.black.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color.lerp(
                        widget.accentColor.withValues(alpha: 0.62),
                        glowColor.withValues(alpha: 0.78),
                        widget.activeBias.clamp(0.0, 1.0).toDouble(),
                      )!,
                      width: 1 + widget.activeBias,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 22,
                        offset: const Offset(0, 14),
                      ),
                      if (widget.activeBias > 0)
                        BoxShadow(
                          color: glowColor.withValues(
                            alpha: widget.activeBias * 0.16,
                          ),
                          blurRadius: 26 + widget.activeBias * 12,
                          spreadRadius: widget.activeBias,
                        ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _CullPhotoImage(
                    palette: widget.palette,
                    photo: photo,
                    fit: BoxFit.contain,
                  ),
                ),
              );
              return AspectRatio(
                aspectRatio: paneAspectRatio,
                child: SizedBox.expand(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: photoFrame,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

String? _comparePhotoImageIdentity(_CullPhotoView? photo) {
  final asset = photo?.asset;
  if (photo == null || asset == null) {
    return null;
  }
  return [
    photo.id,
    asset.previewBytes?.length,
    asset.photo.previewPath,
    asset.photo.thumbnailPath,
    asset.photo.sourceUri,
  ].join('|');
}

bool _comparePhotoCanUseMetadataAspectRatio(_CullPhotoView? photo) {
  final asset = photo?.asset;
  if (asset == null || asset.previewBytes != null) {
    return false;
  }

  final source = asset.photo;
  return !source.dimensionsEstimated && source.width > 0 && source.height > 0;
}

ImageProvider<Object>? _comparePhotoImageProvider(_CullPhotoView? photo) {
  final asset = photo?.asset;
  if (asset == null ||
      asset.photo.availability == AssetAvailability.unavailable) {
    return null;
  }
  final previewBytes = asset.previewBytes;
  if (previewBytes != null) {
    return MemoryImage(previewBytes);
  }
  final displayPath = asset.photo.previewPath ?? asset.photo.thumbnailPath;
  if (displayPath != null && displayPath.isNotEmpty) {
    return importImageProviderFromPath(displayPath);
  }
  return null;
}

double? _comparePhotoPreviewBytesAspectRatio(_CullPhotoView? photo) {
  final previewBytes = photo?.asset?.previewBytes;
  if (previewBytes == null) {
    return null;
  }
  try {
    final decoded = img.decodeImage(previewBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    return decoded.width / decoded.height;
  } catch (_) {
    return null;
  }
}

class _CompareEmptyPane extends StatelessWidget {
  const _CompareEmptyPane({required this.palette, required this.slotKey});

  final NoemaPalette palette;
  final String slotKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('$slotKey-empty'),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.ink.withValues(alpha: 0.12)),
      ),
      child: Center(
        child: Icon(
          Icons.hourglass_empty_rounded,
          size: 18,
          color: palette.ink.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

class _ComparePairPreviewOverlay extends StatefulWidget {
  const _ComparePairPreviewOverlay({
    required this.palette,
    required this.leftPhoto,
    required this.rightPhoto,
    required this.onClose,
  });

  final NoemaPalette palette;
  final _CullPhotoView? leftPhoto;
  final _CullPhotoView? rightPhoto;
  final VoidCallback onClose;

  @override
  State<_ComparePairPreviewOverlay> createState() =>
      _ComparePairPreviewOverlayState();
}

class _ComparePairPreviewOverlayState extends State<_ComparePairPreviewOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TransformationController _leftController = TransformationController();
  final TransformationController _rightController = TransformationController();
  late final AnimationController _openController;
  late final Animation<double> _openProgress;
  late final AnimationController _zoomController;
  Animation<Matrix4>? _zoomAnimation;
  bool _syncing = false;
  bool _closing = false;
  Offset? _overlayPointerDownPosition;
  bool _overlayPointerMoved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openController = AnimationController(
      vsync: this,
      duration: _comparePreviewOpenDuration,
    )..forward();
    _openProgress = CurvedAnimation(
      parent: _openController,
      curve: _comparePreviewOpenEase,
    );
    _zoomController = AnimationController(
      vsync: this,
      duration: _previewZoomDuration,
    )..addListener(_handleZoomTick);
    _leftController.addListener(_handleLeftTransform);
    _rightController.addListener(_handleRightTransform);
  }

  @override
  void didUpdateWidget(covariant _ComparePairPreviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftPhoto?.id != widget.leftPhoto?.id ||
        oldWidget.rightPhoto?.id != widget.rightPhoto?.id) {
      _zoomController.stop();
      _zoomAnimation = null;
      _setBoth(Matrix4.identity());
      _openController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leftController.removeListener(_handleLeftTransform);
    _rightController.removeListener(_handleRightTransform);
    _leftController.dispose();
    _rightController.dispose();
    _openController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    _closePreview();
    return true;
  }

  void _handleLeftTransform() => _syncFrom(_leftController, _rightController);

  void _handleRightTransform() => _syncFrom(_rightController, _leftController);

  void _syncFrom(
    TransformationController source,
    TransformationController target,
  ) {
    if (_syncing) {
      return;
    }
    _syncing = true;
    target.value = Matrix4.copy(source.value);
    _syncing = false;
  }

  void _handleZoomTick() {
    final animation = _zoomAnimation;
    if (animation != null) {
      _setBoth(animation.value);
    }
  }

  void _setBoth(Matrix4 matrix) {
    _syncing = true;
    _leftController.value = Matrix4.copy(matrix);
    _rightController.value = Matrix4.copy(matrix);
    _syncing = false;
  }

  void _closePreview() {
    if (_closing) {
      return;
    }
    _closing = true;
    widget.onClose();
  }

  void _handleOverlayPointerDown(PointerDownEvent event) {
    _overlayPointerDownPosition = event.localPosition;
    _overlayPointerMoved = false;
  }

  void _handleOverlayPointerMove(PointerMoveEvent event) {
    final start = _overlayPointerDownPosition;
    if (start == null) {
      return;
    }
    final delta = event.localPosition - start;
    if (start.dx <= 28 && delta.dx > 72 && delta.dy.abs() < 96) {
      _overlayPointerMoved = true;
      _closePreview();
      return;
    }
    if (delta.distance > 8) {
      _overlayPointerMoved = true;
    }
  }

  void _handleOverlayPointerUp(PointerUpEvent event, List<Rect> photoRects) {
    final start = _overlayPointerDownPosition;
    final tap = event.localPosition;
    if (_overlayPointerMoved || start == null || (tap - start).distance > 8) {
      return;
    }
    _overlayPointerDownPosition = null;
    final hitsPhoto = photoRects.any((rect) => rect.inflate(12).contains(tap));
    if (!hitsPhoto) {
      _closePreview();
    }
  }

  void _handleDoubleTap(Size viewportSize, Offset position) {
    _zoomController.stop();
    final currentScale = _leftController.value.getMaxScaleOnAxis();
    final targetScale = currentScale > 1.05 ? 1.0 : 2.5;
    final target = targetScale <= 1.01 ? Matrix4.identity() : Matrix4.identity()
      ..translateByDouble(
        viewportSize.width / 2 - position.dx * targetScale,
        viewportSize.height / 2 - position.dy * targetScale,
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, targetScale, 1);
    _zoomAnimation = Matrix4Tween(
      begin: _leftController.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomController, curve: _cullEase));
    _zoomController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePreview();
        }
      },
      child: KeyedSubtree(
        key: const ValueKey('compare-cull-pair-preview'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final overlaySize = constraints.biggest;
            final safePadding = MediaQuery.of(context).padding;
            final contentLeft = 18.0;
            final contentTop = safePadding.top + 18;
            final contentRight = math.max(contentLeft, overlaySize.width - 18);
            final contentBottom = math.max(
              contentTop,
              overlaySize.height - safePadding.bottom - 22,
            );
            final contentRect = Rect.fromLTRB(
              contentLeft,
              contentTop,
              contentRight,
              contentBottom,
            );
            final viewport = contentRect.size;
            const gap = 16.0;
            final paneHeight = math.max(0.0, (viewport.height - gap) / 2);
            final topPane = Rect.fromLTWH(0, 0, viewport.width, paneHeight);
            final bottomPane = Rect.fromLTWH(
              0,
              paneHeight + gap,
              viewport.width,
              paneHeight,
            );
            final photoRects = [
              if (widget.leftPhoto != null)
                _transformRect(
                  _leftController.value,
                  _comparePreviewTargetRect(widget.leftPhoto!, topPane),
                ).translate(contentRect.left, contentRect.top),
              if (widget.rightPhoto != null)
                _transformRect(
                  _rightController.value,
                  _comparePreviewTargetRect(widget.rightPhoto!, bottomPane),
                ).translate(contentRect.left, contentRect.top),
            ];

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handleOverlayPointerDown,
              onPointerMove: _handleOverlayPointerMove,
              onPointerUp: (event) =>
                  _handleOverlayPointerUp(event, photoRects),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fromRect(
                          rect: contentRect,
                          child: AnimatedBuilder(
                            animation: _openProgress,
                            builder: (context, _) {
                              final progress = _openProgress.value;
                              final finalOpacity = ((progress - 0.38) / 0.54)
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                              final travelOpacity =
                                  (1 - ((progress - 0.88) / 0.12))
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Opacity(
                                    opacity: finalOpacity,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _CompareSyncedPreviewPane(
                                            palette: widget.palette,
                                            photo: widget.leftPhoto,
                                            controller: _leftController,
                                            paneKeyPrefix:
                                                'compare-cull-preview-left-photo',
                                            edgeColor: _compareLeftAccent,
                                            onDoubleTap: _handleDoubleTap,
                                            onTapOutside: _closePreview,
                                          ),
                                        ),
                                        const SizedBox(height: gap),
                                        Expanded(
                                          child: _CompareSyncedPreviewPane(
                                            palette: widget.palette,
                                            photo: widget.rightPhoto,
                                            controller: _rightController,
                                            paneKeyPrefix:
                                                'compare-cull-preview-right-photo',
                                            edgeColor: _compareRightAccent,
                                            onDoubleTap: _handleDoubleTap,
                                            onTapOutside: _closePreview,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (progress < 1 && widget.leftPhoto != null)
                                    _previewTravelPhoto(
                                      photo: widget.leftPhoto!,
                                      slot: _CompareSlot.left,
                                      viewport: viewport,
                                      targetPane: topPane,
                                      progress: progress,
                                      opacity: travelOpacity,
                                      edgeColor: _compareLeftAccent,
                                    ),
                                  if (progress < 1 && widget.rightPhoto != null)
                                    _previewTravelPhoto(
                                      photo: widget.rightPhoto!,
                                      slot: _CompareSlot.right,
                                      viewport: viewport,
                                      targetPane: bottomPane,
                                      progress: progress,
                                      opacity: travelOpacity,
                                      edgeColor: _compareRightAccent,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _previewTravelPhoto({
    required _CullPhotoView photo,
    required _CompareSlot slot,
    required Size viewport,
    required Rect targetPane,
    required double progress,
    required double opacity,
    required Color edgeColor,
  }) {
    final source = _comparePreviewSourceRect(photo, slot, viewport);
    final target = _comparePreviewTargetRect(photo, targetPane);
    final rect = RectTween(begin: source, end: target).lerp(progress) ?? target;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: RepaintBoundary(
            child: _ComparePreviewTravelPhoto(
              key: ValueKey(
                'compare-cull-preview-travel-${slot == _CompareSlot.left ? 'left' : 'right'}-photo-${photo.id}',
              ),
              palette: widget.palette,
              photo: photo,
              edgeColor: edgeColor,
            ),
          ),
        ),
      ),
    );
  }
}

Rect _comparePreviewSourceRect(
  _CullPhotoView photo,
  _CompareSlot slot,
  Size viewport,
) {
  final ratio = photo.aspectRatio.clamp(0.45, 2.2).toDouble();
  final maxWidth = math.min(126.0, viewport.width * 0.42);
  final maxHeight = math.min(172.0, viewport.height * 0.42);
  var width = maxWidth;
  var height = width / ratio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  final center = Offset(
    viewport.width * (slot == _CompareSlot.left ? 0.32 : 0.68),
    viewport.height * 0.52,
  );
  return Rect.fromCenter(center: center, width: width, height: height);
}

Rect _comparePreviewTargetRect(_CullPhotoView photo, Rect targetPane) {
  final imageSize = _previewPhotoSize(photo.aspectRatio, targetPane.size);
  return Rect.fromCenter(
    center: targetPane.center,
    width: imageSize.width,
    height: imageSize.height,
  );
}

class _ComparePreviewTravelPhoto extends StatelessWidget {
  const _ComparePreviewTravelPhoto({
    super.key,
    required this.palette,
    required this.photo,
    required this.edgeColor,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final Color edgeColor;

  @override
  Widget build(BuildContext context) {
    return _CullPreviewPhotoEdge(
      edgeColor: edgeColor,
      child: _CullPhotoImage(palette: palette, photo: photo, fit: BoxFit.cover),
    );
  }
}

class _CullPreviewPhotoEdge extends StatelessWidget {
  const _CullPreviewPhotoEdge({required this.edgeColor, required this.child});

  final Color edgeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final softEdge = Color.lerp(edgeColor, Colors.white, 0.68)!;
    const radius = 8.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: softEdge.withValues(alpha: 0.7),
                      width: 1.1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareSyncedPreviewPane extends StatefulWidget {
  const _CompareSyncedPreviewPane({
    required this.palette,
    required this.photo,
    required this.controller,
    required this.paneKeyPrefix,
    required this.edgeColor,
    required this.onDoubleTap,
    required this.onTapOutside,
  });

  final NoemaPalette palette;
  final _CullPhotoView? photo;
  final TransformationController controller;
  final String paneKeyPrefix;
  final Color edgeColor;
  final void Function(Size viewportSize, Offset position) onDoubleTap;
  final VoidCallback onTapOutside;

  @override
  State<_CompareSyncedPreviewPane> createState() =>
      _CompareSyncedPreviewPaneState();
}

class _CompareSyncedPreviewPaneState extends State<_CompareSyncedPreviewPane> {
  Offset? _doubleTapPosition;
  Offset? _pointerDownPosition;
  bool _pointerMoved = false;

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.localPosition;
    _pointerMoved = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _pointerDownPosition;
    if (start == null) {
      return;
    }
    final delta = event.localPosition - start;
    if (start.dx <= 28 && delta.dx > 72 && delta.dy.abs() < 96) {
      _pointerMoved = true;
      widget.onTapOutside();
      return;
    }
    if (delta.distance > 8) {
      _pointerMoved = true;
    }
  }

  void _handlePointerUp(
    PointerUpEvent event,
    Size viewportSize,
    Size imageSize,
  ) {
    final tap = event.localPosition;
    final start = _pointerDownPosition;
    if (_pointerMoved || start == null || (tap - start).distance > 8) {
      return;
    }
    _pointerDownPosition = null;
    _handleTapOutside(viewportSize, imageSize, tap);
  }

  void _handleTapOutside(Size viewportSize, Size imageSize, Offset tap) {
    final baseRect = Rect.fromCenter(
      center: Offset(viewportSize.width / 2, viewportSize.height / 2),
      width: imageSize.width,
      height: imageSize.height,
    );
    final transformedRect = _transformRect(
      widget.controller.value,
      baseRect,
    ).inflate(12);
    if (!transformedRect.contains(tap)) {
      widget.onTapOutside();
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    if (photo == null) {
      return GestureDetector(
        key: ValueKey('${widget.paneKeyPrefix}-empty'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapOutside,
        child: _CompareEmptyPane(
          palette: widget.palette,
          slotKey: widget.paneKeyPrefix,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageSize = _previewPhotoSize(photo.aspectRatio, viewportSize);
        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: (event) =>
              _handlePointerUp(event, viewportSize, imageSize),
          child: GestureDetector(
            key: ValueKey('${widget.paneKeyPrefix}-${photo.id}'),
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: () {
              widget.onDoubleTap(
                viewportSize,
                _doubleTapPosition ??
                    Offset(viewportSize.width / 2, viewportSize.height / 2),
              );
            },
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: widget.controller,
                minScale: 1,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(120),
                clipBehavior: Clip.none,
                constrained: false,
                child: SizedBox(
                  width: viewportSize.width,
                  height: viewportSize.height,
                  child: Center(
                    child: SizedBox(
                      width: imageSize.width,
                      height: imageSize.height,
                      child: _CullPreviewPhotoEdge(
                        edgeColor: widget.edgeColor,
                        child: _CullPhotoImage(
                          palette: widget.palette,
                          photo: photo,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Rect _transformRect(Matrix4 transform, Rect rect) {
  final topLeft = MatrixUtils.transformPoint(transform, rect.topLeft);
  final topRight = MatrixUtils.transformPoint(transform, rect.topRight);
  final bottomLeft = MatrixUtils.transformPoint(transform, rect.bottomLeft);
  final bottomRight = MatrixUtils.transformPoint(transform, rect.bottomRight);
  final left = math.min(
    math.min(topLeft.dx, topRight.dx),
    math.min(bottomLeft.dx, bottomRight.dx),
  );
  final top = math.min(
    math.min(topLeft.dy, topRight.dy),
    math.min(bottomLeft.dy, bottomRight.dy),
  );
  final right = math.max(
    math.max(topLeft.dx, topRight.dx),
    math.max(bottomLeft.dx, bottomRight.dx),
  );
  final bottom = math.max(
    math.max(topLeft.dy, topRight.dy),
    math.max(bottomLeft.dy, bottomRight.dy),
  );
  return Rect.fromLTRB(left, top, right, bottom);
}

class _CullPreviewOverlay extends StatefulWidget {
  const _CullPreviewOverlay({
    required this.palette,
    required this.photo,
    required this.onClose,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final VoidCallback onClose;

  @override
  State<_CullPreviewOverlay> createState() => _CullPreviewOverlayState();
}

class _CullPreviewOverlayState extends State<_CullPreviewOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _openController;
  late final Animation<double> _openProgress;

  @override
  void initState() {
    super.initState();
    _openController = AnimationController(
      vsync: this,
      duration: _singlePreviewOpenDuration,
    )..forward();
    _openProgress = CurvedAnimation(
      parent: _openController,
      curve: _previewOpenEase,
    );
  }

  @override
  void didUpdateWidget(covariant _CullPreviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id) {
      _openController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _openController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.palette.tone == NoemaTone.dark
        ? Colors.black
        : const Color(0xFFF4EFE5);
    return Positioned.fill(
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            widget.onClose();
          }
        },
        child: KeyedSubtree(
          key: const ValueKey('cull-preview-backdrop'),
          child: AnimatedBuilder(
            animation: _openProgress,
            builder: (context, _) {
              final progress = _openProgress.value;
              final backgroundOpacity = (progress / 0.86)
                  .clamp(0.0, 1.0)
                  .toDouble();
              final photoOpacity = ((progress - 0.04) / 0.72)
                  .clamp(0.0, 1.0)
                  .toDouble();
              final photoScale = ui.lerpDouble(0.94, 1, progress)!;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: backgroundOpacity),
                ),
                child: IgnorePointer(
                  ignoring: progress < 0.72,
                  child: RepaintBoundary(
                    child: Opacity(
                      key: ValueKey(
                        'cull-preview-open-transition-${widget.photo.id}',
                      ),
                      opacity: photoOpacity,
                      child: Transform.scale(
                        scale: photoScale,
                        child: _CullZoomablePhoto(
                          palette: widget.palette,
                          photo: widget.photo,
                          onTapOutside: widget.onClose,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CullZoomablePhoto extends StatefulWidget {
  const _CullZoomablePhoto({
    required this.palette,
    required this.photo,
    required this.onTapOutside,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final VoidCallback onTapOutside;

  @override
  State<_CullZoomablePhoto> createState() => _CullZoomablePhotoState();
}

class _CullZoomablePhotoState extends State<_CullZoomablePhoto>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TransformationController _controller = TransformationController();
  late final AnimationController _zoomController;
  Animation<Matrix4>? _zoomAnimation;
  Size? _viewportSize;
  Size? _fittedPhotoSize;
  Offset? _doubleTapPosition;
  Offset? _pointerDownPosition;
  bool _clampingMatrix = false;
  bool _interactionActive = false;
  bool _underscaleSeen = false;
  bool _zoomed = false;
  bool _pointerMoved = false;
  bool _closing = false;
  int _activePointerCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zoomController = AnimationController(
      vsync: this,
      duration: _previewZoomDuration,
    )..addListener(_handleZoomTick);
    _controller.addListener(_handleMatrixChanged);
  }

  @override
  void didUpdateWidget(covariant _CullZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id) {
      _zoomController.stop();
      _zoomAnimation = null;
      _interactionActive = false;
      _underscaleSeen = false;
      _activePointerCount = 0;
      _setControllerValue(Matrix4.identity());
      _setZoomed(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleMatrixChanged);
    _controller.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    _closePreview();
    return true;
  }

  void _closePreview() {
    if (_closing) {
      return;
    }
    _closing = true;
    widget.onTapOutside();
  }

  void _handleZoomTick() {
    final animation = _zoomAnimation;
    if (animation != null) {
      _setControllerValue(animation.value);
    }
  }

  void _handleMatrixChanged() {
    if (_clampingMatrix) {
      return;
    }

    final viewportSize = _viewportSize;
    final fittedPhotoSize = _fittedPhotoSize;
    if (viewportSize != null && fittedPhotoSize != null) {
      final clamped = _clampedMatrix(
        _controller.value,
        viewportSize: viewportSize,
        fittedPhotoSize: fittedPhotoSize,
        minScale: _interactionActive ? _singlePreviewMinInteractionScale : 1,
      );
      if (!_cullPreviewMatrixMatches(_controller.value, clamped)) {
        _setControllerValue(clamped);
      }
    }

    final scale = _controller.value.getMaxScaleOnAxis();
    _setZoomed(_activePointerCount > 1 || scale > 1.01);
  }

  void _setControllerValue(Matrix4 value) {
    _clampingMatrix = true;
    _controller.value = value;
    _clampingMatrix = false;
  }

  void _setZoomed(bool zoomed) {
    if (_zoomed == zoomed || !mounted) {
      return;
    }
    setState(() => _zoomed = zoomed);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.localPosition;
    _pointerMoved = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _pointerDownPosition;
    if (start == null) {
      return;
    }
    final delta = event.localPosition - start;
    if (start.dx <= 28 && delta.dx > 72 && delta.dy.abs() < 96) {
      _pointerMoved = true;
      _closePreview();
      return;
    }
    if (delta.distance > 8) {
      _pointerMoved = true;
    }
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _zoomController.stop();
    _interactionActive = true;
    _activePointerCount = details.pointerCount;
    _underscaleSeen = false;
    if (details.pointerCount > 1) {
      _setZoomed(true);
    }
  }

  void _handleInteractionUpdate(
    ScaleUpdateDetails details,
    Size viewportSize,
    Size fittedPhotoSize,
  ) {
    _interactionActive = true;
    _activePointerCount = details.pointerCount;
    final matrix = Matrix4.copy(_controller.value);
    final scale = matrix.getMaxScaleOnAxis();
    if (scale < _singlePreviewDismissScale) {
      _underscaleSeen = true;
    }

    _setControllerValue(
      _clampedMatrix(
        matrix,
        viewportSize: viewportSize,
        fittedPhotoSize: fittedPhotoSize,
        minScale: _singlePreviewMinInteractionScale,
      ),
    );
    _setZoomed(details.pointerCount > 1 || scale > 1.01);
  }

  void _handleInteractionEnd(
    ScaleEndDetails details,
    Size viewportSize,
    Size fittedPhotoSize,
  ) {
    _interactionActive = false;
    _activePointerCount = 0;
    final scale = _controller.value.getMaxScaleOnAxis();
    if (_underscaleSeen || scale < _singlePreviewDismissScale) {
      _closePreview();
      return;
    }
    _underscaleSeen = false;
    if (scale <= 1.01) {
      _setControllerValue(Matrix4.identity());
      _setZoomed(false);
      return;
    }

    _setControllerValue(
      _clampedMatrix(
        _controller.value,
        viewportSize: viewportSize,
        fittedPhotoSize: fittedPhotoSize,
        minScale: 1,
      ),
    );
    _setZoomed(true);
  }

  void _handlePointerUp(
    PointerUpEvent event,
    Size viewportSize,
    Size imageSize,
  ) {
    final tap = event.localPosition;
    final start = _pointerDownPosition;
    if (_pointerMoved || start == null || (tap - start).distance > 8) {
      return;
    }
    _pointerDownPosition = null;
    final baseRect = Rect.fromCenter(
      center: Offset(viewportSize.width / 2, viewportSize.height / 2),
      width: imageSize.width,
      height: imageSize.height,
    );
    final transformedRect = _transformRect(
      _controller.value,
      baseRect,
    ).inflate(12);
    if (!transformedRect.contains(tap)) {
      _closePreview();
    }
  }

  void _handleDoubleTap(Size viewportSize) {
    _zoomController.stop();
    final currentScale = _controller.value.getMaxScaleOnAxis();
    _interactionActive = false;
    _activePointerCount = 0;
    _underscaleSeen = false;
    final targetScale = currentScale > 1.05
        ? 1.0
        : _singlePreviewDoubleTapScale;
    final tap =
        _doubleTapPosition ??
        Offset(viewportSize.width / 2, viewportSize.height / 2);
    final fittedPhotoSize =
        _fittedPhotoSize ??
        _singlePreviewPhotoSize(widget.photo.aspectRatio, viewportSize);
    final target = targetScale <= 1.01
        ? Matrix4.identity()
        : _clampedMatrix(
            Matrix4.identity()
              ..translateByDouble(
                viewportSize.width / 2 - tap.dx * targetScale,
                viewportSize.height / 2 - tap.dy * targetScale,
                0,
                1,
              )
              ..scaleByDouble(targetScale, targetScale, targetScale, 1),
            viewportSize: viewportSize,
            fittedPhotoSize: fittedPhotoSize,
            minScale: 1,
          );
    _zoomAnimation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomController, curve: _cullEase));
    _zoomController.forward(from: 0);
    _setZoomed(targetScale > 1.01);
  }

  Matrix4 _clampedMatrix(
    Matrix4 source, {
    required Size viewportSize,
    required Size fittedPhotoSize,
    required double minScale,
  }) {
    final matrix = Matrix4.copy(source);
    final scale = matrix
        .getMaxScaleOnAxis()
        .clamp(minScale, _singlePreviewMaxScale)
        .toDouble();
    final baseX = viewportSize.width * (1 - scale) / 2;
    final baseY = viewportSize.height * (1 - scale) / 2;
    final maxX = math.max(
      0.0,
      (fittedPhotoSize.width * scale - viewportSize.width) / 2,
    );
    final maxY = math.max(
      0.0,
      (fittedPhotoSize.height * scale - viewportSize.height) / 2,
    );
    final nextX = ((matrix.storage[12] - baseX).clamp(-maxX, maxX) + baseX)
        .toDouble();
    final nextY = ((matrix.storage[13] - baseY).clamp(-maxY, maxY) + baseY)
        .toDouble();

    return Matrix4.identity()
      ..translateByDouble(nextX, nextY, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageSize = _singlePreviewPhotoSize(
          widget.photo.aspectRatio,
          viewportSize,
        );
        _viewportSize = viewportSize;
        _fittedPhotoSize = imageSize;

        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: (event) =>
              _handlePointerUp(event, viewportSize, imageSize),
          child: GestureDetector(
            key: ValueKey('cull-preview-zoomable-${widget.photo.id}'),
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: () => _handleDoubleTap(viewportSize),
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: _singlePreviewMinInteractionScale,
                maxScale: _singlePreviewMaxScale,
                panEnabled: _zoomed,
                scaleEnabled: true,
                boundaryMargin: EdgeInsets.zero,
                clipBehavior: Clip.hardEdge,
                constrained: false,
                onInteractionStart: _handleInteractionStart,
                onInteractionUpdate: (details) =>
                    _handleInteractionUpdate(details, viewportSize, imageSize),
                onInteractionEnd: (details) =>
                    _handleInteractionEnd(details, viewportSize, imageSize),
                child: SizedBox(
                  width: viewportSize.width,
                  height: viewportSize.height,
                  child: Center(
                    child: SizedBox(
                      key: ValueKey(
                        'cull-preview-photo-frame-${widget.photo.id}',
                      ),
                      width: imageSize.width,
                      height: imageSize.height,
                      child: _CullPhotoImage(
                        palette: widget.palette,
                        photo: widget.photo,
                        fit: BoxFit.contain,
                        cacheHeadroom: _zoomed ? 3.0 : 2.2,
                        cacheMaxExtent: _zoomed ? 4096 : 3200,
                        filterQuality: _zoomed
                            ? FilterQuality.high
                            : FilterQuality.medium,
                        viewerFallback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _cullPreviewMatrixMatches(Matrix4 a, Matrix4 b) {
  const epsilon = 0.001;
  final aStorage = a.storage;
  final bStorage = b.storage;
  for (var index = 0; index < aStorage.length; index += 1) {
    if ((aStorage[index] - bStorage[index]).abs() > epsilon) {
      return false;
    }
  }
  return true;
}

Size _singlePreviewPhotoSize(double aspectRatio, Size viewport) {
  if (viewport.width <= 0 || viewport.height <= 0) {
    return Size.zero;
  }
  final ratio = aspectRatio <= 0 ? 1.0 : aspectRatio;
  final viewportRatio = viewport.width / viewport.height;
  if (ratio >= viewportRatio) {
    return Size(viewport.width, viewport.width / ratio);
  }
  return Size(viewport.height * ratio, viewport.height);
}

Size _previewPhotoSize(double aspectRatio, Size viewport) {
  final ratio = aspectRatio.clamp(0.42, 2.4).toDouble();
  final maxWidth = viewport.width * 0.96;
  final maxHeight = viewport.height * 0.88;
  if (ratio >= 1) {
    var width = maxWidth;
    var height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    return Size(width, height);
  }
  var height = maxHeight;
  var width = height * ratio;
  if (width > maxWidth) {
    width = maxWidth;
    height = width / ratio;
  }
  return Size(width, height);
}

class _CullPhotoImage extends StatelessWidget {
  const _CullPhotoImage({
    required this.palette,
    required this.photo,
    required this.fit,
    this.cacheHeadroom = 1.4,
    this.cacheMaxExtent = 1280,
    this.filterQuality = FilterQuality.medium,
    this.viewerFallback = false,
  });

  final NoemaPalette palette;
  final _CullPhotoView photo;
  final BoxFit fit;
  final double cacheHeadroom;
  final int cacheMaxExtent;
  final FilterQuality filterQuality;
  final bool viewerFallback;

  @override
  Widget build(BuildContext context) {
    final fallback = viewerFallback
        ? _CullPhotoViewerFallback(palette: palette, name: photo.name)
        : _CullPhotoFallback(
            palette: palette,
            seed: photo.seed,
            name: photo.name,
          );
    final asset = photo.asset;
    if (asset == null) {
      return fallback;
    }

    final displayPath = asset.photo.previewPath ?? asset.photo.thumbnailPath;
    final unavailable =
        asset.photo.availability == AssetAvailability.unavailable;
    if (unavailable) {
      return fallback;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheSize = noemaImageCacheSize(
          context,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          headroom: cacheHeadroom,
          maxExtent: cacheMaxExtent,
        );
        if (displayPath == null && asset.photo.sourceUri == null) {
          return fallback;
        }
        return NoemaRecoverableReviewImage(
          asset: asset,
          fit: fit,
          cacheWidth: cacheSize.width,
          cacheHeight: cacheSize.height,
          recoverKind: NoemaRecoverableImageKind.preview,
          recoverMaxSize: viewerFallback ? 1800 : 1600,
          filterQuality: filterQuality,
          refreshWhenSourceAvailable: !viewerFallback,
          evictOnDispose: viewerFallback,
          fallback: fallback,
        );
      },
    );
  }
}

class _CullPhotoViewerFallback extends StatelessWidget {
  const _CullPhotoViewerFallback({required this.palette, required this.name});

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
          padding: const EdgeInsets.all(16),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.muted.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CullPhotoFallback extends StatelessWidget {
  const _CullPhotoFallback({
    required this.palette,
    required this.seed,
    required this.name,
  });

  final NoemaPalette palette;
  final int seed;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = [
      Color.lerp(palette.backgroundStart, palette.ink, 0.12)!,
      Color.lerp(palette.backgroundEnd, palette.ink, 0.22 + seed % 5 * 0.025)!,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: CustomPaint(
        painter: _CullFallbackPainter(
          color: palette.ink.withValues(alpha: 0.12),
          seed: seed,
        ),
        child: Center(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.ink.withValues(alpha: 0.44),
              fontFamily: 'NoemaLatin',
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _CullFallbackPainter extends CustomPainter {
  const _CullFallbackPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final step = math.max(24.0, size.shortestSide / 4);
    for (var x = -step; x < size.width + step; x += step) {
      canvas.drawLine(
        Offset(x + seed % 4 * 3, 0),
        Offset(x + step, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CullFallbackPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.seed != seed;
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    super.key,
    required this.palette,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(8)),
  });

  final NoemaPalette palette;
  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final darkTone = palette.tone == NoemaTone.dark;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.sheet.withValues(alpha: darkTone ? 0.82 : 0.9),
            borderRadius: radius,
            border: Border.all(
              color: palette.glassBorder.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: darkTone ? 0.28 : 0.12),
                blurRadius: 36,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
