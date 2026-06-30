import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/router.dart';
import 'package:noema/core/i18n/noema_strings.dart';
import 'package:noema/core/models/decision.dart';
import 'package:noema/core/widgets/review_asset_thumbnail.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({required this.workspaceController, super.key});

  final ReviewWorkspaceController workspaceController;

  @override
  Widget build(BuildContext context) {
    final strings = NoemaStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final counts = workspaceController.decisionCounts;
    final decidedAssets = workspaceController.decisions.values
        .take(6)
        .map(
          (decision) =>
              workspaceController.workspace.assetById(decision.photoId),
        )
        .nonNulls
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(strings.resultsTitle)),
      body: SafeArea(
        child: ListView(
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.all(24),
          children: [
            Text(strings.resultsGenerated, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(strings.resultsBoundaryCopy, style: textTheme.bodyMedium),
            if (decidedAssets.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      width: 72,
                      child: ReviewAssetThumbnail(
                        asset: decidedAssets[index],
                        showName: true,
                        onThumbnailLoaded:
                            workspaceController.updateAssetThumbnailPath,
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemCount: decidedAssets.length,
                ),
              ),
            ],
            const SizedBox(height: 24),
            for (final decision in Decision.values) ...[
              Card(
                child: ListTile(
                  title: Text(strings.decisionLabel(decision)),
                  subtitle: Text(strings.photoCount(counts[decision] ?? 0)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Card(
              child: ListTile(
                title: Text(strings.stillUndecided),
                subtitle: Text(
                  strings.photoCount(workspaceController.undecidedCount),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go(NoemaRoutes.reviewGroups),
              child: Text(strings.reviewGroupsAgain),
            ),
          ],
        ),
      ),
    );
  }
}
