import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/storage/noema_local_store.dart';
import 'package:noema/core/theme/noema_theme.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_message.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';

class NoemaApp extends StatefulWidget {
  const NoemaApp({super.key, this.locale, this.workspaceController});

  final Locale? locale;
  final ReviewWorkspaceController? workspaceController;

  @override
  State<NoemaApp> createState() => _NoemaAppState();
}

class _NoemaAppState extends State<NoemaApp> {
  late final ReviewWorkspaceController _workspaceController;
  late final bool _ownsWorkspaceController;
  late final NoemaAppearanceController _appearanceController;
  late final NoemaMessageController _messageController;
  late final GoRouter _router;
  late final NoemaBackNavigationController _backNavigationController;
  late final NoemaBackButtonDispatcher _backButtonDispatcher;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _ownsWorkspaceController = widget.workspaceController == null;
    _workspaceController =
        widget.workspaceController ??
        ReviewWorkspaceController(
          localStore: NoemaLocalStore(),
          backgroundPreviewCachingEnabled: true,
        );
    _appearanceController = NoemaAppearanceController(
      initialToneMode: _initialToneModeFromUri(),
    );
    _messageController = NoemaMessageController();
    _backNavigationController = NoemaBackNavigationController(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      messageController: _messageController,
    );
    _backNavigationController.attachSystemBackChannel();
    _router = createNoemaRouter(
      _workspaceController,
      _appearanceController,
      _backNavigationController,
    );
    _backNavigationController.router = _router;
    _backButtonDispatcher = NoemaBackButtonDispatcher(
      controller: _backNavigationController,
    );
    if (_ownsWorkspaceController) {
      unawaited(_workspaceController.restore());
    }
  }

  @override
  void dispose() {
    _backNavigationController.dispose();
    _messageController.dispose();
    _appearanceController.dispose();
    if (_ownsWorkspaceController) {
      _workspaceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Noema',
      debugShowCheckedModeBanner: false,
      theme: NoemaTheme.dark(),
      locale: widget.locale,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      localeListResolutionCallback: _resolveLocale,
      routeInformationProvider: _router.routeInformationProvider,
      routeInformationParser: _router.routeInformationParser,
      routerDelegate: _router.routerDelegate,
      backButtonDispatcher: _backButtonDispatcher,
      builder: (context, child) => NoemaMessageHost(
        controller: _messageController,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

NoemaToneMode _initialToneModeFromUri() {
  final value =
      Uri.base.queryParameters['tone'] ?? Uri.base.queryParameters['theme'];
  return switch (value?.toLowerCase()) {
    'light' => NoemaToneMode.light,
    'auto' => NoemaToneMode.auto,
    _ => NoemaToneMode.dark,
  };
}

Locale _resolveLocale(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  final preferredLanguage = locales?.firstOrNull?.languageCode;
  if (preferredLanguage == 'zh') {
    return const Locale('zh');
  }
  return const Locale('en');
}
