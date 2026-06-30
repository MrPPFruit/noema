// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class NoemaLocalStorePlatform {
  static const String _key = 'noema.workspace_store.v1';

  Future<String?> read() async {
    return html.window.localStorage[_key];
  }

  Future<void> write(String source) async {
    html.window.localStorage[_key] = source;
  }

  Future<void> clear() async {
    html.window.localStorage.remove(_key);
  }
}
