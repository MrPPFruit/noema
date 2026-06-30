import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/noema_app.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  test('Noema back target maps business routes', () {
    expect(noemaBackTargetForUri(Uri()), isNull);
    expect(noemaBackTargetForUri(Uri.parse(NoemaRoutes.home)), isNull);
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.import)),
      NoemaRoutes.home,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(appendImportRoute())),
      NoemaRoutes.observe,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.observe)),
      NoemaRoutes.home,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.appraise)),
      NoemaRoutes.observe,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.reviewGroups)),
      NoemaRoutes.observe,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.arena)),
      NoemaRoutes.reviewGroups,
    );
    expect(
      noemaBackTargetForUri(Uri.parse(NoemaRoutes.results)),
      NoemaRoutes.arena,
    );
  });

  testWidgets('home and import keep the same wordmark position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    final homeWordmark = find.text('Noema');
    expect(homeWordmark, findsOneWidget);
    final homeCenter = tester.getCenter(homeWordmark);
    final homeTop = tester.getTopLeft(homeWordmark).dy;

    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);

    final importWordmark = find.text('Noema');
    expect(importWordmark, findsOneWidget);
    final importCenter = tester.getCenter(importWordmark);
    final importTop = tester.getTopLeft(importWordmark).dy;

    expect((homeCenter.dx - importCenter.dx).abs(), lessThan(0.1));
    expect((homeTop - importTop).abs(), lessThan(0.1));
  });

  testWidgets('home and observe keep the same wordmark position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    final homeWordmark = find.text('Noema');
    expect(homeWordmark, findsOneWidget);
    final homeCenter = tester.getCenter(homeWordmark);
    final homeTop = tester.getTopLeft(homeWordmark).dy;

    await tester.tap(find.text('友人').first);
    await _pumpUi(tester);

    final observeWordmark = find.text('Noema').last;
    expect(find.text('Noema'), findsWidgets);
    final observeCenter = tester.getCenter(observeWordmark);
    final observeTop = tester.getTopLeft(observeWordmark).dy;

    expect((homeCenter.dx - observeCenter.dx).abs(), lessThan(0.1));
    expect((homeTop - observeTop).abs(), lessThan(0.1));
    expect(find.text('观'), findsOneWidget);
  });

  testWidgets('Android back on home asks once before exiting', (tester) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('再返回一次，退出 Noema'), findsOneWidget);
    final messageTop = tester.getTopLeft(find.text('再返回一次，退出 Noema')).dy;
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(messageTop, greaterThan(100));
    expect(messageTop, lessThan(logicalHeight * 0.45));
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      hasLength(1),
    );
  });

  testWidgets('Android back from non-home pages returns logically', (
    tester,
  ) async {
    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);
    expect(find.text('为境命名'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpUi(tester);
    expect(find.byTooltip('创建境'), findsOneWidget);
    expect(find.text('为境命名'), findsNothing);

    await tester.tap(find.text('友人').first);
    await _pumpUi(tester);
    expect(find.text('观'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpUi(tester);
    expect(find.byTooltip('创建境'), findsOneWidget);
    expect(find.text('观'), findsNothing);
  });

  testWidgets('Noema app opens the create-space import page in Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    expect(find.text('Noema'), findsOneWidget);

    await tester.tap(find.byTooltip('创建境'));
    await _pumpUi(tester);

    expect(find.text('为境命名'), findsOneWidget);
    expect(find.text('让照片入境'), findsOneWidget);
    expect(find.byTooltip('添加照片'), findsOneWidget);
    expect(find.text('使用样例照片'), findsNothing);
    expect(find.text('开始整理'), findsNothing);
  });

  testWidgets('observe add photos opens import append mode', (tester) async {
    await tester.pumpWidget(
      NoemaApp(
        locale: const Locale('zh'),
        workspaceController: _sampleWorkspaceController(),
      ),
    );

    await tester.tap(find.text('友人').first);
    await _pumpUi(tester);
    await tester.tap(find.byTooltip('添加照片'));
    await _pumpUi(tester);

    expect(find.text('友人'), findsOneWidget);
    expect(find.text('18 张已在此境'), findsOneWidget);
    expect(find.text('添入此境'), findsOneWidget);
    expect(find.text('为境命名'), findsNothing);
  });

  testWidgets('home cover recovery stays scoped to each space', (tester) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final thumbnailRequests = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'createThumbnail') {
        return null;
      }
      final args = Map<Object?, Object?>.from(
        call.arguments as Map<Object?, Object?>,
      );
      final uri = args['uri'] as String;
      thumbnailRequests.add(uri);
      return uri.contains('alpha') ? '/cache/alpha.jpg' : '/cache/beta.jpg';
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
        id: 'alpha',
        name: 'Alpha.jpg',
        sourceUri: 'content://photos/alpha',
      ),
    ], name: '同名境');
    final alphaWorkspaceId = controller.workspace.session.id;
    controller.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'beta',
        name: 'Beta.jpg',
        sourceUri: 'content://photos/beta',
      ),
    ], name: '同名境');
    final betaWorkspaceId = controller.workspace.session.id;

    await tester.pumpWidget(
      NoemaApp(locale: const Locale('zh'), workspaceController: controller),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final alphaWorkspace = controller.workspaces.singleWhere(
      (workspace) => workspace.session.id == alphaWorkspaceId,
    );
    final betaWorkspace = controller.workspaces.singleWhere(
      (workspace) => workspace.session.id == betaWorkspaceId,
    );
    expect(
      thumbnailRequests,
      containsAll(['content://photos/alpha', 'content://photos/beta']),
    );
    expect(alphaWorkspace.assets.single.photo.id, 'photo-1');
    expect(betaWorkspace.assets.single.photo.id, 'photo-1');
    expect(
      alphaWorkspace.assets.single.photo.thumbnailPath,
      '/cache/alpha.jpg',
    );
    expect(betaWorkspace.assets.single.photo.thumbnailPath, '/cache/beta.jpg');
  });

  testWidgets('Noema app opens the create-space import page in English', (
    tester,
  ) async {
    await tester.pumpWidget(const NoemaApp(locale: Locale('en')));

    expect(find.text('Noema'), findsOneWidget);

    await tester.tap(find.byTooltip('Create a space'));
    await _pumpUi(tester);

    expect(find.text('Name this space'), findsOneWidget);
    expect(find.text('Let photos enter'), findsOneWidget);
    expect(find.byTooltip('Add photos'), findsOneWidget);
    expect(find.text('Use sample selection'), findsNothing);
    expect(find.text('Start a review'), findsNothing);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 820));
}

ReviewWorkspaceController _sampleWorkspaceController() {
  final controller = ReviewWorkspaceController();
  controller.loadSelectedAssets(
    List.generate(
      18,
      (index) => SelectedGalleryAsset(
        id: 'sample-${index + 1}',
        name: 'Sample ${(index + 1).toString().padLeft(2, '0')}',
      ),
    ),
    name: '友人',
  );
  return controller;
}
