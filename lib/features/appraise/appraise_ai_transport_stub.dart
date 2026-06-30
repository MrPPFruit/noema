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
  return const AppraiseAiHttpResponse(
    statusCode: 501,
    body: {'error': 'AI networking is not available on this platform.'},
  );
}
