class NoemaRoutes {
  const NoemaRoutes._();

  static const home = '/';
  static const import = '/import';
  static const observe = '/observe';
  static const observePhoto = '/observe/photo';
  static const observeAppreciate = '/observe/appreciate';
  static const appraise = '/appraise';
  static const processing = '/processing';
  static const reviewGroups = '/review-groups';
  static const arena = '/arena';
  static const results = '/results';
}

String appraiseRoute({String? photoId}) {
  return Uri(
    path: NoemaRoutes.appraise,
    queryParameters: {
      if (photoId != null && photoId.isNotEmpty) 'photoId': photoId,
    },
  ).toString();
}

int? parseSelectedCount(String? value) {
  final parsed = int.tryParse(value ?? '');
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

String processingRouteWithCount(int count) {
  return Uri(
    path: NoemaRoutes.processing,
    queryParameters: {'count': '$count'},
  ).toString();
}

String appendImportRoute() {
  return Uri(
    path: NoemaRoutes.import,
    queryParameters: {'mode': 'append'},
  ).toString();
}

String observePhotoRoute({required String photoId, required String sort}) {
  return Uri(
    path: NoemaRoutes.observePhoto,
    queryParameters: {'photoId': photoId, 'sort': sort},
  ).toString();
}

String observeAppreciateRoute({
  String? initialPhotoId,
  String? sortMode,
  String? timeSort,
  String? scoreSort,
}) {
  return Uri(
    path: NoemaRoutes.observeAppreciate,
    queryParameters: {
      if (initialPhotoId != null && initialPhotoId.isNotEmpty)
        'photoId': initialPhotoId,
      if (sortMode != null && sortMode.isNotEmpty) 'sortMode': sortMode,
      if (timeSort != null && timeSort.isNotEmpty) 'timeSort': timeSort,
      if (scoreSort != null && scoreSort.isNotEmpty) 'scoreSort': scoreSort,
    },
  ).toString();
}
