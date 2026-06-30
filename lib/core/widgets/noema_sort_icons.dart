import 'package:flutter/material.dart';
import 'package:noema/core/ui/noema_scene.dart';

class NoemaScoreSortIcon extends StatelessWidget {
  const NoemaScoreSortIcon({
    required this.palette,
    required this.ascending,
    super.key,
  });

  final NoemaPalette palette;
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? palette.ink;
    return Center(
      child: SizedBox(
        width: 28,
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: color, size: 16),
            Transform.translate(
              offset: const Offset(-1, 0),
              child: Icon(
                ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: color,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
