import 'dart:async';

import 'package:workmate/requests/data/request_remote.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/quantity.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/requests/domain/request_op.dart';

const site = Destination(projectId: 'f1', projectName: 'Santos Townhouse', workId: 'f1', workName: 'Main Contract', isMain: true);
const fence = Destination(projectId: 'f1', projectName: 'Santos Townhouse', workId: 'f9', workName: 'AW-03 Fence', isMain: false);
const pipe = CatalogItem(id: 'c1', kind: ItemKind.material, name: 'PVC pipe', spec: '1/2 in', unit: 'pc', category: 'plumbing');
const drill = CatalogItem(id: 'c2', kind: ItemKind.tool, name: 'Drill', spec: 'cordless', unit: 'pc', category: '');
const masonry = MyTeam(id: 't1', name: 'Masonry A', iLead: true, members: [
  TeamMember(id: 'u1', name: 'Juan'),
  TeamMember(id: 'u2', name: 'Pedro'),
]);

/// A RequestRemote whose every answer the test sets, recording every call.
class FakeRequestRemote implements RequestRemote {
  List<Destination> dests = [site, fence];
  List<MyTeam> teams = [masonry];
  List<CatalogItem> items = [pipe, drill];
  Object? readError;

  List<Map<String, dynamic>> requests = [];
  Object? requestsError;

  /// Thrown by the next write (then cleared), or by every write while [writeErrorSticky].
  Object? writeError;
  bool writeErrorSticky = false;

  final calls = <String>[];
  final quantityBases = <int>[];
  Map<String, dynamic> quantityResult = {'status': 'applied', 'version': 2, 'needed': 8};
  final attached = <String>[];
  int submits = 0;

  void _maybeFail() {
    final e = writeError;
    if (e == null) return;
    if (!writeErrorSticky) writeError = null;
    throw e;
  }

  @override
  Future<List<Destination>> destinations() async {
    if (readError != null) throw readError!;
    return dests;
  }

  @override
  Future<List<MyTeam>> myTeams() async {
    if (readError != null) throw readError!;
    return teams;
  }

  @override
  Future<List<CatalogItem>> catalog() async {
    if (readError != null) throw readError!;
    return items;
  }

  @override
  Future<List<Map<String, dynamic>>> myRequests() async {
    if (requestsError != null) throw requestsError!;
    return requests;
  }

  @override
  Future<Map<String, dynamic>> submit(String opId, Map<String, dynamic> payload, {required String workerId}) async {
    calls.add('submit:$opId');
    _maybeFail();
    submits++;
    final lines = payload['lines'] as List;
    return {
      'request_id': 'r$submits',
      'received_at': '2026-10-05T03:00:00+00:00',
      'line_ids': [for (var i = 0; i < lines.length; i++) 'r$submits-l$i'],
    };
  }

  @override
  Future<Map<String, dynamic>> changeQuantity(String opId, String lineId, int baseVersion, double quantity, {required String workerId}) async {
    calls.add('quantity:$lineId:$quantity');
    _maybeFail();
    quantityBases.add(baseVersion);
    return quantityResult;
  }

  @override
  Future<Map<String, dynamic>> cancelLine(String opId, String lineId, {required String workerId}) async {
    calls.add('cancelLine:$lineId');
    _maybeFail();
    return {'status': 'cancelled', 'version': 3};
  }

  @override
  Future<Map<String, dynamic>> cancelRequest(String opId, String requestId, {required String workerId}) async {
    calls.add('cancelRequest:$requestId');
    _maybeFail();
    return {'status': 'cancelled', 'lines': 1};
  }

  @override
  Future<void> attachPhoto({
    required String opId,
    required String requestId,
    required String? lineId,
    required String photoId,
    required String localPath,
    required String workerId,
  }) async {
    calls.add('photo:$requestId:$lineId');
    _maybeFail();
    attached.add(requestPhotoPath(workerId: workerId, requestId: requestId, photoId: photoId));
  }

  @override
  Future<String?> signedUrl(String path) async => 'https://signed/$path';
}

/// A RequestsApi for controllers and screens: in-memory, recording calls.
class FakeRequestsApi implements RequestsApi {
  RequestReferences refs = const RequestReferences(destinations: [site, fence], teams: [masonry], catalog: [pipe, drill]);
  Object? refsError;
  RequestsView view = const RequestsView(entries: []);
  Object? viewError;
  Completer<void>? viewGate;
  int viewReads = 0;
  final savedDrafts = <String, RequestDraft>{};
  final sent = <RequestDraft>[];
  Object? sendError;
  final calls = <String>[];
  final discarded = <String>[];
  var _ids = 0;

  @override
  Future<RequestReferences> references() async {
    if (refsError != null) throw refsError!;
    return refs;
  }

  @override
  Future<List<RequestDraft>> drafts() async => savedDrafts.values.toList();

  @override
  RequestDraft newDraft() => RequestDraft(id: 'd${++_ids}', createdAt: DateTime.utc(2026, 10, 5, 1));

  /// Thrown by every [saveDraft] while set.
  Object? saveError;

  @override
  Future<void> saveDraft(RequestDraft draft) async {
    if (saveError != null) throw saveError!;
    savedDrafts[draft.id] = draft;
  }

  @override
  Future<void> deleteDraft(RequestDraft draft) async {
    calls.add('deleteDraft:${draft.id}');
    savedDrafts.remove(draft.id);
  }

  /// Thrown by [keepPhoto] while set.
  Object? keepError;

  @override
  Future<String> keepPhoto(String draftId, String capturedPath) async {
    if (keepError != null) throw keepError!;
    return '/kept/$draftId/${++_ids}.jpg';
  }

  @override
  Future<void> discardPhoto(String path) async => discarded.add(path);

  @override
  Future<void> send(RequestDraft draft) async {
    if (sendError != null) throw sendError!;
    final issues = draftIssues(draft);
    if (issues.isNotEmpty) throw DraftInvalid(issues);
    sent.add(draft);
    savedDrafts.remove(draft.id);
  }

  @override
  Future<RequestsView> myRequests() async {
    if (viewError != null) throw viewError!;
    viewReads++;
    final snapshot = view; // what the server held when the read started
    final gate = viewGate;
    if (gate != null) await gate.future;
    return snapshot;
  }

  @override
  Future<void> changeQuantity(RemoteRequest request, RemoteLine line, double quantity) async =>
      calls.add('quantity:${line.id}:${formatQuantity(quantity)}');

  @override
  Future<void> cancelLine(RemoteRequest request, RemoteLine line) async => calls.add('cancelLine:${line.id}');

  @override
  Future<void> cancelRequest(RemoteRequest request) async => calls.add('cancelRequest:${request.id}');

  /// What [returnToDrafts] answers. True moves the draft from [view] back
  /// to the drafts, as the repository does; false (refused) changes nothing.
  bool returnToDraftsResult = true;

  @override
  Future<bool> returnToDrafts(String draftId) async {
    calls.add('returnToDrafts:$draftId');
    if (!returnToDraftsResult) return false;
    final draft = view.entries.where((e) => e.draft?.id == draftId).firstOrNull?.draft;
    if (draft != null) {
      savedDrafts[draftId] = draft;
      view = RequestsView(entries: view.entries.where((e) => e.draft?.id != draftId).toList());
    }
    return true;
  }

  @override
  Future<void> dismissFailed(RequestOp op) async => calls.add('dismiss:${op.opId}');

  @override
  Future<String?> photoUrl(String path) async => null;
}
