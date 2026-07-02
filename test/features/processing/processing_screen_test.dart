import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/noema_routes.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/processing/processing_screen.dart';

void main() {
  test('experience dock preview query chooses the expected variant', () {
    expect(
      experienceDockVariantFromQuery(null),
      ExperienceDockVariant.intentSeal,
    );
    expect(
      experienceDockVariantFromQuery('balanced'),
      ExperienceDockVariant.balanced,
    );
    expect(
      experienceDockVariantFromQuery('classic'),
      ExperienceDockVariant.balanced,
    );
    expect(experienceDockVariantFromQuery('lens'), ExperienceDockVariant.lens);
    expect(
      experienceDockVariantFromQuery('mirror'),
      ExperienceDockVariant.lens,
    );
    expect(
      experienceDockVariantFromQuery('object'),
      ExperienceDockVariant.object,
    );
    expect(
      experienceDockVariantFromQuery('emerge'),
      ExperienceDockVariant.object,
    );
    expect(
      experienceDockVariantFromQuery('intent'),
      ExperienceDockVariant.intent,
    );
    expect(
      experienceDockVariantFromQuery('axis'),
      ExperienceDockVariant.intent,
    );
    expect(
      experienceDockVariantFromQuery('intent-ripple'),
      ExperienceDockVariant.intentRipple,
    );
    expect(
      experienceDockVariantFromQuery('ripple'),
      ExperienceDockVariant.intentRipple,
    );
    expect(
      experienceDockVariantFromQuery('intent-seal'),
      ExperienceDockVariant.intentSeal,
    );
    expect(
      experienceDockVariantFromQuery('seal'),
      ExperienceDockVariant.intentSeal,
    );
    expect(
      experienceDockVariantFromQuery('intent-tiles'),
      ExperienceDockVariant.intentTiles,
    );
    expect(
      experienceDockVariantFromQuery('tiles'),
      ExperienceDockVariant.intentTiles,
    );
    expect(
      experienceDockVariantFromQuery('intent-rail'),
      ExperienceDockVariant.intentRail,
    );
    expect(
      experienceDockVariantFromQuery('slate'),
      ExperienceDockVariant.intentRail,
    );
    expect(
      experienceDockVariantFromQuery('intent-gate'),
      ExperienceDockVariant.intentGate,
    );
    expect(
      experienceDockVariantFromQuery('gate'),
      ExperienceDockVariant.intentGate,
    );
    expect(
      experienceDockVariantFromQuery('quiet'),
      ExperienceDockVariant.quiet,
    );
    expect(
      experienceDockVariantFromQuery('orbit'),
      ExperienceDockVariant.orbit,
    );
    expect(experienceDockVariantFromQuery('rail'), ExperienceDockVariant.rail);
  });

  testWidgets('Observe page shows photo wall tools and function entries', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    expect(find.text('Noema'), findsOneWidget);
    expect(find.text('观'), findsOneWidget);
    expect(find.text('友人'), findsOneWidget);
    expect(find.text('18 张'), findsOneWidget);
    expect(find.byTooltip('添加照片'), findsOneWidget);
    expect(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'), findsOneWidget);
    expect(find.text('甄'), findsOneWidget);
    expect(find.text('赏'), findsOneWidget);
    expect(find.text('鉴'), findsOneWidget);
  });

  testWidgets('Observe keeps cull entry when no actionable groups exist', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(id: '/tmp/a.jpg', name: 'A.jpg'),
      SelectedGalleryAsset(id: '/tmp/b.jpg', name: 'B.jpg'),
    ], name: '散片');

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.text('甄'), findsOneWidget);
    expect(find.text('赏'), findsOneWidget);
  });

  testWidgets('Observe hides experience dock when there are no photos', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.text('还没有照片'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('observe-experience-intent')),
      findsNothing,
    );
    expect(find.text('赏'), findsNothing);
  });

  testWidgets('Observe keeps cull entry after cull group is fully decided', (
    tester,
  ) async {
    final controller = _sampleObserveController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);
    expect(find.text('甄'), findsOneWidget);

    controller.recordDecision('photo-1', Decision.keep);
    controller.recordDecision('photo-2', Decision.reviewForRemoval);
    await tester.pump();

    expect(find.text('甄'), findsOneWidget);

    controller.clearDecision('photo-2');
    await tester.pump();

    expect(find.text('甄'), findsOneWidget);
  });

  testWidgets(
    'Observe experiment dock can preview cull entry after completion',
    (tester) async {
      final controller = _sampleObserveController();
      controller.recordDecision('photo-1', Decision.keep);
      controller.recordDecision('photo-2', Decision.reviewForRemoval);

      await tester.pumpWidget(
        _ObserveTestApp(
          controller: controller,
          experienceDockVariant: ExperienceDockVariant.balanced,
        ),
      );
      await _pumpObserveUi(tester);

      expect(find.text('甄'), findsOneWidget);
      expect(find.text('鉴'), findsOneWidget);
    },
  );

  testWidgets('Observe intent seal tuning exposes the parameter readout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ObserveTestApp(
        experienceDockVariant: ExperienceDockVariant.intentSeal,
        experienceDockTuning: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('observe-intent-tune-readout')),
      findsOneWidget,
    );
    expect(find.text('赏终点'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('observe-intent-left-endpoint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('observe-intent-right-endpoint')),
      findsOneWidget,
    );
  });

  testWidgets('Observe Chinese copy uses LXGWWenKaiGB font', (tester) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    expect(
      tester.widget<Text>(find.text('18 张')).style?.fontFamily,
      'LXGWWenKaiGB',
    );
    expect(
      tester.widget<Text>(find.text('甄')).style?.fontFamily,
      'LXGWWenKaiGB',
    );
    expect(
      tester.widget<Text>(find.text('赏')).style?.fontFamily,
      'LXGWWenKaiGB',
    );
    expect(
      tester.widget<Text>(find.text('鉴')).style?.fontFamily,
      'LXGWWenKaiGB',
    );
  });

  testWidgets('Observe English function entries stay compact', (tester) async {
    await tester.pumpWidget(_ObserveTestApp(locale: const Locale('en')));
    await _pumpObserveUi(tester);

    expect(find.text('Cull'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Appreciate'), findsNothing);
  });

  testWidgets('Observe confirmed cull entry stays left of appreciate', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final cullLeft = tester.getTopLeft(find.text('甄')).dx;
    final viewLeft = tester.getTopLeft(find.text('赏')).dx;
    final appraiseLeft = tester.getTopLeft(find.text('鉴')).dx;

    expect(cullLeft, lessThan(viewLeft));
    expect(viewLeft, lessThan(appraiseLeft));
  });

  testWidgets('Observe default dock makes view the visual anchor', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final cullSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-cull')),
    );
    final viewSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-intent')),
    );
    final appraiseSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-appraise')),
    );

    expect(viewSize.width, greaterThan(cullSize.width));
    expect(viewSize.height, greaterThan(cullSize.height));
    expect(viewSize.width, greaterThan(appraiseSize.width));
    expect(viewSize.height, greaterThan(appraiseSize.height));
  });

  testWidgets('Observe intent dock aligns with shared bottom actions', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final viewRect = tester.getRect(
      find.byKey(const ValueKey('observe-experience-intent')),
    );
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    expect((viewportHeight - viewRect.bottom).round(), 32);
  });

  testWidgets('Observe intent dock follows direct touch across entries', (
    tester,
  ) async {
    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          hapticCalls.add(call);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_ObserveTestApp(experienceDockTuning: true));
    await _pumpObserveUi(tester);

    final intent = find.byKey(const ValueKey('observe-experience-intent'));
    final cull = find.byKey(const ValueKey('observe-experience-cull'));
    final appraise = find.byKey(const ValueKey('observe-experience-appraise'));
    final cullCenter = tester.getCenter(cull);
    final appraiseCenter = tester.getCenter(appraise);
    final startIntentCenter = tester.getCenter(intent);

    final gesture = await tester.startGesture(cullCenter);
    await tester.pump();

    expect(
      (tester.getCenter(intent).dx - cullCenter.dx).abs(),
      greaterThan(20),
    );
    final cullSnapStartDistance = (tester.getCenter(intent).dx - cullCenter.dx)
        .abs();
    var jitteredCullCenter = cullCenter;
    for (var index = 0; index < 6; index += 1) {
      jitteredCullCenter = cullCenter.translate(index.isEven ? 1 : -1, 0);
      await gesture.moveTo(jitteredCullCenter);
      await tester.pump(const Duration(milliseconds: 30));
    }
    final cullSnapMidDistance = (tester.getCenter(intent).dx - cullCenter.dx)
        .abs();
    expect(cullSnapMidDistance, lessThan(cullSnapStartDistance - 20));
    expect(cullSnapMidDistance, greaterThan(20));
    await tester.pump(const Duration(milliseconds: 220));
    expect((tester.getCenter(intent).dx - cullCenter.dx).abs(), lessThan(20));
    expect(
      hapticCalls
          .where((call) => call.arguments == 'HapticFeedbackType.lightImpact')
          .length,
      1,
    );

    await gesture.moveTo(cullCenter.translate(0, -80));
    await tester.pump();
    expect(tester.getCenter(intent).dy, lessThan(startIntentCenter.dy));
    expect(hapticCalls.length, 1);

    await gesture.moveTo(appraiseCenter);
    await tester.pump();
    expect(
      (tester.getCenter(intent).dx - appraiseCenter.dx).abs(),
      lessThan(20),
    );
    expect(
      hapticCalls
          .where((call) => call.arguments == 'HapticFeedbackType.lightImpact')
          .length,
      2,
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      (tester.getCenter(intent).dx - startIntentCenter.dx).abs(),
      lessThan(20),
    );
    expect(hapticCalls.length, 2);
  });

  testWidgets('Observe intent dock releases appraise once it is selected', (
    tester,
  ) async {
    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          hapticCalls.add(call);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final controller = _sampleObserveController();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/observe',
      routes: [
        GoRoute(
          path: '/observe',
          builder: (context, state) => ProcessingScreen(
            workspaceController: controller,
            experienceDockVariant: ExperienceDockVariant.intentSeal,
          ),
        ),
        GoRoute(
          path: '/appraise',
          builder: (context, state) => const Text('appraise-destination'),
        ),
        GoRoute(
          path: '/review-groups',
          builder: (context, state) => const Text('review-groups-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
      ),
    );
    await _pumpObserveUi(tester);

    final intent = find.byKey(const ValueKey('observe-experience-intent'));
    final appraise = find.byKey(const ValueKey('observe-experience-appraise'));
    final startIntentCenter = tester.getCenter(intent);
    final appraiseCenter = tester.getCenter(appraise);
    final selectedAppraisePoint = Offset.lerp(
      startIntentCenter,
      appraiseCenter,
      0.56,
    )!;

    final gesture = await tester.startGesture(selectedAppraisePoint);
    await tester.pump();
    expect(
      (tester.getCenter(intent).dx - selectedAppraisePoint.dx).abs(),
      greaterThan(20),
    );
    final appraiseSnapStartDistance =
        (tester.getCenter(intent).dx - selectedAppraisePoint.dx).abs();
    await tester.pump(const Duration(milliseconds: 180));
    final appraiseSnapMidDistance =
        (tester.getCenter(intent).dx - selectedAppraisePoint.dx).abs();
    expect(appraiseSnapMidDistance, lessThan(appraiseSnapStartDistance - 20));
    expect(appraiseSnapMidDistance, greaterThan(20));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      (tester.getCenter(intent).dx - selectedAppraisePoint.dx).abs(),
      lessThan(2),
    );
    expect(find.text('鉴'), findsWidgets);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('appraise-destination'), findsOneWidget);
    expect(
      hapticCalls.any(
        (call) => call.arguments == 'HapticFeedbackType.lightImpact',
      ),
      isTrue,
    );
  });

  testWidgets('Observe drag appreciate seal starts viewer from target photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _sampleObserveController();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/observe',
      routes: [
        GoRoute(
          path: '/observe',
          builder: (context, state) => ProcessingScreen(
            workspaceController: controller,
            experienceDockVariant: ExperienceDockVariant.intentSeal,
          ),
        ),
        GoRoute(
          path: NoemaRoutes.observeAppreciate,
          builder: (context, state) => Text(
            'appreciate-${state.uri.queryParameters['photoId'] ?? 'none'}',
          ),
        ),
        GoRoute(
          path: '/appraise',
          builder: (context, state) => const Text('appraise-destination'),
        ),
        GoRoute(
          path: '/review-groups',
          builder: (context, state) => const Text('review-groups-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
      ),
    );
    await _pumpObserveUi(tester);

    final intent = find.byKey(const ValueKey('observe-experience-intent'));
    final targetTile = find.byKey(const ValueKey('observe-photo-photo-18'));
    final startIntentCenter = tester.getCenter(intent);
    final targetCenter = tester.getCenter(targetTile);
    final gesture = await tester.startGesture(tester.getCenter(intent));
    await tester.pump();
    await gesture.moveTo(targetCenter);
    await tester.pump();

    expect(tester.getCenter(intent).dy, lessThan(startIntentCenter.dy - 30));
    expect(
      tester.getCenter(intent),
      within<Offset>(distance: 2, from: targetCenter),
    );
    expect(
      find.byKey(const ValueKey('observe-appreciate-target-photo-18')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('appreciate-photo-18'), findsOneWidget);
  });

  testWidgets('Observe drag appreciate cancels after returning to dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _sampleObserveController();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/observe',
      routes: [
        GoRoute(
          path: '/observe',
          builder: (context, state) => ProcessingScreen(
            workspaceController: controller,
            experienceDockVariant: ExperienceDockVariant.intentSeal,
          ),
        ),
        GoRoute(
          path: NoemaRoutes.observeAppreciate,
          builder: (context, state) => Text(
            'appreciate-${state.uri.queryParameters['photoId'] ?? 'none'}',
          ),
        ),
        GoRoute(
          path: '/appraise',
          builder: (context, state) => const Text('appraise-destination'),
        ),
        GoRoute(
          path: '/review-groups',
          builder: (context, state) => const Text('review-groups-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
      ),
    );
    await _pumpObserveUi(tester);

    final intent = find.byKey(const ValueKey('observe-experience-intent'));
    final targetTile = find.byKey(const ValueKey('observe-photo-photo-18'));
    final dockCenter = tester.getCenter(intent);
    final gesture = await tester.startGesture(dockCenter);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(targetTile));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('observe-appreciate-target-photo-18')),
      findsOneWidget,
    );

    await gesture.moveTo(dockCenter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('observe-appreciate-target-photo-18')),
      findsNothing,
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('友人'), findsOneWidget);
    expect(find.text('appreciate-photo-18'), findsNothing);
  });

  testWidgets('Observe drag appreciate hit test uses live scroll offset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _sampleObserveController();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/observe',
      routes: [
        GoRoute(
          path: '/observe',
          builder: (context, state) => ProcessingScreen(
            workspaceController: controller,
            experienceDockVariant: ExperienceDockVariant.intentSeal,
          ),
        ),
        GoRoute(
          path: NoemaRoutes.observeAppreciate,
          builder: (context, state) => Text(
            'appreciate-${state.uri.queryParameters['photoId'] ?? 'none'}',
          ),
        ),
        GoRoute(
          path: '/appraise',
          builder: (context, state) => const Text('appraise-destination'),
        ),
        GoRoute(
          path: '/review-groups',
          builder: (context, state) => const Text('review-groups-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
      ),
    );
    await _pumpObserveUi(tester);

    await tester.drag(
      find.byKey(const ValueKey('observe-photo-wall-scroll')),
      const Offset(0, -80),
    );
    await tester.pump(const Duration(milliseconds: 220));

    final intent = find.byKey(const ValueKey('observe-experience-intent'));
    final targetTile = find.byKey(const ValueKey('observe-photo-photo-4'));
    final gesture = await tester.startGesture(tester.getCenter(intent));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(targetTile));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('observe-appreciate-target-photo-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('observe-appreciate-target-photo-1')),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('appreciate-photo-4'), findsOneWidget);
  });

  testWidgets(
    'Observe side entry drag to photo wall does not start appreciate',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _sampleObserveController();
      late final GoRouter router;
      router = GoRouter(
        initialLocation: '/observe',
        routes: [
          GoRoute(
            path: '/observe',
            builder: (context, state) => ProcessingScreen(
              workspaceController: controller,
              experienceDockVariant: ExperienceDockVariant.intentSeal,
            ),
          ),
          GoRoute(
            path: NoemaRoutes.observeAppreciate,
            builder: (context, state) => Text(
              'appreciate-${state.uri.queryParameters['photoId'] ?? 'none'}',
            ),
          ),
          GoRoute(
            path: '/appraise',
            builder: (context, state) => const Text('appraise-destination'),
          ),
          GoRoute(
            path: '/review-groups',
            builder: (context, state) =>
                const Text('review-groups-destination'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          routerConfig: router,
        ),
      );
      await _pumpObserveUi(tester);

      final appraise = find.byKey(
        const ValueKey('observe-experience-appraise'),
      );
      final targetTile = find.byKey(const ValueKey('observe-photo-photo-1'));
      final gesture = await tester.startGesture(tester.getCenter(appraise));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(targetTile));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('observe-appreciate-target-photo-1')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('友人'), findsOneWidget);
      expect(find.text('appreciate-photo-1'), findsNothing);
      expect(find.text('appraise-destination'), findsNothing);
      expect(find.text('review-groups-destination'), findsNothing);
    },
  );

  testWidgets('Observe intent dock opens appraise from direct tap', (
    tester,
  ) async {
    final controller = _sampleObserveController();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/observe',
      routes: [
        GoRoute(
          path: '/observe',
          builder: (context, state) => ProcessingScreen(
            workspaceController: controller,
            experienceDockVariant: ExperienceDockVariant.intentSeal,
          ),
        ),
        GoRoute(
          path: '/appraise',
          builder: (context, state) => const Text('appraise-destination'),
        ),
        GoRoute(
          path: '/review-groups',
          builder: (context, state) => const Text('review-groups-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
      ),
    );
    await _pumpObserveUi(tester);

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('observe-experience-appraise')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('appraise-destination'), findsOneWidget);
  });

  testWidgets('Observe balanced preview keeps three entries at equal weight', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ObserveTestApp(experienceDockVariant: ExperienceDockVariant.balanced),
    );
    await _pumpObserveUi(tester);

    final cullSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-cull')),
    );
    final viewSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-view')),
    );
    final appraiseSize = tester.getSize(
      find.byKey(const ValueKey('observe-experience-appraise')),
    );

    expect(cullSize, viewSize);
    expect(appraiseSize, viewSize);
  });

  testWidgets('space name can be renamed inline', (tester) async {
    final controller = _sampleObserveController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    await tester.tap(find.byTooltip('修改境名'));
    await _pumpObserveUi(tester);

    expect(find.byKey(const ValueKey('observe-name-field')), findsOneWidget);
    expect(find.text('2/10'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('observe-name-field')),
      '城市散步',
    );
    await tester.pump();
    expect(find.text('4/10'), findsOneWidget);

    await tester.tap(find.byTooltip('保存境名'));
    await _pumpObserveUi(tester);

    expect(controller.workspace.session.name, '城市散步');
    expect(find.text('城市散步'), findsOneWidget);
    expect(find.text('4/10'), findsNothing);
  });

  testWidgets('empty inline rename shows a hint and keeps old name', (
    tester,
  ) async {
    final controller = _sampleObserveController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    await tester.tap(find.byTooltip('修改境名'));
    await _pumpObserveUi(tester);
    await tester.enterText(
      find.byKey(const ValueKey('observe-name-field')),
      '',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('保存境名'));
    await _pumpObserveUi(tester);

    expect(controller.workspace.session.name, '友人');
    expect(find.text('先为境命名'), findsOneWidget);
    expect(find.text('0/10'), findsOneWidget);
  });

  testWidgets('long press selects photos and removes them from observe', (
    tester,
  ) async {
    final controller = _sampleObserveController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    await tester.longPress(
      find.byKey(const ValueKey('observe-photo-photo-18')),
    );
    await _pumpObserveUi(tester);

    expect(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'), findsNothing);
    expect(find.byTooltip('添加照片'), findsNothing);
    expect(find.byTooltip('取消'), findsOneWidget);
    expect(find.byTooltip('移除'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('observe-photo-photo-17')));
    await _pumpObserveUi(tester);
    await tester.tap(find.byTooltip('移除'));
    await _pumpObserveUi(tester);

    expect(find.text('从此境移除'), findsOneWidget);
    expect(find.textContaining('可以只从此境移除'), findsOneWidget);
    expect(find.text('只从此境移除'), findsOneWidget);
    expect(find.text('删除手机相册原图'), findsOneWidget);

    await tester.tap(find.text('只从此境移除'));
    await _pumpObserveUi(tester);

    expect(controller.workspace.assets, hasLength(16));
    expect(find.text('16 张'), findsOneWidget);
    expect(find.byKey(const ValueKey('observe-photo-photo-18')), findsNothing);
    expect(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'), findsOneWidget);
  });

  testWidgets('density button reflows the photo wall', (tester) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final firstPhoto = find.byKey(const ValueKey('observe-photo-photo-18'));
    expect(firstPhoto, findsOneWidget);
    final before = tester.getSize(firstPhoto);
    NoemaRecoverableReviewImage reviewImage() =>
        tester.widget<NoemaRecoverableReviewImage>(
          find
              .descendant(
                of: firstPhoto,
                matching: find.byType(NoemaRecoverableReviewImage),
              )
              .first,
        );

    expect(reviewImage().cacheWidth, 640);
    expect(reviewImage().cacheHeight, 640);

    await tester.tap(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byTooltip('密度 标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('密度 大图墙'), findsOneWidget);
    final after = tester.getSize(firstPhoto);
    expect(after.height, greaterThan(before.height));
    expect(reviewImage().cacheWidth, 640);
    expect(reviewImage().cacheHeight, 640);
  });

  testWidgets('photo wall reflow controls ignore rapid repeat taps', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    await tester.tap(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byTooltip('时间倒序'));
    await tester.pump();
    expect(find.byTooltip('时间正序'), findsOneWidget);

    await tester.tap(find.byTooltip('时间正序'));
    await tester.pump();
    expect(find.byTooltip('时间正序'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byTooltip('时间正序'));
    await tester.pump();
    expect(find.byTooltip('时间倒序'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byTooltip('密度 标准墙'));
    await tester.pump();
    expect(find.byTooltip('密度 大图墙'), findsOneWidget);

    await tester.tap(find.byTooltip('密度 大图墙'));
    await tester.pump();
    expect(find.byTooltip('密度 大图墙'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byTooltip('密度 大图墙'));
    await tester.pump();
    expect(find.byTooltip('密度 紧凑墙'), findsOneWidget);
  });

  testWidgets('Observe remembers sort and wall density after remount', (
    tester,
  ) async {
    final controller = _sampleObserveController();

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    await tester.tap(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byTooltip('时间倒序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('密度 标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.workspace.observeViewPreferences.timeSort, 'oldestFirst');
    expect(controller.workspace.observeViewPreferences.density, 'spacious');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.byTooltip('查看选项：时间正序，全部照片，大图墙'), findsOneWidget);
  });

  testWidgets('photo wall keeps a small paint gutter for tile emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final wallLeft = tester
        .getTopLeft(find.byKey(const ValueKey('observe-photo-wall')))
        .dx;
    final firstPhotoLeft = tester
        .getTopLeft(find.byKey(const ValueKey('observe-photo-photo-18')))
        .dx;

    expect(firstPhotoLeft - wallLeft, greaterThanOrEqualTo(8));
  });

  testWidgets('photo wall uses overlay fades instead of a clipping mask', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(NoemaScrollEdgeFade), findsNWidgets(2));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('observe-photo-wall-scroll')),
    );
    expect(scroll.clipBehavior, Clip.hardEdge);
  });

  testWidgets('photo wall does not tint every tile with saveLayer filters', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('photo wall normal tiles avoid per-tile borders and shadows', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final tileContainers = tester.widgetList<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('observe-photo-photo-18')),
        matching: find.byType(Container),
      ),
    );
    final tileDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('observe-photo-photo-18')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>();

    expect(
      tileContainers.any(
        (container) =>
            (container.foregroundDecoration as BoxDecoration?)?.border != null,
      ),
      isFalse,
    );
    expect(
      tileDecorations.any((decoration) => decoration.boxShadow != null),
      isFalse,
    );
  });

  testWidgets('photo wall hides the glass dock while scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    await tester.drag(
      find.byKey(const ValueKey('observe-photo-wall-scroll')),
      const Offset(0, -260),
    );
    await tester.pump();

    final dockOpacityAncestors = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: find.text('赏'), matching: find.byType(AnimatedOpacity)),
    );
    expect(dockOpacityAncestors.any((widget) => widget.opacity == 0), isTrue);

    await tester.pump(const Duration(milliseconds: 240));
    final restoredOpacityAncestors = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: find.text('赏'), matching: find.byType(AnimatedOpacity)),
    );
    expect(
      restoredOpacityAncestors.any((widget) => widget.opacity == 1),
      isTrue,
    );
  });

  testWidgets('missing asset notice opens once and can clear indexes', (
    tester,
  ) async {
    final controller = _sampleObserveController();
    controller.markAssetMissing('photo-1');

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.text('1 张照片找不到了'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('observe-missing-assets-list')),
        matching: find.text('Sample 01'),
      ),
      findsOneWidget,
    );
    expect(controller.unnotifiedMissingAssetIndexes, isEmpty);

    await tester.tap(find.byTooltip('关闭'));
    await _pumpObserveUi(tester);

    expect(find.text('1 张照片找不到了'), findsNothing);
    expect(find.byTooltip('照片索引提醒'), findsOneWidget);

    await tester.tap(find.byTooltip('照片索引提醒'));
    await _pumpObserveUi(tester);

    expect(find.text('1 张照片找不到了'), findsOneWidget);
    await tester.tap(find.text('清除相关索引'));
    await _pumpObserveUi(tester);

    expect(controller.workspace.assetById('photo-1'), isNull);
    expect(controller.missingAssetIndexes, isEmpty);
    expect(find.byTooltip('照片索引提醒'), findsNothing);
    expect(find.text('17 张'), findsOneWidget);
  });

  testWidgets('photo wall virtualizes large spaces', (tester) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(
      List.generate(
        140,
        (index) =>
            SelectedGalleryAsset(id: 'asset-$index', name: 'IMG_$index.JPG'),
      ),
      name: '远行',
    );

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.text('140 张'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('observe-photo-photo-140')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('observe-photo-photo-1')), findsNothing);

    final builtTiles = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('observe-photo-photo-');
        })
        .evaluate()
        .length;
    expect(builtTiles, lessThan(140));
  });

  testWidgets('observe lazily hydrates Android metadata and thumbnail', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls.add(call);
      if (call.method == 'loadMetadata') {
        return Future<Object?>.value({
          'uri': 'content://media/photo/sample',
          'name': 'sample.jpg',
          'width': 1080,
          'height': 1440,
          'mimeType': 'image/jpeg',
          'fileSize': 3456789,
          'iso': 25,
          'shutterSpeed': '1/2094s',
          'aperture': 1.8,
          'focalLengthMm': 5.4,
        });
      }
      if (call.method == 'createThumbnail') {
        return Future<Object?>.value('/cache/sample-thumb.jpg');
      }
      return Future<Object?>.value(null);
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'content://media/photo/sample',
        name: 'sample.jpg',
        sourceUri: 'content://media/photo/sample',
      ),
    ], name: '日本');
    expect(
      controller.workspace.assets.single.photo.dimensionsEstimated,
      isTrue,
    );

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    final before = tester.getSize(
      find.byKey(const ValueKey('observe-photo-photo-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      calls.map((call) => call.method),
      containsAll(['loadMetadata', 'createThumbnail']),
    );
    expect(calls.where((call) => call.method == 'createPreview'), isEmpty);
    final thumbnailCall = calls.singleWhere(
      (call) => call.method == 'createThumbnail',
    );
    expect(thumbnailCall.arguments['uri'], 'content://media/photo/sample');
    expect(thumbnailCall.arguments['maxSize'], 640);

    final photo = controller.workspace.assets.single.photo;
    expect(photo.width, 1080);
    expect(photo.height, 1440);
    expect(photo.dimensionsEstimated, isFalse);
    expect(photo.thumbnailPath, '/cache/sample-thumb.jpg');
    expect(photo.previewPath, isNull);
    expect(photo.mimeType, 'image/jpeg');
    expect(photo.fileSize, 3456789);
    expect(photo.exif?.iso, 25);
    expect(photo.exif?.shutterSpeed, '1/2094s');

    final after = tester.getSize(
      find.byKey(const ValueKey('observe-photo-photo-1')),
    );
    expect(after.height, greaterThan(before.height));
  });

  testWidgets('time sort toggles between descending and ascending', (
    tester,
  ) async {
    await tester.pumpWidget(_ObserveTestApp());
    await _pumpObserveUi(tester);

    final newestFirst = tester.getTopLeft(
      find.byKey(const ValueKey('observe-photo-photo-18')),
    );

    await tester.tap(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.byTooltip('时间倒序'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('observe-photo-photo-18')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('时间正序'), findsOneWidget);
    final oldestFirst = tester.getTopLeft(
      find.byKey(const ValueKey('observe-photo-photo-18')),
    );
    expect(oldestFirst.dy, greaterThan(newestFirst.dy));
  });

  testWidgets('observe options can sort by score and filter cherished photos', (
    tester,
  ) async {
    final controller = _sampleObserveController();
    controller.setAssetAppraisalScore('photo-1', 88);
    controller.setAssetCherished('photo-2', true);

    await tester.pumpWidget(_ObserveTestApp(controller: controller));
    await _pumpObserveUi(tester);

    expect(find.text('88'), findsOneWidget);

    await tester.tap(find.byTooltip('查看选项：时间倒序，全部照片，标准墙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.byTooltip('评分由高到低'), findsOneWidget);
    expect(find.byTooltip('全部照片'), findsOneWidget);

    await tester.tap(find.byTooltip('评分由高到低'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('observe-photo-photo-1')), findsOneWidget);
    expect(find.text('88'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byTooltip('全部照片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('只看珍藏'), findsOneWidget);
    expect(find.text('1 张'), findsOneWidget);
    expect(find.byKey(const ValueKey('observe-photo-photo-2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('observe-photo-heart-photo-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('observe-photo-photo-1')), findsNothing);
  });
}

Future<void> _pumpObserveUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 620));
}

class _ObserveTestApp extends StatelessWidget {
  _ObserveTestApp({
    ReviewWorkspaceController? controller,
    this.locale = const Locale('zh'),
    this.experienceDockVariant = ExperienceDockVariant.intentSeal,
    this.experienceDockTuning = false,
  }) : controller = controller ?? _sampleObserveController();

  final ReviewWorkspaceController controller;
  final Locale locale;
  final ExperienceDockVariant experienceDockVariant;
  final bool experienceDockTuning;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: ProcessingScreen(
        workspaceController: controller,
        experienceDockVariant: experienceDockVariant,
        experienceDockTuning: experienceDockTuning,
      ),
    );
  }
}

ReviewWorkspaceController _sampleObserveController() {
  final controller = ReviewWorkspaceController();
  final capturedAt = DateTime(2026, 6, 3, 10);
  controller.loadSelectedAssets(
    List.generate(
      18,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
        width: 4032,
        height: 3024,
        createdAt: index == 1
            ? capturedAt.add(const Duration(seconds: 2))
            : capturedAt.add(Duration(minutes: index)),
      ),
    ),
    name: '友人',
  );
  return controller;
}
