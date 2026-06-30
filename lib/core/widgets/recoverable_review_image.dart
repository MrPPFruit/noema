import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/features/import/import_image_source.dart';
import 'package:noema/features/import/noema_media_picker.dart';

enum NoemaRecoverableImageKind { thumbnail, preview }

class NoemaRecoverableReviewImage extends StatefulWidget {
  const NoemaRecoverableReviewImage({
    required this.asset,
    required this.fit,
    required this.fallback,
    required this.recoverKind,
    required this.recoverMaxSize,
    super.key,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.recoverWhenPathMissing = true,
    this.refreshWhenSourceAvailable = false,
    this.allowAlternatePathFallback = true,
    this.revealOnFirstAvailable = false,
    this.evictOnDispose = false,
    this.onRecovered,
    this.onRecoveryFailed,
  });

  final ReviewAsset asset;
  final BoxFit fit;
  final Widget fallback;
  final NoemaRecoverableImageKind recoverKind;
  final int recoverMaxSize;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final bool recoverWhenPathMissing;
  final bool refreshWhenSourceAvailable;
  final bool allowAlternatePathFallback;
  final bool revealOnFirstAvailable;
  final bool evictOnDispose;
  final void Function(String photoId, String path)? onRecovered;
  final void Function(String photoId)? onRecoveryFailed;

  @override
  State<NoemaRecoverableReviewImage> createState() =>
      _NoemaRecoverableReviewImageState();
}

