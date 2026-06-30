import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/import_image_source.dart';
import 'package:noema/features/import/noema_media_picker.dart';

const _photoViewerPreviewMaxSize = 4096;
const _photoViewerMaxScale = 4.0;
const _photoViewerMinInteractionScale = 0.82;
const _photoViewerDismissScale = 0.96;
const _photoViewerDoubleTapScale = 2.4;
const _photoViewerPagingLockScale = 1.001;
const _photoViewerDecodeScale = 3.4;
const _photoViewerPrewarmRadius = 1;
const _photoViewerTransitionPrewarmWait = Duration(milliseconds: 1400);
const _photoViewerEase = Cubic(0.16, 1, 0.3, 1);

enum _PhotoViewerSort { newestFirst, oldestFirst }

enum PhotoViewerPageVisualTransition { slide, dissolve }

class PhotoViewerController {
  _PhotoViewerPageState? _state;

  int get currentIndex => _state?._currentIndex ?? 0;

  Future<void> next() => _state?._animateToRelative(1) ?? Future.value();

  Future<void> previous() => _state?._animateToRelative(-1) ?? Future.value();

  Future<void> animateToIndex(int index) {
    return _state?._animateToIndex(index) ?? Future.value();
  }

  void _attach(_PhotoViewerPageState state) {
    _state = state;
  }

