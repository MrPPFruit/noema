import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const noemaTitleCjkFontFamily = 'NoemaTitleCjk';
const noemaCjkFontFamily = 'LXGWWenKaiGB';

enum NoemaToneMode { light, dark, auto }

enum NoemaTone { light, dark }

class NoemaAppearanceController extends ChangeNotifier {
  NoemaAppearanceController({
    NoemaToneMode initialToneMode = NoemaToneMode.dark,
  }) {
    _toneMode = initialToneMode;
  }

  late NoemaToneMode _toneMode;

  NoemaToneMode get toneMode => _toneMode;

  set toneMode(NoemaToneMode value) {
    if (_toneMode == value) {
      return;
    }
    _toneMode = value;
    notifyListeners();
  }

  void cycleToneMode() {
    toneMode = switch (_toneMode) {
      NoemaToneMode.light => NoemaToneMode.dark,
      NoemaToneMode.dark => NoemaToneMode.auto,
      NoemaToneMode.auto => NoemaToneMode.light,
    };
  }

  NoemaTone resolveTone(BuildContext context) {
    if (_toneMode == NoemaToneMode.light) {
      return NoemaTone.light;
    }
    if (_toneMode == NoemaToneMode.dark) {
      return NoemaTone.dark;
    }
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? NoemaTone.dark
        : NoemaTone.light;
  }
}

class NoemaSceneMetrics {
  const NoemaSceneMetrics._();

  static const double designWidth = 390.0;
  static const double designHeight = 844.0;
  static const double topBarHeight = 44.0;
  static const double markLeft = 27.0;
  static const double topBarTop = 28.0;
  static const double markTop = 39.0;
  static const double bodyTop = 72.0;
  static const double sideInset = 24.0;
  static const double iconTapSize = 44.0;
  static const double iconVisualSize = 40.0;
  static const double topBarInset =
      sideInset - ((iconTapSize - iconVisualSize) / 2);
}

class NoemaSceneFrame extends StatelessWidget {
  const NoemaSceneFrame({
    super.key,
    required this.palette,
    required this.child,
  });

  final NoemaPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.backgroundEnd,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(
            constraints.maxWidth,
            NoemaSceneMetrics.designWidth,
          );
          final height = math.max(
            constraints.maxHeight,
            MediaQuery.sizeOf(context).height,
          );
          final contentHeight = math.min(
            height,
            NoemaSceneMetrics.designHeight,
          );

          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: NoemaSceneSurface(
                palette: palette,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(height: contentHeight, child: child),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NoemaSceneSurface extends StatelessWidget {
  const NoemaSceneSurface({
    super.key,
    required this.palette,
    required this.child,
  });

  final NoemaPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.backgroundStart, palette.backgroundEnd],
        ),
      ),
      child: CustomPaint(
        painter: NoemaSceneBackgroundPainter(palette),
        child: child,
      ),
    );
  }
}

class NoemaThemeMark extends StatelessWidget {
  const NoemaThemeMark({super.key, required this.palette, required this.mark});

  final NoemaPalette palette;
  final String mark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          style: TextStyle(
            color: palette.mark,
            fontFamily: noemaTitleCjkFontFamily,
            fontFamilyFallback: _noemaCjkFontFallback,
            fontSize: 164,
            height: 0.82,
            letterSpacing: 0,
            shadows: [
              Shadow(
                color: palette.markShadow,
                offset: const Offset(0, 24),
                blurRadius: 52,
              ),
            ],
          ),
          child: Text(mark),
        ),
      ),
    );
  }
}

class NoemaWordmark extends StatelessWidget {
  const NoemaWordmark({
    super.key,
    required this.color,
    this.text = 'Noema',
    this.opacity = 1,
    this.fontSize = 21,
  });

  final Color color;
  final String text;
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color.withValues(alpha: opacity),
        fontFamily: 'NoemaLatin',
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1,
        letterSpacing: 0,
      ),
    );
  }
}

