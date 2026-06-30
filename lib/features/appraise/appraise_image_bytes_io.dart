import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readAppraiseImageBytes(String path) async {
  final uri = Uri.tryParse(path);
  final isNetwork =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isNetwork) {
    const timeout = Duration(seconds: 20);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } finally {
      client.close(force: true);
    }
  }

  final file = File(uri?.isScheme('file') == true ? uri!.toFilePath() : path);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}
