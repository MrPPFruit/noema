import 'dart:convert';
import 'dart:typed_data';

import 'package:noema/core/models/photo_asset.dart';
import 'package:noema/core/models/series_appraisal.dart';

import 'appraise_ai_transport.dart';

typedef AppraiseAiPostJson =
    Future<AppraiseAiHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
      required Map<String, Object?> body,
    });

typedef AppraiseAiSeriesProgressCallback =
    void Function(AppraiseAiSeriesProgress progress);

const _seriesDirectPhotoLimit = 12;
const _seriesBatchSize = 12;
const _seriesMaxConcurrentBatches = 3;

class AppraiseAiSettings {
  const AppraiseAiSettings({
    required this.enabled,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  factory AppraiseAiSettings.defaults() {
    return const AppraiseAiSettings(
      enabled: false,
      provider: 'qwen',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen3.7-plus',
      apiKey: '',
    );
  }

  factory AppraiseAiSettings.forProvider(String provider) {
    final option = appraiseAiProviderOptionFor(provider);
    return AppraiseAiSettings(
      enabled: false,
      provider: option.id,
      baseUrl: option.baseUrl,
      model: option.defaultModel,
      apiKey: '',
    );
  }

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isReady {
    return enabled &&
        baseUrl.trim().isNotEmpty &&
        model.trim().isNotEmpty &&
        apiKey.trim().isNotEmpty;
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'provider': provider,
      'baseUrl': baseUrl,
      'model': model,
      'apiKey': apiKey,
    };
  }

  factory AppraiseAiSettings.fromJson(
    Map<String, Object?> json, {
    String? providerFallback,
  }) {
    final defaults = providerFallback == null
        ? AppraiseAiSettings.defaults()
        : AppraiseAiSettings.forProvider(providerFallback);
    final provider = _stringValue(json['provider'], defaults.provider);
    final providerOption = appraiseAiProviderOptionFor(provider);
    return AppraiseAiSettings(
      enabled: json['enabled'] == true,
      provider: providerOption.id,
      baseUrl: _stringValue(json['baseUrl'], providerOption.baseUrl),
      model: _stringValue(json['model'], providerOption.defaultModel),
      apiKey: _stringValue(json['apiKey'], defaults.apiKey),
    );
  }

  AppraiseAiSettings copyWith({
    bool? enabled,
    String? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AppraiseAiSettings(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppraiseAiSettings &&
        other.enabled == enabled &&
        other.provider == provider &&
        other.baseUrl == baseUrl &&
        other.model == model &&
        other.apiKey == apiKey;
  }

  @override
  int get hashCode => Object.hash(enabled, provider, baseUrl, model, apiKey);
}

class AppraiseAiSettingsLibrary {
  AppraiseAiSettingsLibrary({
    required this.activeProvider,
    required Map<String, AppraiseAiSettings> providers,
  }) : providers = Map.unmodifiable(providers);

  factory AppraiseAiSettingsLibrary.defaults() {
    final settings = AppraiseAiSettings.defaults();
    return AppraiseAiSettingsLibrary(
      activeProvider: settings.provider,
      providers: {settings.provider: settings},
    );
  }

  factory AppraiseAiSettingsLibrary.fromJson(Map<String, Object?> json) {
    final activeProvider = appraiseAiProviderOptionFor(
      _stringValue(
        json['activeProvider'],
        AppraiseAiSettings.defaults().provider,
      ),
    ).id;
    final providersJson = _jsonMap(json['providers']);
    final providers = <String, AppraiseAiSettings>{};
    for (final entry in providersJson.entries) {
      final option = appraiseAiProviderOptionFor(entry.key);
      final value = _jsonMap(entry.value);
      providers[option.id] = AppraiseAiSettings.fromJson(
        value,
        providerFallback: option.id,
      );
    }
    providers.putIfAbsent(
      activeProvider,
      () => AppraiseAiSettings.forProvider(activeProvider),
    );
    return AppraiseAiSettingsLibrary(
      activeProvider: activeProvider,
      providers: providers,
    );
  }

  final String activeProvider;
  final Map<String, AppraiseAiSettings> providers;

  AppraiseAiSettings get activeSettings => settingsFor(activeProvider);

  AppraiseAiSettings settingsFor(String provider) {
    final option = appraiseAiProviderOptionFor(provider);
    return providers[option.id] ?? AppraiseAiSettings.forProvider(option.id);
  }

  AppraiseAiSettingsLibrary selectProvider(String provider) {
    final settings = settingsFor(provider);
    return AppraiseAiSettingsLibrary(
      activeProvider: settings.provider,
      providers: {...providers, settings.provider: settings},
    );
  }

  AppraiseAiSettingsLibrary withActiveSettings(AppraiseAiSettings settings) {
    final option = appraiseAiProviderOptionFor(settings.provider);
    final normalized = settings.copyWith(provider: option.id);
    return AppraiseAiSettingsLibrary(
      activeProvider: option.id,
      providers: {...providers, option.id: normalized},
    );
  }

  Map<String, Object?> toJson() {
    return {
      'activeProvider': activeProvider,
      'providers': {
        for (final entry in providers.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

class AppraiseAiProviderOption {
  const AppraiseAiProviderOption({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.models,
    required this.allowCustomBaseUrl,
    required this.useJsonMode,
    required this.apiKeyHint,
  });

  final String id;
  final String label;
  final String baseUrl;
  final List<String> models;
  final bool allowCustomBaseUrl;
  final bool useJsonMode;
  final String apiKeyHint;

  String get defaultModel => models.first;
}

const appraiseAiProviderOptions = [
  AppraiseAiProviderOption(
    id: 'qwen',
    label: '千问（推荐）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: [
      'qwen3.7-plus',
      'qwen3.6-plus',
      'qwen3.6-flash',
      'qwen3-vl-plus',
      'qwen3-vl-flash',
    ],
    allowCustomBaseUrl: true,
    useJsonMode: true,
    apiKeyHint: 'sk-...',
  ),
  AppraiseAiProviderOption(
    id: 'kimi',
    label: 'Kimi',
    baseUrl: 'https://api.moonshot.ai/v1',
    models: ['kimi-k2.6'],
    allowCustomBaseUrl: true,
    useJsonMode: true,
    apiKeyHint: 'sk-...',
  ),
  AppraiseAiProviderOption(
    id: 'zhipu',
    label: '智谱',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4.5v', 'glm-5v-turbo'],
    allowCustomBaseUrl: true,
    useJsonMode: false,
    apiKeyHint: '你的 API Key',
  ),
  AppraiseAiProviderOption(
    id: 'minimax',
    label: 'MiniMax',
    baseUrl: 'https://api.minimax.io/v1',
    models: ['MiniMax-M3'],
    allowCustomBaseUrl: true,
    useJsonMode: false,
    apiKeyHint: 'sk-...',
  ),
  AppraiseAiProviderOption(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4.1-mini', 'gpt-4o-mini'],
    allowCustomBaseUrl: false,
    useJsonMode: true,
    apiKeyHint: 'sk-...',
  ),
  AppraiseAiProviderOption(
    id: 'gemini',
    label: 'Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: ['gemini-2.5-flash', 'gemini-2.5-pro'],
    allowCustomBaseUrl: false,
    useJsonMode: true,
    apiKeyHint: 'AIza...',
  ),
  AppraiseAiProviderOption(
    id: 'openai-compatible',
    label: 'OpenAI-compatible',
    baseUrl: 'https://api.example.com/v1',
    models: ['your-vision-model'],
    allowCustomBaseUrl: true,
    useJsonMode: true,
    apiKeyHint: '你的 API Key',
  ),
];

AppraiseAiProviderOption appraiseAiProviderOptionFor(String id) {
  for (final option in appraiseAiProviderOptions) {
    if (option.id == id) {
      return option;
    }
  }
  return appraiseAiProviderOptions.first;
}

String _stringValue(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

class AppraiseAiCheckResult {
  const AppraiseAiCheckResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class AppraiseAiPhotoResult {
  const AppraiseAiPhotoResult({
    required this.initial,
    required this.overall,
    required this.refine,
    required this.question,
    required this.metrics,
  });

  factory AppraiseAiPhotoResult.fromJson(Map<String, Object?> json) {
    final scores = _jsonMap(json['scores']);
    final dimensions = _jsonMap(json['dimensions']);
    return AppraiseAiPhotoResult(
      initial: _string(json['initial']),
      overall: _string(json['overall']),
      refine: _string(json['refine']),
      question: _string(json['question']),
      metrics: [
        AppraiseAiMetric(
          label: '主题',
          value: _score(scores['theme']),
          text: _string(dimensions['theme']),
        ),
        AppraiseAiMetric(
          label: '技术',
          value: _score(scores['technique']),
          text: _string(dimensions['technique']),
        ),
        AppraiseAiMetric(
          label: '情感',
          value: _score(scores['emotion']),
          text: _string(dimensions['emotion']),
        ),
        AppraiseAiMetric(
          label: '联想',
          value: _score(scores['association']),
          text: _string(dimensions['association']),
        ),
      ],
    );
  }

  factory AppraiseAiPhotoResult.fromPhotoAppraisal(PhotoAppraisal appraisal) {
    return AppraiseAiPhotoResult(
      initial: appraisal.initial,
      overall: appraisal.overall,
      refine: appraisal.refine,
      question: appraisal.question,
      metrics: [
        for (final metric in appraisal.metrics)
          AppraiseAiMetric(
            label: metric.label,
            value: metric.value,
            text: metric.text,
          ),
      ],
    );
  }

  final String initial;
  final String overall;
  final String refine;
  final String question;
  final List<AppraiseAiMetric> metrics;

  int get totalScore {
    return metrics.fold<int>(0, (value, metric) => value + metric.value);
  }

  PhotoAppraisal toPhotoAppraisal() {
    return PhotoAppraisal(
      initial: initial,
      overall: overall,
      refine: refine,
      question: question,
      metrics: [
        for (final metric in metrics)
          PhotoAppraisalMetric(
            label: metric.label,
            value: metric.value,
            text: metric.text,
          ),
      ],
    );
  }
}

class AppraiseAiMetric {
  const AppraiseAiMetric({
    required this.label,
    required this.value,
    required this.text,
  });

  final String label;
  final int value;
  final String text;
}

class AppraiseAiSeriesProgress {
  const AppraiseAiSeriesProgress({
    required this.label,
    required this.completed,
    required this.total,
  });

  final String label;
  final int completed;
  final int total;
}

class AppraiseAiSeriesPhoto {
  const AppraiseAiSeriesPhoto({
    required this.id,
    required this.label,
    required this.imageBytes,
    required this.mimeType,
    required this.captureTime,
  });

  final String id;
  final String label;
  final Uint8List imageBytes;
  final String mimeType;
  final DateTime captureTime;
}

class AppraiseAiClient {
  const AppraiseAiClient({this.postJson = postAppraiseAiJson});

  final AppraiseAiPostJson postJson;

  Future<AppraiseAiCheckResult> checkVision(AppraiseAiSettings settings) async {
    final validation = _validate(settings);
    if (validation != null) {
      return AppraiseAiCheckResult(ok: false, message: validation);
    }

    try {
      final response = await postJson(
        _chatCompletionsUri(settings.baseUrl),
        headers: _headers(settings.apiKey),
        body: _chatCompletionBody(
          settings: settings,
          messages: [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Return JSON: {"ok":true}.'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/png;base64,$_tinyPngBase64'},
                },
              ],
            },
          ],
          maxTokens: 32,
        ),
      );
      if (_isSuccess(response.statusCode)) {
        return const AppraiseAiCheckResult(ok: true, message: '测试通过');
      }
      return AppraiseAiCheckResult(
        ok: false,
        message: _safeError(response.body, settings.apiKey),
      );
    } on Object catch (error) {
      return AppraiseAiCheckResult(
        ok: false,
        message: _redact('请求失败 $error', settings.apiKey),
      );
    }
  }

  Future<AppraiseAiPhotoResult> appraisePhoto({
    required AppraiseAiSettings settings,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final validation = _validate(settings);
    if (validation != null) {
      throw AppraiseAiException(validation);
    }
    if (imageBytes.isEmpty) {
      throw const AppraiseAiException('照片数据为空');
    }

    final response = await postJson(
      _chatCompletionsUri(settings.baseUrl),
      headers: _headers(settings.apiKey),
      body: _chatCompletionBody(
        settings: settings,
        messages: [
          {'role': 'system', 'content': _singlePhotoSystemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '请按系统要求品鉴这张照片，只返回 JSON。'},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,${base64Encode(imageBytes)}',
                },
              },
            ],
          },
        ],
        temperature: 0.25,
        maxTokens: 1800,
      ),
    );

    if (!_isSuccess(response.statusCode)) {
      throw AppraiseAiException(_safeError(response.body, settings.apiKey));
    }

    return AppraiseAiPhotoResult.fromJson(
      _jsonObjectFromContent(_messageContent(response.body)),
    );
  }

  Future<PhotoSeriesAppraisalResult> appraiseSeries({
    required AppraiseAiSettings settings,
    required List<AppraiseAiSeriesPhoto> photos,
    required String categoryLabel,
    AppraiseAiSeriesProgressCallback? onProgress,
  }) async {
    final validation = _validate(settings);
    if (validation != null) {
      throw AppraiseAiException(validation);
    }
    if (photos.length < 2) {
      throw const AppraiseAiException('系列品鉴至少需要两张照片');
    }
    if (photos.any((photo) => photo.imageBytes.isEmpty)) {
      throw const AppraiseAiException('系列中有照片数据为空');
    }

    if (photos.length <= _seriesDirectPhotoLimit) {
      onProgress?.call(
        const AppraiseAiSeriesProgress(label: '分析', completed: 0, total: 1),
      );
      final result = await _appraiseSeriesDirect(
        settings: settings,
        photos: photos,
        categoryLabel: categoryLabel,
      );
      onProgress?.call(
        const AppraiseAiSeriesProgress(label: '分析', completed: 1, total: 1),
      );
      return result;
    }

    final batches = _photoBatches(photos, _seriesBatchSize);
    var completedBatches = 0;
    onProgress?.call(
      AppraiseAiSeriesProgress(
        label: '分析',
        completed: completedBatches,
        total: batches.length,
      ),
    );
    final batchSummaries = await _runLimited<String>(
      count: batches.length,
      maxConcurrent: _seriesMaxConcurrentBatches,
      task: (index) async {
        final summary = await _appraiseSeriesBatch(
          settings: settings,
          photos: batches[index],
          categoryLabel: categoryLabel,
          batchIndex: index,
          batchTotal: batches.length,
        );
        completedBatches += 1;
        onProgress?.call(
          AppraiseAiSeriesProgress(
            label: '分析',
            completed: completedBatches,
            total: batches.length,
          ),
        );
        return summary;
      },
    );
    onProgress?.call(
      const AppraiseAiSeriesProgress(label: '整理结论', completed: 0, total: 1),
    );
    final result = await _summarizeSeriesBatches(
      settings: settings,
      photos: photos,
      categoryLabel: categoryLabel,
      batchSummaries: batchSummaries,
    );
    onProgress?.call(
      const AppraiseAiSeriesProgress(label: '整理结论', completed: 1, total: 1),
    );
    return result;
  }

  Future<PhotoSeriesAppraisalResult> _appraiseSeriesDirect({
    required AppraiseAiSettings settings,
    required List<AppraiseAiSeriesPhoto> photos,
    required String categoryLabel,
  }) async {
    final response = await postJson(
      _chatCompletionsUri(settings.baseUrl),
      headers: _headers(settings.apiKey),
      body: _chatCompletionBody(
        settings: settings,
        messages: [
          {'role': 'system', 'content': _seriesPhotoSystemPrompt},
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    '请为“$categoryLabel”中的这组照片做系列品鉴。'
                    '照片按当前展示顺序编号，结构化字段必须使用 photoIds；'
                    '正文不要写 photo-1 这类内部 ID，如需点名请写“照片1”或“第1张照片”。'
                    '\n${_seriesPhotoIndexText(photos)}',
              },
              for (final photo in photos)
                {
                  'type': 'image_url',
                  'image_url': {
                    'url':
                        'data:${photo.mimeType};base64,'
                        '${base64Encode(photo.imageBytes)}',
                  },
                },
            ],
          },
        ],
        temperature: 0.25,
        maxTokens: 4200,
      ),
    );

