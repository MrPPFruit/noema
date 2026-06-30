// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

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
  final request = html.HttpRequest();
  request.open('POST', uri.toString());
  for (final entry in headers.entries) {
    request.setRequestHeader(entry.key, entry.value);
  }
  request.send(jsonEncode(body));
  await request.onLoadEnd.first.timeout(const Duration(seconds: 45));

  final text = request.responseText;
  return AppraiseAiHttpResponse(
    statusCode: request.status ?? 0,
    body: _decodeBody(text) ?? const {'error': '浏览器未收到响应，可能是网络或跨域限制。'},
  );
}

Object? _decodeBody(String? text) {
  if (text == null || text.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}
