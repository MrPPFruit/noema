import 'noema_cached_file_deleter_stub.dart'
    if (dart.library.io) 'noema_cached_file_deleter_io.dart'
    as impl;

Future<int> deleteNoemaLocalCachedFiles(Iterable<String> paths) {
  return impl.deleteNoemaLocalCachedFiles(paths);
}
