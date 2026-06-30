import 'dart:convert';
import 'dart:io';

class AppraiseAiHttpResponse {
  const AppraiseAiHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Object? body;
}

Future<AppraiseAiHttpResponse> postAppraiseAiJson(
  Uri uri, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
}) async {
  const timeout = Duration(seconds: 45);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.postUrl(uri).timeout(timeout);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final encodedBody = utf8.encode(jsonEncode(body));
    request.headers.contentType = ContentType.json;
    request.headers.contentLength = encodedBody.length;
    request.add(encodedBody);

    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join();
    return AppraiseAiHttpResponse(
      statusCode: response.statusCode,
      body: text.trim().isEmpty ? null : jsonDecode(text),
    );
  } finally {
    client.close(force: true);
  }
}
