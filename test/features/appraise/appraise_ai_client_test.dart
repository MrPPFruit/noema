import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noema/features/appraise/appraise_ai_client.dart';
import 'package:noema/features/appraise/appraise_ai_transport.dart';

void main() {
  test('lists only direct vision providers selected for appraise', () {
    expect(appraiseAiProviderOptions.first.id, 'qwen');
    expect(appraiseAiProviderOptions.first.label, '千问（推荐）');
    expect(
      appraiseAiProviderOptions.map((option) => option.id),
      containsAll(['openai', 'kimi', 'qwen', 'gemini', 'minimax', 'zhipu']),
    );
    expect(
      appraiseAiProviderOptions.map((option) => option.id),
      isNot(contains('deepseek')),
    );
    expect(AppraiseAiSettings.defaults().provider, 'qwen');
    expect(appraiseAiProviderOptionFor('qwen').defaultModel, 'qwen3.7-plus');
  });

  test(
    'appraises a photo through OpenAI-compatible image JSON request',
    () async {
      Map<String, Object?>? capturedBody;
      final client = AppraiseAiClient(
        postJson: (uri, {required headers, required body}) async {
          capturedBody = body;
          return AppraiseAiHttpResponse(
            statusCode: 200,
            body: {
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'initial': '画面有明确观看入口。',
                      'scores': {
                        'theme': 20,
                        'technique': 18,
                        'emotion': 21,
                        'association': 17,
                      },
                      'dimensions': {
                        'theme': '主题成立。',
                        'technique': '技术支撑表达。',
                        'emotion': '情绪自然。',
                        'association': '有延展空间。',
                      },
                      'overall': '总观内容。',
                      'refine': '打磨内容。',
                      'question': '你想让观众先看见什么？',
                    }),
                  },
                },
              ],
            },
          );
        },
      );

      final result = await client.appraisePhoto(
        settings: _settings(),
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(
        result.metrics.singleWhere((metric) => metric.label == '主题').value,
        20,
      );
      expect(result.totalScore, 76);
      final messages = capturedBody?['messages'] as List<Object?>;
      final userMessage = messages.last as Map<String, Object?>;
      final content = userMessage['content'] as List<Object?>;
      final imagePart = content.last as Map<String, Object?>;
      final imageUrl = imagePart['image_url'] as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/jpeg;base64,AQID');
    },
  );

  test('appraises a photo series through mocked vision JSON request', () async {
    Map<String, Object?>? capturedBody;
    final client = AppraiseAiClient(
      postJson: (uri, {required headers, required body}) async {
        capturedBody = body;
        return AppraiseAiHttpResponse(
          statusCode: 200,
          body: {
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'title': '春日回声',
                    'overall': '这一组照片有稳定的观看节奏。',
                    'themeLine': '主题围绕春日行走展开。',
                    'relationships': [
                      {
                        'photoIds': ['photo-1', 'photo-2'],
                        'role': '呼应',
                        'text': '两张照片在光线和空间上形成呼应。',
                      },
                    ],
                    'sequence': {
                      'suggestedPhotoIds': ['photo-1', 'photo-2'],
                      'text': '第一张适合开场，第二张适合收束。',
                    },
                    'refine': '可以补一张中景来承接。',
                    'question': '这一组最想留下哪一种时间感？',
                    'scores': {
                      'theme': 18,
                      'technique': 17,
                      'emotion': 19,
                      'association': 16,
                      'editing': 18,
                    },
                  }),
                },
              },
            ],
          },
        );
      },
    );

    final result = await client.appraiseSeries(
      settings: _settings(),
      categoryLabel: '佳作',
      photos: [
        AppraiseAiSeriesPhoto(
          id: 'photo-1',
          label: 'A',
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
          captureTime: DateTime(2026, 4, 1, 8),
        ),
        AppraiseAiSeriesPhoto(
          id: 'photo-2',
          label: 'B',
          imageBytes: Uint8List.fromList([2]),
          mimeType: 'image/png',
          captureTime: DateTime(2026, 4, 1, 9),
        ),
      ],
    );

    expect(result.title, '春日回声');
    expect(result.scores.total, 88);
    expect(result.relationships.single.photoIds, ['photo-1', 'photo-2']);
    final messages = capturedBody?['messages'] as List<Object?>;
    final userMessage = messages.last as Map<String, Object?>;
    final content = userMessage['content'] as List<Object?>;
    expect(
      content.where(
        (part) => part is Map<String, Object?> && part['type'] == 'image_url',
      ),
      hasLength(2),
    );
    expect(jsonEncode(capturedBody), contains('photoId=photo-1'));
    expect(capturedBody?['max_tokens'], 4200);
  });

  test(
    'splits large photo series into batch requests then summarizes',
    () async {
      final capturedBodies = <Map<String, Object?>>[];
      var call = 0;
      final client = AppraiseAiClient(
        postJson: (uri, {required headers, required body}) async {
          capturedBodies.add(body);
          call += 1;
          return call <= 2 ? _seriesBatchResponse() : _seriesFinalResponse();
        },
      );
      final progress = <String>[];

      final result = await client.appraiseSeries(
        settings: _settings(),
        categoryLabel: '珍藏',
        photos: [
          for (var index = 0; index < 13; index += 1)
            AppraiseAiSeriesPhoto(
              id: 'photo-${index + 1}',
              label: 'Photo ${index + 1}',
              imageBytes: Uint8List.fromList([index + 1]),
              mimeType: 'image/jpeg',
              captureTime: DateTime(2026, 4, 1, 8, index),
            ),
        ],
        onProgress: (event) {
          progress.add('${event.label}:${event.completed}/${event.total}');
        },
      );

      expect(result.title, '春日回声');
      expect(capturedBodies, hasLength(3));
      expect(_imagePartCount(capturedBodies[0]), 12);
      expect(_imagePartCount(capturedBodies[1]), 1);
      expect(_imagePartCount(capturedBodies[2]), 0);
      expect(capturedBodies[0]['max_tokens'], 2400);
      expect(capturedBodies[2]['max_tokens'], 4200);
      expect(jsonEncode(capturedBodies[2]), contains('分批观察'));
      expect(
        progress,
        containsAllInOrder([
          '分析:0/2',
          '分析:1/2',
          '分析:2/2',
          '整理结论:0/1',
          '整理结论:1/1',
        ]),
      );
    },
  );

  test(
    'omits json mode for providers whose vision endpoint may reject it',
    () async {
      Map<String, Object?>? capturedBody;
      final client = AppraiseAiClient(
        postJson: (uri, {required headers, required body}) async {
          capturedBody = body;
          return const AppraiseAiHttpResponse(
            statusCode: 200,
            body: {
              'choices': [
                {
                  'message': {
                    'content': '''
```json
{
  "initial": "画面成立。",
  "scores": {"theme": 19, "technique": 18, "emotion": 20, "association": 17},
  "dimensions": {
    "theme": "主体明确。",
    "technique": "光线自然。",
    "emotion": "情绪稳定。",
    "association": "有余味。"
  },
  "overall": "总观内容。",
  "refine": "打磨内容。",
  "question": "你想保留哪一层情绪？"
}
```
''',
                  },
                },
              ],
            },
          );
        },
      );

      final result = await client.appraisePhoto(
        settings: AppraiseAiSettings.defaults().copyWith(
          enabled: true,
          provider: 'minimax',
          baseUrl: 'https://api.minimax.io/v1',
          model: 'MiniMax-M3',
          apiKey: 'sk-test',
        ),
        imageBytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
      );

      expect(capturedBody, isNot(contains('response_format')));
      expect(result.question, '你想保留哪一层情绪？');
    },
  );

  test('uses Kimi vision-compatible request parameters', () async {
    Map<String, Object?>? capturedBody;
    final client = AppraiseAiClient(
      postJson: (uri, {required headers, required body}) async {
        capturedBody = body;
        return AppraiseAiHttpResponse(
          statusCode: 200,
          body: {
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'initial': '画面成立。',
                    'scores': {
                      'theme': 19,
                      'technique': 18,
                      'emotion': 20,
                      'association': 17,
                    },
                    'dimensions': {
                      'theme': '主体明确。',
                      'technique': '光线自然。',
                      'emotion': '情绪稳定。',
                      'association': '有余味。',
                    },
                    'overall': '总观内容。',
                    'refine': '打磨内容。',
                    'question': '这张照片最想留下什么？',
                  }),
                },
              },
            ],
          },
        );
      },
    );

    await client.appraisePhoto(
      settings: AppraiseAiSettings.defaults().copyWith(
        enabled: true,
        provider: 'kimi',
        baseUrl: 'https://api.moonshot.ai/v1',
        model: 'kimi-k2.6',
        apiKey: 'sk-test',
      ),
      imageBytes: Uint8List.fromList([1]),
      mimeType: 'image/png',
    );

    expect(capturedBody, isNot(contains('temperature')));
    expect(capturedBody?['thinking'], {'type': 'disabled'});
    expect(capturedBody?['response_format'], {'type': 'json_object'});
  });

  test('uses Qwen mainstream vision model in non-thinking JSON mode', () async {
    Map<String, Object?>? capturedBody;
    final client = AppraiseAiClient(
      postJson: (uri, {required headers, required body}) async {
        capturedBody = body;
        return AppraiseAiHttpResponse(
          statusCode: 200,
          body: {
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'initial': '画面成立。',
                    'scores': {
                      'theme': 19,
                      'technique': 18,
                      'emotion': 20,
                      'association': 17,
                    },
                    'dimensions': {
                      'theme': '主体明确。',
                      'technique': '光线自然。',
                      'emotion': '情绪稳定。',
                      'association': '有余味。',
                    },
                    'overall': '总观内容。',
                    'refine': '打磨内容。',
                    'question': '这张照片最想留下什么？',
                  }),
                },
              },
            ],
          },
        );
      },
    );

    await client.appraisePhoto(
      settings: AppraiseAiSettings.defaults().copyWith(
        enabled: true,
        provider: 'qwen',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen3.7-plus',
        apiKey: 'sk-test',
      ),
      imageBytes: Uint8List.fromList([1]),
      mimeType: 'image/png',
    );

    expect(capturedBody?['model'], 'qwen3.7-plus');
    expect(capturedBody?['enable_thinking'], false);
    expect(capturedBody?['response_format'], {'type': 'json_object'});
  });

  test('checkVision uses a provider-safe visible test image', () async {
    Map<String, Object?>? capturedBody;
    final client = AppraiseAiClient(
      postJson: (uri, {required headers, required body}) async {
        capturedBody = body;
        return const AppraiseAiHttpResponse(statusCode: 200, body: {});
      },
    );

    final result = await client.checkVision(
      AppraiseAiSettings.defaults().copyWith(
        enabled: true,
        provider: 'qwen',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen3.7-plus',
        apiKey: 'sk-test',
      ),
    );

    final messages = capturedBody?['messages'] as List<Object?>;
    final userMessage = messages.single as Map<String, Object?>;
    final content = userMessage['content'] as List<Object?>;
    final imagePart = content.last as Map<String, Object?>;
    final imageUrl = imagePart['image_url'] as Map<String, Object?>;
    final dataUrl = imageUrl['url'] as String;
    final png = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    final pngBytes = ByteData.sublistView(Uint8List.fromList(png));

    expect(result.ok, isTrue);
    expect(pngBytes.getUint32(16), greaterThan(10));
    expect(pngBytes.getUint32(20), greaterThan(10));
  });

  test('redacts api key from provider errors', () async {
    final client = AppraiseAiClient(
      postJson: (uri, {required headers, required body}) async {
        return const AppraiseAiHttpResponse(
          statusCode: 401,
          body: {'error': 'bad sk-secret'},
        );
      },
    );

    expect(
      () => client.appraisePhoto(
        settings: _settings(apiKey: 'sk-secret'),
        imageBytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<AppraiseAiException>()
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sk-secret')),
            )
            .having(
              (error) => error.message,
              'redacted',
              contains('[redacted]'),
            ),
      ),
    );
  });
}

