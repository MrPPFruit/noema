import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/noema_routes.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/widgets/noema_message.dart';

const _homeExitBackWindow = Duration(milliseconds: 2500);
const _backIntentDebounceWindow = Duration(milliseconds: 350);

typedef NoemaLocalBackHandler = FutureOr<bool> Function();

class NoemaBackNavigationController {
  NoemaBackNavigationController({
    required this.scaffoldMessengerKey,
    required this.messageController,
  });

  static const _systemBackChannel = MethodChannel(
    'com.mrppfruit.noema/system_back',
  );

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final NoemaMessageController messageController;
  GoRouter? router;
  DateTime? _lastHomeBackAt;
  DateTime? _lastBackIntentAt;
  Uri? _lastBackIntentUri;
  final List<NoemaLocalBackHandler> _localBackHandlers = [];

  void attachSystemBackChannel() {
    _systemBackChannel.setMethodCallHandler(_handleSystemBackCall);
  }

  void dispose() {
    messageController.hide();
    _localBackHandlers.clear();
    _systemBackChannel.setMethodCallHandler(null);
  }

  VoidCallback registerLocalBackHandler(NoemaLocalBackHandler handler) {
    _localBackHandlers.add(handler);
    var active = true;
    return () {
      if (!active) {
        return;
      }
      active = false;
      _localBackHandlers.remove(handler);
    };
  }

  Future<Object?> _handleSystemBackCall(MethodCall call) async {
    if (call.method == 'systemBack') {
      return handleBackIntent();
    }
    throw MissingPluginException('Unknown Noema system back method');
  }

  Future<bool> handleBackIntent() async {
    final router = this.router;
    if (router == null) {
      return false;
    }

    final now = DateTime.now();
    final uri = router.routeInformationProvider.value.uri;
    final context =
        router.routerDelegate.navigatorKey.currentContext ??
        scaffoldMessengerKey.currentContext;
    final backAgainToExitMessage = context == null
        ? null
        : NoemaStrings.of(context).backAgainToExit;

    for (final handler in _localBackHandlers.reversed.toList(growable: false)) {
      final handled = await handler();
      if (handled) {
        messageController.hide();
        _lastHomeBackAt = null;
        return true;
      }
    }

    if (router.canPop()) {
      if (_isDuplicateBackIntent(now, uri)) {
        return true;
      }
      messageController.hide();
      _lastHomeBackAt = null;
      router.pop();
      return true;
    }

    final target = noemaBackTargetForUri(uri);
    if (target != null) {
      if (_isDuplicateBackIntent(now, uri)) {
        return true;
      }
      messageController.hide();
      _lastHomeBackAt = null;
      router.go(target);
      return true;
    }

    final lastBackAt = _lastHomeBackAt;
    if (lastBackAt != null &&
        now.difference(lastBackAt) <= _homeExitBackWindow) {
      messageController.hide();
      _lastHomeBackAt = null;
      await SystemNavigator.pop();
      return true;
    }

    _lastHomeBackAt = now;
    if (backAgainToExitMessage != null) {
      messageController.show(backAgainToExitMessage);
    }
    return true;
  }

  bool _isDuplicateBackIntent(DateTime now, Uri uri) {
    final lastBackIntentAt = _lastBackIntentAt;
    final lastBackIntentUri = _lastBackIntentUri;
    _lastBackIntentAt = now;
    _lastBackIntentUri = uri;
    return lastBackIntentAt != null &&
        lastBackIntentUri == uri &&
        now.difference(lastBackIntentAt) <= _backIntentDebounceWindow;
  }
}

class NoemaBackButtonDispatcher extends RootBackButtonDispatcher {
  NoemaBackButtonDispatcher({required this.controller});

  final NoemaBackNavigationController controller;

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) async {
    return controller.handleBackIntent();
  }
}

class NoemaBackNavigationGuard extends StatelessWidget {
  const NoemaBackNavigationGuard({
    required this.controller,
    required this.child,
    super.key,
  });

  final NoemaBackNavigationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NoemaBackNavigationScope(
      controller: controller,
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(controller.handleBackIntent());
          }
        },
        child: child,
      ),
    );
  }
}

class NoemaBackNavigationScope extends InheritedWidget {
  const NoemaBackNavigationScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final NoemaBackNavigationController controller;

  static NoemaBackNavigationController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NoemaBackNavigationScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(covariant NoemaBackNavigationScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

String? noemaBackTargetForUri(Uri uri) {
  return switch (uri.path) {
    '' => null,
    NoemaRoutes.home => null,
    NoemaRoutes.import =>
      uri.queryParameters['mode'] == 'append'
          ? NoemaRoutes.observe
          : NoemaRoutes.home,
    NoemaRoutes.observePhoto => NoemaRoutes.observe,
    NoemaRoutes.appraise => NoemaRoutes.observe,
    NoemaRoutes.observe => NoemaRoutes.home,
    NoemaRoutes.processing => NoemaRoutes.home,
    NoemaRoutes.reviewGroups => NoemaRoutes.observe,
    NoemaRoutes.arena => NoemaRoutes.reviewGroups,
    NoemaRoutes.results => NoemaRoutes.arena,
    _ => NoemaRoutes.home,
  };
}
