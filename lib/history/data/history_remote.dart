import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/history_models.dart';

/// The private bucket of reviewed product photos (0090). Workers may read
/// only APPROVED photos of items with history they may see.
const galleryBucket = 'item-gallery';

const _readTimeout = Duration(seconds: 15);
const _downloadTimeout = Duration(seconds: 60);

/// pr_history_search's arguments, exactly (0090).
Map<String, dynamic> searchParams(HistoryQuery q, {required int offset, required int limit}) => {
      'p_query': q.text.trim(),
      'p_kind': q.kind?.wire,
      'p_category': q.category,
      'p_folder': q.projectId,
      'p_from': q.from,
      'p_to': q.to,
      'p_limit': limit,
      'p_offset': offset,
    };

abstract class HistoryRemote {
  /// {items: [...], has_more: bool}
  Future<Map<String, dynamic>> search(HistoryQuery q, {required int offset, required int limit});

  /// One item's photos and entries; throws HISTORY_NOT_AVAILABLE when none is visible.
  Future<Map<String, dynamic>> item(String itemId);

  /// For each of [itemIds] still visible: {item_id, entries: ['kind:id'], photo_ids: [...]}.
  Future<List<Map<String, dynamic>>> visible(List<String> itemIds);

  /// The photo's bytes (an approved gallery photo the worker may read).
  Future<Uint8List> download(String path);
}

class SupabaseHistoryRemote implements HistoryRemote {
  SupabaseHistoryRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> search(HistoryQuery q, {required int offset, required int limit}) async =>
      Map<String, dynamic>.from(
          await _client.rpc('pr_history_search', params: searchParams(q, offset: offset, limit: limit)).timeout(_readTimeout) as Map);

  @override
  Future<Map<String, dynamic>> item(String itemId) async =>
      Map<String, dynamic>.from(await _client.rpc('pr_history_item', params: {'p_item': itemId}).timeout(_readTimeout) as Map);

  @override
  Future<List<Map<String, dynamic>>> visible(List<String> itemIds) async => [
        for (final r in (await _client.rpc('pr_history_visible', params: {'p_items': itemIds}).timeout(_readTimeout) as List<dynamic>? ??
            const []))
          Map<String, dynamic>.from(r as Map),
      ];

  @override
  Future<Uint8List> download(String path) => _client.storage.from(galleryBucket).download(path).timeout(_downloadTimeout);
}
