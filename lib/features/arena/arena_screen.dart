import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/widgets/review_asset_thumbnail.dart';
import 'package:noema/core/workflow/review_workspace.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';

class ArenaScreen extends StatelessWidget {
  const ArenaScreen({required this.workspaceController, super.key});

  final ReviewWorkspaceController workspaceController;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = workspaceController.workspace;
    final group = workspaceController.activeGroup;
    final visibleAssets = group == null
        ? <ReviewAsset>[]
        : group.photoIds
              .map(workspace.assetById)
              .nonNulls
              .take(2)
              .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(strings.arenaTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visibleAssets.isEmpty)
                Text(strings.noActiveGroup, style: textTheme.bodyMedium)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: ReviewAssetThumbnail(
                        asset: visibleAssets.first,
                        label: 'A',
                        aspectRatio: 0.72,
                        showName: true,
                        onThumbnailLoaded:
                            workspaceController.updateAssetThumbnailPath,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: visibleAssets.length > 1
                          ? ReviewAssetThumbnail(
                              asset: visibleAssets[1],
                              label: 'B',
                              aspectRatio: 0.72,
                              showName: true,
                              onThumbnailLoaded:
                                  workspaceController.updateAssetThumbnailPath,
                            )
                          : _NoPairPlaceholder(label: strings.noPair),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(strings.decisionPrompt, style: textTheme.bodyMedium),
                const SizedBox(height: 12),
                for (final decision in Decision.values) ...[
                  FilledButton(
                    onPressed: () {
                      workspaceController.recordDecision(
                        visibleAssets.first.photo.id,
                        decision,
                      );
                    },
                    child: Text(strings.decisionLabel(decision)),
                  ),
                  const SizedBox(height: 6),
                ],
                OutlinedButton(
                  onPressed: visibleAssets.length > 1
                      ? () {
                          for (final asset in visibleAssets) {
                            workspaceController.recordDecision(
                              asset.photo.id,
                              Decision.keep,
                            );
                          }
                        }
                      : null,
                  child: Text(strings.keepBoth),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () => context.go(NoemaRoutes.results),
                  child: Text(strings.skipPair),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go(NoemaRoutes.results),
                child: Text(strings.finishGroup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoPairPlaceholder extends StatelessWidget {
  const _NoPairPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}