    if (!_isSuccess(response.statusCode)) {
      throw AppraiseAiException(_safeError(response.body, settings.apiKey));
    }

    return PhotoSeriesAppraisalResult.fromJson(
      _jsonObjectFromContent(_messageContent(response.body)),
    );
  }

  Future<String> _appraiseSeriesBatch({
    required AppraiseAiSettings settings,
    required List<AppraiseAiSeriesPhoto> photos,
    required String categoryLabel,
    required int batchIndex,
    required int batchTotal,
  }) async {
    final response = await postJson(
      _chatCompletionsUri(settings.baseUrl),
      headers: _headers(settings.apiKey),
      body: _chatCompletionBody(
        settings: settings,
        messages: [
          {'role': 'system', 'content': _seriesPhotoBatchSystemPrompt},
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    '这是“$categoryLabel”系列品鉴的第 ${batchIndex + 1}/$batchTotal 批照片。'
                    '请先做批次观察，不要输出最终总评。'
                    '结构化字段必须使用 photoIds；正文不要写 photo-1 这类内部 ID，'
                    '如需点名请写“照片1”或“第1张照片”。'
                    '\n${_seriesPhotoIndexText(photos)}',
              },
              for (final photo in photos)
                {
                  'type': 'image_url',
                  'image_url': {
                    'url':
                        'data:${photo.mimeType};base64,'
                        '${base64Encode(photo.imageBytes)}',
                  },
                },
            ],
          },
        ],
        temperature: 0.25,
        maxTokens: 2400,
      ),
    );

    if (!_isSuccess(response.statusCode)) {
      throw AppraiseAiException(_safeError(response.body, settings.apiKey));
    }

    return jsonEncode(_jsonObjectFromContent(_messageContent(response.body)));
  }

  Future<PhotoSeriesAppraisalResult> _summarizeSeriesBatches({
    required AppraiseAiSettings settings,
    required List<AppraiseAiSeriesPhoto> photos,
    required String categoryLabel,
    required List<String> batchSummaries,
  }) async {
    final response = await postJson(
      _chatCompletionsUri(settings.baseUrl),
      headers: _headers(settings.apiKey),
      body: _chatCompletionBody(
        settings: settings,
        messages: [
          {'role': 'system', 'content': _seriesPhotoSystemPrompt},
          {
            'role': 'user',
            'content':
                '请基于以下分批观察，汇总为“$categoryLabel”的最终系列品鉴 JSON。'
                '不要新增不存在的照片信息；结构化字段必须使用 photoIds。'
                '正文不要写 photo-1 这类内部 ID，如需点名请写“照片1”或“第1张照片”。'
                '\n${_seriesPhotoIndexText(photos)}'
                '\n\n分批观察：\n${_numberedSummaries(batchSummaries)}',
          },
        ],
        temperature: 0.25,
        maxTokens: 4200,
      ),
    );

    if (!_isSuccess(response.statusCode)) {
      throw AppraiseAiException(_safeError(response.body, settings.apiKey));
    }

    return PhotoSeriesAppraisalResult.fromJson(
      _jsonObjectFromContent(_messageContent(response.body)),
    );
  }
}

