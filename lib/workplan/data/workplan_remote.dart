import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../requests/data/request_remote.dart' show isAlreadyUploaded;
import '../../requests/domain/request_models.dart';

/// The private bucket every task photo lives in (0093; never `uploads`).
const taskPhotoBucket = 'task-photos';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 20);
const _uploadTimeout = Duration(seconds: 60);

/// {uploader}/{task}/{photo}.jpg — the only shape 0093's upload policy and
/// wp_attach_photo accept.
String taskPhotoPath({required String workerId, required String taskId, required String photoId}) =>
    '$workerId/$taskId/$photoId.jpg';

// The RPC arguments — exactly the 0093 signatures.
Map<String, dynamic> ackParams(String opId, String taskId, int version) => {'p_op': opId, 'p_task': taskId, 'p_version': version};

Map<String, dynamic> taskParams(String opId, String taskId) => {'p_op': opId, 'p_task': taskId};

Map<String, dynamic> noteParams(String opId, String taskId, String note) => {'p_op': opId, 'p_task': taskId, 'p_note': note};

Map<String, dynamic> blockerParams(String opId, String taskId, String kind, String description, String? requestId) =>
    {'p_op': opId, 'p_task': taskId, 'p_kind': kind, 'p_description': description, 'p_request': requestId};

Map<String, dynamic> proposeParams(String opId, String teamId, String folderId, String workId, String title, String details) =>
    {'p_op': opId, 'p_team': teamId, 'p_folder': folderId, 'p_work': workId, 'p_title': title, 'p_details': details};

Map<String, dynamic> attachTaskPhotoParams(String opId, String taskId, String? blockerId, int? eventId, String path) =>
    {'p_op': opId, 'p_task': taskId, 'p_blocker': blockerId, 'p_event': eventId, 'p_path': path};

abstract class WorkPlanRemote {
  /// wp_my_work: every published task the caller has a role on (raw docs).
  Future<List<Map<String, dynamic>>> myWork();

  /// wp_my_notes: the latest shared notes the caller receives.
  Future<List<Map<String, dynamic>>> myNotes();

  /// wp_my_proposals: the caller's own proposals (90 days).
  Future<List<Map<String, dynamic>>> myProposals();

  /// For proposing: open projects / works, and the teams the caller is in.
  Future<List<Destination>> destinations();
  Future<List<MyTeam>> myTeams();

  // Every write files under the CURRENT session: if it is not [workerId], it
  // throws AUTH_REQUIRED instead of sending another worker's change.
  Future<Map<String, dynamic>> acknowledge(String opId, String taskId, int version, {required String workerId});
  Future<Map<String, dynamic>> startWork(String opId, String taskId, {required String workerId});
  Future<Map<String, dynamic>> reportProgress(String opId, String taskId, String note, {required String workerId});
  Future<Map<String, dynamic>> reportBlocker(String opId, String taskId, String kind, String description, String? requestId,
      {required String workerId});
  Future<Map<String, dynamic>> reportDone(String opId, String taskId, String note, {required String workerId});
  Future<Map<String, dynamic>> leaderCheck(String opId, String taskId, String note, {required String workerId});
  Future<Map<String, dynamic>> propose(String opId, Map<String, dynamic> body, {required String workerId});

  /// Uploads the photo, THEN links it (a row must never point at a missing file).
  Future<void> attachPhoto({
    required String opId,
    required String taskId,
    required String? blockerId,
    required int? eventId,
    required String photoId,
    required String localPath,
    required String workerId,
  });

  /// A 10-minute link to one private photo, or null.
  Future<String?> signedUrl(String path);
}

class SupabaseWorkPlanRemote implements WorkPlanRemote {
  SupabaseWorkPlanRemote(this._client);

  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? result) =>
      [for (final r in (result as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

  void _sameWorker(String workerId) {
    final session = _client.auth.currentUser?.id;
    if (session == null || session != workerId) throw StateError('AUTH_REQUIRED');
  }

  Future<Map<String, dynamic>> _write(String fn, Map<String, dynamic> params, String workerId) async {
    _sameWorker(workerId);
    final result = await _client.rpc(fn, params: params).timeout(_rpcTimeout);
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> myWork() async => _rows(await _client.rpc('wp_my_work').timeout(_readTimeout));

  @override
  Future<List<Map<String, dynamic>>> myNotes() async => _rows(await _client.rpc('wp_my_notes').timeout(_readTimeout));

  @override
  Future<List<Map<String, dynamic>>> myProposals() async => _rows(await _client.rpc('wp_my_proposals').timeout(_readTimeout));

  @override
  Future<List<Destination>> destinations() async =>
      _rows(await _client.rpc('pr_destinations').timeout(_readTimeout)).map(Destination.fromRow).toList();

  @override
  Future<List<MyTeam>> myTeams() async => _rows(await _client.rpc('pr_my_teams').timeout(_readTimeout)).map(MyTeam.fromRow).toList();

  @override
  Future<Map<String, dynamic>> acknowledge(String opId, String taskId, int version, {required String workerId}) =>
      _write('wp_acknowledge', ackParams(opId, taskId, version), workerId);

  @override
  Future<Map<String, dynamic>> startWork(String opId, String taskId, {required String workerId}) =>
      _write('wp_start_work', taskParams(opId, taskId), workerId);

  @override
  Future<Map<String, dynamic>> reportProgress(String opId, String taskId, String note, {required String workerId}) =>
      _write('wp_report_progress', noteParams(opId, taskId, note), workerId);

  @override
  Future<Map<String, dynamic>> reportBlocker(String opId, String taskId, String kind, String description, String? requestId,
          {required String workerId}) =>
      _write('wp_report_blocker', blockerParams(opId, taskId, kind, description, requestId), workerId);

  @override
  Future<Map<String, dynamic>> reportDone(String opId, String taskId, String note, {required String workerId}) =>
      _write('wp_report_done', noteParams(opId, taskId, note), workerId);

  @override
  Future<Map<String, dynamic>> leaderCheck(String opId, String taskId, String note, {required String workerId}) =>
      _write('wp_leader_check', noteParams(opId, taskId, note), workerId);

  @override
  Future<Map<String, dynamic>> propose(String opId, Map<String, dynamic> body, {required String workerId}) => _write(
        'wp_propose_task',
        proposeParams(opId, body['team_id'] as String, body['folder_id'] as String, body['work_id'] as String,
            body['title'] as String, (body['details'] as String?) ?? ''),
        workerId,
      );

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
    _sameWorker(workerId);
    final path = taskPhotoPath(workerId: workerId, taskId: taskId, photoId: photoId);
    try {
      await _client.storage
          .from(taskPhotoBucket)
          .upload(path, File(localPath), fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'))
          .timeout(_uploadTimeout);
    } catch (e) {
      // 0093 gives workers no UPDATE on storage: a retry after the upload
      // landed sees "already exists", which is success.
      if (!isAlreadyUploaded(e)) rethrow;
    }
    // The upload can take a minute: a sign-out and another sign-in meanwhile
    // must not link the photo under someone else.
    _sameWorker(workerId);
    await _client.rpc('wp_attach_photo', params: attachTaskPhotoParams(opId, taskId, blockerId, eventId, path)).timeout(_rpcTimeout);
  }

  @override
  Future<String?> signedUrl(String path) async {
    try {
      return await _client.storage.from(taskPhotoBucket).createSignedUrl(path, 600).timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }
}
