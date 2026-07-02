import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_dialog.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';
import 'package:noema/core/widgets/noema_message.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/gallery_asset_picker.dart';
import 'package:noema/features/import/gallery_import_cache.dart';
import 'package:noema/features/import/import_analysis_source.dart';
import 'package:noema/features/import/import_image_source.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

const _createJingHeroTag = 'noema-create-jing-action';
const _gsapPowerOut = Cubic(0.16, 1, 0.3, 1);
const _importAppendBatchSize = 4;
const _importAppendFrameGap = Duration(milliseconds: 12);
const _metadataHydrationConcurrency = 3;
const _thumbnailHydrationConcurrency = 3;
const _importThumbnailMaxSize = 320;
const _importPreviewMaxSize = 3072;
const _importPreviewDecodeMaxExtent = 3072;
const _importGridTopFadeHeight = 48.0;
const _importGridBottomFadeHeight = 128.0;
const _importGridTopPadding = 52.0;
const _importGridBottomPadding = 152.0;
const _importActionRight = 24.0;
const _importActionBottom = 32.0;
const _importActionHitWidth = 84.0;
const _importActionHitHeight = 92.0;
const _nameRequiredHintGap = 14.0;
const _nameRequiredHintMaxWidth = 128.0;
const _nameRequiredHintRight =
    _importActionRight +
    (_importActionHitWidth - _nameRequiredHintMaxWidth) / 2;
const _nameRequiredHintBottom =
    _importActionBottom + _importActionHitHeight + _nameRequiredHintGap;

