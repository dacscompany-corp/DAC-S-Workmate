import 'package:supabase_flutter/supabase_flutter.dart';

import '../../attendance/domain/event_id.dart';
import '../domain/tool_models.dart';
import '../domain/tool_submission.dart';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 30);

/// Tools on the phone (3b): every read and write is one call to 0111's
/// functions — the worker's own tools, a leader's team, and the five writes.
/// The server checks the team on every call, never the role alone. Writes are
/// never queued: a write whose answer was lost is kept by [ToolSubmitter] and
/// sent again unchanged, so it records once (`pur_ops`, Q22).
abstract class ToolsRemote {
  /// `tl_my_tools`: the tools the caller holds now.
  Future<List<PhoneTool>> myTools();

  /// `tl_my_tool`: one tool's records while the caller had it.
  Future<PhoneTool> myTool(String toolId);

  /// `tl_team_tools`: the tools of the current members of the teams the caller leads now.
  Future<List<PhoneTool>> teamTools();

  /// `tl_team_tool`: one of those, with its records while its holder had it.
  Future<PhoneTool> teamTool(String toolId);

  /// `tl_team_find`: an Available tool of this company by its typed number.
  Future<FoundTool> find(String number);

  /// `tl_team_choices`: who the leader may record for, and the open projects.
  Future<TeamChoices> choices();

  /// `tl_team_request_lines`: the tool request lines this tool can fill there.
  Future<List<ToolRequestLine>> requestLines(String toolId, String folderId);

  /// `tl_team_my_records`: the leader's own recent records, and which they can still undo.
  Future<List<LeaderRecord>> myRecords();

  // Writes and checks refuse to act for another account than the signed-in
  // one (AUTH_REQUIRED): a shared site phone could otherwise send for, or
  // misread the records of, the last user.

  /// One tool write, its parameters exactly as given (`p_op` included).
  Future<Map<String, dynamic>> write(ToolWrite write, Map<String, dynamic> params, {required String userId});

  /// The phone's Check, read only (0106's `pur_op_state`): 'recorded',
  /// 'cancelled' or 'none' for the signed-in account's own operation id.
  Future<String> opState(String opId, {required String userId});

  /// The phone's Cancel (0106's `pur_op_cancel`): under the operation's own
  /// lock the server answers 'recorded' (it was — nothing changes) or
  /// 'cancelled' (for good: a late request with this id is refused).
  Future<String> cancelOp(String opId, {required String userId});
}

/// One operation id per submission, made once and kept with its payload —
/// a lost answer sent again is answered, never recorded twice.
String newToolOpId() => newEventId();

class SupabaseToolsRemote implements ToolsRemote {
  SupabaseToolsRemote(this._client);

  final SupabaseClient _client;

  /// Every function the phone calls, with its parameter names: the
  /// contract test holds this list to 0111.
  static const calls = <String, List<String>>{
    'tl_my_tools': [],
    'tl_my_tool': ['p_tool'],
    'tl_team_tools': [],
    'tl_team_tool': ['p_tool'],
    'tl_team_find': ['p_number'],
    'tl_team_choices': [],
    'tl_team_request_lines': ['p_tool', 'p_folder'],
    'tl_team_my_records': ['p_limit'],
    'tl_team_issue': ['p_op', 'p_body'],
    'tl_team_handover': ['p_op', 'p_body'],
    'tl_team_return': ['p_op', 'p_body'],
    'tl_team_reverse': ['p_op', 'p_record', 'p_reason'],
    'tl_report_problem': ['p_op', 'p_tool', 'p_kind', 'p_note'],
    'pur_op_state': ['p_op'],
    'pur_op_cancel': ['p_op'],
  };

  void _same(String userId) {
    final session = _client.auth.currentUser?.id;
    if (session == null || session != userId) throw StateError('AUTH_REQUIRED');
  }

  Future<Object?> _read(String fn, [Map<String, dynamic>? params]) => _client.rpc(fn, params: params).timeout(_readTimeout);

  Map<String, dynamic> _doc(Object? v) => Map<String, dynamic>.from(v as Map);
  List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

  @override
  Future<List<PhoneTool>> myTools() async => _rows(await _read('tl_my_tools')).map(PhoneTool.fromJson).toList();

  @override
  Future<PhoneTool> myTool(String toolId) async => PhoneTool.fromJson(_doc(await _read('tl_my_tool', {'p_tool': toolId})));

  @override
  Future<List<PhoneTool>> teamTools() async => _rows(await _read('tl_team_tools')).map(PhoneTool.fromJson).toList();

  @override
  Future<PhoneTool> teamTool(String toolId) async => PhoneTool.fromJson(_doc(await _read('tl_team_tool', {'p_tool': toolId})));

  @override
  Future<FoundTool> find(String number) async => FoundTool.fromJson(_doc(await _read('tl_team_find', {'p_number': number})));

  @override
  Future<TeamChoices> choices() async => TeamChoices.fromJson(_doc(await _read('tl_team_choices')));

  @override
  Future<List<ToolRequestLine>> requestLines(String toolId, String folderId) async =>
      _rows(await _read('tl_team_request_lines', {'p_tool': toolId, 'p_folder': folderId})).map(ToolRequestLine.fromJson).toList();

  @override
  Future<List<LeaderRecord>> myRecords() async =>
      _rows(await _read('tl_team_my_records', {'p_limit': 30})).map(LeaderRecord.fromJson).toList();

  @override
  Future<Map<String, dynamic>> write(ToolWrite write, Map<String, dynamic> params, {required String userId}) async {
    _same(userId);
    final result = await _client.rpc(write.fn, params: params).timeout(_rpcTimeout);
    return _doc(result);
  }

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