AppraiseAiSettings _settings({String apiKey = 'sk-test'}) {
  return AppraiseAiSettings.defaults().copyWith(enabled: true, apiKey: apiKey);
}

int _imagePartCount(Map<String, Object?> body) {
  final messages = body['messages'] as List<Object?>;
  final userMessage = messages.last as Map<String, Object?>;
  final content = userMessage['content'];
  if (content is! List<Object?>) {
    return 0;
  }
  return content
      .where(
        (part) => part is Map<String, Object?> && part['type'] == 'image_url',
      )
      .length;
}

AppraiseAiHttpResponse _seriesBatchResponse() {
  return AppraiseAiHttpResponse(
    statusCode: 200,
    body: {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'batchSummary': '这一批有稳定的春日气息。',
              'themeNotes': '主题围绕轻松行走展开。',
              'visualNotes': '光线明亮，距离较稳定。',
              'relationships': [
                {
                  'photoIds': ['photo-1', 'photo-2'],
                  'role': '呼应',
                  'text': '两张照片形成呼应。',
                },
              ],
              'sequenceCandidates': ['photo-1', 'photo-2'],
            }),
          },
        },
      ],
    },
  );
}

AppraiseAiHttpResponse _seriesFinalResponse() {
  return AppraiseAiHttpResponse(
    statusCode: 200,
    body: {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'title': '春日回声',
              'overall': '这一组照片有稳定的观看节奏。',
              'themeLine': '主题围绕春日行走展开。',
              'relationships': [
                {
                  'photoIds': ['photo-1', 'photo-2'],
                  'role': '呼应',
                  'text': '两张照片在光线和空间上形成呼应。',
                },
              ],
              'sequence': {
                'suggestedPhotoIds': ['photo-1', 'photo-2'],
                'text': '第一张适合开场，第二张适合收束。',
              },
              'refine': '可以补一张中景来承接。',
              'question': '这一组最想留下哪一种时间感？',
              'scores': {
                'theme': 18,
                'technique': 17,
                'emotion': 19,
                'association': 16,
                'editing': 18,
              },
            }),
          },
        },
      ],
    },
  );
}
