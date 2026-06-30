// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> readAppraiseImageBytes(String path) async {
  final request = await html.HttpRequest.request(
    path,
    responseType: 'arraybuffer',
  );
  final response = request.response;
  if (response is ByteBuffer) {
    return Uint8List.view(response);
  }
  return null;
}
