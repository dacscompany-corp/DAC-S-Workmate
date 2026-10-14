import 'dart:async';

import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/data/workplan_remote.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/domain/wp_task.dart';

import 'workplan_samples.dart';

export 'workplan_samples.dart';

/// One unread task, as My Work shows it.
WorkPlanView viewWithUnread() => WorkPlanView(entries: [WpEntry(task: task0())], notes: [WpNote.fromJson(noteDoc())]);

/// A WorkPlanRemote whose every answer the test sets, recording every call.
class FakeWorkPlanRemote implements WorkPlanRemote {
  List<Map<String, dynamic>> work = [taskDoc()];
  List<Map<String, dynamic>> notes = [noteDoc()];
  List<Map<String, dynamic>> proposals = [];
  List<Destination> dests = [barlin];
  List<MyTeam> teams = [pilotB, otherTeam];
  Object? readError;

  /// Every read waits for it while set (an answer still travelling).
  Completer<void>? readGate;

  /// The task every accepted action answers with (0093 returns it); null
  /// answers an empty map.
  Map<String, dynamic>? taskAnswer;

  /// Thrown by the next write (then cleared), or by every write while [writeErrorSticky].
  Object? writeError;
  bool writeErrorSticky = false;

  final calls = <String>[];
  final attached = <String>[];
  Map<String, dynamic> ackResult = {'stale': false, 'task': {}};
  int events = 0;
  int blockerIds = 0;

  /// Thrown by every write of that kind ('ack', 'start', 'progress',
  /// 'blocker', 'done', 'check', 'propose', 'photo').
  final failOn = <String, Object>{};

  void _maybeFail([String? kind]) {
    final own = failOn[kind];
    if (own != null) throw own;
    final e = writeError;
    if (e == null) return;
    if (!writeErrorSticky) writeError = null;
    throw e;
  }

  Future<List<Map<String, dynamic>>> _read(List<Map<String, dynamic>> v) async {
    final gate = readGate;
    if (gate != null) await gate.future;
    if (readError != null) throw readError!;
    return v;
  }

  Map<String, dynamic> get _answer => {'task': taskAnswer ?? {}};

  @override
  Future<List<Map<String, dynamic>>> myWork() => _read(work);

  @override
  Future<List<Map<String, dynamic>>> myNotes() => _read(notes);

  @override
  Future<List<Map<String, dynamic>>> myProposals() => _read(proposals);

  @override
  Future<List<Destination>> destinations() async {
    final gate = readGate;
    if (gate != null) await gate.future;
    if (readError != null) throw readError!;
    return dests;
  }

  @override
  Future<List<MyTeam>> myTeams() async {
    final gate = readGate;
    if (gate != null) await gate.future;
    if (readError != null) throw readError!;
    return teams;
  }

  @override
  Future<Map<String, dynamic>> acknowledge(String opId, String taskId, int version, {required String workerId}) async {
    calls.add('ack:$taskId:$version');
    _maybeFail('ack');
    return ackResult;
  }

  @override
  Future<Map<String, dynamic>> startWork(String opId, String taskId, {required String workerId}) async {
    calls.add('start:$taskId');
    _maybeFail('start');
    return _answer;
  }

  @override
  Future<Map<String, dynamic>> reportProgress(String opId, String taskId, String note, {required String workerId}) async {
    calls.add('progress:$taskId:$note');
    _maybeFail('progress');
    return {'event_id': ++events, ..._answer};
  }

  @override
  Future<Map<String, dynamic>> reportBlocker(String opId, String taskId, String kind, String description, String? requestId,
      {required String workerId}) async {
    calls.add('blocker:$taskId:$kind:$description:$requestId');
    _maybeFail('blocker');
    return {'blocker_id': 'b${++blockerIds}', ..._answer};
  }

  @override
  Future<Map<String, dynamic>> reportDone(String opId, String taskId, String note, {required String workerId}) async {
    calls.add('done:$taskId');
    _maybeFail('done');
    return _answer;
  }

  @override
  Future<Map<String, dynamic>> leaderCheck(String opId, String taskId, String note, {required String workerId}) async {
    calls.add('check:$taskId');
    _maybeFail('check');
    return _answer;
  }

  @override
  Future<Map<String, dynamic>> propose(String opId, Map<String, dynamic> body, {required String workerId}) async {
    calls.add('propose:${body['title']}:${body['team_id']}:${body['folder_id']}:${body['work_id']}');
    _maybeFail('propose');
    return {'task_id': 'new'};
  }

  @override
  Future<void> attachPhoto({
    required String opId,
    required String taskId,
    required String? blockerId,
    required int? eventId,
    required String photoId,
    required String localPath,
    required String workerId,
  }) async {
    calls.add('photo:$taskId:$blockerId:$eventId');
    _maybeFail('photo');
    attached.add(taskPhotoPath(workerId: workerId, taskId: taskId, photoId: photoId));
  }

  @override
  Future<String?> signedUrl(String path) async => 'https://signed/$path';
}

/// A WorkPlanApi for controllers and screens: in-memory, recording calls.
class FakeWorkPlanApi implements WorkPlanApi {
  WorkPlanView view = WorkPlanView(entries: [], notes: [WpNote.fromJson(noteDoc())]);
  Object? loadError;
  Completer<void>? loadGate;
  int loads = 0;
  WpChoices choicesResult = const WpChoices(teams: [pilotB], destinations: [barlin]);
  Object? choicesError;
  final calls = <String>[];
  final discarded = <String>[];
  var _ids = 0;

  @override
  Future<WorkPlanView> load() async {
    loads++;
    final snapshot = view;
    final gate = loadGate;
    if (gate != null) await gate.future;
    if (loadError != null) throw loadError!;
    return snapshot;
  }

  @override
  Future<void> acknowledge(WpTask task) async => calls.add('ack:${task.id}:${task.version}');

  @override
  Future<void> startWork(WpTask task) async => calls.add('start:${task.id}');

  @override
  Future<void> reportProgress(WpTask task, String note, {String? photo}) async => calls.add('progress:${task.id}:$note:$photo');

  @override
  Future<void> reportProblem(WpTask task, {required String kind, required String description, String? requestId, String? photo}) async =>
      calls.add('problem:${task.id}:$kind:$description:$requestId:$photo');

  @override
  Future<void> reportDone(WpTask task, String note) async => calls.add('done:${task.id}:$note');

  @override
  Future<void> checkWork(WpTask task, String note) async => calls.add('check:${task.id}:$note');

  @override
  Future<WpChoices> choices() async {
    if (choicesError != null) throw choicesError!;
    return choicesResult;
  }

  @override
  Future<void> propose({required MyTeam team, required Destination destination, required String title, required String details}) async =>
      calls.add('propose:${team.id}:${destination.workId}:$title:$details');

  @override
  Future<String> keepPhoto(String capturedPath) async => '/kept/${++_ids}.jpg';

  @override
  Future<void> discardPhoto(String path) async => discarded.add(path);

  @override
  Future<void> dismissFailed(WpOp op) async => calls.add('dismiss:${op.opId}');

  @override
  Future<String?> photoUrl(String path) async => null;

  /// Thrown by [keepOnly] while set.
  Object? keepError;

  @override
  Future<void> keepOnly(String workerId) async {
    calls.add('keepOnly:$workerId');
    if (keepError != null) throw keepError!;
  }
}