class AppraiseAiException implements Exception {
  const AppraiseAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? _validate(AppraiseAiSettings settings) {
  if (!settings.enabled) {
    return 'AI 尚未启用';
  }
  if (settings.baseUrl.trim().isEmpty) {
    return '还差 Base URL';
  }
  if (settings.model.trim().isEmpty) {
    return '还差模型名';
  }
  if (settings.apiKey.trim().isEmpty) {
    return '还差 API Key';
  }
  return null;
}

Uri _chatCompletionsUri(String baseUrl) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  return Uri.parse('$base/chat/completions');
}

Map<String, String> _headers(String apiKey) {
  return {
    'Authorization': 'Bearer ${apiKey.trim()}',
    'Content-Type': 'application/json',
  };
}

Map<String, Object?> _chatCompletionBody({
  required AppraiseAiSettings settings,
  required List<Map<String, Object?>> messages,
  required int maxTokens,
  double? temperature,
}) {
  final body = <String, Object?>{
    'model': settings.model.trim(),
    'messages': messages,
    'max_tokens': maxTokens,
  };
  final option = appraiseAiProviderOptionFor(settings.provider);
  if (temperature != null && option.id != 'kimi') {
    body['temperature'] = temperature;
  }
  if (option.id == 'kimi' && settings.model.trim() == 'kimi-k2.6') {
    body['thinking'] = {'type': 'disabled'};
  }
  if (option.id == 'qwen') {
    body['enable_thinking'] = false;
  }
  if (option.useJsonMode) {
    body['response_format'] = {'type': 'json_object'};
  }
  return body;
}

bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

String _messageContent(Object? body) {
  final root = _jsonMap(body);
  final choices = root['choices'];
  if (choices is! List || choices.isEmpty) {
    throw const AppraiseAiException('AI 返回缺少 choices');
  }
  final first = _jsonMap(choices.first);
  final message = _jsonMap(first['message']);
  final content = message['content'];
  if (content is String && content.trim().isNotEmpty) {
    return content;
  }
  throw const AppraiseAiException('AI 返回内容为空');
}

Map<String, Object?> _jsonObjectFromContent(String content) {
  final trimmed = content.trim();
  final candidates = <String>[
    trimmed,
    _unfencedJson(trimmed),
    _firstJsonObject(trimmed),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) {
      continue;
    }
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } on FormatException {
      continue;
    }
  }
  throw const AppraiseAiException('AI 返回不是 JSON 对象');
}

String _unfencedJson(String content) {
  final match = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(content);
  return match?.group(1)?.trim() ?? '';
}

String _firstJsonObject(String content) {
  final start = content.indexOf('{');
  final end = content.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return '';
  }
  return content.substring(start, end + 1).trim();
}

String _safeError(Object? body, String apiKey) {
  return _redact('Provider 返回错误 $body', apiKey);
}

String _redact(String message, String apiKey) {
  var safe = message;
  final trimmed = apiKey.trim();
  if (trimmed.isNotEmpty) {
    safe = safe.replaceAll(trimmed, '[redacted]');
  }
  return safe
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]+'), '[redacted]')
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+'), 'Bearer [redacted]');
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }
  return const {};
}

