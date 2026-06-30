import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:noema/core/ui/noema_scene.dart';

class NoemaMessageController extends ChangeNotifier {
  String? get message => _message;

  String? _message;
  Timer? _timer;

  void show(
    String message, {
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    _timer?.cancel();
    _message = message;
    notifyListeners();
    _timer = Timer(duration, hide);
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    if (_message == null) {
      return;
    }
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class NoemaMessageHost extends StatelessWidget {
  const NoemaMessageHost({
    required this.controller,
    required this.child,
    super.key,
  });

  final NoemaMessageController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final message = controller.message;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            if (message != null) _NoemaMessageBubble(message: message),
          ],
        );
      },
      child: child,
    );
  }
}

class _NoemaMessageBubble extends StatelessWidget {
  const _NoemaMessageBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final palette = NoemaPalette.fromTone(NoemaTone.dark);
    final topOffset = math.max(132.0, mediaQuery.viewPadding.top + 126);

    return Positioned(
      left: 28,
      right: 28,
      top: topOffset,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 242),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.35, end: 1),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * -5),
                    child: child,
                  ),
                );
              },
              child: NoemaHintBubble(
                palette: palette,
                text: message,
                fontFamily: 'LXGWWenKaiGB',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NoemaHintBubble extends StatelessWidget {
  const NoemaHintBubble({
    required this.palette,
    required this.text,
    super.key,
    this.fontFamily,
    this.liveRegion = false,
  });

  final NoemaPalette palette;
  final String text;
  final String? fontFamily;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.sheet.withValues(alpha: 0.92),
        border: Border.all(color: palette.glassBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: palette.tone == NoemaTone.dark ? 0.24 : 0.08,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Semantics(
          liveRegion: liveRegion,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              inherit: false,
              color: palette.ink,
              fontFamily: fontFamily,
              fontSize: 15,
              height: 1.2,
              letterSpacing: 0,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
