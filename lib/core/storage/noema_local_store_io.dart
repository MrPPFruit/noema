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
    return file.readAsString();
  }

  Future<void> write(String source) async {
    final file = await _storeFile();
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
