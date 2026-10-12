import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:workmate/history/data/history_api.dart';
import 'package:workmate/history/data/history_remote.dart';
import 'package:workmate/history/domain/history_models.dart';

import 'history_samples.dart';

/// A HistoryRemote whose answers the test sets, recording every call.
class FakeHistoryRemote implements HistoryRemote {
  Map<String, dynamic> searchAnswer = {'items': [cardJson()], 'has_more': false};
  final items = <String, Map<String, dynamic>>{'i1': itemJson()};
  List<Map<String, dynamic>>? visibleAnswer;

  /// Thrown by every call while set (e.g. a SocketException for "no signal").
  Object? error;
  final calls = <String>[];
  final downloads = <String>[];
  int photoBytes = 10;
  Future<void> Function()? beforeVisibleAnswer;

  void _maybeFail() {
    if (error != null) throw error!;
  }

  @override
  Future<Map<String, dynamic>> search(HistoryQuery q, {required int offset, required int limit}) async {
    calls.add('search:${q.text}:$offset');
    _maybeFail();
    return searchAnswer;
  }

  @override
  Future<Map<String, dynamic>> item(String itemId) async {
    calls.add('item:$itemId');
    _maybeFail();
    final j = items[itemId];
    if (j == null) throw Exception('HISTORY_NOT_AVAILABLE');
    return j;
  }

  @override
  Future<List<Map<String, dynamic>>> visible(List<String> itemIds) async {
    calls.add('visible:${itemIds.join(',')}');
    if (beforeVisibleAnswer != null) await beforeVisibleAnswer!();
    _maybeFail();
    return visibleAnswer ?? const [];
  }

  @override
  Future<Uint8List> download(String path) async {
    downloads.add(path);
    _maybeFail();
    return Uint8List(photoBytes);
  }
}

/// A HistoryApi for screen tests.
class FakeHistoryApi implements HistoryApi {
  HistoryPage page = HistoryPage.fromJson({'items': [cardJson()], 'has_more': false});
  final items = <String, HistoryItemView>{'i1': HistoryItemView(item: HistoryItem.fromJson(itemJson())!)};

  /// Thrown by search / item while set.
  Object? error;

  /// While set, every search waits for it (a search still running).
  Completer<void>? gate;
  final queries = <HistoryQuery>[];
  int refreshes = 0;
  final kept = <String>[];
  Object? keepError;

  @override
  Future<HistoryPage> search(HistoryQuery q, {int offset = 0}) async {
    queries.add(q);
    final g = gate;
    if (g != null) await g.future;
    if (error != null) throw error!;
    return page;
  }

  @override
  Future<HistoryItemView> item(String itemId) async {
    if (error != null) throw error!;
    final v = items[itemId];
    if (v == null) throw Exception('HISTORY_NOT_AVAILABLE');
    return v;
  }

  @override
  Future<void> refreshSaved() async => refreshes++;

  @override
  Future<File?> photo(String path) async => null;

  @override
  Future<void> keepOnly(String workerId) async {
    kept.add(workerId);
    if (keepError != null) throw keepError!;
  }
}
