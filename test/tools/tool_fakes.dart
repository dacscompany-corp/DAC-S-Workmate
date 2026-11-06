import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/tools/data/tool_pending_store.dart';
import 'package:workmate/tools/data/tools_remote.dart';
import 'package:workmate/tools/domain/tool_models.dart';
import 'package:workmate/tools/domain/tool_submission.dart';

import 'server_answers.dart';

List<Map<String, dynamic>> answerRows(String json) =>
    [for (final r in jsonDecode(json) as List<dynamic>) Map<String, dynamic>.from(r as Map)];
Map<String, dynamic> answerDoc(String json) => Map<String, dynamic>.from(jsonDecode(json) as Map);

PostgrestException refusal(String code) => PostgrestException(message: code, code: 'P0001');

/// The tools server, as the phone sees it, in memory: what each call was sent,
/// and canned answers or refusals — by default the real answers captured from
/// the 3b-a suite (server_answers.dart). Like `pur_ops`, an operation id it
/// has recorded is answered again with the first answer (and `replayed`),
/// whatever the payload. A cancelled id is refused OP_CANCELLED, as 0106's
/// lock does.
class FakeToolsRemote implements ToolsRemote {
  FakeToolsRemote({List<PhoneTool>? mine, List<PhoneTool>? team, List<LeaderRecord>? records, TeamChoices? choices})
      : mineAnswer = mine ?? answerRows(myToolsJson).map(PhoneTool.fromJson).toList(),
        teamAnswer = team ?? answerRows(teamToolsJson).map(PhoneTool.fromJson).toList(),
        recordsAnswer = records ?? answerRows(myRecordsJson).map(LeaderRecord.fromJson).toList(),
        choicesAnswer = choices ?? TeamChoices.fromJson(answerDoc(choicesJson));

  List<PhoneTool> mineAnswer;
  List<PhoneTool> teamAnswer;
  List<LeaderRecord> recordsAnswer;
  TeamChoices choicesAnswer;
  FoundTool? foundAnswer = FoundTool.fromJson(answerDoc(findJson));
  List<ToolRequestLine> linesAnswer = answerRows(requestLinesJson).map(ToolRequestLine.fromJson).toList();

  /// Thrown by every read (until cleared).
  Object? failReads;

  /// Thrown by My tools only (TOOLS_OFF, NOT_A_REQUESTER …).
  Object? failMine;

  /// Thrown by the leader's reads only (NOT_LEADER …).
  Object? failTeam;

  /// Thrown by the next write before it records.
  Object? failNextWrite;

  /// The next write is recorded, then its answer is lost (this is thrown).
  Object? loseNextAnswer;

  /// The next cancel is done on the server, then its answer is lost.
  Object? loseNextCancel;

  /// Ids cancelled for good, per account: 'userId:opId'.
  final cancelled = <String>{};

  /// What the server recorded, once per operation id.
  final writes = <(String fn, Map<String, dynamic> params, String userId)>[];

  /// Every write that reached the call, failed ones included: (op id, exact payload).
  final attempts = <(String opId, String payload)>[];
  int mineCalls = 0;
  int teamCalls = 0;
  int checks = 0;
  int cancels = 0;
  final finds = <String>[];

  Future<T> _read<T>(T value, [Object? also]) async {
    final f = failReads ?? also;
    if (f != null) throw f;
    return value;
  }

  @override
  Future<List<PhoneTool>> myTools() {
    mineCalls++;
    return _read(mineAnswer, failMine);
  }

  /// One tool's page: the captured answer with its history when it is that
  /// tool, otherwise the list's own row.
  PhoneTool _detail(String json, List<PhoneTool> list, String toolId) {
    final d = PhoneTool.fromJson(answerDoc(json));
    return d.id == toolId ? d : list.firstWhere((t) => t.id == toolId);
  }

  @override
  Future<PhoneTool> myTool(String toolId) => _read(_detail(myToolJson, mineAnswer, toolId), failMine);

  @override
  Future<List<PhoneTool>> teamTools() {
    teamCalls++;
    return _read(teamAnswer, failTeam);
  }

  @override
  Future<PhoneTool> teamTool(String toolId) => _read(_detail(teamToolJson, teamAnswer, toolId), failTeam);

  @override
  Future<FoundTool> find(String number) async {
    finds.add(number);
    final f = failReads ?? failTeam;
    if (f != null) throw f;
    final found = foundAnswer;
    if (found == null) throw refusal('TOOL_NOT_AVAILABLE');
    return found;
  }

  @override
  Future<TeamChoices> choices() => _read(choicesAnswer, failTeam);

  @override
  Future<List<ToolRequestLine>> requestLines(String toolId, String folderId) => _read(linesAnswer, failTeam);

  @override
  Future<List<LeaderRecord>> myRecords() => _read(recordsAnswer, failTeam);

  @override
  Future<Map<String, dynamic>> write(ToolWrite w, Map<String, dynamic> params, {required String userId}) async {
    final op = params['p_op'] as String;
    attempts.add((op, jsonEncode(params)));
    final f = failNextWrite;
    if (f != null) {
      failNextWrite = null;
      throw f;
    }
    if (cancelled.contains('$userId:$op')) throw refusal('OP_CANCELLED');
    final i = writes.indexWhere((x) => x.$2['p_op'] == op && x.$3 == userId);
    final answer = {'record_id': 'rec-${i < 0 ? writes.length + 1 : i + 1}', 'tool_id': 't'};
    if (i >= 0) return {...answer, 'replayed': true};
    writes.add((w.fn, params, userId));
    final lost = loseNextAnswer;
    if (lost != null) {
      loseNextAnswer = null;
      throw lost;
    }
    return answer;
  }

  String _state(String opId, String userId) => writes.any((w) => w.$3 == userId && w.$2['p_op'] == opId)
      ? 'recorded'
      : (cancelled.contains('$userId:$opId') ? 'cancelled' : 'none');

  @override
  Future<String> opState(String opId, {required String userId}) {
    checks++;
    return _read(_state(opId, userId));
  }

  @override
  Future<String> cancelOp(String opId, {required String userId}) async {
    cancels++;
    final f = failReads;
    if (f != null) throw f;
    final now = _state(opId, userId);
    if (now == 'none') cancelled.add('$userId:$opId');
    final lost = loseNextCancel;
    if (lost != null) {
      loseNextCancel = null;
      throw lost;
    }
    return now == 'recorded' ? 'recorded' : 'cancelled';
  }
}

/// Tests only: tool submissions kept in memory. The app always keeps them in
/// the phone's settings file (PrefsToolPendingStore).
class MemoryToolPendingStore implements ToolPendingStore {
  List<ToolSubmission> _all = [];

  @override
  Future<ToolPendingLoad> load() async => ToolPendingLoad(readable: List.of(_all));

  @override
  Future<void> save(List<ToolSubmission> readable) async => _all = List.of(readable);

  @override
  Future<void> dropUnreadable(String userId, String opId) async {}
}
