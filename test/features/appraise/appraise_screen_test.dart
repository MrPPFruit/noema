import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/series_appraisal.dart';
import 'package:noema/core/theme/noema_theme.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appraise/appraise_ai_client.dart';
import 'package:noema/features/appraise/appraise_ai_settings_store.dart';
import 'package:noema/features/appraise/appraise_ai_transport.dart';
import 'package:noema/features/appraise/appraise_screen.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Appraise workbench renders lanes, sort, and appraisal sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _sampleWorkspaceController();

    await tester.pumpWidget(_AppraiseTestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Noema'), findsOneWidget);
    expect(find.text('鉴'), findsOneWidget);
    expect(find.text('微瑕'), findsOneWidget);
    expect(find.text('成片'), findsWidgets);
    expect(find.byTooltip('AI 设置'), findsOneWidget);
    expect(find.byTooltip('评分由高到低'), findsNothing);
    expect(find.byKey(const ValueKey('appraise-photo-wall')), findsOneWidget);

    await tester.tap(find.byTooltip('AI 设置'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-ai-settings-page')),
      findsOneWidget,
    );
    expect(find.text('赋'), findsOneWidget);
    expect(find.text('千问（推荐）'), findsOneWidget);
    expect(find.text('qwen3.7-plus'), findsWidgets);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-ai-settings-page')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('appraise-photo-heart-photo-24')),
    );
    await tester.pumpAndSettle();
    expect(find.text('珍藏'), findsWidgets);
    expect(controller.workspace.assetById('photo-24')?.photo.isCherished, true);

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    expect(visiblePhoto, findsWidgets);

    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}')),
      findsOneWidget,
    );
    expect(find.text('清晰度'), findsOneWidget);
    expect(find.text('曝光'), findsOneWidget);
    expect(_svgIconFinder('clarity-sparkles'), findsOneWidget);
    expect(_svgIconFinder('exposure-sun'), findsOneWidget);
    expect(_svgIconFinder('section-diamond'), findsNothing);
    expect(_svgIconFinder('theme-target'), findsNothing);
    expect(_svgIconFinder('tech-aperture'), findsNothing);
    expect(_svgIconFinder('emotion-heart-circle'), findsNothing);
    expect(_svgIconFinder('imagination-ring'), findsNothing);
    expect(find.text('尺寸'), findsNothing);
    expect(find.text('画幅'), findsNothing);
    expect(find.text('初见'), findsNothing);
    expect(find.text('四维'), findsNothing);
    expect(find.text('本机评分'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI 品鉴尚未生成。当前只显示本机初筛信号，不展示临时示例文案。'), findsNothing);
    expect(find.text('启用 AI 品鉴'), findsOneWidget);
    expect(find.text('总观'), findsNothing);
    expect(find.text('打磨'), findsNothing);
    expect(find.text('自问'), findsNothing);

    await tester.tap(find.text('启用 AI 品鉴').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-ai-config-prompt')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('appraise-ai-settings-page')),
      findsNothing,
    );
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
    await tester.tap(find.text('去配置'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-ai-settings-page')),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    await _enterApiKeyAndRunCheck(tester, 'sk-test');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-ai-settings-page')),
      findsNothing,
    );
    expect(find.text('AI 品鉴'), findsOneWidget);
    expect(find.text('启用 AI 品鉴'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('Appraise local basis does not use dimensions as camera params', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(withDimensions: true),
      ),
    );
    await tester.pumpAndSettle();

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('清晰度'), findsOneWidget);
    expect(find.text('曝光'), findsOneWidget);
    expect(find.text('尺寸'), findsNothing);
    expect(find.text('4032×3024'), findsNothing);
  });

  testWidgets('Appraise local basis shows camera params only from EXIF', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(
          withDimensions: true,
          exif: const PhotoExif(
            iso: 100,
            shutterSpeed: '1/500s',
            aperture: 5.6,
            focalLengthMm: 24,
            whiteBalance: 'WB 5600K',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('参数'), findsNothing);
    expect(_svgIconFinder('camera-params'), findsOneWidget);
    expect(find.textContaining('ISO 100'), findsOneWidget);
    expect(find.textContaining('1/500s'), findsOneWidget);
    expect(find.textContaining('f/5.6'), findsOneWidget);
    expect(find.textContaining('24mm'), findsOneWidget);
    expect(find.textContaining('WB 5600K'), findsOneWidget);
    expect(find.text('尺寸'), findsNothing);
  });

  testWidgets('Appraise hydrates missing EXIF for previously imported photos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls.add(call);
      if (call.method == 'loadMetadata') {
        return Future<Object?>.value({
          'uri': 'content://media/photo/old',
          'name': 'old.jpg',
          'width': 4000,
          'height': 3000,
          'iso': 25,
          'shutterSpeed': '1/2094s',
          'aperture': 1.8,
          'focalLengthMm': 5.4,
          'whiteBalance': 'WB 自动',
        });
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
        id: 'content://media/photo/old',
        name: 'old.jpg',
        sourceUri: 'content://media/photo/old',
        width: 4000,
        height: 3000,
      ),
    ]);
    expect(controller.workspace.assets.single.photo.exif, isNull);

    await tester.pumpWidget(_AppraiseTestApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final loadCalls = calls
        .where((call) => call.method == 'loadMetadata')
        .toList(growable: false);
    expect(loadCalls, isNotEmpty);
    expect(loadCalls.first.arguments['uri'], 'content://media/photo/old');
    expect(controller.workspace.assets.single.photo.exif?.iso, 25);

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    await tester.tap(visiblePhoto.first);
    await tester.pumpAndSettle();

    expect(_svgIconFinder('camera-params'), findsOneWidget);
    expect(find.textContaining('ISO 25'), findsOneWidget);
    expect(find.textContaining('1/2094s'), findsOneWidget);
    expect(find.textContaining('f/1.8'), findsOneWidget);
  });

  testWidgets('Appraise viewer keeps photo paging available above the sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(controller: _sampleWorkspaceController()),
    );
    await tester.pumpAndSettle();

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    expect(visiblePhoto, findsWidgets);

    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    expect(find.byType(PageView), findsOneWidget);
    expect(_viewerIndexFinder('1/'), findsOneWidget);

    await tester.dragFrom(const Offset(330, 170), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(_viewerIndexFinder('2/'), findsOneWidget);
  });

  testWidgets('Appraise viewer preserves the original photo aspect ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(withDimensions: true),
      ),
    );
    await tester.pumpAndSettle();

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pumpAndSettle();

    final fittedSize = tester.getSize(
      find.byKey(const ValueKey('photo-viewer-fitted-image')),
    );
    expect(fittedSize.width / fittedSize.height, closeTo(4032 / 3024, 0.01));
  });

  testWidgets('Appraise opens the initial photo from route state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(),
        initialPhotoId: 'photo-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appraise-viewer-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('Appraise viewer sheet snaps to appraisal, peek, and hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(controller: _sampleWorkspaceController()),
    );
    await tester.pumpAndSettle();

    final visiblePhoto = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('appraise-photo-photo-');
    });
    await tester.tap(visiblePhoto.first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('appraise-viewer-sheet'));
    final viewportHeight = tester.view.physicalSize.height;

    final expandedRect = tester.getRect(sheet);
    expect(expandedRect.height, closeTo(viewportHeight * 0.75, 4));
    expect(
      find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
      findsOneWidget,
    );
    final handle = find.byKey(const ValueKey('appraise-viewer-sheet-handle'));
    final heart = find.byKey(const ValueKey('appraise-viewer-sheet-heart'));
    expect(tester.getSize(heart), const Size(34, 34));
    final chromeFade = find.byKey(
      const ValueKey('appraise-viewer-sheet-chrome-fade'),
    );
    final handleTopBeforeScroll = tester.getTopLeft(handle).dy;
    final fadeTopBeforeScroll = tester.getTopLeft(chromeFade).dy;
    final bodyMouseDrag = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await bodyMouseDrag.down(
      Offset(expandedRect.center.dx, expandedRect.top + 132),
    );
    await tester.pump();
    await bodyMouseDrag.moveBy(const Offset(0, 260));
    await tester.pump();
    await bodyMouseDrag.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).height, closeTo(expandedRect.height, 4));

    await tester.drag(
      find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(handle).dy, closeTo(handleTopBeforeScroll, 1));
    expect(tester.getTopLeft(chromeFade).dy, closeTo(fadeTopBeforeScroll, 1));

    final mouseDrag = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouseDrag.down(Offset(expandedRect.center.dx, expandedRect.top + 36));
    await tester.pump();
    await mouseDrag.moveBy(const Offset(0, 360));
    await tester.pump();
    await mouseDrag.up();
    await tester.pumpAndSettle();
    final peekRect = tester.getRect(sheet);
    expect(peekRect.height, closeTo(viewportHeight * 0.25, 8));

    await tester.dragFrom(
      Offset(peekRect.center.dx, peekRect.top + 36),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).height, closeTo(viewportHeight * 0.10, 8));
    expect(
      find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Appraise toolbar AI appraises instead of reopening settings when ready',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _AppraiseTestApp(
          controller: _sampleWorkspaceController(),
          aiClient: _okAiClient(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appraise-ai-config-prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsNothing,
      );
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(find.text('去配置'), findsOneWidget);
      await tester.tap(find.text('去配置'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsOneWidget,
      );

      await _enterApiKeyAndRunCheck(tester, 'sk-test');
      expect(find.text('测试通过'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsNothing,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Appraise toolbar shows reviewed and total AI counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AppraiseTestApp(controller: _sampleWorkspaceController(count: 5)),
    );
    await tester.pumpAndSettle();

    expect(find.text('0/4'), findsOneWidget);
  });

  testWidgets('Appraise score sort appears after current lane has AI score', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Completer<AppraiseAiHttpResponse>>[];
    final controller = _sampleWorkspaceController(
      count: 1,
      withPreviewBytes: true,
      analysisBytes: _checkerPngBytes,
    );

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: controller,
        aiClient: _controlledAiClient(requests),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('评分由高到低'), findsNothing);

    await _enableAi(tester);
    await tester.tap(find.byTooltip('AI 品鉴'));
    await tester.pump();
    expect(requests.length, 1);

    requests.single.complete(_appraiseResponse());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byTooltip('评分由高到低'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(controller.workspace.assetById('photo-1')?.photo.appraisalScore, 72);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_AppraiseTestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
  });

  testWidgets('Appraise wall recovers thumbnail without promoting preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls.add(call);
      if (call.method == 'createThumbnail') {
        return Future<Object?>.value('/files/noema_media/thumbs/photo-1.jpg');
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
        id: 'content://media/photo/1',
        name: 'photo-1.jpg',
        sourceUri: 'content://media/photo/1',
        width: 4032,
        height: 3024,
      ),
    ], name: '友人');
    controller.updateAssetPreviewPath(
      'photo-1',
      '/files/noema_media/previews/photo-1.jpg',
    );

    await tester.pumpWidget(_AppraiseTestApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final thumbnailCalls = calls
        .where((call) => call.method == 'createThumbnail')
        .toList(growable: false);
    expect(thumbnailCalls, hasLength(1));
    expect(thumbnailCalls.single.arguments['uri'], 'content://media/photo/1');
    expect(thumbnailCalls.single.arguments['maxSize'], 640);
    expect(calls.where((call) => call.method == 'createPreview'), isEmpty);
    expect(
      controller.workspace.assetById('photo-1')?.photo.thumbnailPath,
      '/files/noema_media/thumbs/photo-1.jpg',
    );
    expect(
      controller.workspace.assetById('photo-1')?.photo.previewPath,
      '/files/noema_media/previews/photo-1.jpg',
    );
  });

  testWidgets('Appraise series appraisal runs through mocked real UI flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Completer<AppraiseAiHttpResponse>>[];
    final controller = _sampleWorkspaceController(
      count: 3,
      withPreviewBytes: true,
      analysisBytes: _checkerPngBytes,
    );

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: controller,
        aiClient: _controlledAiClient(requests),
      ),
    );
    await tester.pumpAndSettle();
    await _enableAi(tester);

    expect(find.byTooltip('系列品鉴'), findsOneWidget);
    await tester.tap(find.byTooltip('系列品鉴'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appraise-series-confirm-prompt')),
      findsOneWidget,
    );
    expect(find.text('先品鉴单张'), findsOneWidget);
    expect(find.text('仍生成系列'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(requests, isEmpty);
    final runSinglesRect = tester.getRect(find.text('先品鉴单张'));
    final runSeriesRect = tester.getRect(find.text('仍生成系列'));
    expect(runSinglesRect.right, lessThan(runSeriesRect.left));
    expect(runSinglesRect.center.dy, closeTo(runSeriesRect.center.dy, 1));

    await tester.tap(find.text('仍生成系列'));
    await tester.pump();
    expect(requests.length, 1);
    requests.single.complete(_seriesAppraiseResponse());
    await tester.pump();
    await tester.pumpAndSettle();

    final appraisal = controller.workspace.seriesAppraisalFor(
      SeriesAppraisalBand.formed,
    );
    expect(appraisal?.result.title, '春日回声');
    expect(appraisal?.photoIds, ['photo-3', 'photo-2', 'photo-1']);
    expect(
      find.byKey(const ValueKey('appraise-series-sheet-scroll')),
      findsOneWidget,
    );
    expect(find.text('春日回声'), findsOneWidget);
    expect(
      _textInsideKey(tester, const ValueKey('appraise-sheet-meta-time')),
      matches(RegExp(r'\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}')),
    );
    expect(
      _textInsideKey(tester, const ValueKey('appraise-sheet-meta-time')),
      isNot(contains('...')),
    );
    expect(
      _textInsideKey(tester, const ValueKey('appraise-sheet-meta-detail')),
      '成片   3 张',
    );
    expect(find.text('主题线'), findsOneWidget);
    expect(find.text('组内关系'), findsOneWidget);
    expect(find.textContaining('照片3 与 照片1'), findsOneWidget);
    expect(find.textContaining('照片3'), findsWidgets);
    expect(find.textContaining('照片2'), findsWidgets);
    expect(find.textContaining('Photo-2'), findsNothing);
    expect(find.textContaining('photo-1'), findsNothing);
    final overallText = _textWidgetContaining(tester, '照片3 与 照片1');
    expect(_spanHasHighlightedRef(overallText.textSpan!, '照片3'), isTrue);
    expect(_spanHasHighlightedRef(overallText.textSpan!, '照片1'), isTrue);
    expect(
      find.byKey(const ValueKey('appraise-series-thumbnail-photo-1')),
      findsNWidgets(3),
    );
    final relationshipBlock = find.byKey(
      const ValueKey('appraise-series-relationship-0'),
    );
    final relationshipPhotoFinder = find.descendant(
      of: relationshipBlock,
      matching: find.byKey(const ValueKey('appraise-series-thumbnail-photo-1')),
    );
    expect(relationshipPhotoFinder, findsOneWidget);
    final relationshipTitleRect = tester.getRect(find.text('呼应'));
    final relationshipPhotoRect = tester.getRect(relationshipPhotoFinder);
    expect(
      relationshipPhotoRect.top,
      greaterThan(relationshipTitleRect.bottom),
    );

    await tester.drag(
      find.byKey(const ValueKey('appraise-series-sheet-handle')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsNothing);
    expect(find.byTooltip('查看系列品鉴'), findsOneWidget);

    controller.setAssetAppraisal('photo-1', _finePhotoAppraisal());
    await tester.pumpAndSettle();
    expect(find.byTooltip('重新生成系列品鉴'), findsOneWidget);

    await tester.tap(find.byTooltip('重新生成系列品鉴'));
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appraise-series-update')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('appraise-series-thumbnail-photo-1')),
      findsNWidgets(3),
    );
    expect(requests.length, 1);

    await tester.drag(
      find.byKey(const ValueKey('appraise-series-sheet-handle')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsNothing);

    controller.setAssetAppraisal('photo-2', _finePhotoAppraisal());
    await tester.pumpAndSettle();
    expect(find.byTooltip('查看系列品鉴'), findsOneWidget);
    expect(find.byTooltip('重新生成系列品鉴'), findsNothing);

    await tester.tap(find.byTooltip('查看系列品鉴'));
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsOneWidget);
    expect(find.byKey(const ValueKey('appraise-series-update')), findsNothing);
    expect(
      find.byKey(const ValueKey('appraise-series-regenerate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('appraise-series-thumbnail-photo-1')),
      findsNWidgets(3),
    );
    expect(
      find.byKey(const ValueKey('appraise-series-thumbnail-photo-2')),
      findsNWidgets(3),
    );
    expect(requests.length, 1);

    await tester.drag(
      find.byKey(const ValueKey('appraise-series-sheet-handle')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsNothing);

    controller.appendSelectedAssets([
      SelectedGalleryAsset(
        id: 'late-photo',
        name: 'Late photo',
        previewBytes: _tinyPngBytes,
        analysisBytes: _checkerPngBytes,
        mimeType: 'image/png',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byTooltip('重新生成系列品鉴'), findsOneWidget);

    await tester.tap(find.byTooltip('重新生成系列品鉴'));
    await tester.pumpAndSettle();
    expect(find.text('春日回声'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appraise-series-update')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('appraise-series-thumbnail-late-photo')),
      findsNothing,
    );
    expect(requests.length, 1);
    await tester.tap(find.byKey(const ValueKey('appraise-series-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仍生成系列'));
    await tester.pump();
    expect(requests.length, 2);
    requests.last.complete(_seriesAppraiseResponse());
    await tester.pump();
    await tester.pumpAndSettle();
  });

  testWidgets('Appraise series prompt can run single appraisals first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Completer<AppraiseAiHttpResponse>>[];
    final controller = _sampleWorkspaceController(
      count: 3,
      withPreviewBytes: true,
      analysisBytes: _checkerPngBytes,
    );

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: controller,
        aiClient: _controlledAiClient(requests),
      ),
    );
    await tester.pumpAndSettle();
    await _enableAi(tester);

    await tester.tap(find.byTooltip('系列品鉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('先品鉴单张'));
    await tester.pump();

    expect(requests.length, 3);
    expect(
      controller.workspace.seriesAppraisalFor(SeriesAppraisalBand.formed),
      isNull,
    );

    for (final request in requests) {
      request.complete(_appraiseResponse());
    }
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('AI 品鉴完成'), findsOneWidget);
    expect(
      controller.workspace.seriesAppraisalFor(SeriesAppraisalBand.formed),
      isNull,
    );
  });

  testWidgets('AI appraisal promotes strong finished photos into fine lane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Completer<AppraiseAiHttpResponse>>[];

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(
          count: 1,
          withPreviewBytes: true,
          analysisBytes: _checkerPngBytes,
        ),
        aiClient: _controlledAiClient(requests),
      ),
    );
    await tester.pumpAndSettle();
    await _enableAi(tester);

    await tester.tap(find.byTooltip('AI 品鉴'));
    await tester.pump();
    expect(requests.length, 1);

    requests.single.complete(
      _appraiseResponse(theme: 21, technique: 20, emotion: 20, association: 20),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('佳作'), findsOneWidget);
  });

  testWidgets(
    'Appraise metric rows keep body text out of the old icon column',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Completer<AppraiseAiHttpResponse>>[];
      final controller = _sampleWorkspaceController(
        count: 1,
        withPreviewBytes: true,
        analysisBytes: _checkerPngBytes,
      );

      await tester.pumpWidget(
        _AppraiseTestApp(
          controller: controller,
          aiClient: _controlledAiClient(requests),
        ),
      );
      await tester.pumpAndSettle();
      await _enableAi(tester);

      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pump();
      requests.single.complete(_appraiseResponse());
      await tester.pump();
      await tester.pumpAndSettle();

      final visiblePhoto = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('appraise-photo-photo-');
      });
      await tester.tap(visiblePhoto.first);
      await tester.pump();
      await tester.pumpAndSettle();

      final body = find.byKey(const ValueKey('appraise-metric-body-主题'));
      await tester.scrollUntilVisible(
        body,
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('appraise-viewer-sheet-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      final iconRect = tester.getRect(
        find.byKey(const ValueKey('appraise-metric-icon-主题')),
      );
      final labelRect = tester.getRect(
        find.byKey(const ValueKey('appraise-metric-label-主题')),
      );
      final bodyRect = tester.getRect(body);
      expect((iconRect.center.dy - labelRect.center.dy).abs(), lessThan(4));
      expect(bodyRect.left, lessThan(iconRect.right));
    },
  );

  testWidgets('AI score controls lane even when local gate hard-fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Completer<AppraiseAiHttpResponse>>[];
    final controller = _sampleWorkspaceController(
      count: 1,
      withPreviewBytes: true,
      analysisBytes: _blackPngBytes,
    );

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: controller,
        aiClient: _controlledAiClient(requests),
      ),
    );
    await tester.pumpAndSettle();
    await _enableAi(tester);
    await tester.tap(find.text('微瑕').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('AI 品鉴'));
    await tester.pump();
    expect(requests.length, 1);

    requests.single.complete(
      _appraiseResponse(theme: 21, technique: 16, emotion: 23, association: 21),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.workspace.assetById('photo-1')?.photo.appraisalScore, 81);
    expect(find.text('佳作'), findsOneWidget);

    await tester.tap(find.text('佳作').first);
    await tester.pumpAndSettle();
    expect(find.text('81'), findsOneWidget);
  });

  testWidgets('Qwen recommendation shows Bailian guide before opening browser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final openedUrls = <String>[];
    const channel = MethodChannel('noema/external_links');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openUrl');
          final args = Map<String, Object?>.from(call.arguments as Map);
          openedUrls.add(args['url']! as String);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      _AppraiseTestApp(controller: _sampleWorkspaceController()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('AI 设置'));
    await tester.pumpAndSettle();

    expect(find.text('千问（推荐）'), findsOneWidget);
    expect(find.text('千问可通过阿里云百炼平台接入，新用户拥有免费额度。'), findsOneWidget);
    expect(find.text('查看获取 API Key 的方式'), findsOneWidget);

    await tester.tap(find.text('查看获取 API Key 的方式'));
    await tester.pumpAndSettle();

    expect(find.text('阿里云百炼配置指引'), findsOneWidget);
    expect(find.text('API Key 说明'), findsOneWidget);
    expect(find.text('接口兼容说明'), findsOneWidget);

    await tester.tap(find.text('API Key 说明'));
    await tester.pump();
    expect(
      openedUrls.single,
      'https://help.aliyun.com/zh/model-studio/get-api-key',
    );

    await tester.tap(find.text('接口兼容说明'));
    await tester.pump();
    expect(
      openedUrls.last,
      'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope',
    );

    await tester.tap(find.text('打开百炼控制台'));
    await tester.pumpAndSettle();

    expect(openedUrls.last, 'https://bailian.console.aliyun.com/');
    expect(find.text('阿里云百炼配置指引'), findsNothing);
  });

  testWidgets(
    'AI settings test enables and saves only the tested provider key',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _AppraiseTestApp(
          controller: _sampleWorkspaceController(),
          aiClient: _okAiClient(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('AI 设置'));
      await tester.pumpAndSettle();

      await _enterApiKeyAndRunCheck(tester, 'sk-qwen');
      expect(find.text('测试通过'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('appraise-ai-settings-page')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('AI 设置'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        _apiKeyFieldFinder(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已填写，可重新输入'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('千问（推荐）').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        _apiKeyFieldFinder(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已填写，可重新输入'), findsOneWidget);
    },
  );

  testWidgets('AI settings panel follows restored current provider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final restore = Completer<AppraiseAiSettingsLibrary>();
    final store = _DelayedAiSettingsStore(restore);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(),
        aiSettingsStore: store,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('AI 设置'));
    await tester.pumpAndSettle();
    expect(find.text('千问（推荐）'), findsOneWidget);

    final openAiSettings = AppraiseAiSettings.forProvider(
      'openai',
    ).copyWith(enabled: true, apiKey: 'sk-openai');
    restore.complete(
      AppraiseAiSettingsLibrary(
        activeProvider: 'openai',
        providers: {
          AppraiseAiSettings.defaults().provider: AppraiseAiSettings.defaults(),
          openAiSettings.provider: openAiSettings,
        },
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('gpt-4.1-mini'), findsWidgets);
    await tester.scrollUntilVisible(
      _apiKeyFieldFinder(),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('已填写，可重新输入'), findsOneWidget);
  });

  testWidgets('AI settings stays legible in light scene under dark app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearanceController = NoemaAppearanceController(
      initialToneMode: NoemaToneMode.light,
    );
    addTearDown(appearanceController.dispose);

    await tester.pumpWidget(
      _AppraiseTestApp(
        controller: _sampleWorkspaceController(),
        appearanceController: appearanceController,
        theme: NoemaTheme.dark(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('AI 设置'));
    await tester.pumpAndSettle();

    final dropdownTheme = Theme.of(
      tester.element(find.byType(DropdownButtonFormField<String>)),
    );
    expect(dropdownTheme.canvasColor.computeLuminance(), greaterThan(0.80));
    expect(
      dropdownTheme.colorScheme.onSurface.computeLuminance(),
      lessThan(0.08),
    );

    final editableTexts = tester.widgetList<EditableText>(
      find.byType(EditableText),
    );
    expect(
      editableTexts.every((field) {
        final color = field.style.color;
        return color != null && color.computeLuminance() < 0.08;
      }),
      isTrue,
    );

    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    final chipColor = chip.color;
    expect(
      chipColor?.resolve(<WidgetState>{})?.computeLuminance(),
      greaterThan(0.80),
    );
    expect(
      chipColor?.resolve(<WidgetState>{
        WidgetState.selected,
      })?.computeLuminance(),
      greaterThan(0.70),
    );
  });

  testWidgets(
    'AI batch ramps from three requests and stop resets immediately',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Completer<AppraiseAiHttpResponse>>[];

      await tester.pumpWidget(
        _AppraiseTestApp(
          controller: _sampleWorkspaceController(
            count: 14,
            withPreviewBytes: true,
          ),
          aiClient: _controlledAiClient(requests),
        ),
      );
      await tester.pumpAndSettle();
      await _enableAi(tester);
      await tester.tap(find.text('微瑕').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pump();
      expect(requests.length, 3);
      expect(find.byTooltip('停止 AI 品鉴'), findsOneWidget);

      for (final request in requests.take(3)) {
        request.complete(_appraiseResponse());
      }
      await tester.pump();
      await tester.pump();
      expect(requests.length, 6);

      for (final request in requests.skip(3).take(3)) {
        request.complete(_appraiseResponse());
      }
      await tester.pump();
      await tester.pump();
      expect(requests.length, 10);

      await tester.tap(find.byTooltip('停止 AI 品鉴'));
      await tester.pump();
      expect(find.byTooltip('AI 品鉴'), findsOneWidget);
      expect(find.byTooltip('停止 AI 品鉴'), findsNothing);

      await tester.tap(find.byTooltip('AI 品鉴'));
      await tester.pump();
      expect(requests.length, 10);
      expect(find.byTooltip('AI 品鉴'), findsOneWidget);

      for (final request in requests.skip(6).take(4).toList()) {
        request.complete(_appraiseResponse());
      }
      await tester.pump();
      await tester.pump();
      expect(requests.length, 13);

      for (final request in requests.skip(10).toList()) {
        request.complete(_appraiseResponse());
      }
      await tester.pump();
      await tester.pump();
      expect(requests.length, 14);

      requests.last.complete(_appraiseResponse());
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets('Appraise empty state stays calm without fake photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      _AppraiseTestApp(controller: ReviewWorkspaceController()),
    );
    await tester.pumpAndSettle();

    expect(find.text('此境还没有可鉴的照片'), findsOneWidget);
    expect(find.byKey(const ValueKey('appraise-photo-wall')), findsNothing);
  });

  testWidgets('Appraise ignores unavailable imported assets', (tester) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'broken',
        name: 'broken.jpg',
        previewUnavailable: true,
      ),
    ], name: '异常导入');

    await tester.pumpWidget(_AppraiseTestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('此境还没有可鉴的照片'), findsOneWidget);
    expect(find.byKey(const ValueKey('appraise-photo-wall')), findsNothing);
  });
}

