import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/appraise/appraise_ai_client.dart';
import 'package:noema/features/appraise/appraise_ai_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI settings store restores saved provider settings', () async {
    FlutterSecureStorage.setMockInitialValues({});

    final openAiSettings = AppraiseAiSettings.forProvider('openai');
    final qwenSettings = AppraiseAiSettings.forProvider(
      'qwen',
    ).copyWith(enabled: true, apiKey: 'sk-persisted');
    await AppraiseAiSettingsStore().writeSettingsLibrary(
      AppraiseAiSettingsLibrary(
        activeProvider: 'qwen',
        providers: {
          openAiSettings.provider: openAiSettings,
          qwenSettings.provider: qwenSettings,
        },
      ),
    );

    final restored = await AppraiseAiSettingsStore().readSettingsLibrary();
    expect(restored.activeProvider, 'qwen');
    expect(restored.activeSettings.isReady, isTrue);
    expect(restored.activeSettings.model, 'qwen3.7-plus');
    expect(restored.activeSettings.apiKey, 'sk-persisted');
    expect(restored.settingsFor('openai').apiKey, isEmpty);
  });
}
