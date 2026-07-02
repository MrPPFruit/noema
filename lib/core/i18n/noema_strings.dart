import 'package:flutter/widgets.dart';
import 'package:noema/core/models/analysis_result.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/models/similar_group.dart';

class NoemaStrings {
  const NoemaStrings._(this.locale);

  factory NoemaStrings.of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return NoemaStrings._(locale.languageCode == 'zh' ? 'zh' : 'en');
  }

  final String locale;

  bool get isZh => locale == 'zh';

  String get appName => 'Noema';
  String get homeValueLine => isZh
      ? '整理一组照片，留下真正值得保留的。'
      : 'Start with a set of photos. Keep what matters.';
  String get startReview => isZh ? '创建境' : 'Create a space';
  String get recentSessions => isZh ? '最近整理' : 'Recent sessions';
  String get emptyRecentSessions =>
      isZh ? '创建一个境，把照片先带进来。' : 'Create a space and bring photos in.';

  String get back => isZh ? '返回' : 'Back';
  String get backAgainToExit => '再返回一次，退出 Noema';
  String get createJing => isZh ? '创建境' : 'Create space';
  String get remove => isZh ? '移除' : 'Remove';
  String get removeFromSpaceOnly =>
      isZh ? '只从此境移除' : 'Remove from this space only';
  String get removeAndDeleteSystemPhoto =>
      isZh ? '删除手机相册原图' : 'Delete from photo library';
  String get close => isZh ? '关闭' : 'Close';
  String get importAddPhotos => isZh ? '添加照片' : 'Add photos';
  String get importAppendPhotos => isZh ? '添入此境' : 'Add to this space';
  String get jingNameHint => isZh ? '为境命名' : 'Name this space';
  String get nameRequiredTitle => isZh ? '先为境命名' : 'Name this space first';
  String get importPurpose => isZh ? '让照片入境' : 'Let photos enter';
  String get importAppendPurpose => isZh ? '添入此境' : 'Add to this space';
  String importPhotoCount(int count) => isZh
      ? '$count 张'
      : count == 1
      ? '1 photo'
      : '$count photos';
  String importExistingPhotoCount(int count) => isZh
      ? '$count 张已在此境'
      : count == 1
      ? '1 photo already here'
      : '$count photos already here';
  String importThisTimeCount(int count) => isZh
      ? '本次 $count 张'
      : count == 1
      ? '1 new photo'
      : '$count new photos';
  String importSelectedCount(int count) => isZh
      ? '已选 $count 张'
      : count == 1
      ? '1 selected'
      : '$count selected';
  String get openingLibrary => isZh ? '正在打开相册' : 'Opening library';
  String get importingPhotos => isZh ? '正在带入照片' : 'Bringing photos in';
  String get importNoPhotosSelected => isZh ? '还没有选择照片' : 'No photos selected';
  String get importPickerError =>
      isZh ? '没能打开相册' : 'Noema could not open the photo picker';
  String get importGalleryPermissionDenied =>
      isZh ? '需要先允许访问图库' : 'Photo library access is required first';
  String get importDuplicateSkipped =>
      isZh ? '已略过重复照片' : 'Duplicate photos were skipped';
  String get importUnavailableSkipped =>
      isZh ? '已略过无法读取的照片' : 'Unreadable photos were skipped';
  String importLargeSpaceWarning(int limit) => isZh
      ? '此境已超过 $limit 张，建议拆成多个境'
      : 'This space has over $limit photos. Splitting it is recommended.';
  String importPhotoLimitReached(int limit) => isZh
      ? '单个境最多先支持 $limit 张'
      : 'A single space currently supports up to $limit photos.';
  String get removeFromJingTitle => isZh ? '从此境移除' : 'Remove from this space?';
  String get removeFromJingBody =>
      isZh ? '原照片仍在系统相册中' : 'Original photos stay in your photo library.';
  String get removeFromJingChoiceBody => isZh
      ? '可以只从此境移除；也可以先通过系统确认删除手机相册原图，确认成功后 Noema 会同步移除。'
      : 'Remove only from this space, or use the system confirmation to delete the original photo and then remove it from Noema.';
  String get removeSystemPhotoUnavailable => isZh
      ? '有些照片不是可删除的系统相册项目，暂时只能从 Noema 移除。'
      : 'Some photos are not deletable system library items. Remove them from Noema only for now.';
  String get removeSystemPhotoPermissionDenied => isZh
      ? '需要先允许访问图库，才能删除手机相册原图。'
      : 'Photo library access is required before deleting the original photo.';
  String get removeSystemPhotoFailed => isZh
      ? '系统没有完成删除，照片仍保留在 Noema。'
      : 'The system did not complete deletion, so the photo stays in Noema.';

  String get processingTitle => isZh ? '正在整理' : 'Processing';
  String get readingPhotoDetails => isZh ? '正在读取照片信息' : 'Reading photo details';
  String selectedPhotoCount(int count) => isZh
      ? '正在整理 $count 张照片'
      : count == 1
      ? 'Reviewing 1 selected photo'
      : 'Reviewing $count selected photos';
  String get selectedPreview => isZh ? '已选预览' : 'Selected preview';
  String get buildThumbnails => isZh ? '正在生成缩略图' : 'Building thumbnails';
  String get findSimilarShots => isZh ? '正在寻找相似照片' : 'Finding similar shots';
  String get checkBlurExposure =>
      isZh ? '正在检查模糊和曝光' : 'Checking blur and exposure';
  String get localAnalysis =>
      isZh ? '这些分析在本机完成' : 'This review happens on your device';
  String get noAlbumChanges =>
      isZh ? '不会改动你的相册' : 'No changes are made to your photo library';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get viewReviewGroups => isZh ? '查看相似组' : 'View review groups';

  String observePhotoCount(int count) => isZh
      ? '$count 张'
      : count == 1
      ? '1 photo'
      : '$count photos';
  String get observeEmptyTitle => isZh ? '还没有照片' : 'No photos yet';
  String get observeSortTimeAscending => isZh ? '时间正序' : 'Time ascending';
  String get observeSortTimeDescending => isZh ? '时间倒序' : 'Time descending';
  String get observeDensityCompact => isZh ? '紧凑墙' : 'Compact wall';
  String get observeDensityBalanced => isZh ? '标准墙' : 'Balanced wall';
  String get observeDensitySpacious => isZh ? '大图墙' : 'Large wall';
  String observeDensityTooltip(String value) =>
      isZh ? '密度 $value' : 'Density $value';
  String get observeEditName => isZh ? '修改境名' : 'Rename space';
  String get observeSaveName => isZh ? '保存境名' : 'Save name';
  String get observeCancelNameEdit => isZh ? '取消改名' : 'Cancel rename';
  String get observeMissingAssetsTooltip =>
      isZh ? '照片索引提醒' : 'Missing photo indexes';
  String observeMissingAssetsTitle(int count) => isZh
      ? '$count 张照片找不到了'
      : count == 1
      ? '1 photo cannot be found'
      : '$count photos cannot be found';
  String get observeMissingAssetsBody => isZh
      ? '这些照片可能已在 Noema 外被移动或删除。原文件不在 Noema 内，当前只会处理此境里的索引记录。'
      : 'These photos may have been moved or deleted outside Noema. Noema will only update this space index.';
  String get observeClearMissingIndexes =>
      isZh ? '清除相关索引' : 'Clear related indexes';
  String get observeDistill => isZh ? '甄' : 'Cull';
  String get observeAppraise => isZh ? '鉴' : 'Rate';
  String get observeAppreciate => isZh ? '赏' : 'View';

  String get appraiseTitle => isZh ? '全境评鉴' : 'Space appraisal';
  String get appraiseSingleTitle => isZh ? '单张评鉴' : 'Single appraisal';
  String get appraiseProgress => isZh ? '待鉴' : 'To appraise';
  String get appraiseValue => isZh ? '价值' : 'Value';
  String get appraiseReasons => isZh ? '理由' : 'Reasons';
  String get appraiseNoteTitle => isZh ? '鉴语' : 'Note';
  String get appraiseQueue => isZh ? '照片队列' : 'Queue';
  String get appraiseKeepHigh => isZh ? '珍藏' : 'Treasure';
  String get appraiseKeep => isZh ? '留存' : 'Keep';
  String get appraiseLater => isZh ? '待看' : 'Revisit';
  String get appraiseConfirm => isZh ? '记下判断' : 'Commit appraisal';
  String get appraiseNext => isZh ? '下一张' : 'Next';
  String get appraisePrevious => isZh ? '上一张' : 'Previous';
  String get appraiseDone => isZh ? '已鉴' : 'Done';

  String get reviewGroupsTitle => isZh ? '相似组复核' : 'Review groups';
  String get cullFastMode => isZh ? '快甄' : 'Quick cull';
  String get cullCompareMode => isZh ? '对照甄' : 'Compare cull';
  String get cullDiscardTarget => isZh ? '丢弃' : 'Discard';
  String get cullKeepTarget => isZh ? '保留' : 'Keep';
  String get cullClearOut => isZh ? '清除出境' : 'Clear out';
  String get cullClearCompletedOut =>
      isZh ? '删除已完成丢弃' : 'Delete completed discards';
  String get cullDeleteLocal => isZh ? '删除本地数据' : 'Delete local data';
  String get cullClearOutTitle => isZh ? '处理出境照片' : 'Clear outbound photos';
  String get cullGroupComplete => isZh ? '这组已完成' : 'This group is complete';
  String get cullReturnToGroups => isZh ? '返回甄页面' : 'Back to cull';
  String get cullNextUnfinished => isZh ? '下一组未完成' : 'Next unfinished group';
  String get cullAllGroupsComplete => isZh ? '全部已完成' : 'All groups complete';
  String cullClearConfirm(int count) => isZh
      ? '将处理 $count 张出境照片。可只从此境移除，也可通过系统确认删除手机相册原图。'
      : count == 1
      ? 'Handle 1 outbound photo. Remove it only from this space or delete the original through system confirmation.'
      : 'Handle $count outbound photos. Remove them only from this space or delete originals through system confirmation.';
  String get cullClearCompletedTitle =>
      isZh ? '处理已完成丢弃' : 'Clear completed discards';
  String cullClearCompletedConfirm(int count) => isZh
      ? '将处理已完成组中标记丢弃的 $count 张照片。可只从此境移除，也可通过系统确认删除手机相册原图。'
      : count == 1
      ? 'Handle 1 discarded photo from completed groups. Remove it only from this space or delete the original through system confirmation.'
      : 'Handle $count discarded photos from completed groups. Remove them only from this space or delete originals through system confirmation.';
  String get cullClearCompletedEmpty => isZh
      ? '当前没有已完成组中标记丢弃的照片。'
      : 'No discarded photos in completed groups right now.';
  String get noActiveReview =>
      isZh ? '选择一组照片开始整理。' : 'Choose a set of photos to start a review.';
  String similarPhotoCount(int count) =>
      isZh ? '$count 张相似照片' : '$count similar photos';
  String groupReason(GroupReason reason) => switch (reason) {
    GroupReason.burst =>
      isZh
          ? '这些照片拍摄时间很接近。'
          : 'Photos captured close together. Pick what matters.',
    GroupReason.nearDuplicate =>
      isZh
          ? '这组照片很相似，建议选出最值得保留的照片。'
          : 'These photos are similar. Pick the ones worth keeping.',
    GroupReason.timeCluster =>
      isZh ? '这一组适合一起复核。' : 'Review this set together.',
    GroupReason.needsAttention =>
      isZh
          ? '有些照片可能需要你多看一眼再决定。'
          : 'Some photos may need a closer look before deciding.',
  };
  String attentionHint(String hints) => isZh ? '提示：$hints' : 'Hint: $hints';
  String qualityFlag(QualityFlag flag) => switch (flag) {
    QualityFlag.possibleBlur => isZh ? '可能模糊' : 'possible blur',
    QualityFlag.dark => isZh ? '偏暗' : 'dark',
    QualityFlag.overexposed => isZh ? '过曝' : 'overexposed',
    QualityFlag.highlightRisk => isZh ? '高光风险' : 'highlight risk',
    QualityFlag.screenshot => isZh ? '截图' : 'screenshot',
    QualityFlag.video => isZh ? '视频' : 'video',
    QualityFlag.livePhoto => isZh ? 'Live Photo' : 'live photo',
    QualityFlag.raw => 'RAW',
    QualityFlag.unavailable => isZh ? '不可用' : 'unavailable',
    QualityFlag.unsupportedType => isZh ? '暂不支持的类型' : 'unsupported type',
  };
  String get review => isZh ? '复核' : 'Review';

  String get arenaTitle => isZh ? '对比选择' : 'A/B Arena';
  String get noCullGroups => isZh
      ? '当前境内暂无可甄选的相似照片'
      : 'No similar photos to cull in this space right now.';
  String get noActiveGroup =>
      isZh ? '当前没有可复核的相似组。' : 'No active group. Start from review groups.';
  String get decisionPrompt => isZh
      ? '先为照片 A 做决定，之后可以再调整。'
      : 'Choose a decision for photo A. You can adjust decisions later.';
  String decisionLabel(Decision decision) => switch (decision) {
    Decision.keep => isZh ? '保留' : 'Keep',
    Decision.maybe => isZh ? '待定' : 'Maybe',
    Decision.reviewForRemoval => isZh ? '建议复核' : 'Review for removal',
  };
  String get keepBoth => isZh ? '两张都保留' : 'Keep both';
  String get skipPair => isZh ? '跳过这组' : 'Skip pair';
  String get finishGroup => isZh ? '完成这组' : 'Finish group';
  String get noPair => isZh ? '没有可对比照片' : 'No pair';

  String get resultsTitle => isZh ? '整理结果' : 'Results';
  String get resultsGenerated => isZh ? '整理建议已生成。' : 'Review notes are ready.';
  String get resultsBoundaryCopy => isZh
      ? 'Noema 还没有改动你的相册，这里只是整理建议。'
      : 'Noema has not changed your photo library. These are review notes only.';
  String photoCount(int count) => isZh
      ? '$count 张照片'
      : count == 1
      ? '1 photo'
      : '$count photos';
  String get stillUndecided => isZh ? '尚未决定' : 'Still undecided';
  String get reviewGroupsAgain => isZh ? '重新复核相似组' : 'Review groups again';
}