Finder _viewerIndexFinder(String prefix) {
  return find.byWidgetPredicate((widget) {
    return widget is Text && widget.data?.startsWith(prefix) == true;
  });
}

String _textInsideKey(WidgetTester tester, ValueKey<String> key) {
  final text = tester.widget<Text>(
    find.descendant(of: find.byKey(key), matching: find.byType(Text)),
  );
  return _textContent(text);
}

Text _textWidgetContaining(WidgetTester tester, String value) {
  return tester.widgetList<Text>(find.byType(Text)).firstWhere((widget) {
    return _textContent(widget).contains(value);
  });
}

String _textContent(Text text) {
  return text.data ?? text.textSpan?.toPlainText() ?? '';
}

bool _spanHasHighlightedRef(InlineSpan span, String ref) {
  if (span is! TextSpan) {
    return false;
  }
  if (span.text == ref &&
      span.style?.fontWeight == FontWeight.w600 &&
      span.style?.backgroundColor == null) {
    return true;
  }
  return span.children?.any((child) => _spanHasHighlightedRef(child, ref)) ??
      false;
}

Finder _svgIconFinder(String name) {
  return find.byKey(
    ValueKey('appraise-svg-assets/icons/svg/currentColor/$name.svg'),
  );
}

Finder _apiKeyFieldFinder() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('appraise-ai-api-key-field-');
  });
}

