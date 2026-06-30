import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appreciate/appreciate_viewer_page.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';
import 'package:noema/features/processing/photo_viewer_page.dart';

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('viewer shows the single bottom control layer and panels', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(controller: _controller()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('赏'), findsNothing);
    expect(
      find.byKey(const ValueKey('appreciate-page-indicator')),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('顺序'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    expect(find.text('竖屏'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('10s')).style?.fontFamily,
      noemaCjkFontFamily,
    );

    await tester.tap(find.text('全部'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('微瑕'), findsOneWidget);
    expect(find.text('成片'), findsOneWidget);
    expect(find.text('佳作'), findsOneWidget);
    expect(find.text('珍藏'), findsOneWidget);

    await tester.tap(find.text('10s'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('5s - 30s'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appreciate-interval-slider')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('5s - 30s')).style?.fontFamily,
      noemaCjkFontFamily,
    );
  });

  testWidgets('viewer interval slider updates playback seconds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_TestApp(controller: _controller()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    await tester.tap(find.text('10s'));
    await tester.pump(const Duration(milliseconds: 220));

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('appreciate-interval-slider')),
    );
    expect(slider.min, 5);
    expect(slider.max, 30);
    expect(slider.divisions, 25);
    expect(slider.value, 10);
    expect(slider.label, isNull);
    final panelRect = tester.getRect(
      find.byKey(const ValueKey('appreciate-interval-panel')),
    );
    expect(panelRect.left, greaterThanOrEqualTo(0));
    expect(panelRect.right, lessThanOrEqualTo(390));
    expect(panelRect.height, lessThan(96));

    slider.onChanged?.call(18);
    await tester.pump();

    expect(find.text('18s'), findsWidgets);
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('appreciate-interval-slider')),
          )
          .value,
      18,
    );
  });

  testWidgets(
    'viewer restores persisted appreciate preferences after remount',
    (tester) async {
      final controller = _controller();
      controller.setAppreciateViewPreferences(
        const AppreciateViewPreferences(
          rangeMask: 0x08,
          order: 'shuffle',
          intervalSeconds: 18,
        ),
      );

      await tester.pumpWidget(_TestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('珍藏'), findsOneWidget);
      expect(find.text('随机'), findsOneWidget);
      expect(find.text('18s'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_TestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('珍藏'), findsOneWidget);
      expect(find.text('随机'), findsOneWidget);
      expect(find.text('18s'), findsOneWidget);
    },
  );

  testWidgets('viewer falls back when persisted ranges have no photos', (
    tester,
  ) async {
    final controller = _controller(count: 3);
    controller.setAppreciateViewPreferences(
      const AppreciateViewPreferences(
        rangeMask: 0x08,
        order: 'shuffle',
        intervalSeconds: 44,
      ),
    );

    await tester.pumpWidget(_TestApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('随机'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(
      controller.workspace.appreciateViewPreferences.rangeMask,
      AppreciateViewPreferences.allRangeMask,
    );
    expect(controller.workspace.appreciateViewPreferences.intervalSeconds, 30);
  });

  testWidgets('viewer uses dissolve photo transitions', (tester) async {
    await tester.pumpWidget(_TestApp(controller: _controller()));
    await tester.pump();

    final viewer = tester.widget<PhotoViewerPage>(find.byType(PhotoViewerPage));
    expect(
      viewer.pageVisualTransition,
      PhotoViewerPageVisualTransition.dissolve,
    );
    expect(viewer.pageTransitionDuration, const Duration(milliseconds: 1250));
  });

  testWidgets(
    'hidden chrome disables controls until the next tap restores UI',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_TestApp(controller: _controller()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      await tester.tapAt(const Offset(195, 360));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('播放').hitTestable(), findsNothing);

      await tester.tapAt(const Offset(195, 360));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('播放').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('idle timeout and playback enter immersive hidden chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_TestApp(controller: _controller()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('播放').hitTestable(), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('播放').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(195, 360));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('暂停').hitTestable(), findsOneWidget);

    await tester.tap(find.text('暂停'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('播放').hitTestable(), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tapAt(const Offset(195, 360));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('播放').hitTestable(), findsOneWidget);
  });

  testWidgets('single-photo playlist disables autoplay', (tester) async {
    await tester.pumpWidget(_TestApp(controller: _controller(count: 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    final playButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '播放'),
    );
    expect(playButton.onPressed, isNull);
  });

  testWidgets(
    'orientation button displays current state and toggles orientation',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });

      await tester.pumpWidget(_TestApp(controller: _controller()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(
        calls.where(
          (call) => call.method == 'SystemChrome.setPreferredOrientations',
        ),
        isNotEmpty,
      );

      expect(find.text('竖屏'), findsOneWidget);

      await tester.tap(find.text('竖屏'));
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        calls.any(
          (call) =>
              call.method == 'SystemChrome.setPreferredOrientations' &&
              (call.arguments as List<Object?>).contains(
                'DeviceOrientation.landscapeLeft',
              ),
        ),
        isTrue,
      );
      expect(find.text('横屏'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        calls
            .lastWhere(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .arguments,
        contains('DeviceOrientation.portraitUp'),
      );
    },
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.controller});

  final ReviewWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: AppreciateViewerPage(
        workspaceController: controller,
        appearanceController: NoemaAppearanceController(),
      ),
    );
  }
}

ReviewWorkspaceController _controller({int count = 4}) {
  final controller = ReviewWorkspaceController();
  final now = DateTime(2026, 6, 29, 12);
  final assets = [
    for (var index = 0; index < count; index += 1)
      SelectedGalleryAsset(
        id: 'asset-$index',
        name: 'Asset $index',
        previewBytes: _tinyPngBytes,
        analysisBytes: _tinyPngBytes,
        width: index.isEven ? 1200 : 800,
        height: index.isEven ? 800 : 1200,
        createdAt: now.add(Duration(minutes: index)),
        mimeType: 'image/png',
      ),
  ];
  controller.loadSelectedAssets(assets, name: '赏测试');
  for (final asset in controller.workspace.assets) {
    switch (asset.photo.platformAssetId) {
      case 'asset-0':
        controller.setAssetAppraisalScore(asset.photo.id, 86);
      case 'asset-1':
        controller.setAssetAppraisalScore(asset.photo.id, 72);
      case 'asset-2':
        controller.setAssetAppraisalScore(asset.photo.id, 42);
      case 'asset-3':
        controller.setAssetAppraisalScore(asset.photo.id, 91);
        controller.setAssetCherished(asset.photo.id, true);
    }
  }
  return controller;
}

final Uint8List _tinyPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR4nGP4TyFgGDVg1IBRA4aLAQBdePwur/3haQAAAABJRU5ErkJggg==',
  ),
);
