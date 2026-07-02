import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

const MethodChannel _storageChannel = MethodChannel('noema/local_storage');

Future<String?> persistGalleryImportFile(XFile file) async {
  final sourcePath = file.path;
  if (sourcePath.isEmpty) {
    return null;
  }

  try {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return null;
    }

    final directory = await _importCacheDirectory();
    final sourceAbsolutePath = source.absolute.path;
    final directoryAbsolutePath = directory.absolute.path;
    if (_isInsideDirectory(sourceAbsolutePath, directoryAbsolutePath)) {
      return sourceAbsolutePath;
    }

    final destination = await _nextDestinationFile(
      directory,
      sourcePath: sourcePath,
      displayName: file.name,
      sourceLength: await source.length(),
    );
    await source.copy(destination.path);
    if (!await destination.exists()) {
      return null;
    }
    return destination.path;
  } catch (_) {
    return null;
  }
}

Future<Directory> _importCacheDirectory() async {
  final root = await _noemaStorageDirectory();
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}noema_media'
    '${Platform.pathSeparator}imports',
  );
  await directory.create(recursive: true);
  return directory;
}

Future<Directory> _noemaStorageDirectory() async {
  try {
    final path = await _storageChannel.invokeMethod<String>(
      'getStorageDirectory',
    );
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

Future<File> _nextDestinationFile(
  Directory directory, {
  required String sourcePath,
  required String displayName,
  required int sourceLength,
}) async {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final stem = _safeStem(displayName, sourcePath);
  final extension = _safeExtension(displayName, sourcePath);
  var candidate = File(
    '${directory.path}${Platform.pathSeparator}v1_${timestamp}_${sourceLength}_$stem$extension',
  );
  var suffix = 1;
  while (await candidate.exists()) {
    candidate = File(
      '${directory.path}${Platform.pathSeparator}v1_${timestamp}_${sourceLength}_${stem}_$suffix$extension',
    );
    suffix += 1;
  }
  return candidate;
}

String _safeStem(String displayName, String sourcePath) {
  final name = _lastPathSegment(
    displayName.isNotEmpty ? displayName : sourcePath,
  );
  final dotIndex = name.lastIndexOf('.');
  final rawStem = dotIndex > 0 ? name.substring(0, dotIndex) : name;
  final safe = rawStem
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  return safe.isEmpty ? 'photo' : safe;
}

String _safeExtension(String displayName, String sourcePath) {
  final candidates = [_extensionFrom(displayName), _extensionFrom(sourcePath)];
  for (final extension in candidates) {
    if (extension != null) {
      return extension;
    }
  }
  return '.jpg';
}

String? _extensionFrom(String path) {
  final name = _lastPathSegment(path);
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == name.length - 1) {
    return null;
  }
  final extension = name.substring(dotIndex).toLowerCase();
  if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
    return extension;
  }
  return null;
}

String _lastPathSegment(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final segments = normalized.split('/').where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

bool _isInsideDirectory(String sourcePath, String directoryPath) {
  final normalizedDirectory = directoryPath.endsWith(Platform.pathSeparator)
      ? directoryPath
      : '$directoryPath${Platform.pathSeparator}';
  return sourcePath == directoryPath ||
      sourcePath.startsWith(normalizedDirectory);
}