AppraiseAiClient _okAiClient() {
  return AppraiseAiClient(
    postJson: (uri, {required headers, required body}) async {
      return const AppraiseAiHttpResponse(statusCode: 200, body: {});
    },
  );
}

AppraiseAiClient _controlledAiClient(
  List<Completer<AppraiseAiHttpResponse>> requests,
) {
  return AppraiseAiClient(
    postJson: (uri, {required headers, required body}) async {
      if (body['max_tokens'] == 32) {
        return const AppraiseAiHttpResponse(statusCode: 200, body: {});
      }
      final request = Completer<AppraiseAiHttpResponse>();
      requests.add(request);
      return request.future;
    },
  );
}

Future<void> _enableAi(WidgetTester tester) async {
  await tester.tap(find.byTooltip('AI 设置'));
  await tester.pumpAndSettle();
  await _enterApiKeyAndRunCheck(tester, 'sk-test');
  await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded).last);
  await tester.pumpAndSettle();
}

Future<void> _enterApiKeyAndRunCheck(WidgetTester tester, String apiKey) async {
  await tester.scrollUntilVisible(
    _apiKeyFieldFinder(),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(_apiKeyFieldFinder(), apiKey);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('测试'),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('测试'));
  await tester.pumpAndSettle();
}

AppraiseAiHttpResponse _appraiseResponse({
  int theme = 18,
  int technique = 18,
  int emotion = 18,
  int association = 18,
}) {
  return AppraiseAiHttpResponse(
    statusCode: 200,
    body: {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'initial': '画面入口清楚。',
              'scores': {
                'theme': theme,
                'technique': technique,
                'emotion': emotion,
                'association': association,
              },
              'dimensions': {
                'theme': '主题明确。',
                'technique': '技术稳定。',
                'emotion': '情绪自然。',
                'association': '有延展。',
              },
              'overall': '总观内容。',
              'refine': '打磨内容。',
              'question': '你最想保留哪一点？',
            }),
          },
        },
      ],
    },
  );
}

