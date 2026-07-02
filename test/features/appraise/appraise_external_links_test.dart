import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/appraise/appraise_screen.dart';

void main() {
  group('isAppraiseExternalLinkOpenFailure', () {
    test('treats platform and missing-plugin failures as recoverable', () {
      expect(
        isAppraiseExternalLinkOpenFailure(
          PlatformException(code: 'open_failed'),
        ),
        isTrue,
      );
      expect(
        isAppraiseExternalLinkOpenFailure(
          MissingPluginException('noema/external_links'),
        ),
        isTrue,
      );
    });

    test('does not hide unexpected errors', () {
      expect(
        isAppraiseExternalLinkOpenFailure(StateError('unexpected')),
        isFalse,
      );
    });
  });
}
