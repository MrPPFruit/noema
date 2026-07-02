import 'dart:io';

import 'package:flutter/services.dart';

class NoemaLocalStorePlatform {
  static const MethodChannel _channel = MethodChannel('noema/local_storage');
  static const String _fileName = 'noema_workspace_store_v1.json';

  Future<String?> read() async {
    final file = await _storeFile();
    if (!await file.exists()) {
      return null;
    }
    final source = await file.readAsString();
    final migrated = _migrateNoemaStoragePaths(source, file.parent.path);
    if (migrated != source) {
      await _writeSource(file, migrated);
    }
    return migrated;
  }

  Future<void> write(String source) async {
    final file = await _storeFile();
    await _writeSource(file, source);
  }

  Future<void> _writeSource(File file, String source) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(source, flush: true);
    try {
      await temporaryFile.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temporaryFile.rename(file.path);
    }
  }

  Future<void> clear() async {
    final file = await _storeFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _storeFile() async {
    final directory = await _storeDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Directory> _storeDirectory() async {
    try {
      final path = await _channel.invokeMethod<String>('getStorageDirectory');
      if (path != null && path.isNotEmpty) {
        return Directory(path);
      }
    } on MissingPluginException {
      return _fallbackDirectory();
    } on PlatformException {
      return _fallbackDirectory();
    }
    return _fallbackDirectory();
  }

  Directory _fallbackDirectory() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home${Platform.pathSeparator}.noema');
    }
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}noema',
    );
  }
}

String _migrateNoemaStoragePaths(String source, String currentNoemaPath) {
  var migrated = source;
  final normalizedCurrentPath = currentNoemaPath.replaceAll(r'\', '/');
  final patterns = [
    RegExp(
      r'/var/mobile/Containers/Data/Application/[^"/]+/Library/Application Support/Noema',
    ),
    RegExp(
      r'/Users/[^"]+?/Library/Developer/CoreSimulator/Devices/[^"]+?/data/Containers/Data/Application/[^"/]+/Library/Application Support/Noema',
    ),
  ];
  for (final pattern in patterns) {
    migrated = migrated.replaceAll(pattern, normalizedCurrentPath);
  }
  return migrated;
}