  void _detach(_PhotoViewerPageState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

typedef PhotoViewerOverlayBuilder =
    Widget Function(
      BuildContext context,
      NoemaPalette palette,
      ReviewAsset asset,
      int index,
      int total,
    );

class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.initialPhotoId,
    this.sort,
    this.assets,
    this.overlayBuilder,
    this.imageBottomInsetFraction = 0,
    this.imageBottomInsetFractionListenable,
    this.imageFit = BoxFit.contain,
    this.fillByPhotoOrientation = false,
    this.controller,
    this.onIndexChanged,
    this.onTap,
    this.interactionsEnabled = true,
    this.blurredBackground = false,
    this.pageTransitionDuration = const Duration(milliseconds: 360),
    this.pageTransitionCurve = _photoViewerEase,
    this.pageVisualTransition = PhotoViewerPageVisualTransition.slide,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final String? initialPhotoId;
  final String? sort;
  final List<ReviewAsset>? assets;
  final PhotoViewerOverlayBuilder? overlayBuilder;
  final double imageBottomInsetFraction;
  final ValueListenable<double>? imageBottomInsetFractionListenable;
  final BoxFit imageFit;
  final bool fillByPhotoOrientation;
  final PhotoViewerController? controller;
  final ValueChanged<int>? onIndexChanged;
  final VoidCallback? onTap;
  final bool interactionsEnabled;
  final bool blurredBackground;
  final Duration pageTransitionDuration;
  final Curve pageTransitionCurve;
  final PhotoViewerPageVisualTransition pageVisualTransition;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pageController;
  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;

  int _virtualPage = 0;
  bool _pageLocked = false;
  bool _closing = false;
  final Set<String> _precachedImageKeys = {};

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    widget.workspaceController.addListener(_handleWorkspaceChanged);
    _virtualPage = _loopPageFor(_initialIndex(_orderedAssets));
    _pageController = PageController(initialPage: _virtualPage);
    widget.controller?._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchAround());
  }

  @override
  void didUpdateWidget(covariant PhotoViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceController != widget.workspaceController) {
      oldWidget.workspaceController.removeListener(_handleWorkspaceChanged);
      widget.workspaceController.addListener(_handleWorkspaceChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    widget.workspaceController.removeListener(_handleWorkspaceChanged);
    _pageController.dispose();
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
  }

  List<ReviewAsset> get _orderedAssets {
    final scopedAssets = widget.assets;
    if (scopedAssets != null) {
      return List<ReviewAsset>.unmodifiable(scopedAssets);
    }
    final assets = [...widget.workspaceController.workspace.assets];
    final sort = _parseSort(widget.sort);
    assets.sort((a, b) {
      return switch (sort) {
        _PhotoViewerSort.newestFirst => b.photo.createdAt.compareTo(
          a.photo.createdAt,
        ),
        _PhotoViewerSort.oldestFirst => a.photo.createdAt.compareTo(
          b.photo.createdAt,
        ),
      };
    });
    return assets;
  }

  int get _currentIndex => _indexForPage(_virtualPage, _orderedAssets.length);

  void _handleWorkspaceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _prefetchAround();
  }

  int _initialIndex(List<ReviewAsset> assets) {
    final initialPhotoId = widget.initialPhotoId;
    final index = assets.indexWhere(
      (asset) => asset.photo.id == initialPhotoId,
    );
    return index == -1 ? 0 : index;
  }

  int _loopPageFor(int index) {
    final length = math.max(1, _orderedAssets.length);
    return length * 1000 + index.clamp(0, length - 1);
  }

  int _indexForPage(int page, int length) {
    if (length == 0) {
      return 0;
    }
    return ((page % length) + length) % length;
  }

  void _handlePageChanged(int page) {
    setState(() {
      _virtualPage = page;
      _pageLocked = false;
    });
    widget.onIndexChanged?.call(_indexForPage(page, _orderedAssets.length));
    _prefetchAround();
  }

  Future<void> _animateToRelative(int delta) {
    final assets = _orderedAssets;
    if (assets.length <= 1) {
      return Future.value();
    }
    return _animateToPage(_virtualPage + delta);
  }

  Future<void> _animateToIndex(int index) {
    final assets = _orderedAssets;
    if (assets.isEmpty) {
      return Future.value();
    }
    final targetIndex = index.clamp(0, assets.length - 1).toInt();
    final currentIndex = _indexForPage(_virtualPage, assets.length);
    return _animateToPage(_virtualPage + targetIndex - currentIndex);
  }

  Future<void> _animateToPage(int page) async {
    if (_pageController.hasClients) {
      await _prewarmForTransition(
        page,
      ).timeout(_photoViewerTransitionPrewarmWait, onTimeout: () {});
    }
    if (!mounted) {
      return;
    }
    if (!_pageController.hasClients) {
      setState(() {
        _virtualPage = page;
      });
      return;
    }
    await _pageController.animateToPage(
      page,
      duration: widget.pageTransitionDuration,
      curve: widget.pageTransitionCurve,
    );
  }

  void _handleZoomChanged(bool zoomed) {
    if (_pageLocked == zoomed) {
      return;
    }
    setState(() {
      _pageLocked = zoomed;
    });
  }

  Future<void> _prefetchAround() async {
    final assets = _orderedAssets;
    if (!mounted || assets.isEmpty) {
      return;
    }
    final indexes = _prewarmIndexesAroundPage(_virtualPage, assets);
    for (final index in indexes) {
      unawaited(_precacheAsset(assets[index]));
    }
  }

  Set<int> _prewarmIndexesAroundPage(int page, List<ReviewAsset> assets) {
    if (assets.isEmpty) {
      return const {};
    }
    final currentIndex = _indexForPage(page, assets.length);
    return {
      for (
        var offset = -_photoViewerPrewarmRadius;
        offset <= _photoViewerPrewarmRadius;
        offset += 1
      )
        _indexForPage(currentIndex + offset, assets.length),
    };
  }

  Future<void> _prewarmForTransition(int page) async {
    final assets = _orderedAssets;
    if (!mounted || assets.isEmpty) {
      return;
    }
    final targetIndex = _indexForPage(page, assets.length);
    await _precacheAsset(assets[targetIndex]);
    if (!mounted) {
      return;
    }
    for (final index in _prewarmIndexesAroundPage(page, assets)) {
      if (index != targetIndex) {
        unawaited(_precacheAsset(assets[index]));
      }
    }
  }

  Future<void> _precacheAsset(ReviewAsset asset) async {
    final previewPath = await _ensurePreview(asset);
    if (!mounted || asset.photo.availability == AssetAvailability.unavailable) {
      return;
    }
    final provider = photoViewerPrecacheImageProvider(
      context,
      asset,
      previewPathOverride: previewPath,
    );
    if (provider == null) {
      return;
    }
    final cacheKey = _precacheKeyFor(
      context,
      asset,
      previewPathOverride: previewPath,
    );
    if (!_precachedImageKeys.add(cacheKey)) {
      return;
    }
    try {
      await precacheImage(provider, context);
    } catch (_) {
      _precachedImageKeys.remove(cacheKey);
    }
  }

  Future<String?> _ensurePreview(ReviewAsset asset) async {
    final existingPreviewPath = asset.photo.previewPath;
    if (existingPreviewPath != null && existingPreviewPath.isNotEmpty) {
      return existingPreviewPath;
    }
    if (asset.photo.availability == AssetAvailability.unavailable) {
      return null;
    }
    final sourceUri = asset.photo.sourceUri;
    if (sourceUri == null || sourceUri.isEmpty) {
      return null;
    }

    String? previewPath;
    try {
      previewPath = await const NoemaMediaPicker().createPreview(
        uri: sourceUri,
        maxSize: _photoViewerPreviewMaxSize,
      );
    } catch (_) {
      previewPath = null;
    }
    if (!mounted || previewPath == null || previewPath.isEmpty) {
      return null;
    }
    widget.workspaceController.updateAssetPreviewPath(
      asset.photo.id,
      previewPath,
    );
    return previewPath;
  }

  void _dismiss() {
    if (_closing) {
      return;
    }
    setState(() {
      _closing = true;
      _pageLocked = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 170), () {
      if (mounted) {
        context.pop();
      }
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
        final assets = _orderedAssets;
        final darkTone = palette.tone == NoemaTone.dark;
        final currentIndex = _indexForPage(_virtualPage, assets.length);
        final overlayBuilder = widget.overlayBuilder;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AnimatedOpacity(
            opacity: _closing ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _closing ? 0.92 : 1,
              duration: const Duration(milliseconds: 170),
              curve: _photoViewerEase,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: darkTone ? Colors.black : const Color(0xFFF4EFE5),
                ),
                child: assets.isEmpty
                    ? const SizedBox.expand()
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: _buildPageView(palette, assets),
                          ),
                          if (overlayBuilder != null)
                            Positioned.fill(
                              child: overlayBuilder(
                                context,
                                palette,
                                assets[currentIndex],
                                currentIndex,
                                assets.length,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageView(NoemaPalette palette, List<ReviewAsset> assets) {
    final listenable = widget.imageBottomInsetFractionListenable;
    if (listenable == null) {
      return _buildPageViewForInset(
        palette,
        assets,
        widget.imageBottomInsetFraction,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, insetFraction, _) {
        return _buildPageViewForInset(palette, assets, insetFraction);
      },
    );
  }

  Widget _buildPageViewForInset(
    NoemaPalette palette,
    List<ReviewAsset> assets,
    double bottomInsetFraction,
  ) {
    return PageView.builder(
      controller: _pageController,
      physics: _pageLocked
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      onPageChanged: _handlePageChanged,
      itemBuilder: (context, page) {
        final asset = assets[_indexForPage(page, assets.length)];
        return _PhotoViewerPageTransition(
          key: ValueKey('photo-viewer-${asset.photo.id}-$page'),
          controller: _pageController,
          page: page,
          style: widget.pageVisualTransition,
          child: _PhotoViewerImagePage(
            palette: palette,
            asset: asset,
            bottomInsetFraction: bottomInsetFraction,
            imageFit: widget.imageFit,
            fillByPhotoOrientation: widget.fillByPhotoOrientation,
            interactionsEnabled: widget.interactionsEnabled,
            blurredBackground: widget.blurredBackground,
            onTap: widget.onTap,
            onZoomChanged: _handleZoomChanged,
            onDismiss: _dismiss,
            onPreviewLoaded: widget.workspaceController.updateAssetPreviewPath,
          ),
        );
      },
    );
  }
}

class _PhotoViewerPageTransition extends StatelessWidget {
  const _PhotoViewerPageTransition({
    required super.key,
    required this.controller,
    required this.page,
    required this.style,
    required this.child,
  });

  final PageController controller;
  final int page;
  final PhotoViewerPageVisualTransition style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (style == PhotoViewerPageVisualTransition.slide) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: controller,
          child: child,
          builder: (context, child) {
            final pagePosition =
                controller.hasClients &&
                    controller.position.hasContentDimensions
                ? controller.page ?? controller.initialPage.toDouble()
                : controller.initialPage.toDouble();
            final delta = page - pagePosition;
            final distance = delta.abs().clamp(0.0, 1.0).toDouble();
            final presence = Curves.easeOutCubic.transform(1 - distance);
            // ponytail: PageView keeps real paging/gestures; this only softens
            // the visual feel for Appreciate without a second viewer engine.
            return Transform.translate(
              offset: Offset(-delta * constraints.maxWidth, 0),
              child: Opacity(
                opacity: presence,
                child: Transform.scale(
                  scale: 0.985 + presence * 0.015,
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PhotoViewerImagePage extends StatefulWidget {
  const _PhotoViewerImagePage({
    required this.palette,
    required this.asset,
    required this.bottomInsetFraction,
    required this.imageFit,
    required this.fillByPhotoOrientation,
    required this.interactionsEnabled,
    required this.blurredBackground,
    required this.onTap,
    required this.onZoomChanged,
    required this.onDismiss,
    required this.onPreviewLoaded,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final double bottomInsetFraction;
  final BoxFit imageFit;
  final bool fillByPhotoOrientation;
  final bool interactionsEnabled;
  final bool blurredBackground;
  final VoidCallback? onTap;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onDismiss;
  final void Function(String photoId, String previewPath) onPreviewLoaded;

  @override
  State<_PhotoViewerImagePage> createState() => _PhotoViewerImagePageState();
}

class _PhotoViewerImagePageState extends State<_PhotoViewerImagePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late final AnimationController _doubleTapZoomController;

  Size? _viewportSize;
  Size? _fittedPhotoSize;
  Animation<Matrix4>? _doubleTapZoomAnimation;
  Offset? _doubleTapPosition;
  bool _clampingMatrix = false;
  bool _interactionActive = false;
  bool _underscaleSeen = false;
  bool _scalePanEnabled = false;
  int _activePointerCount = 0;
  int _rawPointerCount = 0;
  String? _imageAspectIdentity;
  double? _resolvedImageAspectRatio;
  ImageStream? _imageAspectStream;
  ImageStreamListener? _imageAspectStreamListener;

  @override
  void initState() {
    super.initState();
    _doubleTapZoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    )..addListener(_handleDoubleTapZoomTick);
    _controller.addListener(_handleMatrixChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageAspectRatioIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _PhotoViewerImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_photoViewerImageIdentity(oldWidget.asset) !=
            _photoViewerImageIdentity(widget.asset) ||
        oldWidget.asset.photo.width != widget.asset.photo.width ||
        oldWidget.asset.photo.height != widget.asset.photo.height) {
      _resolvedImageAspectRatio = null;
      _clearImageAspectStream();
      _resolveImageAspectRatioIfNeeded();
    }
  }

  @override
  void dispose() {
    _clearImageAspectStream();
    _controller.removeListener(_handleMatrixChanged);
    _controller.dispose();
    _doubleTapZoomController.dispose();
    widget.onZoomChanged(false);
    super.dispose();
  }

  void _clearImageAspectStream() {
    final stream = _imageAspectStream;
    final listener = _imageAspectStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageAspectStream = null;
    _imageAspectStreamListener = null;
  }

  void _resolveImageAspectRatioIfNeeded() {
    final identity = _photoViewerImageIdentity(widget.asset);
    if (identity == null ||
        identity == _imageAspectIdentity && _imageAspectStream != null) {
      _imageAspectIdentity = identity;
      return;
    }

    _clearImageAspectStream();
    _imageAspectIdentity = identity;

    final previewBytesRatio = _photoViewerPreviewBytesAspectRatio(widget.asset);
    if (previewBytesRatio != null &&
        _photoViewerDisplayPath(widget.asset) == null &&
        !_photoViewerCanRecoverFromSource(widget.asset)) {
      _resolvedImageAspectRatio = previewBytesRatio;
      return;
    }

    final provider = _photoViewerImageProvider(widget.asset);
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
      if (!ratio.isFinite ||
          (_resolvedImageAspectRatio != null &&
              (_resolvedImageAspectRatio! - ratio).abs() < 0.001)) {
        return;
      }
      setState(() => _resolvedImageAspectRatio = ratio);
    });
    _imageAspectStream = stream;
    _imageAspectStreamListener = listener;
    stream.addListener(listener);
  }

  void _handleDoubleTapZoomTick() {
    final animation = _doubleTapZoomAnimation;
    if (animation == null) {
      return;
    }
    _setControllerValue(animation.value);
  }

  void _handleMatrixChanged() {
    if (_clampingMatrix) {
      return;
    }

    final viewportSize = _viewportSize;
    final fittedImageSize = _fittedPhotoSize;
    if (viewportSize != null && fittedImageSize != null) {
      final clamped = _clampedMatrix(
        _controller.value,
        viewportSize: viewportSize,
        fittedImageSize: fittedImageSize,
        minScale: _interactionActive ? _photoViewerMinInteractionScale : 1,
      );
      if (!_matrixMatches(_controller.value, clamped)) {
        _setControllerValue(clamped);
      }
    }

    final scale = _controller.value.getMaxScaleOnAxis();
    _syncZoomChanged(scale);
  }

  void _setControllerValue(Matrix4 value) {
    _clampingMatrix = true;
    _controller.value = value;
    _clampingMatrix = false;
    _syncZoomChanged(value.getMaxScaleOnAxis());
  }

  void _syncZoomChanged([double? scale]) {
    final effectiveScale = scale ?? _controller.value.getMaxScaleOnAxis();
    final scalePanEnabled = effectiveScale > _photoViewerPagingLockScale;
    if (_scalePanEnabled != scalePanEnabled && mounted) {
      setState(() {
        _scalePanEnabled = scalePanEnabled;
      });
    }
    widget.onZoomChanged(
      _rawPointerCount > 1 || _activePointerCount > 1 || scalePanEnabled,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _rawPointerCount += 1;
    if (_rawPointerCount > 1) {
      _syncZoomChanged();
    }
  }

  void _handlePointerUpOrCancel() {
    _rawPointerCount = math.max(0, _rawPointerCount - 1);
    _syncZoomChanged();
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _doubleTapZoomController.stop();
    _interactionActive = true;
    _activePointerCount = details.pointerCount;
    _underscaleSeen = false;
    _syncZoomChanged();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final viewportSize = _viewportSize;
    final fittedImageSize = _fittedPhotoSize;
    if (viewportSize == null || fittedImageSize == null) {
      return;
    }

    _doubleTapZoomController.stop();
    _interactionActive = false;
    _activePointerCount = 0;
    _underscaleSeen = false;

    final currentScale = _controller.value.getMaxScaleOnAxis();
    final target = currentScale > 1.01
        ? Matrix4.identity()
        : _clampedMatrix(
            Matrix4.identity()
              ..translateByDouble(
                viewportSize.width / 2 -
                    (_doubleTapPosition?.dx ?? viewportSize.width / 2) *
                        _photoViewerDoubleTapScale,
                viewportSize.height / 2 -
                    (_doubleTapPosition?.dy ?? viewportSize.height / 2) *
                        _photoViewerDoubleTapScale,
                0,
                1,
              )
              ..scaleByDouble(
                _photoViewerDoubleTapScale,
                _photoViewerDoubleTapScale,
                _photoViewerDoubleTapScale,
                1,
              ),
            viewportSize: viewportSize,
            fittedImageSize: fittedImageSize,
            minScale: 1,
          );

    _doubleTapZoomAnimation =
        Matrix4Tween(begin: _controller.value, end: target).animate(
          CurvedAnimation(
            parent: _doubleTapZoomController,
            curve: _photoViewerEase,
          ),
        );
    _doubleTapZoomController.forward(from: 0);
    _syncZoomChanged(target.getMaxScaleOnAxis());
  }

  void _handleInteractionUpdate(
    ScaleUpdateDetails details,
    Size viewportSize,
    Size fittedImageSize,
  ) {
    _interactionActive = true;
    _activePointerCount = details.pointerCount;
    _syncZoomChanged();

    final matrix = Matrix4.copy(_controller.value);
    final scale = matrix.getMaxScaleOnAxis();
    if (scale < _photoViewerDismissScale) {
      _underscaleSeen = true;
    }

    _setControllerValue(
      _clampedMatrix(
        matrix,
        viewportSize: viewportSize,
        fittedImageSize: fittedImageSize,
        minScale: _photoViewerMinInteractionScale,
      ),
    );
  }

  void _handleInteractionEnd(
    ScaleEndDetails details,
    Size viewportSize,
    Size fittedImageSize,
  ) {
    _interactionActive = false;
    _activePointerCount = 0;
    final scale = _controller.value.getMaxScaleOnAxis();
    if (_underscaleSeen || scale < _photoViewerDismissScale) {
      widget.onDismiss();
      return;
    }
    _underscaleSeen = false;
    if (scale <= 1.01) {
      _controller.value = Matrix4.identity();
      _syncZoomChanged(1);
      return;
    }

    _controller.value = _clampedMatrix(
      _controller.value,
      viewportSize: viewportSize,
      fittedImageSize: fittedImageSize,
      minScale: 1,
    );
    _syncZoomChanged(_controller.value.getMaxScaleOnAxis());
  }

  Matrix4 _clampedMatrix(
    Matrix4 source, {
    required Size viewportSize,
    required Size fittedImageSize,
    required double minScale,
  }) {
    final matrix = Matrix4.copy(source);
    final scale = matrix
        .getMaxScaleOnAxis()
        .clamp(minScale, _photoViewerMaxScale)
        .toDouble();
    final baseX = viewportSize.width * (1 - scale) / 2;
    final baseY = viewportSize.height * (1 - scale) / 2;
    final maxX = math.max(
      0.0,
      (fittedImageSize.width * scale - viewportSize.width) / 2,
    );
    final maxY = math.max(
      0.0,
      (fittedImageSize.height * scale - viewportSize.height) / 2,
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
        final reservedBottom =
            constraints.maxHeight *
            widget.bottomInsetFraction.clamp(0.0, 0.82).toDouble();
        final viewportSize = Size(
          constraints.maxWidth,
          math.max(1, constraints.maxHeight - reservedBottom),
        );
        final fullViewportSize = Size(
          constraints.maxWidth,
          math.max(1, constraints.maxHeight),
        );
        final effectiveImageFit = widget.fillByPhotoOrientation
            ? BoxFit.cover
            : widget.imageFit;
        final imageAspectRatio =
            _resolvedImageAspectRatio ?? _assetAspectRatio(widget.asset);
        final imageSize =
            widget.imageFit == BoxFit.cover || widget.fillByPhotoOrientation
            ? viewportSize
            : _fittedImageSizeForAspectRatio(imageAspectRatio, viewportSize);
        final cacheImageSize =
            widget.imageFit == BoxFit.cover || widget.fillByPhotoOrientation
            ? fullViewportSize
            : _fittedImageSizeForAspectRatio(
                imageAspectRatio,
                fullViewportSize,
              );
        // ponytail: keep decode size stable while the appraisal sheet moves;
        // revisit per-frame cache tuning only if memory pressure shows up.
        final cacheSize = _viewerCacheSize(context, cacheImageSize);
        _viewportSize = viewportSize;
        _fittedPhotoSize = imageSize;

        final foreground = Listener(
          onPointerDown: widget.interactionsEnabled ? _handlePointerDown : null,
          onPointerUp: widget.interactionsEnabled
              ? (_) => _handlePointerUpOrCancel()
              : null,
          onPointerCancel: widget.interactionsEnabled
              ? (_) => _handlePointerUpOrCancel()
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            onDoubleTapDown: widget.interactionsEnabled
                ? _handleDoubleTapDown
                : null,
            onDoubleTap: widget.interactionsEnabled
                ? _handleDoubleTap
                : widget.onTap,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: _photoViewerMinInteractionScale,
                  maxScale: _photoViewerMaxScale,
                  panEnabled:
                      widget.interactionsEnabled &&
                      (_rawPointerCount > 1 ||
                          _activePointerCount > 1 ||
                          _scalePanEnabled),
                  scaleEnabled: widget.interactionsEnabled,
                  constrained: false,
                  clipBehavior: Clip.hardEdge,
                  boundaryMargin: EdgeInsets.zero,
                  onInteractionStart: widget.interactionsEnabled
                      ? _handleInteractionStart
                      : null,
                  onInteractionUpdate: widget.interactionsEnabled
                      ? (details) => _handleInteractionUpdate(
                          details,
                          viewportSize,
                          imageSize,
                        )
                      : null,
                  onInteractionEnd: widget.interactionsEnabled
                      ? (details) => _handleInteractionEnd(
                          details,
                          viewportSize,
                          imageSize,
                        )
                      : null,
                  child: SizedBox(
                    width: viewportSize.width,
                    height: viewportSize.height,
                    child: Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        key: const ValueKey('photo-viewer-fitted-image'),
                        width: imageSize.width,
                        height: imageSize.height,
                        child: _PhotoViewerImage(
                          palette: widget.palette,
                          asset: widget.asset,
                          fit: effectiveImageFit,
                          cacheWidth: cacheSize.width,
                          cacheHeight: cacheSize.height,
                          onPreviewLoaded: widget.onPreviewLoaded,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (!widget.blurredBackground) {
          return foreground;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _PhotoViewerBlurredBackground(
              palette: widget.palette,
              asset: widget.asset,
              cacheWidth: cacheSize.width,
              cacheHeight: cacheSize.height,
              onPreviewLoaded: widget.onPreviewLoaded,
            ),
            foreground,
          ],
        );
      },
    );
  }
}

class _PhotoViewerBlurredBackground extends StatelessWidget {
  const _PhotoViewerBlurredBackground({
    required this.palette,
    required this.asset,
    required this.cacheWidth,
    required this.cacheHeight,
    required this.onPreviewLoaded,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final int? cacheWidth;
  final int? cacheHeight;
  final void Function(String photoId, String previewPath) onPreviewLoaded;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.08,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: _PhotoViewerImage(
                palette: palette,
                asset: asset,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                onPreviewLoaded: onPreviewLoaded,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0x66000000)),
          ),
        ],
      ),
    );
  }
}

bool _matrixMatches(Matrix4 a, Matrix4 b) {
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

class _PhotoViewerImage extends StatelessWidget {
  const _PhotoViewerImage({
    required this.palette,
    required this.asset,
    required this.fit,
    required this.cacheWidth,
    required this.cacheHeight,
    required this.onPreviewLoaded,
  });

  final NoemaPalette palette;
  final ReviewAsset asset;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final void Function(String photoId, String previewPath) onPreviewLoaded;

  @override
  Widget build(BuildContext context) {
    if (asset.photo.availability == AssetAvailability.unavailable) {
      return _PhotoViewerUnavailable(palette: palette, name: asset.displayName);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: NoemaRecoverableReviewImage(
        asset: asset,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        recoverKind: NoemaRecoverableImageKind.preview,
        recoverMaxSize: _photoViewerPreviewMaxSize,
        recoverWhenPathMissing: true,
        refreshWhenSourceAvailable: true,
        onRecovered: onPreviewLoaded,
        filterQuality: FilterQuality.high,
        fallback: _PhotoViewerUnavailable(
          palette: palette,
          name: asset.displayName,
        ),
      ),
    );
  }
}

class _PhotoViewerUnavailable extends StatelessWidget {
  const _PhotoViewerUnavailable({required this.palette, required this.name});

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

_PhotoViewerSort _parseSort(String? value) {
  return switch (value) {
    'oldestFirst' => _PhotoViewerSort.oldestFirst,
    _ => _PhotoViewerSort.newestFirst,
  };
}

Size _fittedImageSizeForAspectRatio(double aspectRatio, Size viewportSize) {
  final viewportRatio = viewportSize.width / viewportSize.height;
  if (aspectRatio >= viewportRatio) {
    return Size(viewportSize.width, viewportSize.width / aspectRatio);
  }
  return Size(viewportSize.height * aspectRatio, viewportSize.height);
}

double _assetAspectRatio(ReviewAsset asset) {
  final width = asset.photo.width;
  final height = asset.photo.height;
  if (width <= 0 || height <= 0) {
    return 1;
  }
  return width / height;
}

String? _photoViewerImageIdentity(ReviewAsset asset) {
  final displayPath = _photoViewerDisplayPath(asset);
  if (displayPath == null || displayPath.isEmpty) {
    final previewBytes = asset.previewBytes;
    if (previewBytes != null && !_photoViewerCanRecoverFromSource(asset)) {
      return 'bytes:${asset.photo.id}:${identityHashCode(previewBytes)}:${previewBytes.length}';
    }
    return null;
  }
  return 'path:$displayPath';
}

ImageProvider<Object>? _photoViewerImageProvider(ReviewAsset asset) {
  return _photoViewerImageProviderWithPreview(asset);
}

ImageProvider<Object>? _photoViewerImageProviderWithPreview(
  ReviewAsset asset, {
  String? previewPathOverride,
}) {
  if (asset.photo.availability == AssetAvailability.unavailable) {
    return null;
  }
  final displayPath =
      previewPathOverride != null && previewPathOverride.isNotEmpty
      ? previewPathOverride
      : _photoViewerDisplayPath(asset);
  if (displayPath == null || displayPath.isEmpty) {
    final previewBytes = asset.previewBytes;
    if (previewBytes != null && !_photoViewerCanRecoverFromSource(asset)) {
      return MemoryImage(previewBytes);
    }
    return null;
  }
  return importImageProviderFromPath(displayPath);
}

ImageProvider<Object>? photoViewerPrecacheImageProvider(
  BuildContext context,
  ReviewAsset asset, {
  String? previewPathOverride,
}) {
  final provider = _photoViewerImageProviderWithPreview(
    asset,
    previewPathOverride: previewPathOverride,
  );
  if (provider == null) {
    return null;
  }
  final viewportSize = MediaQuery.sizeOf(context);
  final imageSize = _fittedImageSizeForAspectRatio(
    _assetAspectRatio(asset),
    viewportSize,
  );
  final cacheSize = _viewerCacheSize(context, imageSize);
  return ResizeImage.resizeIfNeeded(
    cacheSize.width,
    cacheSize.height,
    provider,
  );
}

String _precacheKeyFor(
  BuildContext context,
  ReviewAsset asset, {
  String? previewPathOverride,
}) {
  final viewportSize = MediaQuery.sizeOf(context);
  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
  final viewportKey =
      '${viewportSize.width.toStringAsFixed(1)}x'
      '${viewportSize.height.toStringAsFixed(1)}@'
      '${pixelRatio.toStringAsFixed(2)}';
  final displayPath =
      previewPathOverride != null && previewPathOverride.isNotEmpty
      ? previewPathOverride
      : _photoViewerDisplayPath(asset);
  if (displayPath != null && displayPath.isNotEmpty) {
    return 'path:$viewportKey:${asset.photo.id}:$displayPath';
  }
  final previewBytes = asset.previewBytes;
  if (previewBytes != null && !_photoViewerCanRecoverFromSource(asset)) {
    return 'bytes:$viewportKey:${asset.photo.id}:${identityHashCode(previewBytes)}:${previewBytes.length}';
  }
  return 'asset:$viewportKey:${asset.photo.id}';
}

String? _photoViewerDisplayPath(ReviewAsset asset) {
  return asset.photo.previewPath ?? asset.photo.thumbnailPath;
}

bool _photoViewerCanRecoverFromSource(ReviewAsset asset) {
  final sourceUri = asset.photo.sourceUri;
  return sourceUri != null && sourceUri.isNotEmpty;
}

double? _photoViewerPreviewBytesAspectRatio(ReviewAsset asset) {
  final previewBytes = asset.previewBytes;
  if (previewBytes == null) {
    return null;
  }
  try {
    final decoded = img.decodeImage(previewBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    final oriented = img.bakeOrientation(decoded);
    return oriented.width / oriented.height;
  } catch (_) {
    return null;
  }
}

({int? width, int? height}) _viewerCacheSize(
  BuildContext context,
  Size imageSize,
) {
  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
  final width = math
      .min(
        _photoViewerPreviewMaxSize,
        math.max(
          1,
          (imageSize.width * pixelRatio * _photoViewerDecodeScale).round(),
        ),
      )
      .toInt();
  final height = math
      .min(
        _photoViewerPreviewMaxSize,
        math.max(
          1,
          (imageSize.height * pixelRatio * _photoViewerDecodeScale).round(),
        ),
      )
      .toInt();
  return (width: width, height: height);
}
