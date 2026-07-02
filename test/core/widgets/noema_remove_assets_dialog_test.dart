import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/app/back_navigation.dart';
import 'package:noema/core/ui/noema_scene.dart';
import 'package:noema/core/widgets/noema_message.dart';
import 'package:noema/core/widgets/noema_remove_assets_dialog.dart';
import 'package:noema/core/workflow/review_workspace_controller.dart';
import 'package:noema/features/import/noema_media_picker.dart';
import 'package:noema/features/import/selected_gallery_asset.dart';

void main() {
  testWidgets('remove dialog hides system delete when source is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showNoemaRemoveAssetsDialog(
                context: context,
                palette: NoemaPalette.fromTone(NoemaTone.light),
                canDeleteSystemPhoto: false,
              );
            },
            child: const Text('show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    expect(find.text('只从此境移除'), findsOneWidget);
    expect(find.text('删除手机相册原图'), findsNothing);
    expect(find.textContaining('只能从 Noema 移除'), findsOneWidget);
  });

  testWidgets('system delete permission notice uses the Noema message host', (
    tester,
  ) async {
    const channel = MethodChannel(noemaMediaPickerChannelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'galleryAccessStatus' ||
          call.method == 'requestGalleryAccess') {
        return 'denied';
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    final messageController = NoemaMessageController();
    final backController = NoemaBackNavigationController(
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
      messageController: messageController,
    );
    final workspaceController = ReviewWorkspaceController();
    workspaceController.loadSelectedAssets(const [
      SelectedGalleryAsset(
        id: 'asset-1',
        name: 'A.jpg',
        sourceUri: 'content://media/external/images/media/1',
      ),
    ]);
    addTearDown(() {
      backController.dispose();
      messageController.dispose();
      workspaceController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        scaffoldMessengerKey: backController.scaffoldMessengerKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: NoemaMessageHost(
          controller: messageController,
          child: NoemaBackNavigationScope(
            controller: backController,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    await removeNoemaAssetsWithChoice(
                      context: context,
                      workspaceController: workspaceController,
                      photoIds: const {'photo-1'},
                      choice: NoemaRemoveChoice.deleteSystemPhoto,
                    );
                  },
                  child: const Text('delete'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(NoemaHintBubble), findsOneWidget);
    expect(find.textContaining('需要先允许访问图库'), findsOneWidget);
    expect(calls.map((call) => call.method), [
      'galleryAccessStatus',
      'requestGalleryAccess',
    ]);

    messageController.hide();
    await tester.pump();
  });
}