class NoemaScrollEdgeFade extends StatelessWidget {
  const NoemaScrollEdgeFade({
    super.key,
    required this.palette,
    required this.top,
    this.height = 56,
  });

  final NoemaPalette palette;
  final bool top;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: _gradient()),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  LinearGradient _gradient() {
    final edge = top ? palette.backgroundStart : palette.backgroundEnd;
    return LinearGradient(
      begin: top ? Alignment.topCenter : Alignment.bottomCenter,
      end: top ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [
        edge.withValues(alpha: 0.94),
        edge.withValues(alpha: 0.18),
        edge.withValues(alpha: 0),
      ],
      stops: const [0, 0.64, 1],
    );
  }
}

class NoemaFloatingActionButton extends StatelessWidget {
  const NoemaFloatingActionButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.enabled = true,
    this.onDisabledPressed,
  });

  final NoemaPalette palette;
  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool enabled;
  final VoidCallback? onDisabledPressed;

  @override
  Widget build(BuildContext context) {
    return NoemaSquareActionButton(
      palette: palette,
      tooltip: tooltip,
      enabled: enabled,
      onDisabledPressed: onDisabledPressed,
      onPressed: onPressed,
      cardSize: const Size(58, 74),
      hitSize: const Size(84, 92),
      radius: 18,
      glassScale: 1.18,
      strokeOpacity: 0.96,
      shadowScale: 1.22,
      child: child,
    );
  }
}

class NoemaSquareActionButton extends StatelessWidget {
  const NoemaSquareActionButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.child,
    this.actionKey,
    this.enabled = true,
    this.onDisabledPressed,
    this.cardSize = const Size(58, 74),
    this.hitSize = const Size(84, 92),
    this.cjkFontSize = 29,
    this.latinFontSize = 12,
    this.radius = 18,
    this.opacity = 1,
    this.glassScale = 1,
    this.strokeOpacity = 0.88,
    this.shadowScale = 1,
    this.motifOpacity = 1,
  });

  final NoemaPalette palette;
  final String tooltip;
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final Key? actionKey;
  final bool enabled;
  final VoidCallback? onDisabledPressed;
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
    final effectiveOnTap = enabled ? onPressed : onDisabledPressed;
    final interactiveInactive = !enabled && onDisabledPressed != null;
    final darkTone = palette.tone == NoemaTone.dark;
    final glassBase = darkTone ? const Color(0xFF070A0A) : palette.glass;
    final stabilizingFill = darkTone
        ? const Color(0xFF020303).withValues(alpha: 0.99)
        : Colors.white.withValues(alpha: 0.28);
    final topGlassAlpha = ((darkTone ? 0.78 : 0.56) * glassScale)
        .clamp(0.0, 1.0)
        .toDouble();
    final bottomGlassAlpha = ((darkTone ? 0.94 : 0.72) * glassScale)
        .clamp(0.0, 1.0)
        .toDouble();
    final disabledAlpha = interactiveInactive
        ? (darkTone ? 0.62 : 0.7)
        : (darkTone ? 0.34 : 0.42);
    final foreground = enabled
        ? palette.ink
        : palette.ink.withValues(alpha: disabledAlpha);
    final border = enabled
        ? palette.glassBorder.withValues(alpha: strokeOpacity)
        : interactiveInactive
        ? palette.ink.withValues(alpha: darkTone ? 0.22 : 0.28)
        : palette.glassBorder.withValues(alpha: 0.36);
    final shadowAlpha =
        ((enabled
                    ? (darkTone ? 0.42 : 0.12)
                    : interactiveInactive
                    ? (darkTone ? 0.16 : 0.08)
                    : (darkTone ? 0.08 : 0.04)) *
                shadowScale)
            .clamp(0.0, 1.0)
            .toDouble();
    final rimGlowAlpha =
        ((enabled
                    ? (darkTone ? 0.14 : 0.05)
                    : interactiveInactive
                    ? (darkTone ? 0.08 : 0.03)
                    : 0.0) *
                shadowScale)
            .clamp(0.0, 0.2)
            .toDouble();
    final shadowExtent = shadowScale.clamp(0.35, 1.2).toDouble();
    final labelText = label;
    final hasCjk = labelText != null && _noemaContainsCjk(labelText);

    return Opacity(
      opacity: opacity,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: effectiveOnTap != null,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: effectiveOnTap,
            child: SizedBox(
              key: actionKey,
              width: hitSize.width,
              height: hitSize.height,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: cardSize.width,
                      height: cardSize.height,
                      decoration: BoxDecoration(
                        color: stabilizingFill,
                        borderRadius: BorderRadius.circular(radius),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            glassBase.withValues(alpha: topGlassAlpha),
                            glassBase.withValues(alpha: bottomGlassAlpha),
                          ],
                        ),
                        border: Border.all(
                          color: border,
                          width: enabled ? 1.28 : 1,
                        ),
                        boxShadow: [
                          if (rimGlowAlpha > 0)
                            BoxShadow(
                              color: palette.ink.withValues(
                                alpha: rimGlowAlpha,
                              ),
                              blurRadius: 18 * shadowExtent,
                              spreadRadius: -3 * shadowExtent,
                            ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha),
                            blurRadius: 26 * shadowExtent,
                            offset: Offset(0, 14 * shadowExtent),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (motifOpacity > 0)
                            Positioned(
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: foreground.withValues(
                                    alpha: 0.34 * motifOpacity,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const SizedBox(width: 14, height: 1),
                              ),
                            ),
                          if (labelText != null)
                            Text(
                              labelText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontFamily:
                                    _noemaFontForText(labelText) ??
                                    'NoemaLatin',
                                fontFamilyFallback: hasCjk
                                    ? _noemaCjkFontFallback
                                    : null,
                                fontSize: hasCjk ? cjkFontSize : latinFontSize,
                                height: 1,
                                letterSpacing: 0,
                              ),
                            )
                          else
                            IconTheme(
                              data: IconThemeData(color: foreground, size: 32),
                              child: child ?? const SizedBox.shrink(),
                            ),
                          if (motifOpacity > 0)
                            Positioned(
                              bottom: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: foreground.withValues(
                                    alpha: 0.24 * motifOpacity,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const SizedBox(width: 10, height: 1),
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
      ),
    );
  }
}

