import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noema/app/noema_app.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  await configureNoemaImageCache();
  runApp(const NoemaApp());
}