class _NoemaRecoverableReviewImageState
    extends State<NoemaRecoverableReviewImage> {
  int _generation = 0;
  String? _recoveredPath;
  String? _recoveringKey;
  String? _failedRecoveryKey;
  String? _reportedFailureKey;
  String? _refreshedSourceUri;
  ImageProvider<Object>? _activeImageProvider;

  @override
  void didUpdateWidget(covariant NoemaRecoverableReviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.photo.id != widget.asset.photo.id ||
        oldWidget.asset.photo.sourceUri != widget.asset.photo.sourceUri ||
        oldWidget.recoverKind != widget.recoverKind ||
        oldWidget.allowAlternatePathFallback !=
            widget.allowAlternatePathFallback) {
      _evictActiveImageProvider();
      _generation += 1;
      _recoveredPath = null;
      _recoveringKey = null;
      _failedRecoveryKey = null;
      _reportedFailureKey = null;
      _refreshedSourceUri = null;
    }
  }

  @override
  void dispose() {
    _evictActiveImageProvider();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    if (asset.photo.availability == AssetAvailability.unavailable) {
      return widget.fallback;
    }

    final displayPath = _displayPath(asset);
    _refreshIfNeeded();
    if (displayPath == null || displayPath.isEmpty) {
      if (widget.recoverWhenPathMissing) {
        _requestRecovery(failedPath: null);
      }
      final previewBytes = asset.previewBytes;
      if (previewBytes != null) {
        // ponytail: import preview bytes are only a low-res bridge; path
        // recovery must still run so viewer surfaces can replace them.
        final provider = _rememberImageProvider(
          ResizeImage.resizeIfNeeded(
            widget.cacheWidth,
            widget.cacheHeight,
            MemoryImage(previewBytes),
          ),
        );
        return Image(
          image: provider,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: widget.filterQuality,
          frameBuilder: widget.revealOnFirstAvailable ? _revealFrame : null,
          errorBuilder: (context, error, stackTrace) => widget.fallback,
        );
      }
      return widget.fallback;
    }

    final provider = _rememberImageProvider(
      ResizeImage.resizeIfNeeded(
        widget.cacheWidth,
        widget.cacheHeight,
        importImageProviderFromPath(displayPath),
      ),
    );
    return Image(
      image: provider,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: widget.filterQuality,
      frameBuilder: widget.revealOnFirstAvailable ? _revealFrame : null,
      errorBuilder: (context, error, stackTrace) {
        final sourceUri = widget.asset.photo.sourceUri;
        if (sourceUri == null || sourceUri.isEmpty) {
          _reportRecoveryFailed('missing-source|$displayPath');
        }
        _requestRecovery(failedPath: displayPath);
        return widget.fallback;
      },
    );
  }

  Widget _revealFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) {
      return child;
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: child,
    );
  }

  ImageProvider<Object> _rememberImageProvider(ImageProvider<Object> provider) {
    final activeProvider = _activeImageProvider;
    if (activeProvider != provider) {
      _evictImageProvider(activeProvider);
      _activeImageProvider = provider;
    }
    return provider;
  }

  void _evictActiveImageProvider() {
    final activeProvider = _activeImageProvider;
    _activeImageProvider = null;
    _evictImageProvider(activeProvider);
  }

  void _evictImageProvider(ImageProvider<Object>? provider) {
    if (!widget.evictOnDispose || provider == null) {
      return;
    }
    unawaited(provider.evict());
  }

  String? _displayPath(ReviewAsset asset) {
    final recoveredPath = _recoveredPath;
    if (recoveredPath != null && recoveredPath.isNotEmpty) {
      return recoveredPath;
    }
    final primaryPath = _rawPrimaryPath(asset);
    if (primaryPath != null && primaryPath.isNotEmpty) {
      return primaryPath;
    }
    return switch (widget.recoverKind) {
      NoemaRecoverableImageKind.thumbnail =>
        widget.allowAlternatePathFallback
            ? _rawDisplayPath(asset.photo.previewPath, asset.photo.sourceUri)
            : null,
      NoemaRecoverableImageKind.preview =>
        widget.allowAlternatePathFallback
            ? _rawDisplayPath(asset.photo.thumbnailPath, asset.photo.sourceUri)
            : null,
    };
  }

  void _refreshIfNeeded() {
    final hasStalePath = _hasStaleDisplayPath(widget.asset);
    if (!widget.refreshWhenSourceAvailable && !hasStalePath) {
      return;
    }
    final recoveredPath = _recoveredPath;
    if (recoveredPath != null && recoveredPath.isNotEmpty) {
      return;
    }
    final primaryPath = _primaryPath(widget.asset);
    if (primaryPath != null && primaryPath.isNotEmpty) {
      return;
    }
    final sourceUri = widget.asset.photo.sourceUri;
    final refreshKey = '$sourceUri|stale=$hasStalePath';
    if (sourceUri == null ||
        sourceUri.isEmpty ||
        refreshKey == _refreshedSourceUri) {
      return;
    }
    _refreshedSourceUri = refreshKey;
    _requestRecovery(
      failedPath: null,
      retryFailed: true,
      reportFailure: !hasStalePath,
    );
  }

  String? _primaryPath(ReviewAsset asset) {
    return _usableNoemaImagePath(switch (widget.recoverKind) {
      NoemaRecoverableImageKind.thumbnail => asset.photo.thumbnailPath,
      NoemaRecoverableImageKind.preview => asset.photo.previewPath,
    }, asset.photo.sourceUri);
  }

  String? _rawPrimaryPath(ReviewAsset asset) {
    return _rawDisplayPath(switch (widget.recoverKind) {
      NoemaRecoverableImageKind.thumbnail => asset.photo.thumbnailPath,
      NoemaRecoverableImageKind.preview => asset.photo.previewPath,
    }, asset.photo.sourceUri);
  }

  bool _hasStaleDisplayPath(ReviewAsset asset) {
    final sourceUri = asset.photo.sourceUri;
    final primaryPath = switch (widget.recoverKind) {
      NoemaRecoverableImageKind.thumbnail => asset.photo.thumbnailPath,
      NoemaRecoverableImageKind.preview => asset.photo.previewPath,
    };
    if (_isStaleNoemaCachedImagePath(primaryPath ?? '') ||
        _isNoemaCachedImagePathForDifferentSource(primaryPath, sourceUri)) {
      return true;
    }
    if (!widget.allowAlternatePathFallback) {
      return false;
    }
    final alternatePath = switch (widget.recoverKind) {
      NoemaRecoverableImageKind.thumbnail => asset.photo.previewPath,
      NoemaRecoverableImageKind.preview => asset.photo.thumbnailPath,
    };
    return _isStaleNoemaCachedImagePath(alternatePath ?? '') ||
        _isNoemaCachedImagePathForDifferentSource(alternatePath, sourceUri);
  }

  void _requestRecovery({
    required String? failedPath,
    bool retryFailed = false,
    bool reportFailure = true,
  }) {
    final sourceUri = widget.asset.photo.sourceUri;
    if (sourceUri == null || sourceUri.isEmpty) {
      return;
    }
    final recoveryKey =
        '${widget.recoverKind.name}|$sourceUri|${failedPath ?? '<missing>'}';
    if (_recoveringKey == recoveryKey) {
      return;
    }
    if (!retryFailed && _failedRecoveryKey == recoveryKey) {
      return;
    }

    _recoveringKey = recoveryKey;
    final generation = ++_generation;
    unawaited(_recover(sourceUri, recoveryKey, generation, reportFailure));
  }

  Future<void> _recover(
    String sourceUri,
    String recoveryKey,
    int generation,
    bool reportFailure,
  ) async {
    String? path;
    try {
      path = switch (widget.recoverKind) {
        NoemaRecoverableImageKind.thumbnail =>
          await const NoemaMediaPicker().createThumbnail(
            uri: sourceUri,
            maxSize: widget.recoverMaxSize,
          ),
        NoemaRecoverableImageKind.preview =>
          await const NoemaMediaPicker().createPreview(
            uri: sourceUri,
            maxSize: widget.recoverMaxSize,
          ),
      };
    } catch (_) {
      path = null;
    }

    if (!mounted || generation != _generation) {
      return;
    }
    _recoveringKey = null;
    if (path == null || path.isEmpty) {
      _failedRecoveryKey = recoveryKey;
      if (reportFailure) {
        _reportRecoveryFailed(recoveryKey);
      }
      return;
    }

    setState(() {
      _recoveredPath = path;
      _failedRecoveryKey = null;
    });
    widget.onRecovered?.call(widget.asset.photo.id, path);
  }

  void _reportRecoveryFailed(String failureKey) {
    if (_reportedFailureKey == failureKey) {
      return;
    }
    _reportedFailureKey = failureKey;
    widget.onRecoveryFailed?.call(widget.asset.photo.id);
  }
}

