import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/theme/noema_theme.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/home/home_screen.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  testWidgets('HomeScreen shows the formal Noema home in Chinese', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.text('Noema'), findsOneWidget);
    expect(find.text('境'), findsOneWidget);
    expect(find.text('创建一个境，把照片先带进来。'), findsOneWidget);
    expect(find.text('东京'), findsNothing);
    expect(find.text('婚礼'), findsNothing);
    expect(find.byTooltip('创建境'), findsOneWidget);
    expect(find.byTooltip('显示选项'), findsOneWidget);
  });

  testWidgets('HomeScreen does not render bundled sample album images', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('HomeScreen fades scrolling albums without covering the mark', (
    tester,
  ) async {
    await _pumpHome(tester);

    expect(find.byType(ShaderMask), findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.clipBehavior, Clip.hardEdge);
  });

  testWidgets('HomeScreen keeps actions above the photo wall boundary', (
    tester,
  ) async {
    await _pumpHome(tester);

    final titleBottom = tester.getBottomLeft(find.text('Noema')).dy;
    final optionsRect = tester.getRect(find.byTooltip('显示选项'));
    final scrollTop = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;

    expect(optionsRect.top, greaterThan(titleBottom));
    expect(scrollTop, greaterThan(optionsRect.bottom));
  });

  testWidgets('HomeScreen options separate sort and one-button layout groups', (
    tester,
  ) async {
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('显示选项'));
    await tester.pumpAndSettle();

    final optionsButtonRect = tester.getRect(find.byTooltip('显示选项'));
    final sheetRect = tester.getRect(
      find.byKey(const ValueKey('home-options-sheet')),
    );
    expect(sheetRect.top - optionsButtonRect.bottom, closeTo(8, 1));

    expect(find.text('排序'), findsOneWidget);
    expect(find.text('排布'), findsOneWidget);
    expect(find.byTooltip('宽松排布'), findsOneWidget);

    await tester.tap(find.byTooltip('宽松排布'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('均衡排布'), findsOneWidget);
    expect(find.byTooltip('宽松排布'), findsNothing);
  });

  testWidgets('HomeScreen uses top scored photos for album covers', (
    tester,
  ) async {
    final controller = ReviewWorkspaceController();
    controller.loadSelectedAssets(
      List.generate(
        5,
        (index) => SelectedGalleryAsset(
          id: 'photo-source-${index + 1}',
          name: 'Photo ${index + 1}',
        ),
      ),
      name: '评分境',
    );

    await _pumpHome(tester, workspaceController: controller);

    var coverIds = _homeCoverPhotoIds(tester);
    expect(coverIds, containsAll(['photo-1', 'photo-2', 'photo-3']));
    expect(coverIds, isNot(contains('photo-4')));
    expect(coverIds, isNot(contains('photo-5')));

    controller.setAssetAppraisalScore('photo-1', 40);
    controller.setAssetAppraisalScore('photo-2', 90);
    controller.setAssetAppraisalScore('photo-4', 72);
    controller.setAssetAppraisalScore('photo-5', 88);
    await tester.pump();

    coverIds = _homeCoverPhotoIds(tester);
    expect(coverIds, containsAll(['photo-2', 'photo-5', 'photo-4']));
    expect(coverIds, isNot(contains('photo-1')));
    expect(coverIds, isNot(contains('photo-3')));
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  ReviewWorkspaceController? workspaceController,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      theme: NoemaTheme.dark(),
      home: HomeScreen(workspaceController: workspaceController),
    ),
  );
}

List<String> _homeCoverPhotoIds(WidgetTester tester) {
  return [
    for (final image in tester.widgetList<NoemaRecoverableReviewImage>(
      find.byType(NoemaRecoverableReviewImage),
    ))
      image.asset.photo.id,
  ];
}
