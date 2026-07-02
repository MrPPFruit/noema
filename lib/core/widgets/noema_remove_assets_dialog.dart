import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_dialog.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';

enum NoemaRemoveChoice { indexOnly, deleteSystemPhoto }

Future<NoemaRemoveChoice?> showNoemaRemoveAssetsDialog({
  required BuildContext context,
  required NoemaPalette palette,
  String? bodyText,
  bool canDeleteSystemPhoto = true,
}) {
  return showDialog<NoemaRemoveChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    builder: (context) => NoemaRemoveAssetsDialog(
      palette: palette,
      bodyText: bodyText,
      canDeleteSystemPhoto: canDeleteSystemPhoto,
      onCancel: () => Navigator.of(context).pop(),
      onRemoveFromSpace: () =>
          Navigator.of(context).pop(NoemaRemoveChoice.indexOnly),
      onRemoveAndDeleteSystemPhoto: () =>
          Navigator.of(context).pop(NoemaRemoveChoice.deleteSystemPhoto),
    ),
  );
}

Future<bool> confirmAndRemoveNoemaAssets({
  required BuildContext context,
  required NoemaPalette palette,
  required ReviewWorkspaceController workspaceController,
  required Set<String> photoIds,
  String? bodyText,
}) async {
  final choice = await showNoemaRemoveAssetsDialog(
    context: context,
    palette: palette,
    bodyText: bodyText,
    canDeleteSystemPhoto: workspaceController.canDeleteSystemMediaForAssetIds(
      photoIds,
    ),
  );
  if (choice == null || !context.mounted) {
    return false;
  }
  return removeNoemaAssetsWithChoice(
    context: context,
    workspaceController: workspaceController,
    photoIds: photoIds,
    choice: choice,
  );
}

Future<bool> removeNoemaAssetsWithChoice({
  required BuildContext context,
  required ReviewWorkspaceController workspaceController,
  required Set<String> photoIds,
  required NoemaRemoveChoice choice,
}) async {
  if (photoIds.isEmpty) {
    return false;
  }
  if (choice == NoemaRemoveChoice.indexOnly) {
    workspaceController.removeAssetsByIds(photoIds, deleteCachedFiles: false);
    return true;
  }

  try {
    return await workspaceController.removeAssetsByIdsAfterSystemDelete(
      photoIds,
    );
  } on NoemaSystemPhotoDeleteUnavailableException {
    if (context.mounted) {
      _showRemoveNotice(
        context,
        NoemaStrings.of(context).removeSystemPhotoUnavailable,
      );
    }
  } on NoemaSystemPhotoDeletePermissionDeniedException {
    if (context.mounted) {
      _showRemoveNotice(
        context,
        NoemaStrings.of(context).removeSystemPhotoPermissionDenied,
      );
    }
  } on MissingPluginException {
    if (context.mounted) {
      _showRemoveNotice(
        context,
        NoemaStrings.of(context).removeSystemPhotoFailed,
      );
    }
  } on PlatformException catch (error) {
    if (!context.mounted || error.code == 'system_media_delete_cancelled') {
      return false;
    }
    final strings = NoemaStrings.of(context);
    if (error.code == 'unsupported_media_uri' ||
        error.code == 'system_media_delete_unsupported') {
      _showRemoveNotice(context, strings.removeSystemPhotoUnavailable);
    } else {
      _showRemoveNotice(context, strings.removeSystemPhotoFailed);
    }
  }
  return false;
}

void _showRemoveNotice(BuildContext context, String message) {
  final messageController = NoemaBackNavigationScope.maybeOf(
    context,
  )?.messageController;
  if (messageController != null) {
    messageController.show(message);
    return;
  }

  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ),
    );
}

class NoemaRemoveAssetsDialog extends StatelessWidget {
  const NoemaRemoveAssetsDialog({
    required this.palette,
    required this.onCancel,
    required this.onRemoveFromSpace,
    required this.onRemoveAndDeleteSystemPhoto,
    this.bodyText,
    this.canDeleteSystemPhoto = true,
    super.key,
  });

  final NoemaPalette palette;
  final String? bodyText;
  final bool canDeleteSystemPhoto;
  final VoidCallback onCancel;
  final VoidCallback onRemoveFromSpace;
  final VoidCallback onRemoveAndDeleteSystemPhoto;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final resolvedBodyText =
        bodyText ??
        (canDeleteSystemPhoto
            ? strings.removeFromJingChoiceBody
            : strings.removeSystemPhotoUnavailable);

    return NoemaDialogPanel(
      panelKey: const ValueKey('noema-remove-assets-dialog-panel'),
      palette: palette,
      title: strings.removeFromJingTitle,
      onClose: onCancel,
      closeTooltip: strings.close,
      body: NoemaDialogText(
        palette: palette,
        text: resolvedBodyText,
        color: palette.muted,
      ),
      actions: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: NoemaDialogButton(
              palette: palette,
              label: strings.removeFromSpaceOnly,
              icon: Icons.link_off_rounded,
              onPressed: onRemoveFromSpace,
            ),
          ),
          if (canDeleteSystemPhoto) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NoemaDialogButton(
                palette: palette,
                label: strings.removeAndDeleteSystemPhoto,
                icon: Icons.delete_outline_rounded,
                tone: NoemaDialogButtonTone.danger,
                onPressed: onRemoveAndDeleteSystemPhoto,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
