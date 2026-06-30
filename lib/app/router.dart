import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/app/noema_routes.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/appreciate/appreciate_viewer_page.dart';
import 'package:noema/features/arena/arena_screen.dart';
import 'package:noema/features/appraise/appraise_screen.dart';
import 'package:noema/features/home/home_screen.dart';
import 'package:noema/features/import/import_screen.dart';
import 'package:noema/features/processing/processing_screen.dart';
import 'package:noema/features/results/results_screen.dart';
import 'package:noema/features/review_groups/review_groups_screen.dart';

export 'noema_routes.dart';

GoRouter createNoemaRouter(
  ReviewWorkspaceController workspaceController,
  NoemaAppearanceController appearanceController,
  NoemaBackNavigationController backNavigationController,
) {
  return GoRouter(
    routes: [
      GoRoute(
        path: NoemaRoutes.home,
        pageBuilder: (context, state) => _mainRoutePage(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            HomeScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
            ),
          ),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.import,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            ImportScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              appendMode: state.uri.queryParameters['mode'] == 'append',
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: NoemaRoutes.observe,
        pageBuilder: (context, state) => _mainRoutePage(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            ProcessingScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              selectedCount: parseSelectedCount(
                state.uri.queryParameters['count'],
              ),
              experienceDockVariant: experienceDockVariantFromQuery(
                state.uri.queryParameters['dock'],
              ),
              experienceDockTuning:
                  state.uri.queryParameters['tune'] == '1' ||
                  state.uri.queryParameters['tune'] == 'true',
            ),
          ),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.observePhoto,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          child: _withBackGuard(
            backNavigationController,
            AppraiseSheetPhotoViewerPage(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              initialPhotoId: state.uri.queryParameters['photoId'],
              sort: state.uri.queryParameters['sort'],
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.965, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: NoemaRoutes.observeAppreciate,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          child: _withBackGuard(
            backNavigationController,
            AppreciateViewerPage(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              initialPhotoId: state.uri.queryParameters['photoId'],
              sortMode: state.uri.queryParameters['sortMode'],
              timeSort: state.uri.queryParameters['timeSort'],
              scoreSort: state.uri.queryParameters['scoreSort'],
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.965, end: 1).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: NoemaRoutes.appraise,
        pageBuilder: (context, state) => _mainRoutePage(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            AppraiseScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              initialPhotoId: state.uri.queryParameters['photoId'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.processing,
        pageBuilder: (context, state) => _mainRoutePage(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            ProcessingScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
              selectedCount: parseSelectedCount(
                state.uri.queryParameters['count'],
              ),
              experienceDockVariant: experienceDockVariantFromQuery(
                state.uri.queryParameters['dock'],
              ),
              experienceDockTuning:
                  state.uri.queryParameters['tune'] == '1' ||
                  state.uri.queryParameters['tune'] == 'true',
            ),
          ),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.reviewGroups,
        pageBuilder: (context, state) => _mainRoutePage(
          key: state.pageKey,
          child: _withBackGuard(
            backNavigationController,
            ReviewGroupsScreen(
              workspaceController: workspaceController,
              appearanceController: appearanceController,
            ),
          ),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.arena,
        builder: (context, state) => _withBackGuard(
          backNavigationController,
          ArenaScreen(workspaceController: workspaceController),
        ),
      ),
      GoRoute(
        path: NoemaRoutes.results,
        builder: (context, state) => _withBackGuard(
          backNavigationController,
          ResultsScreen(workspaceController: workspaceController),
        ),
      ),
    ],
  );
}

Widget _withBackGuard(NoemaBackNavigationController controller, Widget child) {
  return NoemaBackNavigationGuard(controller: controller, child: child);
}

CustomTransitionPage<void> _mainRoutePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