class NoemaGlassIconButton extends StatelessWidget {
  const NoemaGlassIconButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.child,
    this.danger = false,
    this.visualKey,
    this.surfaceOpacityScale = 1,
  }) : assert(icon != null || child != null);

  final NoemaPalette palette;
  final String tooltip;
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final bool danger;
  final Key? visualKey;
  final double surfaceOpacityScale;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = danger
        ? (palette.tone == NoemaTone.dark
              ? const Color(0xFFE1A39B)
              : const Color(0xFF8D3028))
        : palette.ink;

    final iconColor = onPressed == null
        ? palette.muted.withValues(alpha: 0.5)
        : effectiveColor;
    final surfaceAlpha =
        ((palette.tone == NoemaTone.dark ? 0.26 : 0.46) * surfaceOpacityScale)
            .clamp(0.0, 1.0)
            .toDouble();
    final button = AnimatedContainer(
      key: visualKey,
      duration: const Duration(milliseconds: 160),
      width: NoemaSceneMetrics.iconVisualSize,
      height: NoemaSceneMetrics.iconVisualSize,
      decoration: BoxDecoration(
        color: palette.glass.withValues(alpha: surfaceAlpha),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: child != null
            ? IconTheme(
                data: IconThemeData(color: iconColor, size: 24),
                child: child!,
              )
            : Icon(icon, size: 24, color: iconColor),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: NoemaSceneMetrics.iconTapSize,
            height: NoemaSceneMetrics.iconTapSize,
            child: Center(child: button),
          ),
        ),
      ),
    );
  }
}

String? _noemaFontForText(String text) {
  return _noemaContainsCjk(text) ? noemaCjkFontFamily : null;
}