String _string(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

int _score(Object? value) {
  if (value is num) {
    return value.round().clamp(0, 25).toInt();
  }
  return int.tryParse('$value')?.clamp(0, 25).toInt() ?? 0;
}

String _seriesPhotoIndexText(List<AppraiseAiSeriesPhoto> photos) {
  String two(int number) => number.toString().padLeft(2, '0');
  return [
    '参与照片：',
    for (var index = 0; index < photos.length; index += 1)
      '${index + 1}. photoId=${photos[index].id}, '
          'name=${photos[index].label}, '
          'capture=${photos[index].captureTime.year}-'
          '${two(photos[index].captureTime.month)}-'
          '${two(photos[index].captureTime.day)} '
          '${two(photos[index].captureTime.hour)}:'
          '${two(photos[index].captureTime.minute)}',
  ].join('\n');
}

List<List<AppraiseAiSeriesPhoto>> _photoBatches(
  List<AppraiseAiSeriesPhoto> photos,
  int size,
) {
  return [
    for (var start = 0; start < photos.length; start += size)
      photos.sublist(
        start,
        start + size > photos.length ? photos.length : start + size,
      ),
  ];
}

Future<List<T>> _runLimited<T>({
  required int count,
  required int maxConcurrent,
  required Future<T> Function(int index) task,
}) async {
  final results = List<T?>.filled(count, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next;
      if (index >= count) {
        return;
      }
      next += 1;
      results[index] = await task(index);
    }
  }

  final workerCount = count < maxConcurrent ? count : maxConcurrent;
  await Future.wait([for (var i = 0; i < workerCount; i += 1) worker()]);
  return [for (final result in results) result as T];
}