enum _ImportMessage {
  noPhotosSelected,
  pickerError,
  galleryPermissionDenied,
  duplicateSkipped,
  unavailableSkipped,
  largeSpaceWarning,
  photoLimitReached,
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    required this.workspaceController,
    super.key,
    this.appearanceController,
    this.pickAssets = pickGalleryAssets,
    this.appendMode = false,
  });

  final ReviewWorkspaceController workspaceController;
  final NoemaAppearanceController? appearanceController;
  final GalleryAssetPicker pickAssets;
  final bool appendMode;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final List<SelectedGalleryAsset> _assets = [];
  final Set<String> _selectedIds = {};
  final Set<String> _metadataPendingIds = {};
  final Set<String> _thumbnailPendingIds = {};

  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;

  Timer? _nameHintTimer;
  bool _isPicking = false;
  bool _showNameRequiredHint = false;
  _ImportMessage? _message;
  SelectedGalleryAsset? _previewAsset;
  NoemaBackNavigationController? _backNavigationController;
  VoidCallback? _unregisterBackHandler;

  String get _jingName => _nameController.text.trim();
  bool get _hasName => _jingName.isNotEmpty;
  bool get _canCreate => _hasName && _assets.isNotEmpty;
  bool get _canComplete =>
      (widget.appendMode ? _assets.isNotEmpty : _canCreate) &&
      !_isPreparingMedia;
  bool get _selecting => _selectedIds.isNotEmpty;
  bool get _isPreparingMedia =>
      _metadataPendingIds.isNotEmpty || _thumbnailPendingIds.isNotEmpty;
  int get _existingImportPhotoCount => widget.appendMode
      ? widget.workspaceController.workspace.assets.length
      : 0;
  int get _stagedImportPhotoCount => _existingImportPhotoCount + _assets.length;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    _nameController.addListener(() {
      if (_showNameRequiredHint && _hasName) {
        _nameHintTimer?.cancel();
        setState(() {
          _showNameRequiredHint = false;
        });
        return;
      }
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = NoemaBackNavigationScope.maybeOf(context);
    if (controller == _backNavigationController) {
      return;
    }
    _unregisterBackHandler?.call();
    _backNavigationController = controller;
    _unregisterBackHandler = controller?.registerLocalBackHandler(
      _handleLocalBackIntent,
    );
  }

  @override
  void dispose() {
    _unregisterBackHandler?.call();
    _nameHintTimer?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    super.dispose();
  }

  bool _handleLocalBackIntent() {
    if (_previewAsset != null) {
      setState(() => _previewAsset = null);
      return true;
    }
    if (_selecting) {
      setState(() => _selectedIds.clear());
      return true;
    }
    if (_nameFocusNode.hasFocus) {
      _nameFocusNode.unfocus();
      return true;
    }
    return false;
  }

  Future<void> _chooseFromLibrary() async {
    if (_isPicking) {
      return;
    }

    setState(() {
      _isPicking = true;
      _message = null;
    });

    try {
      final pickedAssets = await widget.pickAssets(context);
      if (!mounted) {
        return;
      }

      if (pickedAssets.isEmpty) {
        setState(() {
          _isPicking = false;
          _message = _assets.isEmpty ? _ImportMessage.noPhotosSelected : null;
        });
        return;
      }

      final appendedAssets = await _appendPickedAssetsProgressively(
        pickedAssets,
      );
      unawaited(_hydrateMetadata(appendedAssets));
      unawaited(_hydrateThumbnails(appendedAssets));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPicking = false;
        _message = error is NoemaGalleryAccessDeniedException
            ? _ImportMessage.galleryPermissionDenied
            : _ImportMessage.pickerError;
      });
    }
  }

  Future<List<SelectedGalleryAsset>> _appendPickedAssetsProgressively(
    List<SelectedGalleryAsset> pickedAssets,
  ) async {
    final knownIds = {
      for (final asset in _assets) asset.id,
      if (widget.appendMode)
        for (final asset in widget.workspaceController.workspace.assets)
          asset.photo.platformAssetId,
    };
    final appendedAssets = <SelectedGalleryAsset>[];
    var skippedDuplicate = false;
    var skippedUnavailable = false;
    var skippedForLimit = false;
    var index = 0;
    final startingPhotoCount = _stagedImportPhotoCount;

    while (index < pickedAssets.length) {
      if (!mounted) {
        return appendedAssets;
      }

      final batch = <SelectedGalleryAsset>[];
      while (index < pickedAssets.length &&
          batch.length < _importAppendBatchSize) {
        final asset = pickedAssets[index];
        index += 1;
        if (asset.previewUnavailable) {
          skippedUnavailable = true;
          continue;
        }
        if (!knownIds.add(asset.id)) {
          skippedDuplicate = true;
          continue;
        }
        final nextPhotoCount = startingPhotoCount + appendedAssets.length + 1;
        if (nextPhotoCount > noemaWorkspaceHardPhotoLimit) {
          skippedForLimit = true;
          continue;
        }
        batch.add(asset);
        appendedAssets.add(asset);
      }

      if (batch.isNotEmpty) {
        setState(() {
          _assets.addAll(batch);
          _message = null;
        });
      }

      if (index < pickedAssets.length) {
        await Future<void>.delayed(_importAppendFrameGap);
      }
    }

    if (!mounted) {
      return appendedAssets;
    }

    setState(() {
      _isPicking = false;
      _message = skippedForLimit
          ? _ImportMessage.photoLimitReached
          : skippedUnavailable
          ? _ImportMessage.unavailableSkipped
          : skippedDuplicate
          ? _ImportMessage.duplicateSkipped
          : startingPhotoCount + appendedAssets.length >=
                noemaWorkspaceSoftPhotoLimit
          ? _ImportMessage.largeSpaceWarning
          : null;
    });
    return appendedAssets;
  }

  Future<void> _hydrateMetadata(List<SelectedGalleryAsset> pickedAssets) async {
    final targets = [
      for (final asset in pickedAssets)
        if (asset.sourceUri != null && !asset.previewUnavailable) asset,
    ];
    if (targets.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _metadataPendingIds.addAll(targets.map((asset) => asset.id));
      });
    }

    const mediaPicker = NoemaMediaPicker();
    var nextIndex = 0;

    Future<void> hydrateNext() async {
      while (mounted) {
        if (nextIndex >= targets.length) {
          return;
        }

        final asset = targets[nextIndex];
        nextIndex += 1;
        final sourceUri = asset.sourceUri;
        if (sourceUri == null) {
          _markMetadataHydrated(asset.id);
          continue;
        }

        SelectedGalleryAsset? metadata;
        try {
          metadata = await mediaPicker.loadMetadata(uri: sourceUri);
        } catch (_) {
          metadata = null;
        }

        if (!mounted) {
          return;
        }

        _markMetadataHydrated(asset.id, metadata: metadata);
      }
    }

    final workerCount = math.min(_metadataHydrationConcurrency, targets.length);
    await Future.wait([
      for (var index = 0; index < workerCount; index++) hydrateNext(),
    ]);
  }

  Future<void> _hydrateThumbnails(
    List<SelectedGalleryAsset> pickedAssets,
  ) async {
    final targets = [
      for (final asset in pickedAssets)
        if (!asset.previewUnavailable &&
            asset.analysisBytes == null &&
            (asset.sourceUri != null || asset.thumbnailPath != null))
          asset,
    ];
    if (targets.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _thumbnailPendingIds.addAll(targets.map((asset) => asset.id));
      });
    }

    const mediaPicker = NoemaMediaPicker();
    var nextIndex = 0;

    Future<void> hydrateNext() async {
      while (mounted) {
        if (nextIndex >= targets.length) {
          return;
        }

        final asset = targets[nextIndex];
        nextIndex += 1;
        final sourceUri = asset.sourceUri;

        var thumbnailPath = asset.thumbnailPath;
        if (thumbnailPath == null && sourceUri == null) {
          _markThumbnailHydrated(asset.id);
          continue;
        }
        if (thumbnailPath == null && sourceUri != null) {
          try {
            thumbnailPath = await mediaPicker.createThumbnail(
              uri: sourceUri,
              maxSize: _importThumbnailMaxSize,
            );
          } catch (_) {
            thumbnailPath = null;
          }
        }
        if (thumbnailPath != null && sourceUri == null) {
          final persistedPath = await persistGalleryImportFile(
            XFile(thumbnailPath, name: asset.name),
          );
          if (persistedPath != null && persistedPath.isNotEmpty) {
            thumbnailPath = persistedPath;
          }
        }
        final analysisBytes = await loadImportAnalysisBytes(thumbnailPath);

        if (!mounted) {
          return;
        }

        _markThumbnailHydrated(
          asset.id,
          thumbnailPath: thumbnailPath,
          analysisBytes: analysisBytes,
        );
      }
    }

    final workerCount = math.min(
      _thumbnailHydrationConcurrency,
      targets.length,
    );
    await Future.wait([
      for (var index = 0; index < workerCount; index++) hydrateNext(),
    ]);
  }

  void _markMetadataHydrated(String assetId, {SelectedGalleryAsset? metadata}) {
    if (!mounted) {
      return;
    }

    setState(() {
      final index = _assets.indexWhere((item) => item.id == assetId);
      if (index != -1 && metadata != null) {
        final current = _assets[index];
        _assets[index] = current.copyWith(
          name: metadata.name,
          width: metadata.width,
          height: metadata.height,
          createdAt: metadata.createdAt,
          updatedAt: metadata.updatedAt,
          mimeType: metadata.mimeType,
          fileSize: metadata.fileSize,
          exif: metadata.exif,
        );
      }
      _metadataPendingIds.remove(assetId);
    });
  }

  void _markThumbnailHydrated(
    String assetId, {
    String? thumbnailPath,
    Uint8List? analysisBytes,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      final index = _assets.indexWhere((item) => item.id == assetId);
      if (index != -1 && (thumbnailPath != null || analysisBytes != null)) {
        _assets[index] = _assets[index].copyWith(
          thumbnailPath: thumbnailPath,
          analysisBytes: analysisBytes,
        );
      }
      _thumbnailPendingIds.remove(assetId);
    });
  }

  Future<void> _confirmRemoveSelected() async {
    final palette = NoemaPalette.fromTone(
      _appearanceController.resolveTone(context),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (context) => _RemoveDialog(
        palette: palette,
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _assets.removeWhere((asset) => _selectedIds.contains(asset.id));
      _metadataPendingIds.removeAll(_selectedIds);
      _thumbnailPendingIds.removeAll(_selectedIds);
      _selectedIds.clear();
    });
  }

  void _toggleSelection(SelectedGalleryAsset asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  void _startSelection(SelectedGalleryAsset asset) {
    setState(() {
      _selectedIds.add(asset.id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _revealNameRequiredHint() {
    _nameHintTimer?.cancel();
    setState(() {
      _showNameRequiredHint = true;
    });
    _nameFocusNode.requestFocus();
    _nameHintTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showNameRequiredHint = false;
      });
    });
  }

  void _completeImport() {
    if (!_canComplete) {
      return;
    }

    final result = widget.appendMode
        ? widget.workspaceController.appendSelectedAssets(_assets)
        : widget.workspaceController.loadSelectedAssets(
            _assets,
            name: _jingName,
          );
    if (result == ReviewWorkspaceImportResult.tooManyPhotos) {
      setState(() => _message = _ImportMessage.photoLimitReached);
      return;
    }
    if (result == ReviewWorkspaceImportResult.empty) {
      setState(() => _message = _ImportMessage.noPhotosSelected);
      return;
    }
    context.go(NoemaRoutes.observe);
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final message = switch (_message) {
      _ImportMessage.noPhotosSelected => strings.importNoPhotosSelected,
      _ImportMessage.pickerError => strings.importPickerError,
      _ImportMessage.galleryPermissionDenied =>
        strings.importGalleryPermissionDenied,
      _ImportMessage.duplicateSkipped => strings.importDuplicateSkipped,
      _ImportMessage.unavailableSkipped => strings.importUnavailableSkipped,
      _ImportMessage.largeSpaceWarning => strings.importLargeSpaceWarning(
        noemaWorkspaceSoftPhotoLimit,
      ),
      _ImportMessage.photoLimitReached => strings.importPhotoLimitReached(
        noemaWorkspaceHardPhotoLimit,
      ),
      null => null,
    };

    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final palette = NoemaPalette.fromTone(
          _appearanceController.resolveTone(context),
        );
        final sceneLayout = NoemaSceneMetrics.layoutOf(context);
        final topBarTop = sceneLayout.topBarTop;
        final topShift = sceneLayout.topSafeShift;

        return Scaffold(
          body: NoemaSceneFrame(
            palette: palette,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: sceneLayout.markLeft,
                  top: NoemaSceneMetrics.markTop,
                  child: NoemaThemeMark(palette: palette, mark: '入'),
                ),
                Positioned(
                  left: sceneLayout.topBarInset,
                  right: sceneLayout.topBarInset,
                  top: topBarTop,
                  child: _ImportTopBar(
                    palette: palette,
                    selecting: _selecting,
                    onBack: () => context.go(
                      widget.appendMode
                          ? NoemaRoutes.observe
                          : NoemaRoutes.home,
                    ),
                  ),
                ),
                Positioned(
                  left: sceneLayout.sideInset,
                  right: sceneLayout.sideInset,
                  top: 94 + topShift,
                  bottom: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.appendMode)
                        _AppendSpaceSummary(
                          palette: palette,
                          name:
                              widget.workspaceController.workspace.session.name,
                          count: widget
                              .workspaceController
                              .workspace
                              .session
                              .totalCount,
                        )
                      else
                        _JingNameField(
                          palette: palette,
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                        ),
                      const SizedBox(height: 16),
                      _ImportPurpose(
                        palette: palette,
                        count: _assets.length,
                        message: message,
                        isPicking: _isPicking,
                        isPreparingMedia: _isPreparingMedia,
                        selecting: _selecting,
                        appendMode: widget.appendMode,
                        onClearSelection: _clearSelection,
                        onRemoveSelected: _confirmRemoveSelected,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _assets.isEmpty
                            ? const SizedBox.shrink()
                            : _ImportGrid(
                                palette: palette,
                                assets: _assets,
                                selectedIds: _selectedIds,
                                onPreview: (asset) {
                                  setState(() => _previewAsset = asset);
                                },
                                onLongPress: _startSelection,
                                onToggleSelection: _toggleSelection,
                              ),
                      ),
                    ],
                  ),
                ),
                if (!_selecting)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 32,
                    child: Center(
                      child: Hero(
                        tag: _createJingHeroTag,
                        child: NoemaFloatingActionButton(
                          palette: palette,
                          tooltip: strings.importAddPhotos,
                          enabled: !_isPicking,
                          onPressed: _isPicking ? null : _chooseFromLibrary,
                          child: Icon(
                            _isPicking
                                ? Icons.hourglass_empty_rounded
                                : Icons.add_photo_alternate_outlined,
                            size: _isPicking ? 28 : 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_selecting && _assets.isNotEmpty)
                  Positioned(
                    right: _nameRequiredHintRight,
                    bottom: _nameRequiredHintBottom,
                    width: _nameRequiredHintMaxWidth,
                    child: IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        reverseDuration: const Duration(milliseconds: 150),
                        switchInCurve: _gsapPowerOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation);
                          final scale = Tween<double>(
                            begin: 0.96,
                            end: 1,
                          ).animate(animation);

                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: scale,
                              alignment: Alignment.bottomCenter,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: _showNameRequiredHint
                            ? Center(
                                key: const ValueKey('name-required-hint'),
                                child: _NameRequiredHint(
                                  palette: palette,
                                  text: strings.nameRequiredTitle,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('name-required-empty'),
                              ),
                      ),
                    ),
                  ),
                if (!_selecting && _assets.isNotEmpty)
                  Positioned(
                    right: _importActionRight,
                    bottom: _importActionBottom,
                    child: SizedBox(
                      key: const ValueKey('create-jing-action-anchor'),
                      width: _importActionHitWidth,
                      height: _importActionHitHeight,
                      child: NoemaFloatingActionButton(
                        palette: palette,
                        tooltip: widget.appendMode
                            ? strings.importAppendPhotos
                            : strings.createJing,
                        enabled: _canComplete,
                        onDisabledPressed: widget.appendMode || _hasName
                            ? null
                            : _revealNameRequiredHint,
                        onPressed: _canComplete ? _completeImport : null,
                        child: const Icon(Icons.check_rounded, size: 32),
                      ),
                    ),
                  ),
                if (_previewAsset != null)
                  _PhotoPreview(
                    palette: palette,
                    asset: _previewAsset!,
                    onClose: () {
                      setState(() => _previewAsset = null);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImportTopBar extends StatelessWidget {
  const _ImportTopBar({
    required this.palette,
    required this.selecting,
    required this.onBack,
  });

  final NoemaPalette palette;
  final bool selecting;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final foreground = palette.ink;

    return SizedBox(
      height: NoemaSceneMetrics.topBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!selecting)
            Align(
              alignment: Alignment.centerLeft,
              child: _GlassIconButton(
                visualKey: const ValueKey('import-back-button-visual'),
                palette: palette,
                tooltip: strings.back,
                icon: Icons.arrow_back_ios_new_rounded,
                onPressed: onBack,
              ),
            ),
          AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 140),
            child: Center(
              child: NoemaWordmark(color: foreground, text: strings.appName),
            ),
          ),
        ],
      ),
    );
  }
}