AppraiseAiHttpResponse _seriesAppraiseResponse() {
  return AppraiseAiHttpResponse(
    statusCode: 200,
    body: {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'title': '春日回声',
              'overall': 'photo-1 与 photo-3 共同构成春日行走的两端，节奏稳定。',
              'themeLine': 'Photo-2 承接了明亮天气与轻松行走之间的中段节奏。',
              'relationships': [
                {
                  'photoIds': ['photo-1', 'photo-2'],
                  'role': '呼应',
                  'text': 'photo-1 和 photo-2 的光线方向和观看距离互相呼应。',
                },
              ],
              'sequence': {
                'suggestedPhotoIds': ['photo-1', 'photo-2', 'photo-3'],
                'text': 'photo-3 适合开场，photo-2 推进，photo-1 收束。',
              },
              'refine': '可以补充一张更安静的过渡画面。',
              'question': '这一组最想留下哪一种时间感？',
              'scores': {
                'theme': 18,
                'technique': 17,
                'emotion': 19,
                'association': 16,
                'editing': 18,
              },
            }),
          },
        },
      ],
    },
  );
}

PhotoAppraisal _finePhotoAppraisal() {
  return PhotoAppraisal(
    initial: '完整。',
    overall: '这张照片已经进入佳作。',
    refine: '保持。',
    question: '还想留下什么？',
    metrics: const [
      PhotoAppraisalMetric(label: 'theme', value: 25, text: '主题明确。'),
      PhotoAppraisalMetric(label: 'technique', value: 25, text: '技术稳定。'),
      PhotoAppraisalMetric(label: 'emotion', value: 25, text: '情绪清楚。'),
      PhotoAppraisalMetric(label: 'association', value: 25, text: '联想充分。'),
    ],
  );
}

