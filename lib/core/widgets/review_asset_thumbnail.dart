import 'package:flutter/material.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';

class ReviewAssetThumbnail extends StatelessWidget {
  const ReviewAssetThumbnail({
    required this.asset,
    super.key,
    this.label,
    this.aspectRatio = 1,
    this.showName = false,
    this.cacheExtent = 256,
    this.onThumbnailLoaded,
  });

  final ReviewAsset asset;
  final String? label;
  final double aspectRatio;
  final bool showName;
  final int cacheExtent;
  final void Function(String photoId, String thumbnailPath)? onThumbnailLoaded;

  @override
  Widget build(BuildContext context) {
    final displayPath = asset.photo.previewPath ?? asset.photo.thumbnailPath;
    final hasPreviewPath = displayPath != null;
    final isUnavailable =
        asset.photo.availability == AssetAvailability.unavailable;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cacheSize = noemaImageCacheSize(
            context,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            maxExtent: cacheExtent,
          );

          final fallback = _ThumbnailFallback(
            assetName: asset.displayName,
            unavailable: isUnavailable,
          );

          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isUnavailable)
                    fallback
                  else
                    NoemaRecoverableReviewImage(
                      asset: asset,
                      fit: BoxFit.cover,
                      cacheWidth: cacheSize.width,
                      cacheHeight: cacheSize.height,
                      recoverKind: NoemaRecoverableImageKind.thumbnail,
                      recoverMaxSize: cacheExtent,
                      refreshWhenSourceAvailable: true,
                      onRecovered: onThumbnailLoaded,
                      filterQuality: FilterQuality.low,
                      fallback: fallback,
                    ),
                  if (label != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _ThumbnailBadge(label: label!),
                    ),
                  if (showName &&
                      (hasPreviewPath || asset.previewBytes != null))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ThumbnailCaption(assetName: asset.displayName),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback({required this.assetName, this.unavailable = false});

  final String assetName;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.surfaceContainerHighest, colorScheme.surface],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Text(
            unavailable ? '$assetName\nPreview unavailable' : assetName,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _ThumbnailBadge extends StatelessWidget {
  const _ThumbnailBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ThumbnailCaption extends StatelessWidget {
  const _ThumbnailCaption({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.68)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Text(
          assetName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
