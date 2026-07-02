import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/ui/noema_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NoemaSceneLayout> pumpScene(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    NoemaSceneLayout? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: NoemaSceneFrame(
          palette: NoemaPalette.fromTone(NoemaTone.light),
          child: Builder(
            builder: (context) {
              captured = NoemaSceneMetrics.layoutOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(captured, isNotNull);
    return captured!;
  }

  testWidgets('keeps compact iPhone scene metrics unchanged', (tester) async {
    final layout = await pumpScene(tester, size: const Size(390, 844));

    expect(layout.isTablet, isFalse);
    expect(layout.frameWidth, NoemaSceneMetrics.designWidth);
    expect(layout.contentHeight, NoemaSceneMetrics.designHeight);
    expect(layout.sideInset, NoemaSceneMetrics.sideInset);
    expect(layout.topBarInset, NoemaSceneMetrics.topBarInset);
    expect(layout.markLeft, NoemaSceneMetrics.markLeft);
  });

  testWidgets('keeps the default 800x600 test viewport compact', (
    tester,
  ) async {
    final layout = await pumpScene(tester, size: const Size(800, 600));

    expect(layout.isTablet, isFalse);
    expect(layout.frameWidth, NoemaSceneMetrics.designWidth);
  });

  testWidgets('expands scene metrics for iPad portrait', (tester) async {
    final layout = await pumpScene(tester, size: const Size(768, 1024));

    expect(layout.isTablet, isTrue);
    expect(layout.frameWidth, 768);
    expect(layout.contentHeight, 1024);
    expect(layout.sideInset, greaterThan(NoemaSceneMetrics.sideInset));
  });

  testWidgets('uses full available width for wide iPad scene', (tester) async {
    final layout = await pumpScene(tester, size: const Size(1024, 768));

    expect(layout.isTablet, isTrue);
    expect(layout.frameWidth, 1024);
    expect(layout.contentHeight, 768);
  });
}