class _AppraiseTestApp extends StatelessWidget {
  const _AppraiseTestApp({
    required this.controller,
    this.aiClient,
    this.aiSettingsStore,
    this.appearanceController,
    this.theme,
    this.initialPhotoId,
  });

  final ReviewWorkspaceController controller;
  final AppraiseAiClient? aiClient;
  final AppraiseAiSettingsStore? aiSettingsStore;
  final NoemaAppearanceController? appearanceController;
  final ThemeData? theme;
  final String? initialPhotoId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      theme: theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: AppraiseScreen(
        workspaceController: controller,
        aiClient: aiClient ?? const AppraiseAiClient(),
        aiSettingsStore: aiSettingsStore,
        appearanceController: appearanceController,
        initialPhotoId: initialPhotoId,
      ),
    );
  }
}

class _DelayedAiSettingsStore extends AppraiseAiSettingsStore {
  _DelayedAiSettingsStore(this.restore);

  final Completer<AppraiseAiSettingsLibrary> restore;

  @override
  Future<AppraiseAiSettingsLibrary> readSettingsLibrary() => restore.future;

  @override
  Future<void> writeSettingsLibrary(AppraiseAiSettingsLibrary settings) async {}
}

ReviewWorkspaceController _sampleWorkspaceController({
  int count = 24,
  bool withPreviewBytes = false,
  Uint8List? analysisBytes,
  bool withDimensions = false,
  PhotoExif? exif,
}) {
  final controller = ReviewWorkspaceController();
  controller.loadSelectedAssets(
    List.generate(
      count,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
        previewBytes: withPreviewBytes ? _tinyPngBytes : null,
        analysisBytes: analysisBytes,
        mimeType: withPreviewBytes ? 'image/png' : null,
        width: withDimensions ? 4032 : null,
        height: withDimensions ? 3024 : null,
        exif: exif,
      ),
    ),
    name: '友人',
  );
  return controller;
}

final _tinyPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR4nGP4TyFgGDVg1IBRA4aLAQBdePwur/3haQAAAABJRU5ErkJggg==',
  ),
);

final _checkerPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAH0lEQVR42mNgYGD4DwJk0xRpBtIMoy4YdcGoCwaJCwB8on2fWEEerQAAAABJRU5ErkJggg==',
  ),
);

final _blackPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
  ),
);
