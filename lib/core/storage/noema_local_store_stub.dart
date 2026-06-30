class NoemaLocalStorePlatform {
  String? _source;

  Future<String?> read() async => _source;

  Future<void> write(String source) async {
    _source = source;
  }

  Future<void> clear() async {
    _source = null;
  }
}
