import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/noema_routes.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/theme/noema_colors.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appraise/appraise_band.dart';
import 'package:noema/features/processing/photo_viewer_page.dart';

const _appreciateUiRestoreGuard = Duration(milliseconds: 260);
const _appreciateIdleChromeDelay = Duration(seconds: 3);
const _appreciateIntroFadeDuration = Duration(milliseconds: 920);
const _appreciatePhotoTransitionDuration = Duration(milliseconds: 1250);
const _appreciatePhotoTransitionCurve = Curves.easeInOutCubic;
const _appreciateMinIntervalSeconds = 5;
const _appreciateMaxIntervalSeconds = 30;

enum _AppreciateRange { flaw, formed, fine, cherished }

enum _AppreciateOrder { sequence, shuffle }

enum _AppreciateSortMode { time, score }

enum _AppreciateTimeSort { newestFirst, oldestFirst }

enum _AppreciateScoreSort { highToLow, lowToHigh }

class AppreciateViewerPage extends StatefulWidget {
  const AppreciateViewerPage({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.initialPhotoId,
    this.sortMode,
    this.timeSort,
    this.scoreSort,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final String? initialPhotoId;
  final String? sortMode;
  final String? timeSort;
  final String? scoreSort;

  @override
  State<AppreciateViewerPage> createState() => _AppreciateViewerPageState();
}

class _AppreciateViewerPageState extends State<AppreciateViewerPage> {
  final PhotoViewerController _viewerController = PhotoViewerController();
  final math.Random _random = math.Random();

  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;
  late final _AppreciateSortMode _sortMode;
  late final _AppreciateTimeSort _timeSort;
  late final _AppreciateScoreSort _scoreSort;
  late Set<_AppreciateRange> _selectedRanges;
  late _AppreciateOrder _order;
  late int _intervalSeconds;

  List<String> _shuffleQueueIds = const [];
  Timer? _playTimer;
  Timer? _restoreGuardTimer;
  Timer? _chromeIdleTimer;
  bool _playing = false;
  bool _manualPlaybackPaused = false;
  bool _chromeVisible = true;
  bool _rangePanelOpen = false;
  bool _intervalPanelOpen = false;
  bool _landscape = false;
  bool _restoreGuardActive = false;
  bool _introCurtainVisible = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    _sortMode = _appreciateSortModeFromValue(widget.sortMode);
    _timeSort = _appreciateTimeSortFromValue(widget.timeSort);
    _scoreSort = _appreciateScoreSortFromValue(widget.scoreSort);
    final preferences =
        widget.workspaceController.workspace.appreciateViewPreferences;
    _selectedRanges = _validatedRanges(
      _appreciateRangesFromMask(preferences.rangeMask),
    );
    _order = _appreciateOrderFromValue(preferences.order);
    _intervalSeconds = _clampedAppreciateInterval(preferences.intervalSeconds);
    widget.workspaceController.addListener(_handleWorkspaceChanged);
    _currentIndex = _initialIndex(_filteredAssets);
    final normalizedPreferences = AppreciateViewPreferences(
      rangeMask: _appreciateMaskForRanges(_selectedRanges),
      order: _order.name,
      intervalSeconds: _intervalSeconds,
    );
    if (normalizedPreferences != preferences) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _persistAppreciatePreferences();
        }
      });
    }
    unawaited(_setPortrait(markActivity: false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _introCurtainVisible = false;
      });
      _scheduleChromeAutoHide();
    });
  }

  @override
  void dispose() {
    _stopPlayback(setStateAfter: false);
    _restoreGuardTimer?.cancel();
    _chromeIdleTimer?.cancel();
    widget.workspaceController.removeListener(_handleWorkspaceChanged);
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    unawaited(_setPortrait(markActivity: false));
    super.dispose();
  }

  List<ReviewAsset> get _orderedAssets {
    final assets = [
      for (final asset in widget.workspaceController.workspace.assets)
        if (asset.photo.availability == AssetAvailability.available) asset,
    ];
    final hasScores = assets.any((asset) => asset.photo.appraisalScore != null);
    final sortMode = _sortMode == _AppreciateSortMode.score && !hasScores
        ? _AppreciateSortMode.time
        : _sortMode;
    assets.sort((a, b) {
      if (sortMode == _AppreciateSortMode.score) {
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
            return _scoreSort == _AppreciateScoreSort.highToLow
                ? -scoreValue
                : scoreValue;
          }
        }
      }
      return switch (_timeSort) {
        _AppreciateTimeSort.newestFirst => b.photo.createdAt.compareTo(
          a.photo.createdAt,
        ),
        _AppreciateTimeSort.oldestFirst => a.photo.createdAt.compareTo(
          b.photo.createdAt,
        ),
      };
    });
    return assets;
  }

  Map<String, AnalysisResult> get _analysisByPhotoId {
    return {
      for (final result in widget.workspaceController.workspace.analysisResults)
        result.photoId: result,
    };
  }

  List<ReviewAsset> get _filteredAssets {
    return _assetsForRanges(_selectedRanges);
  }

  List<ReviewAsset> _assetsForRanges(Set<_AppreciateRange> ranges) {
    if (ranges.isEmpty) {
      return const [];
    }
    final analysisByPhotoId = _analysisByPhotoId;
    return [
      for (final asset in _orderedAssets)
        if (_matchesRanges(asset, analysisByPhotoId[asset.photo.id], ranges))
          asset,
    ];
  }

  Set<_AppreciateRange> _validatedRanges(Set<_AppreciateRange> ranges) {
    final normalized = {
      for (final range in ranges)
        if (_AppreciateRange.values.contains(range)) range,
    };
    final candidate = normalized.isEmpty
        ? {..._AppreciateRange.values}
        : normalized;
    if (_assetsForRanges(candidate).isNotEmpty ||
        _assetsForRanges({..._AppreciateRange.values}).isEmpty) {
      return candidate;
    }
    return {..._AppreciateRange.values};
  }

  void _persistAppreciatePreferences() {
    widget.workspaceController.setAppreciateViewPreferences(
      AppreciateViewPreferences(
        rangeMask: _appreciateMaskForRanges(_selectedRanges),
        order: _order.name,
        intervalSeconds: _intervalSeconds,
      ),
    );
  }

  bool _matchesRanges(
    ReviewAsset asset,
    AnalysisResult? analysis,
    Set<_AppreciateRange> ranges,
  ) {
    final photo = asset.photo;
    if (ranges.contains(_rangeForBand(appraiseBandForPhoto(photo, analysis)))) {
      return true;
    }
    return ranges.contains(_AppreciateRange.cherished) && photo.isCherished;
  }

  int _initialIndex(List<ReviewAsset> assets) {
    final initialPhotoId = widget.initialPhotoId;
    if (initialPhotoId == null || initialPhotoId.isEmpty) {
      return 0;
    }
    final index = assets.indexWhere(
      (asset) => asset.photo.id == initialPhotoId,
    );
    return index == -1 ? 0 : index;
  }

  void _handleWorkspaceChanged() {
    if (!mounted) {
      return;
    }
    final nextRanges = _validatedRanges(_selectedRanges);
    final rangesChanged = !_sameAppreciateRanges(_selectedRanges, nextRanges);
    final assets = _assetsForRanges(nextRanges);
    setState(() {
      if (rangesChanged) {
        _selectedRanges = nextRanges;
      }
      _currentIndex = _clampedIndexForCurrentPhoto(assets);
      if (assets.length <= 1) {
        _stopPlayback(setStateAfter: false);
      }
    });
    if (rangesChanged) {
      _persistAppreciatePreferences();
    }
  }

  int _clampedIndexForCurrentPhoto(List<ReviewAsset> assets) {
    if (assets.isEmpty) {
      return 0;
    }
    final currentId = _currentAssetId;
    if (currentId != null) {
      final nextIndex = assets.indexWhere(
        (asset) => asset.photo.id == currentId,
      );
      if (nextIndex != -1) {
        return nextIndex;
      }
    }
    return _currentIndex.clamp(0, assets.length - 1).toInt();
  }

  String? get _currentAssetId {
    final assets = _filteredAssets;
    if (assets.isEmpty || _currentIndex >= assets.length) {
      return null;
    }
    return assets[_currentIndex].photo.id;
  }

  String get _intervalLabel => '${_intervalSeconds}s';

  Duration get _playbackInterval => Duration(seconds: _intervalSeconds);

  bool get _canStartPlayback =>
      !_playing && !_manualPlaybackPaused && _filteredAssets.length > 1;

  Future<void> _exitViewer() async {
    _stopPlayback();
    _chromeIdleTimer?.cancel();
    await _setPortrait(markActivity: false);
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(NoemaRoutes.observe);
    }
  }

  void _toggleChrome() {
    if (_chromeVisible) {
      _hideChrome();
      return;
    }
    _restoreGuardTimer?.cancel();
    setState(() {
      _chromeVisible = true;
      _restoreGuardActive = true;
    });
    _restoreGuardTimer = Timer(_appreciateUiRestoreGuard, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _restoreGuardActive = false;
      });
    });
    _scheduleChromeAutoHide();
  }

  void _hideChrome({bool autoStartPlayback = false}) {
    _chromeIdleTimer?.cancel();
    if (!_chromeVisible &&
        !_rangePanelOpen &&
        !_intervalPanelOpen &&
        !_restoreGuardActive) {
      return;
    }
    final shouldStartPlayback =
        autoStartPlayback &&
        !_rangePanelOpen &&
        !_intervalPanelOpen &&
        _canStartPlayback;
    setState(() {
      _chromeVisible = false;
      _rangePanelOpen = false;
      _intervalPanelOpen = false;
      _restoreGuardActive = false;
      if (shouldStartPlayback) {
        _playing = true;
      }
    });
    if (shouldStartPlayback) {
      _schedulePlayback();
    }
  }

  void _scheduleChromeAutoHide() {
    _chromeIdleTimer?.cancel();
    if (!_chromeVisible) {
      return;
    }
    _chromeIdleTimer = Timer(_appreciateIdleChromeDelay, () {
      if (!mounted || !_chromeVisible) {
        return;
      }
      _hideChrome(autoStartPlayback: true);
    });
  }

  void _markChromeActivity() {
    if (_chromeVisible) {
      _scheduleChromeAutoHide();
    }
  }

  void _toggleRangePanel() {
    setState(() {
      _chromeVisible = true;
      _rangePanelOpen = !_rangePanelOpen;
      _intervalPanelOpen = false;
    });
    _scheduleChromeAutoHide();
  }

  void _toggleIntervalPanel() {
    setState(() {
      _chromeVisible = true;
      _intervalPanelOpen = !_intervalPanelOpen;
      _rangePanelOpen = false;
    });
    _scheduleChromeAutoHide();
  }

  void _toggleRange(_AppreciateRange range) {
    final nextRanges = Set<_AppreciateRange>.from(_selectedRanges);
    if (nextRanges.contains(range)) {
      nextRanges.remove(range);
    } else {
      nextRanges.add(range);
    }
    if (nextRanges.isEmpty || _assetsForRanges(nextRanges).isEmpty) {
      _markChromeActivity();
      return;
    }
    final currentId = _currentAssetId;
    final nextAssets = _assetsForRanges(nextRanges);
    final nextIndex = currentId == null
        ? 0
        : nextAssets.indexWhere((asset) => asset.photo.id == currentId);
    setState(() {
      _selectedRanges
        ..clear()
        ..addAll(nextRanges);
      _currentIndex = nextIndex == -1 ? 0 : nextIndex;
      _shuffleQueueIds = const [];
    });
    _persistAppreciatePreferences();
    _scheduleChromeAutoHide();
    if (nextAssets.length <= 1) {
      _stopPlayback();
    } else if (_playing) {
      _schedulePlayback();
    }
  }

  bool _rangeToggleAllowed(_AppreciateRange range) {
    final nextRanges = Set<_AppreciateRange>.from(_selectedRanges);
    if (nextRanges.contains(range)) {
      nextRanges.remove(range);
    } else {
      nextRanges.add(range);
    }
    return nextRanges.isNotEmpty && _assetsForRanges(nextRanges).isNotEmpty;
  }

  void _toggleOrder() {
    setState(() {
      _order = _order == _AppreciateOrder.sequence
          ? _AppreciateOrder.shuffle
          : _AppreciateOrder.sequence;
      _shuffleQueueIds = const [];
    });
    _persistAppreciatePreferences();
    _markChromeActivity();
    if (_playing) {
      _schedulePlayback();
    }
  }

  void _togglePlayback() {
    if (_filteredAssets.length <= 1) {
      return;
    }
    if (_playing) {
      _stopPlayback(userInitiated: true);
      _markChromeActivity();
      return;
    }
    _startPlayback();
  }

  void _startPlayback() {
    _chromeIdleTimer?.cancel();
    setState(() {
      _playing = true;
      _manualPlaybackPaused = false;
      _chromeVisible = false;
      _rangePanelOpen = false;
      _intervalPanelOpen = false;
      _restoreGuardActive = false;
    });
    _schedulePlayback();
  }

  void _stopPlayback({bool setStateAfter = true, bool userInitiated = false}) {
    _playTimer?.cancel();
    _playTimer = null;
    if (!_playing) {
      if (userInitiated) {
        _manualPlaybackPaused = true;
      }
      return;
    }
    if (setStateAfter && mounted) {
      setState(() {
        _playing = false;
        _manualPlaybackPaused = userInitiated;
      });
    } else {
      _playing = false;
      _manualPlaybackPaused = userInitiated;
    }
  }

  void _schedulePlayback() {
    _playTimer?.cancel();
    if (!_playing || _filteredAssets.length <= 1) {
      return;
    }
    _playTimer = Timer(_playbackInterval, () {
      unawaited(_advancePlayback());
    });
  }

  Future<void> _advancePlayback() async {
    if (!mounted || !_playing) {
      return;
    }
    final assets = _filteredAssets;
    if (assets.length <= 1) {
      _stopPlayback();
      return;
    }
    final nextIndex = _order == _AppreciateOrder.shuffle
        ? _nextShuffleIndex(assets)
        : (_currentIndex + 1) % assets.length;
    setState(() {
      _currentIndex = nextIndex;
    });
    await _viewerController.animateToIndex(nextIndex);
    _schedulePlayback();
  }

  int _nextShuffleIndex(List<ReviewAsset> assets) {
    final validIds = {for (final asset in assets) asset.photo.id};
    var queue = _shuffleQueueIds.where(validIds.contains).toList();
    if (queue.isEmpty) {
      queue = [
        for (final asset in assets)
          if (asset.photo.id != _currentAssetId) asset.photo.id,
      ]..shuffle(_random);
    }
    if (queue.isEmpty) {
      return _currentIndex.clamp(0, assets.length - 1).toInt();
    }
    final nextId = queue.removeAt(0);
    _shuffleQueueIds = queue;
    final index = assets.indexWhere((asset) => asset.photo.id == nextId);
    return index == -1 ? (_currentIndex + 1) % assets.length : index;
  }

  void _setIntervalSeconds(int seconds) {
    final next = seconds
        .clamp(_appreciateMinIntervalSeconds, _appreciateMaxIntervalSeconds)
        .toInt();
    if (next == _intervalSeconds) {
      _markChromeActivity();
      return;
    }
    setState(() {
      _intervalSeconds = next;
    });
    _persistAppreciatePreferences();
    _scheduleChromeAutoHide();
    if (_playing) {
      _schedulePlayback();
    }
  }

  Future<void> _toggleOrientation() async {
    if (_landscape) {
      await _setPortrait();
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) {
        setState(() {
          _landscape = true;
        });
        _scheduleChromeAutoHide();
      }
    }
  }

  Future<void> _setPortrait({bool markActivity = true}) async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (mounted) {
      setState(() {
        _landscape = false;
      });
      if (markActivity) {
        _markChromeActivity();
      }
    }
  }

  void _handleViewerIndexChanged(int index) {
    final assets = _filteredAssets;
    if (assets.isEmpty) {
      return;
    }
    final clamped = index.clamp(0, assets.length - 1).toInt();
    final currentId = assets[clamped].photo.id;
    setState(() {
      _currentIndex = clamped;
      _shuffleQueueIds = [
        for (final id in _shuffleQueueIds)
          if (id != currentId) id,
      ];
    });
    if (_playing) {
      _schedulePlayback();
    } else {
      _markChromeActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final assets = _filteredAssets;
        final currentIndex = assets.isEmpty
            ? 0
            : _currentIndex.clamp(0, assets.length - 1).toInt();

        return Stack(
          children: [
            PhotoViewerPage(
              key: ValueKey(_playlistKey(assets)),
              workspaceController: widget.workspaceController,
              appearanceController: _appearanceController,
              assets: assets,
              initialPhotoId: assets.isEmpty
                  ? null
                  : assets[currentIndex].photo.id,
              controller: _viewerController,
              onIndexChanged: _handleViewerIndexChanged,
              onTap: _toggleChrome,
              interactionsEnabled: _chromeVisible && !_restoreGuardActive,
              blurredBackground: true,
              imageFit: BoxFit.contain,
              pageTransitionDuration: _appreciatePhotoTransitionDuration,
              pageTransitionCurve: _appreciatePhotoTransitionCurve,
              pageVisualTransition: PhotoViewerPageVisualTransition.dissolve,
              overlayBuilder: (context, palette, asset, index, total) {
                return _AppreciateChrome(
                  palette: palette,
                  visible: _chromeVisible,
                  rangePanelOpen: _rangePanelOpen,
                  intervalPanelOpen: _intervalPanelOpen,
                  selectedRanges: _selectedRanges,
                  order: _order,
                  playing: _playing,
                  playbackEnabled: total > 1,
                  intervalSeconds: _intervalSeconds,
                  intervalLabel: _intervalLabel,
                  landscape: _landscape,
                  pageIndex: index,
                  pageTotal: total,
                  onBack: _exitViewer,
                  onToggleRangePanel: _toggleRangePanel,
                  onToggleOrder: _toggleOrder,
                  onTogglePlayback: _togglePlayback,
                  onToggleIntervalPanel: _toggleIntervalPanel,
                  onToggleOrientation: _toggleOrientation,
                  onToggleRange: _toggleRange,
                  rangeToggleAllowed: _rangeToggleAllowed,
                  onIntervalChanged: _setIntervalSeconds,
                );
              },
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                key: const ValueKey('appreciate-intro-curtain'),
                opacity: _introCurtainVisible ? 1 : 0,
                duration: _appreciateIntroFadeDuration,
                curve: Curves.easeInOutCubic,
                child: const ColoredBox(
                  color: Colors.black,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppreciateChrome extends StatelessWidget {
  const _AppreciateChrome({
    required this.palette,
    required this.visible,
    required this.rangePanelOpen,
    required this.intervalPanelOpen,
    required this.selectedRanges,
    required this.order,
    required this.playing,
    required this.playbackEnabled,
    required this.intervalSeconds,
    required this.intervalLabel,
    required this.landscape,
    required this.pageIndex,
    required this.pageTotal,
    required this.onBack,
    required this.onToggleRangePanel,
    required this.onToggleOrder,
    required this.onTogglePlayback,
    required this.onToggleIntervalPanel,
    required this.onToggleOrientation,
    required this.onToggleRange,
    required this.rangeToggleAllowed,
    required this.onIntervalChanged,
  });

  final NoemaPalette palette;
  final bool visible;
  final bool rangePanelOpen;
  final bool intervalPanelOpen;
  final Set<_AppreciateRange> selectedRanges;
  final _AppreciateOrder order;
  final bool playing;
  final bool playbackEnabled;
  final int intervalSeconds;
  final String intervalLabel;
  final bool landscape;
  final int pageIndex;
  final int pageTotal;
  final Future<void> Function() onBack;
  final VoidCallback onToggleRangePanel;
  final VoidCallback onToggleOrder;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleIntervalPanel;
  final Future<void> Function() onToggleOrientation;
  final ValueChanged<_AppreciateRange> onToggleRange;
  final bool Function(_AppreciateRange range) rangeToggleAllowed;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: visible ? 1 : 0,
        child: Stack(
          children: [
            const _AppreciateGradient(top: true),
            const _AppreciateGradient(top: false),
            Positioned(
              left: NoemaSceneMetrics.topBarInset,
              right: NoemaSceneMetrics.topBarInset,
              top: NoemaSceneMetrics.topBarTop,
              child: SizedBox(
                height: NoemaSceneMetrics.topBarHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _AppreciateIconButton(
                    tooltip: strings.back,
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => unawaited(onBack()),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: rangePanelOpen
                          ? _AppreciateRangePanel(
                              key: const ValueKey('appreciate-range-panel'),
                              selectedRanges: selectedRanges,
                              onToggleRange: onToggleRange,
                              rangeToggleAllowed: rangeToggleAllowed,
                            )
                          : intervalPanelOpen
                          ? _AppreciateIntervalPanel(
                              key: const ValueKey('appreciate-interval-panel'),
                              intervalSeconds: intervalSeconds,
                              onIntervalChanged: onIntervalChanged,
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (rangePanelOpen || intervalPanelOpen)
                      const SizedBox(height: 10),
                    _AppreciatePageIndicator(
                      palette: palette,
                      total: pageTotal,
                      selectedIndex: pageIndex,
                    ),
                    const SizedBox(height: 8),
                    _AppreciateControlBar(
                      rangeLabel: _rangeSummary(selectedRanges),
                      shuffle: order == _AppreciateOrder.shuffle,
                      playing: playing,
                      playbackEnabled: playbackEnabled,
                      intervalLabel: intervalLabel,
                      landscape: landscape,
                      onToggleRangePanel: onToggleRangePanel,
                      onToggleOrder: onToggleOrder,
                      onTogglePlayback: onTogglePlayback,
                      onToggleIntervalPanel: onToggleIntervalPanel,
                      onToggleOrientation: onToggleOrientation,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppreciateGradient extends StatelessWidget {
  const _AppreciateGradient({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: top ? 156 : 190,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: const [
                  Color(0xB8000000),
                  Color(0x52000000),
                  Color(0x00000000),
                ],
                stops: const [0, 0.58, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _AppreciatePageIndicator extends StatelessWidget {
  const _AppreciatePageIndicator({
    required this.palette,
    required this.total,
    required this.selectedIndex,
  });

  final NoemaPalette palette;
  final int total;
  final int selectedIndex;

  static const _slotCount = 7;
  static const _centerSlot = 3;
  static const _slotWidth = 18.0;
  static const _slotGap = 6.0;

  @override
  Widget build(BuildContext context) {
    if (total <= 1) {
      return const SizedBox.shrink();
    }
    final safeSelectedIndex = selectedIndex.clamp(0, total - 1).toInt();
    final slots = [
      for (var slot = 0; slot < _slotCount; slot += 1)
        _slotForOffset(slot - _centerSlot, safeSelectedIndex),
    ];

    return Center(
      child: SizedBox(
        key: const ValueKey('appreciate-page-indicator'),
        width: _slotCount * _slotWidth + (_slotCount - 1) * _slotGap,
        height: 18,
        child: Row(
          children: [
            for (final entry in slots.asMap().entries) ...[
              _AppreciatePageIndicatorSlot(
                key: ValueKey('appreciate-page-indicator-slot-${entry.key}'),
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

  _AppreciatePageIndicatorSlotData _slotForOffset(int offset, int selected) {
    if (offset == 0) {
      return const _AppreciatePageIndicatorSlotData.page(current: true);
    }

    final targetIndex = selected + offset;
    if (targetIndex < 0 || targetIndex >= total) {
      return const _AppreciatePageIndicatorSlotData.placeholder();
    }

    if (offset == -_centerSlot && targetIndex > 0) {
      return const _AppreciatePageIndicatorSlotData.ellipsis(leading: true);
    }
    if (offset == _centerSlot && targetIndex < total - 1) {
      return const _AppreciatePageIndicatorSlotData.ellipsis(leading: false);
    }

    return const _AppreciatePageIndicatorSlotData.page();
  }
}

class _AppreciatePageIndicatorSlotData {
  const _AppreciatePageIndicatorSlotData._({
    required this.kind,
    this.current = false,
    this.leading = false,
  });

  const _AppreciatePageIndicatorSlotData.placeholder()
    : this._(kind: _AppreciatePageIndicatorSlotKind.placeholder);

  const _AppreciatePageIndicatorSlotData.ellipsis({required bool leading})
    : this._(kind: _AppreciatePageIndicatorSlotKind.ellipsis, leading: leading);

  const _AppreciatePageIndicatorSlotData.page({bool current = false})
    : this._(kind: _AppreciatePageIndicatorSlotKind.page, current: current);

  final _AppreciatePageIndicatorSlotKind kind;
  final bool current;
  final bool leading;
}

enum _AppreciatePageIndicatorSlotKind { placeholder, ellipsis, page }

class _AppreciatePageIndicatorSlot extends StatelessWidget {
  const _AppreciatePageIndicatorSlot({
    super.key,
    required this.palette,
    required this.slot,
  });

  final NoemaPalette palette;
  final _AppreciatePageIndicatorSlotData slot;

  @override
  Widget build(BuildContext context) {
    final child = switch (slot.kind) {
      _AppreciatePageIndicatorSlotKind.placeholder => const SizedBox.shrink(),
      _AppreciatePageIndicatorSlotKind.ellipsis => _AppreciatePageOverflowDot(
        key: ValueKey(
          slot.leading
              ? 'appreciate-page-indicator-ellipsis-leading'
              : 'appreciate-page-indicator-ellipsis-trailing',
        ),
        palette: palette,
      ),
      _AppreciatePageIndicatorSlotKind.page => _AppreciatePageSegment(
        key: slot.current
            ? const ValueKey('appreciate-page-indicator-current')
            : null,
        palette: palette,
        current: slot.current,
      ),
    };

    return SizedBox(
      width: _AppreciatePageIndicator._slotWidth,
      height: 18,
      child: Center(child: child),
    );
  }
}

class _AppreciatePageOverflowDot extends StatelessWidget {
  const _AppreciatePageOverflowDot({super.key, required this.palette});

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

class _AppreciatePageSegment extends StatelessWidget {
  const _AppreciatePageSegment({
    super.key,
    required this.palette,
    required this.current,
  });

  final NoemaPalette palette;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: current ? 8 : 15,
      height: current ? 8 : 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: current ? 0.82 : 0.42),
        borderRadius: BorderRadius.circular(current ? 99 : 3),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: current ? 0.18 : 0.06),
            blurRadius: current ? 10 : 5,
          ),
        ],
      ),
    );
  }
}

class _AppreciateControlBar extends StatelessWidget {
  const _AppreciateControlBar({
    required this.rangeLabel,
    required this.shuffle,
    required this.playing,
    required this.playbackEnabled,
    required this.intervalLabel,
    required this.landscape,
    required this.onToggleRangePanel,
    required this.onToggleOrder,
    required this.onTogglePlayback,
    required this.onToggleIntervalPanel,
    required this.onToggleOrientation,
  });

  final String rangeLabel;
  final bool shuffle;
  final bool playing;
  final bool playbackEnabled;
  final String intervalLabel;
  final bool landscape;
  final VoidCallback onToggleRangePanel;
  final VoidCallback onToggleOrder;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleIntervalPanel;
  final Future<void> Function() onToggleOrientation;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AppreciateControlButton(
                  icon: Icons.tune_rounded,
                  label: rangeLabel,
                  selected: false,
                  onPressed: onToggleRangePanel,
                ),
                _AppreciateControlButton(
                  icon: shuffle
                      ? Icons.shuffle_rounded
                      : Icons.format_list_numbered_rounded,
                  label: shuffle ? '随机' : '顺序',
                  selected: shuffle,
                  onPressed: onToggleOrder,
                ),
                _AppreciateControlButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: playing ? '暂停' : '播放',
                  selected: playing,
                  enabled: playbackEnabled,
                  onPressed: onTogglePlayback,
                ),
                _AppreciateControlButton(
                  icon: Icons.timer_outlined,
                  label: intervalLabel,
                  selected: false,
                  onPressed: onToggleIntervalPanel,
                ),
                _AppreciateControlButton(
                  icon: landscape
                      ? Icons.stay_current_landscape_rounded
                      : Icons.stay_current_portrait_rounded,
                  label: landscape ? '横屏' : '竖屏',
                  selected: landscape,
                  onPressed: () => unawaited(onToggleOrientation()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppreciateControlButton extends StatelessWidget {
  const _AppreciateControlButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? selected
              ? const Color(0xFFFFFFFF)
              : const Color(0xDDEDEDED)
        : const Color(0x66FFFFFF);
    final background = selected
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.transparent;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: SizedBox(
          width: 62,
          height: 48,
          child: TextButton(
            onPressed: enabled ? onPressed : null,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: foreground,
              disabledForegroundColor: foreground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              backgroundColor: background,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontFamily: noemaCjkFontFamily,
                    fontFamilyFallback: const ['NoemaCjkFallback'],
                    fontSize: 11,
                    height: 1,
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

class _AppreciateRangePanel extends StatelessWidget {
  const _AppreciateRangePanel({
    super.key,
    required this.selectedRanges,
    required this.onToggleRange,
    required this.rangeToggleAllowed,
  });

  final Set<_AppreciateRange> selectedRanges;
  final ValueChanged<_AppreciateRange> onToggleRange;
  final bool Function(_AppreciateRange range) rangeToggleAllowed;

  @override
  Widget build(BuildContext context) {
    return _AppreciateFloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final range in _AppreciateRange.values) ...[
            _AppreciateChoiceChip(
              label: _rangeLabel(range),
              selected: selectedRanges.contains(range),
              enabled: rangeToggleAllowed(range),
              onPressed: () => onToggleRange(range),
            ),
            if (range != _AppreciateRange.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _AppreciateIntervalPanel extends StatelessWidget {
  const _AppreciateIntervalPanel({
    super.key,
    required this.intervalSeconds,
    required this.onIntervalChanged,
  });

  final int intervalSeconds;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    return _AppreciateFloatingPanel(
      child: SizedBox(
        width: 232,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: NoemaColors.accentPrimary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: NoemaColors.accentPrimary.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '播放间隔',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontFamily: noemaCjkFontFamily,
                          fontFamilyFallback: const ['NoemaCjkFallback'],
                          fontSize: 12,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '5s - 30s',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.44),
                          fontFamily: noemaCjkFontFamily,
                          fontFamilyFallback: const ['NoemaCjkFallback'],
                          fontSize: 10,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _AppreciateIntervalValueChip(
                  key: const ValueKey('appreciate-interval-value'),
                  seconds: intervalSeconds,
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: NoemaColors.accentPrimary.withValues(
                  alpha: 0.86,
                ),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                thumbColor: const Color(0xFFF4F0EA),
                overlayColor: NoemaColors.accentPrimary.withValues(alpha: 0.12),
                tickMarkShape: SliderTickMarkShape.noTickMark,
                showValueIndicator: ShowValueIndicator.never,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
              ),
              child: Slider(
                key: const ValueKey('appreciate-interval-slider'),
                value: intervalSeconds.toDouble(),
                min: _appreciateMinIntervalSeconds.toDouble(),
                max: _appreciateMaxIntervalSeconds.toDouble(),
                divisions:
                    _appreciateMaxIntervalSeconds -
                    _appreciateMinIntervalSeconds,
                onChanged: (value) => onIntervalChanged(value.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppreciateIntervalValueChip extends StatelessWidget {
  const _AppreciateIntervalValueChip({super.key, required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 42,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: NoemaColors.accentPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: NoemaColors.accentPrimary.withValues(alpha: 0.40),
        ),
      ),
      child: Text(
        '${seconds}s',
        style: const TextStyle(
          color: Color(0xFFF0D8AA),
          fontFamily: noemaCjkFontFamily,
          fontFamilyFallback: ['NoemaCjkFallback'],
          fontSize: 14,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AppreciateFloatingPanel extends StatelessWidget {
  const _AppreciateFloatingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AppreciateChoiceChip extends StatelessWidget {
  const _AppreciateChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? selected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.34);
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: color,
          disabledForegroundColor: color,
          backgroundColor: selected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(
              color: selected
                  ? Colors.white.withValues(alpha: 0.36)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: noemaCjkFontFamily,
            fontFamilyFallback: const ['NoemaCjkFallback'],
            fontSize: 13,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _AppreciateIconButton extends StatelessWidget {
  const _AppreciateIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: NoemaSceneMetrics.iconTapSize,
        height: NoemaSceneMetrics.iconTapSize,
        child: Center(
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            color: Colors.white.withValues(alpha: 0.88),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(NoemaSceneMetrics.iconVisualSize),
              backgroundColor: Colors.black.withValues(alpha: 0.26),
              shape: const CircleBorder(),
            ),
          ),
        ),
      ),
    );
  }
}

_AppreciateRange _rangeForBand(AppraisePhotoBand band) {
  return switch (band) {
    AppraisePhotoBand.flaw => _AppreciateRange.flaw,
    AppraisePhotoBand.formed => _AppreciateRange.formed,
    AppraisePhotoBand.fine => _AppreciateRange.fine,
  };
}

String _rangeSummary(Set<_AppreciateRange> ranges) {
  final selected = [
    for (final range in _AppreciateRange.values)
      if (ranges.contains(range)) range,
  ];
  if (selected.length == _AppreciateRange.values.length) {
    return '全部';
  }
  if (selected.length == 1) {
    return _rangeLabel(selected.first);
  }
  if (selected.length == 2) {
    return '${_rangeLabel(selected.first)}+${_rangeLabel(selected.last)}';
  }
  return '${selected.length}类';
}

String _rangeLabel(_AppreciateRange range) {
  return switch (range) {
    _AppreciateRange.flaw => '微瑕',
    _AppreciateRange.formed => '成片',
    _AppreciateRange.fine => '佳作',
    _AppreciateRange.cherished => '珍藏',
  };
}

Set<_AppreciateRange> _appreciateRangesFromMask(int mask) {
  final validMask = mask & AppreciateViewPreferences.allRangeMask;
  if (validMask == 0) {
    return {..._AppreciateRange.values};
  }
  return {
    for (final range in _AppreciateRange.values)
      if ((validMask & (1 << range.index)) != 0) range,
  };
}

int _appreciateMaskForRanges(Set<_AppreciateRange> ranges) {
  var mask = 0;
  for (final range in ranges) {
    mask |= 1 << range.index;
  }
  final validMask = mask & AppreciateViewPreferences.allRangeMask;
  return validMask == 0 ? AppreciateViewPreferences.allRangeMask : validMask;
}

bool _sameAppreciateRanges(
  Set<_AppreciateRange> left,
  Set<_AppreciateRange> right,
) {
  return left.length == right.length && left.containsAll(right);
}

_AppreciateOrder _appreciateOrderFromValue(String? value) {
  return switch (value) {
    'shuffle' => _AppreciateOrder.shuffle,
    _ => _AppreciateOrder.sequence,
  };
}

int _clampedAppreciateInterval(int value) {
  return value
      .clamp(_appreciateMinIntervalSeconds, _appreciateMaxIntervalSeconds)
      .toInt();
}

_AppreciateSortMode _appreciateSortModeFromValue(String? value) {
  return switch (value) {
    'score' => _AppreciateSortMode.score,
    _ => _AppreciateSortMode.time,
  };
}

_AppreciateTimeSort _appreciateTimeSortFromValue(String? value) {
  return switch (value) {
    'oldestFirst' => _AppreciateTimeSort.oldestFirst,
    _ => _AppreciateTimeSort.newestFirst,
  };
}

_AppreciateScoreSort _appreciateScoreSortFromValue(String? value) {
  return switch (value) {
    'lowToHigh' => _AppreciateScoreSort.lowToHigh,
    _ => _AppreciateScoreSort.highToLow,
  };
}

String _playlistKey(List<ReviewAsset> assets) {
  return Object.hashAll([
    for (final asset in assets) asset.photo.id,
  ]).toString();
}
