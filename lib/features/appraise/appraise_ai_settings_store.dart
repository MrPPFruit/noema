import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:noema/features/appraise/appraise_ai_client.dart';

class AppraiseAiSettingsStore {
  AppraiseAiSettingsStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _settingsKey = 'noema.appraise.ai_settings.v2';

  final FlutterSecureStorage _secureStorage;

  Future<AppraiseAiSettingsLibrary> readSettingsLibrary() async {
    try {
      final source = await _secureStorage.read(key: _settingsKey);
      if (source == null || source.trim().isEmpty) {
        return AppraiseAiSettingsLibrary.defaults();
      }
      final decoded = jsonDecode(source);
      if (decoded is Map<String, Object?>) {
        return AppraiseAiSettingsLibrary.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppraiseAiSettingsLibrary.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } catch (error) {
      debugPrint('Noema AI settings restore skipped: $error');
    }
    return AppraiseAiSettingsLibrary.defaults();
  }

  Future<void> writeSettingsLibrary(AppraiseAiSettingsLibrary settings) async {
    try {
      await _secureStorage.write(
        key: _settingsKey,
        value: jsonEncode(settings.toJson()),
      );
    } catch (error) {
      debugPrint('Noema AI settings save failed: $error');
    }
  }

  Future<AppraiseAiSettings> readSettings() async {
    final library = await readSettingsLibrary();
    return library.activeSettings;
  }

  Future<void> writeSettings(AppraiseAiSettings settings) {
    return writeSettingsLibrary(
      AppraiseAiSettingsLibrary.defaults().withActiveSettings(settings),
    );
  }
}
