import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/ui/noema_orientation.dart';

void main() {
  test('iOS default defers to Info.plist orientation declarations', () {
    expect(noemaDefaultOrientationsForPlatform(isIOS: true), isEmpty);
  });

  test('non-iOS default remains portrait only', () {
    expect(noemaDefaultOrientationsForPlatform(isIOS: false), const [
      DeviceOrientation.portraitUp,
    ]);
  });
}