String? _usableNoemaImagePath(String? path, String? sourceUri) {
  if (path == null || path.isEmpty) {
    return path;
  }
  if (_isNoemaCachedImagePathForDifferentSource(path, sourceUri)) {
    return null;
  }
  if (!_isStaleNoemaCachedImagePath(path)) {
    return path;
  }
  return null;
}

String? _rawDisplayPath(String? path, String? sourceUri) {
  if (path == null || path.isEmpty) {
    return path;
  }
  if (_isNoemaCachedImagePathForDifferentSource(path, sourceUri)) {
    return null;
  }
  return path;
}

bool _isStaleNoemaCachedImagePath(String path) {
  if (!path.contains('/noema_media/')) {
    return false;
  }
  final fileName = path.split('/').last;
  return fileName.startsWith('v') && !fileName.startsWith('v5_');
}

bool _isNoemaCachedImagePathForDifferentSource(
  String? path,
  String? sourceUri,
) {
  if (path == null ||
      path.isEmpty ||
      sourceUri == null ||
      sourceUri.isEmpty ||
      !path.contains('/noema_media/')) {
    return false;
  }
  final fileName = path.split('/').last;
  if (!fileName.startsWith('v5_')) {
    return false;
  }
  return !fileName.startsWith('v5_${_javaStringHashAbs(sourceUri)}_');
}

int _javaStringHashAbs(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (31 * hash + codeUnit) & 0xffffffff;
  }
  if ((hash & 0x80000000) != 0) {
    hash -= 0x100000000;
  }
  return hash == -0x80000000 ? hash : hash.abs();
}
