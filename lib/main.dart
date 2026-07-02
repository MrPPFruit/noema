import 'package:flutter/material.dart';
import 'package:noema/app/noema_app.dart';
import 'package:noema/core/ui/noema_orientation.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setNoemaDefaultOrientations();
  await configureNoemaImageCache();
  runApp(const NoemaApp());
}
