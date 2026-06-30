import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/ui/noema_scene.dart';

void main() {
  testWidgets('dark floating action keeps a prominent seal surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NoemaFloatingActionButton(
            palette: NoemaPalette.fromTone(NoemaTone.dark),
            tooltip: '添加照片',
            onPressed: () {},
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    final border = decoration.border! as Border;
    final shadows = decoration.boxShadow!;

    expect(gradient.colors.first.a, greaterThanOrEqualTo(0.9));
    expect(gradient.colors.last.a, 1);
    expect(border.top.width, greaterThanOrEqualTo(1.2));
    expect(border.top.color.a, greaterThanOrEqualTo(0.9));
    expect(shadows.length, greaterThanOrEqualTo(2));
  });

  testWidgets('interactive inactive floating action stays legible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NoemaFloatingActionButton(
            palette: NoemaPalette.fromTone(NoemaTone.light),
            tooltip: '创建境',
            enabled: false,
            onPressed: null,
            onDisabledPressed: () {},
            child: const Icon(Icons.check_rounded),
          ),
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    final border = decoration.border! as Border;
    final iconColor = IconTheme.of(
      tester.element(find.byIcon(Icons.check_rounded)),
    ).color!;

    expect(gradient.colors.first.a, greaterThanOrEqualTo(0.56));
    expect(gradient.colors.last.a, greaterThanOrEqualTo(0.7));
    expect(border.top.color.a, greaterThanOrEqualTo(0.26));
    expect(iconColor.a, greaterThanOrEqualTo(0.5));
  });

  testWidgets(
    'glass icon button can tone down its surface and keeps icon centered',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: NoemaGlassIconButton(
              palette: NoemaPalette.fromTone(NoemaTone.dark),
              tooltip: '返回',
              icon: Icons.close_rounded,
              onPressed: () {},
              surfaceOpacityScale: 0,
            ),
          ),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color!.a, 0);
      expect(container.child, isA<Center>());
    },
  );
}
