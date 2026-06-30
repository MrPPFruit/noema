import 'package:flutter/material.dart';
import 'package:noema/core/ui/noema_scene.dart';

class NoemaPhotoWallHeartBadge extends StatelessWidget {
  const NoemaPhotoWallHeartBadge({
    super.key,
    required this.palette,
    required this.cherished,
    this.onTap,
    this.tooltip,
  });

  final NoemaPalette palette;
  final bool cherished;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = cherished
        ? const Color(0xFFE9B7AF)
        : Colors.white.withValues(alpha: 0.88);
    final visual = SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.24),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 23,
            height: 23,
            child: Icon(
              cherished
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: color,
              size: 14,
            ),
          ),
        ),
      ),
    );

    if (onTap == null) {
      return visual;
    }

    return Tooltip(
      message: tooltip ?? (cherished ? '取消珍藏' : '珍藏'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: visual,
      ),
    );
  }
}

class NoemaPhotoWallScoreBadge extends StatelessWidget {
  const NoemaPhotoWallScoreBadge({
    super.key,
    required this.palette,
    required this.score,
  });

  final NoemaPalette palette;
  final int score;

  @override
  Widget build(BuildContext context) {
    final scoreColor = noemaPhotoWallScoreColor(palette, score);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scoreColor.withValues(alpha: 0.12),
          Colors.black.withValues(alpha: 0.58),
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scoreColor.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          '$score',
          style: TextStyle(
            color: scoreColor,
            fontFamily: 'NoemaDigits',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 0,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.70),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color noemaPhotoWallScoreColor(NoemaPalette palette, int score) {
  final normalized = score.clamp(0, 100);
  if (palette.tone == NoemaTone.light) {
    if (normalized >= 80) {
      return const Color(0xFFB8D88B);
    }
    if (normalized >= 70) {
      return const Color(0xFFE0AD5E);
    }
    if (normalized >= 60) {
      return const Color(0xFFE5B770);
    }
    return const Color(0xFFE49578);
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
