import 'package:flutter/material.dart';
import 'package:noema/core/theme/noema_colors.dart';
import 'package:noema/core/ui/noema_scene.dart';

enum NoemaDialogButtonTone { neutral, primary, danger }

class NoemaDialogPanel extends StatelessWidget {
  const NoemaDialogPanel({
    required this.palette,
    required this.title,
    required this.body,
    required this.actions,
    super.key,
    this.maxWidth = 326,
    this.accentColor = NoemaColors.accentPrimary,
    this.surfaceColor,
    this.borderColor,
    this.panelKey,
    this.onClose,
    this.closeTooltip = '关闭',
  });

  final NoemaPalette palette;
  final String title;
  final Widget body;
  final Widget actions;
  final double maxWidth;
  final Color accentColor;
  final Color? surfaceColor;
  final Color? borderColor;
  final Key? panelKey;
  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      child: ConstrainedBox(
        key: panelKey,
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor ?? palette.sheet.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor ?? accentColor.withValues(alpha: 0.74),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.tone == NoemaTone.dark ? 0.42 : 0.18,
                ),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: accentColor,
                          fontFamily: 'LXGWWenKaiGB',
                          fontFamilyFallback: const ['NoemaCjkFallback'],
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: 0,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 12),
                      _NoemaDialogCloseButton(
                        palette: palette,
                        tooltip: closeTooltip,
                        onPressed: onClose!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                body,
                const SizedBox(height: 18),
                actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoemaDialogCloseButton extends StatelessWidget {
  const _NoemaDialogCloseButton({
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = palette.ink.withValues(alpha: 0.72);

    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.close_rounded, size: 18, color: foreground),
        style: IconButton.styleFrom(
          backgroundColor: palette.glass.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          side: BorderSide(color: palette.glassBorder.withValues(alpha: 0.34)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class NoemaDialogText extends StatelessWidget {
  const NoemaDialogText({
    required this.palette,
    required this.text,
    super.key,
    this.color,
  });

  final NoemaPalette palette;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? palette.ink.withValues(alpha: 0.88),
        fontFamily: 'LXGWWenKaiGB',
        fontFamilyFallback: const ['NoemaCjkFallback'],
        fontSize: 14.5,
        height: 1.65,
        letterSpacing: 0,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class NoemaDialogButton extends StatelessWidget {
  const NoemaDialogButton({
    required this.palette,
    required this.label,
    required this.onPressed,
    super.key,
    this.tone = NoemaDialogButtonTone.neutral,
    this.icon,
    this.accentColor = NoemaColors.accentPrimary,
    this.minWidth = 0,
  });

  final NoemaPalette palette;
  final String label;
  final VoidCallback onPressed;
  final NoemaDialogButtonTone tone;
  final IconData? icon;
  final Color accentColor;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final dangerColor = palette.tone == NoemaTone.dark
        ? const Color(0xFFE1A39B)
        : const Color(0xFF8D3028);
    final foreground = switch (tone) {
      NoemaDialogButtonTone.primary => accentColor,
      NoemaDialogButtonTone.danger => dangerColor,
      NoemaDialogButtonTone.neutral => palette.ink.withValues(alpha: 0.84),
    };
    final backgroundAlpha = switch (tone) {
      NoemaDialogButtonTone.primary => 0.13,
      NoemaDialogButtonTone.danger => 0.11,
      NoemaDialogButtonTone.neutral => 0.055,
    };
    final borderAlpha = switch (tone) {
      NoemaDialogButtonTone.primary => 0.82,
      NoemaDialogButtonTone.danger => 0.62,
      NoemaDialogButtonTone.neutral => 0.58,
    };

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 7)],
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size(minWidth, 38),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        foregroundColor: foreground,
        backgroundColor: foreground.withValues(alpha: backgroundAlpha),
        shape: const StadiumBorder(),
        side: BorderSide(color: foreground.withValues(alpha: borderAlpha)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontFamily: 'LXGWWenKaiGB',
          fontFamilyFallback: ['NoemaCjkFallback'],
          fontSize: 13.5,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
      child: child,
    );
  }
}
