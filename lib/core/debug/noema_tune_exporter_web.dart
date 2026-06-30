// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void exportNoemaTune(String key, String payload) {
  html.window.localStorage[key] = payload;
  final existing = html.document.getElementById(key);
  final element = existing ?? html.MetaElement();
  element.id = key;
  element.setAttribute('data-value', payload);
  if (existing == null) {
    html.document.head?.append(element);
  }
}