const _noemaCjkFontFallback = <String>[
  noemaCjkFontFamily,
  'NoemaCjkFallback',
  'PingFang SC',
  'Heiti SC',
  'Noto Sans CJK SC',
  'Microsoft YaHei',
  'sans-serif',
];

bool _noemaContainsCjk(String text) {
  return text.runes.any(
    (rune) =>
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF),
  );
}

class NoemaSceneBackgroundPainter extends CustomPainter {
  const NoemaSceneBackgroundPainter(this.palette);

  final NoemaPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final topGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [palette.glowTop, palette.glowTop.withValues(alpha: 0)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.12),
              radius: 210,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.12),
      210,
      topGlow,
    );

    final bottomGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              palette.glowBottom,
              palette.glowBottom.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.74, size.height * 0.79),
              radius: 220,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.79),
      220,
      bottomGlow,
    );
  }

  @override
  bool shouldRepaint(covariant NoemaSceneBackgroundPainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class NoemaPalette {
  const NoemaPalette({
    required this.tone,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.ink,
    required this.muted,
    required this.mark,
    required this.markShadow,
    required this.cardBorder,
    required this.cardShadow,
    required this.glass,
    required this.glassBorder,
    required this.sheet,
    required this.glowTop,
    required this.glowBottom,
    required this.photoFallback,
    required this.photoFallbackAlt,
    required this.photoFilter,
  });

  final NoemaTone tone;
  final Color backgroundStart;
  final Color backgroundEnd;
  final Color ink;
  final Color muted;
  final Color mark;
  final Color markShadow;
  final Color cardBorder;
  final Color cardShadow;
  final Color glass;
  final Color glassBorder;
  final Color sheet;
  final Color glowTop;
  final Color glowBottom;
  final Color photoFallback;
  final Color photoFallbackAlt;
  final ColorFilter photoFilter;

  factory NoemaPalette.fromTone(NoemaTone tone) {
    return switch (tone) {
      NoemaTone.light => NoemaPalette(
        tone: tone,
        backgroundStart: const Color(0xFFFBF8F1),
        backgroundEnd: const Color(0xFFF2EDE3),
        ink: const Color(0xFF24211D),
        muted: const Color(0xFF5D5750),
        mark: const Color(0x13211F1B),
        markShadow: Colors.black.withValues(alpha: 0.04),
        cardBorder: const Color(0x2E2A2621),
        cardShadow: const Color(0x24322A1F),
        glass: Colors.white.withValues(alpha: 0.72),
        glassBorder: const Color(0x1A2D2720),
        sheet: const Color(0xDBFDFAF4),
        glowTop: Colors.white.withValues(alpha: 0.95),
        glowBottom: const Color(0x3DDED5C5),
        photoFallback: const Color(0xFFC9C5BC),
        photoFallbackAlt: const Color(0xFFE7E1D4),
        photoFilter: const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
      ),
      NoemaTone.dark => NoemaPalette(
        tone: tone,
        backgroundStart: const Color(0xFF101313),
        backgroundEnd: const Color(0xFF060707),
        ink: const Color(0xFFF2EEE5),
        muted: const Color(0xFFB9B0A2),
        mark: const Color(0x0EF5F1E7),
        markShadow: Colors.black.withValues(alpha: 0.18),
        cardBorder: const Color(0x6BF5EFE2),
        cardShadow: Colors.black.withValues(alpha: 0.42),
        glass: const Color(0x942A2A28),
        glassBorder: const Color(0x3DF5EFE2),
        sheet: const Color(0xE0141616),
        glowTop: Colors.white.withValues(alpha: 0.055),
        glowBottom: Colors.white.withValues(alpha: 0.035),
        photoFallback: const Color(0xFF252827),
        photoFallbackAlt: const Color(0xFF4C4A43),
        photoFilter: const ColorFilter.matrix(<double>[
          0.7963, 0.0519, 0.0052, 0, -5.2275, //
          0.0147, 0.8335, 0.0052, 0, -5.2275, //
          0.0147, 0.0519, 0.7868, 0, -5.2275, //
          0, 0, 0, 1, 0,
        ]),
      ),
    };
  }
}
