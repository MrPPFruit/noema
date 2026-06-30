import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_dialog.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';
import 'package:noema/core/widgets/recoverable_review_image.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';

enum _AlbumSort { modified, name, time }

enum _SortDirection { asc, desc }

const _createJingHeroTag = 'noema-create-jing-action';
const _homeTopBarTop = NoemaSceneMetrics.topBarTop;
const _homeActionRowTop = 48.0;
const _homeOptionsSheetTop =
    _homeTopBarTop + _homeActionRowTop + NoemaSceneMetrics.iconTapSize + 8.0;
const _homePhotoWallTop = 150.0;
const _homeTopBarHeight = _homeActionRowTop + NoemaSceneMetrics.iconVisualSize;

typedef _HomeToneMode = NoemaToneMode;
typedef _HomeTone = NoemaTone;
typedef _HomePalette = NoemaPalette;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.appearanceController,
    this.workspaceController,
  });

  final NoemaAppearanceController? appearanceController;
  final ReviewWorkspaceController? workspaceController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final NoemaAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;
  late final ReviewWorkspaceController _workspaceController;
  late final bool _ownsWorkspaceController;
  _AlbumSort _sort = _AlbumSort.modified;
  _SortDirection _direction = _SortDirection.desc;
  int _columns = 2;
  bool _optionsOpen = false;

  @override
  void initState() {
    super.initState();
    _ownsAppearanceController = widget.appearanceController == null;
    _appearanceController =
        widget.appearanceController ?? NoemaAppearanceController();
    _ownsWorkspaceController = widget.workspaceController == null;
    _workspaceController =
        widget.workspaceController ?? ReviewWorkspaceController();
    _workspaceController.addListener(_handleWorkspaceChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _workspaceController.removeListener(_handleWorkspaceChanged);
    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }
    if (_ownsWorkspaceController) {
      _workspaceController.dispose();
    }
    super.dispose();
  }

  void _handleWorkspaceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final resolvedTone = _appearanceController.resolveTone(context);
        final palette = _HomePalette.fromTone(resolvedTone);
        final albums = _orderedAlbums;

        return Scaffold(
          body: NoemaSceneFrame(
            palette: palette,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -16,
                  right: -16,
                  top: _homePhotoWallTop,
                  bottom: 0,
                  child: _AlbumScrollWindow(
                    palette: palette,
                    columns: _columns,
                    albums: albums,
                    onOpenAlbum: _openAlbum,
                    onLongPressAlbum: _confirmDeleteAlbum,
                    onThumbnailLoaded:
                        _workspaceController.updateWorkspaceAssetThumbnailPath,
                  ),
                ),
                if (albums.isEmpty)
                  Positioned(
                    left: NoemaSceneMetrics.sideInset,
                    right: NoemaSceneMetrics.sideInset,
                    top: 208,
                    bottom: 144,
                    child: _HomeEmptyState(palette: palette),
                  ),
                Positioned(
                  left: NoemaSceneMetrics.markLeft,
                  top: NoemaSceneMetrics.markTop,
                  child: NoemaThemeMark(palette: palette, mark: '境'),
                ),
                Positioned(
                  left: 28,
                  right: 28,
                  top: _homeTopBarTop,
                  child: _TopBar(
                    palette: palette,
                    toneMode: _appearanceController.toneMode,
                    optionsOpen: _optionsOpen,
                    onCycleTone: _appearanceController.cycleToneMode,
                    onToggleOptions: () {
                      setState(() {
                        _optionsOpen = !_optionsOpen;
                      });
                    },
                  ),
                ),
                if (_optionsOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        setState(() {
                          _optionsOpen = false;
                        });
                      },
                    ),
                  ),
                Positioned(
                  right: NoemaSceneMetrics.sideInset,
                  top: _homeOptionsSheetTop,
                  child: _OptionsSheet(
                    palette: palette,
                    open: _optionsOpen,
                    columns: _columns,
                    sort: _sort,
                    direction: _direction,
                    onCycleColumns: _cycleColumns,
                    onSortChanged: _chooseSort,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 32,
                  child: Center(
                    child: Hero(
                      tag: _createJingHeroTag,
                      child: NoemaFloatingActionButton(
                        palette: palette,
                        tooltip: strings.startReview,
                        onPressed: () => context.go(NoemaRoutes.import),
                        child: const Icon(Icons.add, size: 39, weight: 300),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_Album> get _orderedAlbums {
    final ordered = [
      for (final workspace in _workspaceController.workspaces)
        _Album.fromWorkspace(workspace),
    ];
    ordered.sort((a, b) {
      final value = switch (_sort) {
        _AlbumSort.modified => a.modified.compareTo(b.modified),
        _AlbumSort.name => a.name.compareTo(b.name),
        _AlbumSort.time => a.created.compareTo(b.created),
      };
      return _direction == _SortDirection.asc ? value : -value;
    });
    return ordered;
  }

  void _setColumns(int columns) {
    if (_columns == columns) {
      return;
    }
    setState(() {
      _columns = columns;
    });
  }

  void _cycleColumns() {
    _setColumns(switch (_columns) {
      2 => 3,
      3 => 4,
      _ => 2,
    });
  }

  void _chooseSort(_AlbumSort nextSort) {
    setState(() {
      if (_sort == nextSort) {
        _direction = _direction == _SortDirection.asc
            ? _SortDirection.desc
            : _SortDirection.asc;
        return;
      }

      _sort = nextSort;
      _direction = _defaultDirection(nextSort);
    });
  }

  void _openAlbum(_Album album) {
    if (_workspaceController.activateWorkspace(album.id)) {
      context.go(NoemaRoutes.observe);
    }
  }

  Future<void> _confirmDeleteAlbum(_Album album) async {
    final palette = _HomePalette.fromTone(
      _appearanceController.resolveTone(context),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (dialogContext) => _DeleteAlbumDialog(
        palette: palette,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed == true && mounted) {
      _workspaceController.deleteWorkspace(album.id);
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.palette,
    required this.toneMode,
    required this.optionsOpen,
    required this.onCycleTone,
    required this.onToggleOptions,
  });

  final _HomePalette palette;
  final _HomeToneMode toneMode;
  final bool optionsOpen;
  final VoidCallback onCycleTone;
  final VoidCallback onToggleOptions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _homeTopBarHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: NoemaSceneMetrics.topBarHeight,
            child: Center(child: NoemaWordmark(color: palette.ink)),
          ),
          Positioned(
            right: 0,
            top: _homeActionRowTop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoundIconButton(
                  palette: palette,
                  tooltip: _toneTooltip(toneMode),
                  onPressed: onCycleTone,
                  child: _ThemeModeIcon(mode: toneMode),
                ),
                const SizedBox(width: 4),
                _RoundIconButton(
                  palette: palette,
                  tooltip: '显示选项',
                  onPressed: onToggleOptions,
                  child: Icon(
                    optionsOpen ? Icons.tune_rounded : Icons.tune_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.emptyRecentSessions,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.muted,
              fontFamily: _fontForText(strings.emptyRecentSessions),
              fontSize: 16,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumScrollWindow extends StatelessWidget {
  const _AlbumScrollWindow({
    required this.palette,
    required this.columns,
    required this.albums,
    required this.onOpenAlbum,
    required this.onLongPressAlbum,
    required this.onThumbnailLoaded,
  });

  final _HomePalette palette;
  final int columns;
  final List<_Album> albums;
  final ValueChanged<_Album> onOpenAlbum;
  final ValueChanged<_Album> onLongPressAlbum;
  final void Function(String workspaceId, String photoId, String thumbnailPath)
  onThumbnailLoaded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0, 0.075, 0.84, 1],
          ).createShader(bounds),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            clipBehavior: Clip.hardEdge,
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _GridMetrics.forColumns(
                  columns,
                  constraints.maxWidth,
                );
                final rows = (albums.length / columns).ceil();
                final height =
                    metrics.paddingTop +
                    rows * metrics.itemHeight +
                    math.max(0, rows - 1) * metrics.rowGap +
                    metrics.paddingBottom;

                return SizedBox(
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var index = 0; index < albums.length; index++)
                        _PositionedAlbum(
                          key: ValueKey(albums[index].id),
                          album: albums[index],
                          index: index,
                          metrics: metrics,
                          palette: palette,
                          onOpen: () => onOpenAlbum(albums[index]),
                          onLongPress: () => onLongPressAlbum(albums[index]),
                          onThumbnailLoaded: onThumbnailLoaded,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PositionedAlbum extends StatelessWidget {
  const _PositionedAlbum({
    super.key,
    required this.album,
    required this.index,
    required this.metrics,
    required this.palette,
    required this.onOpen,
    required this.onLongPress,
    required this.onThumbnailLoaded,
  });

  final _Album album;
  final int index;
  final _GridMetrics metrics;
  final _HomePalette palette;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final void Function(String workspaceId, String photoId, String thumbnailPath)
  onThumbnailLoaded;

  @override
  Widget build(BuildContext context) {
    final row = index ~/ metrics.columns;
    final column = index % metrics.columns;
    final left = column * (metrics.cellWidth + metrics.columnGap);
    final top =
        metrics.paddingTop + row * (metrics.itemHeight + metrics.rowGap);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: metrics.cellWidth,
      height: metrics.itemHeight,
      child: _AlbumTile(
        album: album,
        index: index,
        metrics: metrics,
        palette: palette,
        onOpen: onOpen,
        onLongPress: onLongPress,
        onThumbnailLoaded: onThumbnailLoaded,
      ),
    );
  }
}

class _AlbumTile extends StatefulWidget {
  const _AlbumTile({
    required this.album,
    required this.index,
    required this.metrics,
    required this.palette,
    required this.onOpen,
    required this.onLongPress,
    required this.onThumbnailLoaded,
  });

  final _Album album;
  final int index;
  final _GridMetrics metrics;
  final _HomePalette palette;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final void Function(String workspaceId, String photoId, String thumbnailPath)
  onThumbnailLoaded;

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.album.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onOpen();
        },
        onLongPress: widget.onLongPress,
        child: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                scale: _pressed ? 0.985 : 1,
                child: SizedBox(
                  width: widget.metrics.coverWidth,
                  height: widget.metrics.coverHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _PhotoCard(
                        asset: widget.album.coverAsset(1),
                        fallbackLabel: widget.album.coverLabel,
                        palette: widget.palette,
                        opacity: 0.72,
                        displayWidth: widget.metrics.coverWidth,
                        displayHeight: widget.metrics.coverHeight,
                        onThumbnailLoaded: widget.onThumbnailLoaded,
                        transform: Matrix4.identity()
                          ..translateByDouble(
                            -10.0 * widget.metrics.stackSpread,
                            7.0 * widget.metrics.stackSpread,
                            0,
                            1,
                          )
                          ..rotateZ(
                            _degreesToRadians(-6 * widget.metrics.stackRotate),
                          ),
                      ),
                      _PhotoCard(
                        asset: widget.album.coverAsset(2),
                        fallbackLabel: widget.album.coverLabel,
                        palette: widget.palette,
                        opacity: 0.64,
                        displayWidth: widget.metrics.coverWidth,
                        displayHeight: widget.metrics.coverHeight,
                        onThumbnailLoaded: widget.onThumbnailLoaded,
                        transform: Matrix4.identity()
                          ..translateByDouble(
                            11.0 * widget.metrics.stackSpread,
                            4.0 * widget.metrics.stackSpread,
                            0,
                            1,
                          )
                          ..rotateZ(
                            _degreesToRadians(4.5 * widget.metrics.stackRotate),
                          ),
                      ),
                      _PhotoCard(
                        asset: widget.album.coverAsset(0),
                        fallbackLabel: widget.album.coverLabel,
                        palette: widget.palette,
                        opacity: 1,
                        displayWidth: widget.metrics.coverWidth,
                        displayHeight: widget.metrics.coverHeight,
                        onThumbnailLoaded: widget.onThumbnailLoaded,
                        transform: Matrix4.identity()
                          ..rotateZ(
                            _degreesToRadians(
                              _tilts[widget.index % _tilts.length],
                            ),
                          ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: widget.metrics.labelGap),
              SizedBox(
                height: widget.metrics.labelLine,
                child: Center(
                  child: Text(
                    widget.album.name,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: widget.palette.ink,
                      fontFamily: 'LXGWWenKaiGB',
                      fontSize: widget.metrics.labelSize,
                      height:
                          widget.metrics.labelLine / widget.metrics.labelSize,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.asset,
    required this.fallbackLabel,
    required this.palette,
    required this.opacity,
    required this.displayWidth,
    required this.displayHeight,
    required this.onThumbnailLoaded,
    required this.transform,
  });

  final ReviewAsset? asset;
  final String fallbackLabel;
  final _HomePalette palette;
  final double opacity;
  final double displayWidth;
  final double displayHeight;
  final void Function(String workspaceId, String photoId, String thumbnailPath)
  onThumbnailLoaded;
  final Matrix4 transform;

  @override
  Widget build(BuildContext context) {
    final cacheSize = noemaImageCacheSize(
      context,
      width: displayWidth,
      height: displayHeight,
      headroom: 1.18,
    );

    return Positioned.fill(
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _multiplyAlpha(palette.cardShadow, opacity),
                blurRadius: palette.tone == _HomeTone.dark ? 36 : 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _multiplyAlpha(palette.photoFallback, opacity),
                border: Border.all(
                  color: _multiplyAlpha(palette.cardBorder, opacity),
                ),
              ),
              child: ColorFiltered(
                colorFilter: palette.photoFilter,
                child: _AlbumCoverImage(
                  asset: asset,
                  fallbackLabel: fallbackLabel,
                  palette: palette,
                  opacity: opacity,
                  onThumbnailLoaded: onThumbnailLoaded,
                  cacheWidth: cacheSize.width,
                  cacheHeight: cacheSize.height,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumCoverImage extends StatelessWidget {
  const _AlbumCoverImage({
    required this.asset,
    required this.fallbackLabel,
    required this.palette,
    required this.opacity,
    required this.onThumbnailLoaded,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  final ReviewAsset? asset;
  final String fallbackLabel;
  final _HomePalette palette;
  final double opacity;
  final void Function(String workspaceId, String photoId, String thumbnailPath)
  onThumbnailLoaded;
  final int cacheWidth;
  final int cacheHeight;

  @override
  Widget build(BuildContext context) {
    final coverAsset = asset;
    if (coverAsset == null) {
      return _AlbumCoverFallback(
        label: fallbackLabel,
        palette: palette,
        opacity: opacity,
      );
    }

    return Opacity(
      opacity: opacity,
      child: NoemaRecoverableReviewImage(
        asset: coverAsset,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        recoverKind: NoemaRecoverableImageKind.thumbnail,
        recoverMaxSize: math.max(cacheWidth, cacheHeight),
        refreshWhenSourceAvailable: true,
        onRecovered: (photoId, thumbnailPath) => onThumbnailLoaded(
          coverAsset.photo.sessionId,
          photoId,
          thumbnailPath,
        ),
        filterQuality: FilterQuality.low,
        fallback: _AlbumCoverFallback(
          label: fallbackLabel,
          palette: palette,
          opacity: 1,
        ),
      ),
    );
  }
}

class _AlbumCoverFallback extends StatelessWidget {
  const _AlbumCoverFallback({
    required this.label,
    required this.palette,
    required this.opacity,
  });

  final String label;
  final _HomePalette palette;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _multiplyAlpha(palette.photoFallback, opacity),
            _multiplyAlpha(palette.photoFallbackAlt, opacity),
          ],
        ),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.muted.withValues(alpha: 0.72 * opacity),
            fontFamily: _fontForText(label),
            fontSize: 13,
            height: 1,
          ),
        ),
      ),
    );
  }
}

Color _multiplyAlpha(Color color, double factor) {
  return color.withValues(alpha: (color.a * factor).clamp(0, 1));
}

class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({
    required this.palette,
    required this.open,
    required this.columns,
    required this.sort,
    required this.direction,
    required this.onCycleColumns,
    required this.onSortChanged,
  });

  final _HomePalette palette;
  final bool open;
  final int columns;
  final _AlbumSort sort;
  final _SortDirection direction;
  final VoidCallback onCycleColumns;
  final ValueChanged<_AlbumSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: Duration(milliseconds: open ? 160 : 120),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: open ? 1 : 0.985,
          alignment: const Alignment(0.72, -1),
          duration: Duration(milliseconds: open ? 160 : 120),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                key: const ValueKey('home-options-sheet'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.sheet,
                  border: Border.all(color: palette.glassBorder),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 42,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _HomeOptionsGroup(
                          palette: palette,
                          label: '排序',
                          children: [
                            _SortPill(
                              palette: palette,
                              active: sort == _AlbumSort.modified,
                              direction: sort == _AlbumSort.modified
                                  ? direction
                                  : _defaultDirection(_AlbumSort.modified),
                              tooltip: _sortTooltip(
                                _AlbumSort.modified,
                                sort == _AlbumSort.modified
                                    ? direction
                                    : _defaultDirection(_AlbumSort.modified),
                              ),
                              onPressed: () =>
                                  onSortChanged(_AlbumSort.modified),
                              child: const _ModifiedIcon(),
                            ),
                            const SizedBox(width: 4),
                            _SortPill(
                              palette: palette,
                              active: sort == _AlbumSort.name,
                              direction: sort == _AlbumSort.name
                                  ? direction
                                  : _defaultDirection(_AlbumSort.name),
                              tooltip: _sortTooltip(
                                _AlbumSort.name,
                                sort == _AlbumSort.name
                                    ? direction
                                    : _defaultDirection(_AlbumSort.name),
                              ),
                              onPressed: () => onSortChanged(_AlbumSort.name),
                              child: const _NameSortIcon(),
                            ),
                            const SizedBox(width: 4),
                            _SortPill(
                              palette: palette,
                              active: sort == _AlbumSort.time,
                              direction: sort == _AlbumSort.time
                                  ? direction
                                  : _defaultDirection(_AlbumSort.time),
                              tooltip: _sortTooltip(
                                _AlbumSort.time,
                                sort == _AlbumSort.time
                                    ? direction
                                    : _defaultDirection(_AlbumSort.time),
                              ),
                              onPressed: () => onSortChanged(_AlbumSort.time),
                              child: const _TimeSortIcon(),
                            ),
                          ],
                        ),
                        _HomeOptionsDivider(palette: palette),
                        _HomeOptionsGroup(
                          palette: palette,
                          label: '排布',
                          children: [
                            _OptionPill(
                              palette: palette,
                              active: true,
                              tooltip: _columnsTooltip(columns),
                              onPressed: onCycleColumns,
                              child: _ColumnsIcon(columns: columns),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeOptionsGroup extends StatelessWidget {
  const _HomeOptionsGroup({
    required this.palette,
    required this.label,
    required this.children,
  });

  final _HomePalette palette;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.muted.withValues(alpha: 0.82),
            fontFamily: 'LXGWWenKaiGB',
            fontSize: 11,
            height: 1,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 9),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

class _HomeOptionsDivider extends StatelessWidget {
  const _HomeOptionsDivider({required this.palette});

  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: palette.glassBorder.withValues(alpha: 0.72),
    );
  }
}

class _OptionPill extends StatelessWidget {
  const _OptionPill({
    required this.palette,
    required this.active,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final _HomePalette palette;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.ink : palette.muted;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 44,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? palette.glass.withValues(alpha: 0.9)
                  : Colors.transparent,
              border: Border.all(
                color: active ? palette.glassBorder : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: IconTheme(
              data: IconThemeData(color: color, size: 22),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.palette,
    required this.active,
    required this.direction,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final _HomePalette palette;
  final bool active;
  final _SortDirection direction;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _OptionPill(
      palette: palette,
      active: active,
      tooltip: tooltip,
      onPressed: onPressed,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: child),
          Positioned(
            right: 3,
            bottom: 2,
            child: AnimatedOpacity(
              opacity: active ? 0.84 : 0,
              duration: const Duration(milliseconds: 160),
              child: Transform.rotate(
                angle: direction == _SortDirection.asc ? math.pi : 0,
                child: CustomPaint(
                  size: const Size(10, 10),
                  painter: _SortOrderPainter(
                    color: active ? palette.ink : palette.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteAlbumDialog extends StatelessWidget {
  const _DeleteAlbumDialog({
    required this.palette,
    required this.onCancel,
    required this.onConfirm,
  });

  final _HomePalette palette;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return NoemaDialogPanel(
      panelKey: const ValueKey('home-delete-dialog-panel'),
      palette: palette,
      title: '删除这个境？',
      onClose: onCancel,
      body: NoemaDialogText(
        palette: palette,
        text: '不会删除你系统相册里的原照片。',
        color: palette.muted,
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          NoemaDialogButton(
            palette: palette,
            label: '删除',
            icon: Icons.delete_outline_rounded,
            tone: NoemaDialogButtonTone.danger,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.palette,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final _HomePalette palette;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NoemaGlassIconButton(
      palette: palette,
      tooltip: tooltip,
      onPressed: onPressed,
      surfaceOpacityScale: 0,
      child: child,
    );
  }
}

class _ThemeModeIcon extends StatelessWidget {
  const _ThemeModeIcon({required this.mode});

  final _HomeToneMode mode;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _ThemeModeIconPainter(color: color, mode: mode),
      ),
    );
  }
}

class _ColumnsIcon extends StatelessWidget {
  const _ColumnsIcon({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _ColumnsIconPainter(color: color, columns: columns),
      ),
    );
  }
}

class _ModifiedIcon extends StatelessWidget {
  const _ModifiedIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _ModifiedIconPainter(color)),
    );
  }
}

class _NameSortIcon extends StatelessWidget {
  const _NameSortIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _NameSortIconPainter(color)),
    );
  }
}

class _TimeSortIcon extends StatelessWidget {
  const _TimeSortIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _TimeSortIconPainter(color)),
    );
  }
}

class _ThemeModeIconPainter extends CustomPainter {
  const _ThemeModeIconPainter({required this.color, required this.mode});

  final Color color;
  final _HomeToneMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const center = Offset(12, 12);

    if (mode == _HomeToneMode.light) {
      canvas.drawCircle(center, 4.2, paint);
      canvas
        ..drawLine(const Offset(12, 3.8), const Offset(12, 5.8), paint)
        ..drawLine(const Offset(12, 18.2), const Offset(12, 20.2), paint)
        ..drawLine(const Offset(3.8, 12), const Offset(5.8, 12), paint)
        ..drawLine(const Offset(18.2, 12), const Offset(20.2, 12), paint)
        ..drawLine(const Offset(6.2, 6.2), const Offset(7.6, 7.6), paint)
        ..drawLine(const Offset(16.4, 16.4), const Offset(17.8, 17.8), paint)
        ..drawLine(const Offset(17.8, 6.2), const Offset(16.4, 7.6), paint)
        ..drawLine(const Offset(7.6, 16.4), const Offset(6.2, 17.8), paint);
      canvas.restore();
      return;
    }

    if (mode == _HomeToneMode.dark) {
      final path = Path()
        ..moveTo(18.8, 14.4)
        ..cubicTo(15.8, 16.7, 11.3, 16.0, 9.0, 13.0)
        ..cubicTo(7.2, 10.6, 7.4, 7.4, 9.6, 5.2)
        ..cubicTo(5.4, 6.4, 3.0, 10.9, 4.9, 15.0)
        ..cubicTo(7.1, 19.6, 13.0, 21.1, 17.1, 18.1)
        ..cubicTo(18.2, 17.3, 18.8, 16.0, 18.8, 14.4);
      canvas.drawPath(path, paint);
      canvas.restore();
      return;
    }

    canvas.drawCircle(center, 7.4, paint);
    canvas.drawLine(
      Offset(center.dx, center.dy - 7.4),
      Offset(center.dx, center.dy + 7.4),
      paint,
    );
    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(12, 4.6)
      ..arcTo(
        Rect.fromCircle(center: center, radius: 7.4),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..lineTo(12, 19.4)
      ..close();
    canvas.drawPath(path, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ThemeModeIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.mode != mode;
  }
}

class _ColumnsIconPainter extends CustomPainter {
  const _ColumnsIconPainter({required this.color, required this.columns});

  final Color color;
  final int columns;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rows = 2;
    final rectWidth = columns == 2 ? 5.0 : (columns == 3 ? 3.6 : 2.8);
    final rectHeight = columns == 2 ? 5.0 : (columns == 3 ? 4.8 : 4.6);
    final startX = columns == 2 ? 5.0 : (columns == 3 ? 4.0 : 3.6);
    final gapX = columns == 2 ? 9.0 : (columns == 3 ? 6.2 : 4.7);
    final startY = columns == 2 ? 5.0 : 6.0;
    final gapY = columns == 2 ? 9.0 : (columns == 3 ? 7.2 : 7.4);

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final rect = Rect.fromLTWH(
          startX + gapX * column,
          startY + gapY * row,
          rectWidth,
          rectHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.1)),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ColumnsIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.columns != columns;
  }
}

class _ModifiedIconPainter extends CustomPainter {
  const _ModifiedIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawCircle(const Offset(10, 10), 4.9, paint)
      ..drawLine(const Offset(10, 7.3), const Offset(10, 10.4), paint)
      ..drawLine(const Offset(10, 10.4), const Offset(12, 11.5), paint);

    final pen = Path()
      ..moveTo(14.3, 16.8)
      ..lineTo(18.4, 12.7)
      ..quadraticBezierTo(19.2, 11.9, 20, 12.7)
      ..quadraticBezierTo(20.8, 13.5, 20, 14.3)
      ..lineTo(15.9, 18.4)
      ..lineTo(13.8, 18.9)
      ..close();
    canvas.drawPath(pen, paint);

    final sweep = Path()
      ..moveTo(6.5, 16.4)
      ..quadraticBezierTo(8.6, 18.2, 11.6, 17.9);
    canvas.drawPath(sweep, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ModifiedIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NameSortIconPainter extends CustomPainter {
  const _NameSortIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        style: TextStyle(
          color: color,
          fontFamily: 'Georgia',
          fontSize: 7,
          fontWeight: FontWeight.w600,
        ),
        children: const [
          TextSpan(text: 'A\n'),
          TextSpan(text: 'Z'),
        ],
      ),
    )..layout();
    textPainter.paint(canvas, const Offset(5.2, 4.2));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(const Offset(15.8, 5.8), const Offset(15.8, 18.2), paint)
      ..drawLine(const Offset(13.2, 15.8), const Offset(15.8, 18.2), paint)
      ..drawLine(const Offset(18.4, 15.8), const Offset(15.8, 18.2), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NameSortIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TimeSortIconPainter extends CustomPainter {
  const _TimeSortIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.2, 6.4, 13.6, 11.8),
          const Radius.circular(2.2),
        ),
        paint,
      )
      ..drawLine(const Offset(8.4, 4.8), const Offset(8.4, 7.9), paint)
      ..drawLine(const Offset(15.6, 4.8), const Offset(15.6, 7.9), paint)
      ..drawLine(const Offset(5.2, 10.1), const Offset(18.8, 10.1), paint)
      ..drawCircle(const Offset(12, 14.4), 2.4, paint)
      ..drawLine(const Offset(12, 13.1), const Offset(12, 14.6), paint)
      ..drawLine(const Offset(12, 14.6), const Offset(13.1, 15.3), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimeSortIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SortOrderPainter extends CustomPainter {
  const _SortOrderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(2, 3.6)
      ..lineTo(5, 6.6)
      ..lineTo(8, 3.6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SortOrderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _GridMetrics {
  const _GridMetrics({
    required this.columns,
    required this.cellWidth,
    required this.coverWidth,
    required this.coverHeight,
    required this.columnGap,
    required this.rowGap,
    required this.paddingTop,
    required this.paddingBottom,
    required this.labelSize,
    required this.labelLine,
    required this.labelGap,
    required this.stackSpread,
    required this.stackRotate,
  });

  final int columns;
  final double cellWidth;
  final double coverWidth;
  final double coverHeight;
  final double columnGap;
  final double rowGap;
  final double paddingTop;
  final double paddingBottom;
  final double labelSize;
  final double labelLine;
  final double labelGap;
  final double stackSpread;
  final double stackRotate;

  double get itemHeight => coverHeight + labelGap + labelLine;

  factory _GridMetrics.forColumns(int columns, double width) {
    final columnGap = switch (columns) {
      2 => 34.0,
      3 => 18.0,
      _ => 10.0,
    };
    final coverScale = switch (columns) {
      2 => 1.0,
      3 => 0.92,
      _ => 0.86,
    };
    final cellWidth = (width - (columns - 1) * columnGap) / columns;
    final coverWidth = cellWidth * coverScale;

    return _GridMetrics(
      columns: columns,
      cellWidth: cellWidth,
      coverWidth: coverWidth,
      coverHeight: coverWidth * 0.82 / 1.12,
      columnGap: columnGap,
      rowGap: switch (columns) {
        2 => 30.0,
        3 => 28.0,
        _ => 23.0,
      },
      paddingTop: switch (columns) {
        2 => 64.0,
        3 => 62.0,
        _ => 60.0,
      },
      paddingBottom: 118,
      labelSize: switch (columns) {
        2 => 18.0,
        3 => 15.0,
        _ => 13.0,
      },
      labelLine: switch (columns) {
        2 => 22.0,
        3 => 19.0,
        _ => 17.0,
      },
      labelGap: switch (columns) {
        2 => 12.0,
        3 => 9.0,
        _ => 7.0,
      },
      stackSpread: switch (columns) {
        2 => 1.0,
        3 => 0.48,
        _ => 0.28,
      },
      stackRotate: switch (columns) {
        2 => 1.0,
        3 => 0.58,
        _ => 0.38,
      },
    );
  }
}

class _Album {
  _Album({
    required this.id,
    required this.name,
    required this.created,
    required this.modified,
    required this.photoCount,
    required List<ReviewAsset> coverAssets,
  }) : _coverAssets = List.unmodifiable(coverAssets);

  factory _Album.fromWorkspace(ReviewWorkspace workspace) {
    return _Album(
      id: workspace.session.id,
      name: workspace.session.name,
      created: workspace.session.createdAt,
      modified: workspace.session.updatedAt,
      photoCount: workspace.session.totalCount,
      coverAssets: _coverAssetsForWorkspace(workspace),
    );
  }

  final String id;
  final String name;
  final DateTime created;
  final DateTime modified;
  final int photoCount;
  final List<ReviewAsset> _coverAssets;

  String get coverLabel => photoCount <= 0 ? '空境' : '$photoCount 张';

  ReviewAsset? coverAsset(int slot) {
    if (_coverAssets.isEmpty) {
      return null;
    }
    return _coverAssets[slot % _coverAssets.length];
  }
}

List<ReviewAsset> _coverAssetsForWorkspace(ReviewWorkspace workspace) {
  final assets = workspace.assets;
  if (!assets.any((asset) => _coverScore(asset) != null)) {
    return assets.take(3).toList(growable: false);
  }

  final indexed = assets.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final scoreValue = (_coverScore(b.$2) ?? -1).compareTo(
      _coverScore(a.$2) ?? -1,
    );
    if (scoreValue != 0) {
      return scoreValue;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed.take(3)) entry.$2];
}

int? _coverScore(ReviewAsset asset) {
  return asset.photo.appraisal?.totalScore ?? asset.photo.appraisalScore;
}

const _tilts = [-1.6, 1.8, -0.8, 1.4, -2.0, 1.2];

_SortDirection _defaultDirection(_AlbumSort sort) {
  return switch (sort) {
    _AlbumSort.modified => _SortDirection.desc,
    _AlbumSort.name => _SortDirection.asc,
    _AlbumSort.time => _SortDirection.desc,
  };
}

String _toneTooltip(_HomeToneMode mode) {
  return switch (mode) {
    _HomeToneMode.light => '当前白色，点击切换色调',
    _HomeToneMode.dark => '当前黑色，点击切换色调',
    _HomeToneMode.auto => '当前自动，点击切换色调',
  };
}

String _sortTooltip(_AlbumSort sort, _SortDirection direction) {
  final label = switch (sort) {
    _AlbumSort.modified => '最新修改',
    _AlbumSort.name => '名称',
    _AlbumSort.time => '创建时间',
  };
  final order = direction == _SortDirection.asc ? '升序' : '降序';
  return '按$label$order排序';
}

String _columnsTooltip(int columns) {
  return switch (columns) {
    2 => '宽松排布',
    3 => '均衡排布',
    _ => '紧凑排布',
  };
}

double _degreesToRadians(double degrees) {
  return degrees * math.pi / 180;
}

String? _fontForText(String text) {
  return _containsCjk(text) ? 'LXGWWenKaiGB' : null;
}

bool _containsCjk(String text) {
  return text.runes.any((rune) => rune >= 0x4E00 && rune <= 0x9FFF);
}
