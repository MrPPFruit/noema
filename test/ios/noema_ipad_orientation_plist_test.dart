import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPhone stays portrait-only while iPad supports landscape', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final iPhoneOrientations = _arrayForKey(
      plist,
      'UISupportedInterfaceOrientations',
    );
    final iPadOrientations = _arrayForKey(
      plist,
      'UISupportedInterfaceOrientations~ipad',
    );

    expect(iPhoneOrientations, contains('UIInterfaceOrientationPortrait'));
    expect(
      iPhoneOrientations,
      isNot(contains('UIInterfaceOrientationLandscapeLeft')),
    );
    expect(
      iPhoneOrientations,
      isNot(contains('UIInterfaceOrientationLandscapeRight')),
    );
    expect(iPadOrientations, contains('UIInterfaceOrientationPortrait'));
    expect(iPadOrientations, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(iPadOrientations, contains('UIInterfaceOrientationLandscapeRight'));
    expect(_boolForKey(plist, 'UIRequiresFullScreen'), isFalse);
  });
}

List<String> _arrayForKey(String plist, String key) {
  final match = RegExp(
    '<key>$key</key>\\s*<array>(.*?)</array>',
    dotAll: true,
  ).firstMatch(plist);
  expect(match, isNotNull, reason: 'Missing plist array for $key');
  return RegExp(
    '<string>(.*?)</string>',
  ).allMatches(match!.group(1)!).map((match) => match.group(1)!).toList();
}

bool _boolForKey(String plist, String key) {
  final match = RegExp('<key>$key</key>\\s*<(true|false)/>').firstMatch(plist);
  expect(match, isNotNull, reason: 'Missing plist bool for $key');
  return match!.group(1) == 'true';
}
