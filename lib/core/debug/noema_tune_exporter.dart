import 'noema_tune_exporter_stub.dart'
    if (dart.library.html) 'noema_tune_exporter_web.dart'
    as exporter;

void exportNoemaTune(String key, String payload) {
  exporter.exportNoemaTune(key, payload);
}
