import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const noemaPortraitOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

const noemaLandscapeOrientations = <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

List<DeviceOrientation> noemaDefaultOrientationsForPlatform({
  required bool isIOS,
}) {
  return isIOS ? const <DeviceOrientation>[] : noemaPortraitOrientations;
}

Future<void> setNoemaDefaultOrientations() {
  return SystemChrome.setPreferredOrientations(
    noemaDefaultOrientationsForPlatform(isIOS: Platform.isIOS),
  );
}

Future<void> setNoemaPortraitOrientation() {
  return SystemChrome.setPreferredOrientations(noemaPortraitOrientations);
}

Future<void> setNoemaLandscapeOrientations() {
  return SystemChrome.setPreferredOrientations(noemaLandscapeOrientations);
}
