import 'package:supabase_flutter/supabase_flutter.dart';

import '../../attendance/domain/event_id.dart';
import '../domain/stock_models.dart';
import '../domain/stock_submission.dart';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 30);

/// Stock on the phone (Q26): online only — every read and write is one call
/// to 0104/0105's `stk_*` functions, the same ones the web Stock tab uses.
/// Nothing is queued: a write whose answer was lost is kept by
/// [StockSubmitter] and sent again unchanged, so it records once (`pur_ops`).
abstract class StockRemote {
  Future<StockStatus> status();
  Future<StockOverview> overview();
  Future<StockChoices> choices();
  Future<List<StockRequestLine>> requestLines(String folderId);
  Future<List<StockLine>> projectLines(String folderId);

  // Writes and checks refuse to act for another account than the signed-in
  // one (AUTH_REQUIRED): a shared site phone could otherwise send for, or
  // misread the records of, the last user.

  /// One stock write, its parameters exactly as given (`p_op` included).
  Future<Map<String, dynamic>> write(StockWrite write, Map<String, dynamic> params, {required String userId});

  /// The phone's Check, read only (0106's `pur_op_state`): 'recorded',
  /// 'cancelled' or 'none' for the signed-in account's own operation id.
  Future<String> opState(String opId, {required String userId});

  /// The phone's Cancel (0106's `pur_op_cancel`): under the operation's own
  /// lock the server answers 'recorded' (it was — nothing changes) or
  /// 'cancelled' (for good: a late request with this id is refused).
  Future<String> cancelOp(String opId, {required String userId});
}

/// One operation id per submission, made once and kept with its payload —
/// a lost answer sent again is answered, never recorded twice (R101).
String newStockOpId() => newEventId();

class SupabaseStockRemote implements StockRemote {
  SupabaseStockRemote(this._client);

  final SupabaseClient _client;

  void _same(String userId) {
    final session = _client.auth.currentUser?.id;
    if (session == null || session != userId) throw StateError('AUTH_REQUIRED');
  }

  Future<Object?> _read(String fn, [Map<String, dynamic>? params]) => _client.rpc(fn, params: params).timeout(_readTimeout);

  Future<Map<String, dynamic>> _write(String fn, Map<String, dynamic> params, String userId) async {
    _same(userId);
    final result = await _client.rpc(fn, params: params).timeout(_rpcTimeout);
    return Map<String, dynamic>.from(result as Map);
  }

  List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

  @override
  Future<StockStatus> status() async => StockStatus.fromJson(Map<String, dynamic>.from(await _read('stk_status') as Map));

  @override
  Future<StockOverview> overview() async => StockOverview.fromJson(Map<String, dynamic>.from(await _read('stk_overview') as Map));

  @override
  Future<StockChoices> choices() async => StockChoices.fromJson(Map<String, dynamic>.from(await _read('stk_choices') as Map));

  @override
  Future<List<StockRequestLine>> requestLines(String folderId) async =>
      _rows(await _read('stk_request_lines', {'p_folder': folderId})).map(StockRequestLine.fromJson).toList();

  @override
  Future<List<StockLine>> projectLines(String folderId) async =>
      _rows(await _read('stk_project_lines', {'p_folder': folderId})).map(StockLine.fromJson).toList();

  @override
  Future<Map<String, dynamic>> write(StockWrite write, Map<String, dynamic> params, {required String userId}) =>
      _write(write.fn, params, userId);

  @override
  Future<String> opState(String opId, {required String userId}) async {
    _same(userId);
    return await _read('pur_op_state', {'p_op': opId}) as String;
  }

  @override
  Future<String> cancelOp(String opId, {required String userId}) async {
    _same(userId);
    return await _client.rpc('pur_op_cancel', params: {'p_op': opId}).timeout(_rpcTimeout) as String;
  }
}