String _numberedSummaries(List<String> summaries) {
  return [
    for (var index = 0; index < summaries.length; index += 1)
      '批次 ${index + 1}:\n${summaries[index]}',
  ].join('\n\n');
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR4nGP4TyFgGDVg1IBRA4aLAQBdePwur/3haQAAAABJRU5ErkJggg==';

const _singlePhotoSystemPrompt = '''
你是 Photo Appraiser。请基于照片本身进行摄影品鉴，不要编造拍摄者背景。

评分采用四个维度，每项 25 分：
1. 主题价值：照片是否有明确表达核心，主体、空间、光线是否服务主题。
2. 技术价值：构图、光线、曝光、色彩、焦点、景深、后期是否帮助照片成立。
3. 情感价值：画面是否产生自然、稳定、有余韵的情绪力量。
4. 联想价值：照片是否留下画面之外的故事、象征、文化或心理延展。

输出要求：
- 只返回 JSON，不要 Markdown。
- 不要写成长篇课堂讲解，但信息密度要足够专业。
- 建议要有启发性，不要命令创作者。
- 分数必须是 0 到 25 的整数。
- 总分由四项分数相加得到，不要单独编造另一个总分。

JSON 结构：
{
  "initial": "初见判断，2-4 句",
  "scores": {
    "theme": 0,
    "technique": 0,
    "emotion": 0,
    "association": 0
  },
  "dimensions": {
    "theme": "主题价值分析，2-4 句",
    "technique": "技术价值分析，2-4 句",
    "emotion": "情感价值分析，2-4 句",
    "association": "联想价值分析，2-4 句"
  },
  "overall": "总观，综合说明这张照片成立在哪里、限制在哪里，4-7 句",
  "refine": "打磨，以可选择方向的方式提出改进或深化路径，3-5 句",
  "question": "自问，一个最关键的问题"
}
''';

const _seriesPhotoBatchSystemPrompt = '''
你是 Photo Appraiser 的系列品鉴批次观察模块。你只负责观察这一批照片，不输出最终系列报告。

观察重点：
1. 这一批共同呈现的主题、视觉语言和情绪。
2. 批次内部哪些照片互相补充，哪些承担相似角色。
3. 哪些照片可能适合作为开场、推进、转折或收束候选。
4. 这一批和大系列可能产生的连接点。

输出要求：
- 只返回 JSON，不要 Markdown。
- 不要编造照片之外的地点、人物身份或拍摄者背景。
- 讲到具体照片时，结构化字段必须使用 photoIds 数组；正文文本不要写 photo-1 这类内部 ID，如需点名请写“照片1”或“第1张照片”。
- 这是中间观察，不要写最终总观、最终系列名或最终分数。

JSON 结构：
{
  "batchSummary": "这一批的总体观察，3-5 句",
  "themeNotes": "主题与情绪线索，2-4 句",
  "visualNotes": "视觉语言观察，2-4 句",
  "relationships": [
    {
      "photoIds": ["photo-1", "photo-3"],
      "role": "呼应 / 推进 / 转折 / 收束 / 相似角色",
      "text": "这几张之间的关系，1-3 句"
    }
  ],
  "sequenceCandidates": ["photo-1", "photo-3"]
}
''';

const _seriesPhotoSystemPrompt = '''
你是 Photo Appraiser 的系列品鉴模块。你的任务不是筛选、删除或去重，而是判断一组照片作为系列是否成立。

分析方向：
1. 系列主题：这组照片共同在讲什么。
2. 视觉一致性：色调、构图、光线、主体距离、画面气质是否统一。
3. 叙事关系：是否有开场、推进、转折、收束。
4. 情绪路径：观看感受是否有变化和余韵。
5. 组内关系：哪些照片互相补充，哪些承担相似角色。
6. 编排建议：可以建议开头、推进、结尾，但不要变成淘汰清单。
7. 打磨：给出进一步拍摄、编辑或呈现方向。
8. 自问：只保留一个能启发创作者的问题。

输出要求：
- 只返回 JSON，不要 Markdown。
- 文风要像“暗房札记”，专业、克制、具体。
- 不要编造照片之外的地点、人物身份或拍摄者背景。
- 讲到具体照片时，结构化字段必须使用 photoIds 数组；正文文本不要写 photo-1 这类内部 ID，如需点名请写“照片1”或“第1张照片”。
- 分数每项 0 到 20 分，五项总分 100 分。
- title 是给这一组照片取的系列名，短而有辨识度，不要超过 10 个汉字。

JSON 结构：
{
  "title": "系列名",
  "overall": "总观，4-7 句",
  "themeLine": "主题线，3-5 句",
  "relationships": [
    {
      "photoIds": ["photo-1", "photo-3"],
      "role": "呼应 / 推进 / 转折 / 收束 / 相似角色",
      "text": "这几张之间的关系，2-4 句"
    }
  ],
  "sequence": {
    "suggestedPhotoIds": ["photo-1", "photo-3", "photo-2"],
    "text": "编排建议，3-5 句"
  },
  "refine": "打磨建议，3-5 句",
  "question": "自问，一个最关键的问题",
  "scores": {
    "theme": 0,
    "technique": 0,
    "emotion": 0,
    "association": 0,
    "editing": 0
  }
}
''';
