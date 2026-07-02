import 'dart:io';

Future<int> deleteNoemaLocalCachedFiles(Iterable<String> paths) async {
  var deleted = 0;
  final uniquePaths = {
    for (final path in paths) path.trim(),
  }.where((path) => path.isNotEmpty);

  for (final path in uniquePaths) {
    if (!_isNoemaMediaPath(path)) {
      continue;
    }
    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      await File(path).delete();
      deleted += 1;
    } catch (_) {
      // Best-effort cache cleanup must not break the user's workspace update.
    }
  }

  return deleted;
}

bool _isNoemaMediaPath(String path) {
  return path.replaceAll(r'\', '/').contains('/noema_media/');
}