class _JingNameField extends StatelessWidget {
  const _JingNameField({
    required this.palette,
    required this.controller,
    required this.focusNode,
  });

  final NoemaPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    const displayFont = 'LXGWWenKaiGB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              TextField(
                key: const ValueKey('import-name-input'),
                focusNode: focusNode,
                controller: controller,
                maxLength: 10,
                inputFormatters: [LengthLimitingTextInputFormatter(10)],
                cursorColor: controller.text.isEmpty
                    ? Colors.transparent
                    : palette.ink,
                style: TextStyle(
                  color: palette.ink,
                  fontFamily: displayFont,
                  fontSize: 30,
                  height: 1.08,
                  letterSpacing: 0,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.text.isNotEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    child: _EmptyNameHint(
                      palette: palette,
                      text: strings.jingNameHint,
                      fontFamily: displayFont,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return Text(
              '${value.text.characters.length}/10',
              style: TextStyle(color: palette.muted, fontSize: 12, height: 1),
            );
          },
        ),
      ],
    );
  }
}

class _AppendSpaceSummary extends StatelessWidget {
  const _AppendSpaceSummary({
    required this.palette,
    required this.name,
    required this.count,
  });

  final NoemaPalette palette;
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return SizedBox(
      height: 58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontFamily: 'LXGWWenKaiGB',
                  fontSize: 30,
                  height: 1.08,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.importExistingPhotoCount(count),
            style: TextStyle(
              color: palette.muted,
              fontFamily: _fontForText(strings.importExistingPhotoCount(count)),
              fontSize: 12,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNameHint extends StatelessWidget {
  const _EmptyNameHint({
    required this.palette,
    required this.text,
    required this.fontFamily,
  });

  final NoemaPalette palette;
  final String text;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: palette.ink.withValues(alpha: 0.35),
      fontFamily: fontFamily,
      fontSize: 30,
      height: 1.08,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(text, style: style),
                  const SizedBox(width: 7),
                  Transform.translate(
                    offset: const Offset(0, -1),
                    child: _BlinkingCursor(
                      color: palette.ink.withValues(alpha: 0.46),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});

  final Color color;

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.18, end: 1).animate(_controller),
      child: Container(
        width: 1.4,
        height: 29,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ImportPurpose extends StatelessWidget {
  const _ImportPurpose({
    required this.palette,
    required this.count,
    required this.message,
    required this.isPicking,
    required this.isPreparingMedia,
    required this.selecting,
    required this.appendMode,
    required this.onClearSelection,
    required this.onRemoveSelected,
  });

  final NoemaPalette palette;
  final int count;
  final String? message;
  final bool isPicking;
  final bool isPreparingMedia;
  final bool selecting;
  final bool appendMode;
  final VoidCallback onClearSelection;
  final VoidCallback onRemoveSelected;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final text =
        message ??
        (appendMode ? strings.importAppendPurpose : strings.importPurpose);
    final countText = appendMode
        ? strings.importThisTimeCount(count)
        : strings.importPhotoCount(count);

    return SizedBox(
      height: 42,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        child: selecting
            ? _SelectionActionStrip(
                key: const ValueKey('selection-actions'),
                palette: palette,
                onClearSelection: onClearSelection,
                onRemoveSelected: onRemoveSelected,
              )
            : Stack(
                key: const ValueKey('import-purpose-summary'),
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    child: Text(
                      isPicking
                          ? strings.openingLibrary
                          : isPreparingMedia
                          ? strings.importingPhotos
                          : text,
                      key: ValueKey(
                        'import-purpose-copy-$isPicking-$isPreparingMedia-$text',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.muted,
                        fontFamily: 'LXGWWenKaiGB',
                        fontSize: 14,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      countText,
                      style: TextStyle(
                        color: palette.muted,
                        fontFamily: _fontForText(countText),
                        fontSize: 12,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SelectionActionStrip extends StatelessWidget {
  const _SelectionActionStrip({
    super.key,
    required this.palette,
    required this.onClearSelection,
    required this.onRemoveSelected,
  });

  final NoemaPalette palette;
  final VoidCallback onClearSelection;
  final VoidCallback onRemoveSelected;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _GlassIconButton(
          palette: palette,
          tooltip: strings.cancel,
          icon: Icons.close_rounded,
          onPressed: onClearSelection,
        ),
        _GlassIconButton(
          palette: palette,
          tooltip: strings.remove,
          icon: Icons.delete_outline_rounded,
          danger: true,
          onPressed: onRemoveSelected,
        ),
      ],
    );
  }
}

class _ImportGrid extends StatelessWidget {
  const _ImportGrid({
    required this.palette,
    required this.assets,
    required this.selectedIds,
    required this.onPreview,
    required this.onLongPress,
    required this.onToggleSelection,
  });

  final NoemaPalette palette;
  final List<SelectedGalleryAsset> assets;
  final Set<String> selectedIds;
  final ValueChanged<SelectedGalleryAsset> onPreview;
  final ValueChanged<SelectedGalleryAsset> onLongPress;
  final ValueChanged<SelectedGalleryAsset> onToggleSelection;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.only(
                top: _importGridTopPadding,
                bottom: _importGridBottomPadding,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _importGridCrossAxisCount(constraints.maxWidth),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: assets.length,
              itemBuilder: (context, index) {
                final asset = assets[index];
                final selected = selectedIds.contains(asset.id);
                return _ImportThumbnail(
                  palette: palette,
                  asset: asset,
                  selected: selected,
                  selecting: selectedIds.isNotEmpty,
                  onTap: () {
                    if (selectedIds.isEmpty) {
                      onPreview(asset);
                    } else {
                      onToggleSelection(asset);
                    }
                  },
                  onLongPress: () => onLongPress(asset),
                );
              },
            );
          },
        ),
        NoemaScrollEdgeFade(
          palette: palette,
          top: true,
          height: _importGridTopFadeHeight,
        ),
        NoemaScrollEdgeFade(
          palette: palette,
          top: false,
          height: _importGridBottomFadeHeight,
        ),
      ],
    );
  }
}

int _importGridCrossAxisCount(double width) {
  if (width < NoemaSceneMetrics.tabletBreakpoint) {
    return 4;
  }
  return math.max(4, math.min(8, width ~/ 120));
}

class _ImportThumbnail extends StatelessWidget {
  const _ImportThumbnail({
    required this.palette,
    required this.asset,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final NoemaPalette palette;
  final SelectedGalleryAsset asset;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: selected ? 0.94 : 1,
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? palette.ink
                    : palette.ink.withValues(alpha: 0.18),
                width: selected ? 1.6 : 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cacheSize = noemaImageCacheSize(
                    context,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _SelectedAssetImage(
                        asset: asset,
                        palette: palette,
                        cacheWidth: cacheSize.width,
                        cacheHeight: cacheSize.height,
                      ),
                      if (selecting)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          color: selected
                              ? Colors.black.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.38),
                        ),
                      if (selected)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: palette.ink,
                            size: 18,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedAssetImage extends StatelessWidget {
  const _SelectedAssetImage({
    required this.asset,
    required this.palette,
    this.fit = BoxFit.cover,
    this.applyTone = true,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
  });

  final SelectedGalleryAsset asset;
  final NoemaPalette palette;
  final BoxFit fit;
  final bool applyTone;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    if (!asset.previewUnavailable && asset.previewBytes != null) {
      return _toneImage(
        Image.memory(
          asset.previewBytes!,
          fit: fit,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          filterQuality: filterQuality,
        ),
      );
    }

    final thumbnailPath = asset.thumbnailPath;
    if (!asset.previewUnavailable &&
        thumbnailPath != null &&
        thumbnailPath.isNotEmpty) {
      return _toneImage(
        buildImportImageFromPath(
          path: thumbnailPath,
          fit: fit,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (context, error, stackTrace) => _UnavailableAssetTile(
            palette: palette,
            name: asset.name,
            unavailable: asset.previewUnavailable,
          ),
          filterQuality: filterQuality,
        ),
      );
    }

    return _UnavailableAssetTile(
      palette: palette,
      name: asset.name,
      unavailable: asset.previewUnavailable,
    );
  }

  Widget _toneImage(Widget image) {
    if (!applyTone) {
      return image;
    }
    return ColorFiltered(colorFilter: palette.photoFilter, child: image);
  }
}

class _UnavailableAssetTile extends StatelessWidget {
  const _UnavailableAssetTile({
    required this.palette,
    required this.name,
    required this.unavailable,
  });

  final NoemaPalette palette;
  final String name;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final color = unavailable ? palette.photoFallback : palette.glass;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, palette.photoFallbackAlt],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Text(
            unavailable ? '不可用' : name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatefulWidget {
  const _PhotoPreview({
    required this.palette,
    required this.asset,
    required this.onClose,
  });

  final NoemaPalette palette;
  final SelectedGalleryAsset asset;
  final VoidCallback onClose;

  @override
  State<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<_PhotoPreview> {
  String? _previewPath;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _PhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _previewPath = null;
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final generation = ++_previewGeneration;
    final sourceUri = widget.asset.sourceUri;
    if (sourceUri == null) {
      return;
    }

    try {
      final path = await const NoemaMediaPicker().createPreview(
        uri: sourceUri,
        maxSize: _importPreviewMaxSize,
      );
      if (!mounted ||
          generation != _previewGeneration ||
          widget.asset.sourceUri != sourceUri ||
          path == null ||
          path.isEmpty) {
        return;
      }
      setState(() {
        _previewPath = path;
      });
    } catch (_) {
      // Keep the thumbnail or unavailable state visible.
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final previewAsset = _previewPath == null
        ? widget.asset
        : widget.asset.copyWith(thumbnailPath: _previewPath);

    return Positioned.fill(
      child: ColoredBox(
        color: widget.palette.tone == NoemaTone.dark
            ? Colors.black.withValues(alpha: 0.86)
            : const Color(0xFFF2EDE3).withValues(alpha: 0.92),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxImageHeight = math.max(160.0, constraints.maxHeight - 154);
            final maxImageWidth = math.max(160.0, constraints.maxWidth - 56);
            final cacheSize = _previewImageCacheSize(
              context,
              asset: previewAsset,
              width: maxImageWidth,
              height: maxImageHeight,
            );

            return Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 38, 28, 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxImageWidth,
                        maxHeight: maxImageHeight,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _SelectedAssetImage(
                          asset: previewAsset,
                          palette: widget.palette,
                          fit: BoxFit.contain,
                          applyTone: false,
                          cacheWidth: cacheSize.width,
                          cacheHeight: cacheSize.height,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _PreviewCloseButton(
                      palette: widget.palette,
                      tooltip: strings.close,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

({int? width, int? height}) _previewImageCacheSize(
  BuildContext context, {
  required SelectedGalleryAsset asset,
  required double width,
  required double height,
}) {
  final assetWidth = asset.width;
  final assetHeight = asset.height;
  if (assetWidth == null ||
      assetHeight == null ||
      assetWidth <= 0 ||
      assetHeight <= 0) {
    return (
      width: null,
      height: noemaImageCacheExtent(
        height,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        headroom: 1.08,
        maxExtent: _importPreviewDecodeMaxExtent,
      ),
    );
  }

  final imageAspect = assetWidth / assetHeight;
  final boxAspect = width / height;
  final fittedWidth = imageAspect > boxAspect ? width : height * imageAspect;
  final fittedHeight = imageAspect > boxAspect ? width / imageAspect : height;
  final cacheSize = noemaImageCacheSize(
    context,
    width: fittedWidth,
    height: fittedHeight,
    headroom: 1.08,
    maxExtent: _importPreviewDecodeMaxExtent,
  );
  return (width: cacheSize.width, height: cacheSize.height);
}

class _PreviewCloseButton extends StatelessWidget {
  const _PreviewCloseButton({
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final NoemaPalette palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return NoemaSquareActionButton(
      palette: palette,
      tooltip: tooltip,
      onPressed: onPressed,
      cardSize: const Size(48, 48),
      hitSize: const Size(52, 52),
      radius: 14,
      glassScale: 1,
      strokeOpacity: 0.78,
      shadowScale: 1,
      motifOpacity: 0,
      child: const Icon(Icons.close_rounded, size: 25),
    );
  }
}

class _RemoveDialog extends StatelessWidget {
  const _RemoveDialog({
    required this.palette,
    required this.onCancel,
    required this.onConfirm,
  });

  final NoemaPalette palette;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);

    return NoemaDialogPanel(
      panelKey: const ValueKey('remove-dialog-panel'),
      palette: palette,
      title: strings.removeFromJingTitle,
      onClose: onCancel,
      closeTooltip: strings.close,
      body: NoemaDialogText(
        palette: palette,
        text: strings.removeFromJingBody,
        color: palette.muted,
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: strings.remove,
            child: NoemaDialogButton(
              palette: palette,
              label: strings.remove,
              icon: Icons.delete_outline_rounded,
              tone: NoemaDialogButtonTone.danger,
              onPressed: onConfirm,
            ),
          ),
        ],
      ),
    );
  }
}

class _NameRequiredHint extends StatelessWidget {
  const _NameRequiredHint({required this.palette, required this.text});

  final NoemaPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final titleFont = strings.isZh ? 'LXGWWenKaiGB' : 'NoemaLatin';

    return NoemaHintBubble(palette: palette, text: text, fontFamily: titleFont);
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.visualKey,
  });

  final NoemaPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final Key? visualKey;

  @override
  Widget build(BuildContext context) {
    return NoemaGlassIconButton(
      palette: palette,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      danger: danger,
      visualKey: visualKey,
    );
  }
}

String? _fontForText(String text) {
  return _containsCjk(text) ? 'LXGWWenKaiGB' : null;
}

bool _containsCjk(String text) {
  return text.runes.any((rune) => rune >= 0x4E00 && rune <= 0x9FFF);
}
