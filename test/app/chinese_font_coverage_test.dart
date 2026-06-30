import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/app/noema_app.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  testWidgets(
    'main Chinese screens use LXGWWenKaiGB or LXGWWenKaiGB fallback',
    (tester) async {
      await tester.pumpWidget(
        NoemaApp(
          locale: const Locale('zh'),
          workspaceController: _sampleWorkspaceController(),
        ),
      );
      await _pumpUi(tester);

      _expectChineseTextCovered(tester);
      _expectTitleMarkFont(tester, '境');

      await tester.tap(find.byTooltip('创建境'));
      await _pumpUi(tester);
      _expectChineseTextCovered(tester);
      _expectTitleMarkFont(tester, '入');

      await tester.tap(find.byTooltip('返回'));
      await _pumpUi(tester);
      await tester.tap(find.text('友人').first);
      await _pumpUi(tester);
      _expectChineseTextCovered(tester);
      _expectTitleMarkFont(tester, '观');
    },
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 820));
}

void _expectChineseTextCovered(WidgetTester tester) {
  final texts = find.byType(Text).evaluate();

  for (final element in texts) {
    final widget = element.widget as Text;
    final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (!_containsCjk(value)) {
      continue;
    }

    final explicitStyle = widget.style;
    final defaultStyle = DefaultTextStyle.of(element).style;
    final themeFallback =
        Theme.of(element).textTheme.bodyMedium?.fontFamilyFallback ?? const [];
    final fallback =
        explicitStyle?.fontFamilyFallback ??
        defaultStyle.fontFamilyFallback ??
        themeFallback;
    final fontFamily = explicitStyle?.fontFamily ?? defaultStyle.fontFamily;

    expect(
      fontFamily == 'LXGWWenKaiGB' ||
          fontFamily == noemaTitleCjkFontFamily ||
          fallback.contains('LXGWWenKaiGB'),
      isTrue,
      reason:
          'Chinese text "$value" should use LXGWWenKaiGB or the title font.',
    );
  }
}

void _expectTitleMarkFont(WidgetTester tester, String mark) {
  final matchingTextElements = find.text(mark).evaluate();

  expect(
    matchingTextElements.any((element) {
      final widget = element.widget as Text;
      final defaultStyle = DefaultTextStyle.of(element).style;
      return widget.style?.fontFamily == noemaTitleCjkFontFamily ||
          defaultStyle.fontFamily == noemaTitleCjkFontFamily;
    }),
    isTrue,
    reason: 'Title mark "$mark" should use $noemaTitleCjkFontFamily.',
  );
}

bool _containsCjk(String text) {
  return text.runes.any((rune) => rune >= 0x4E00 && rune <= 0x9FFF);
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
