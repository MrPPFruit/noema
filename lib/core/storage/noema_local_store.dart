import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:noema/core/models/photo_decision.dart';
import 'package:noema/core/workflow/review_workspace.dart';

import 'noema_local_store_stub.dart'
    if (dart.library.io) 'noema_local_store_io.dart'
    if (dart.library.html) 'noema_local_store_web.dart'
    as storage_impl;

class NoemaLocalStore {
  NoemaLocalStore({storage_impl.NoemaLocalStorePlatform? platform})
    : _platform = platform ?? storage_impl.NoemaLocalStorePlatform();

  final storage_impl.NoemaLocalStorePlatform _platform;

  Future<NoemaStoreSnapshot?> readSnapshot() async {
    try {
      final source = await _platform.read();
      if (source == null || source.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(source);
      return NoemaStoreSnapshot.fromJson(_jsonMap(decoded));
    } catch (error) {
      debugPrint('Noema local restore skipped: $error');
      return null;
    }
  }

  Future<void> writeSnapshot(NoemaStoreSnapshot snapshot) async {
    try {
      await _platform.write(jsonEncode(snapshot.toJson()));
    } catch (error) {
      debugPrint('Noema local save failed: $error');
    }
  }

  Future<void> clearSnapshot() => _platform.clear();
}

class NoemaStoreSnapshot {
  NoemaStoreSnapshot({
    required List<ReviewWorkspace> workspaces,
    required this.activeWorkspaceId,
    required Map<String, Map<String, PhotoDecision>> decisionsByWorkspaceId,
  }) : workspaces = List.unmodifiable(workspaces),
       decisionsByWorkspaceId = Map.unmodifiable({
         for (final entry in decisionsByWorkspaceId.entries)
           entry.key: Map<String, PhotoDecision>.unmodifiable(entry.value),
       });

  factory NoemaStoreSnapshot.fromJson(Map<String, Object?> json) {
    final workspaces = [
      for (final workspace in _jsonMapList(json['workspaces']))
        ReviewWorkspace.fromJson(workspace),
    ];
    final workspaceIds = {
      for (final workspace in workspaces) workspace.session.id,
    };
    final rawActiveWorkspaceId = _nullableStringValue(
      json['activeWorkspaceId'],
    );
    final activeWorkspaceId = workspaceIds.contains(rawActiveWorkspaceId)
        ? rawActiveWorkspaceId
        : workspaces.isEmpty
        ? null
        : workspaces.first.session.id;
    final decisionsByWorkspaceId = <String, Map<String, PhotoDecision>>{};
    final decisionRoot = _jsonMap(json['decisionsByWorkspaceId']);
    for (final workspaceEntry in decisionRoot.entries) {
      final workspaceId = workspaceEntry.key;
      if (!workspaceIds.contains(workspaceId)) {
        continue;
      }
      final photoEntries = _jsonMap(workspaceEntry.value);
      decisionsByWorkspaceId[workspaceId] = {
        for (final photoEntry in photoEntries.entries)
          photoEntry.key: PhotoDecision.fromJson(_jsonMap(photoEntry.value)),
      };
    }
    for (final workspace in workspaces) {
      decisionsByWorkspaceId.putIfAbsent(workspace.session.id, () => {});
    }

    return NoemaStoreSnapshot(
      workspaces: workspaces,
      activeWorkspaceId: activeWorkspaceId,
      decisionsByWorkspaceId: decisionsByWorkspaceId,
    );
  }

  final List<ReviewWorkspace> workspaces;
  final String? activeWorkspaceId;
  final Map<String, Map<String, PhotoDecision>> decisionsByWorkspaceId;

  Map<String, Object?> toJson() {
    return {
      'version': 1,
      'activeWorkspaceId': activeWorkspaceId,
      'workspaces': [for (final workspace in workspaces) workspace.toJson()],
      'decisionsByWorkspaceId': {
        for (final workspaceEntry in decisionsByWorkspaceId.entries)
          workspaceEntry.key: {
            for (final photoEntry in workspaceEntry.value.entries)
              photoEntry.key: photoEntry.value.toJson(),
          },
      },
    };
  }
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _jsonMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [for (final item in value) _jsonMap(item)];
}

String? _nullableStringValue(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}
