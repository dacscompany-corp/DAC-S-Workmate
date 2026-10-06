import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/request_models.dart';

/// The private bucket every request photo lives in (0085; never `uploads`).
const requestPhotoBucket = 'request-photos';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 20);
const _uploadTimeout = Duration(seconds: 60);

/// {requester}/{request}/{photo}.jpg — the only shape 0085's upload policy
/// and pr_attach_photo accept.
String requestPhotoPath({required String workerId, required String requestId, required String photoId}) =>
    '$workerId/$requestId/$photoId.jpg';

// The RPC arguments — exactly the 0085 signatures.
Map<String, dynamic> submitParams(String opId, Map<String, dynamic> payload) => {'p_op': opId, 'p_request': payload};

Map<String, dynamic> quantityParams(String opId, String lineId, int baseVersion, double quantity) =>
    {'p_op': opId, 'p_line': lineId, 'p_base_version': baseVersion, 'p_quantity': quantity};

Map<String, dynamic> cancelLineParams(String opId, String lineId) => {'p_op': opId, 'p_line': lineId};

Map<String, dynamic> cancelRequestParams(String opId, String requestId) => {'p_op': opId, 'p_request': requestId};

Map<String, dynamic> attachParams(String opId, String requestId, String? lineId, String path) =>
    {'p_op': opId, 'p_request': requestId, 'p_line': lineId, 'p_path': path};

/// A retry after the upload landed but the attach did not: the object is
/// already there. 0085 gives workers no UPDATE on storage, so an upsert would
/// be refused; "already exists" is success.
bool isAlreadyUploaded(Object error) =>
    error is StorageException &&
    (error.statusCode == '409' || error.message.toLowerCase().contains('exists') || error.message.contains('Duplicate'));

abstract class RequestRemote {
  Future<List<Destination>> destinations();
  Future<List<MyTeam>> myTeams();
  Future<List<CatalogItem>> catalog();

  /// The caller's requests plus, for a current leader, the team's (newest first).
  Future<List<Map<String, dynamic>>> myRequests();

  // Every write files under the CURRENT session: if it is not [workerId], it
  // throws AUTH_REQUIRED instead of sending another worker's change.
  Future<Map<String, dynamic>> submit(String opId, Map<String, dynamic> payload, {required String workerId});
  Future<Map<String, dynamic>> changeQuantity(String opId, String lineId, int baseVersion, double quantity, {required String workerId});
  Future<Map<String, dynamic>> cancelLine(String opId, String lineId, {required String workerId});
  Future<Map<String, dynamic>> cancelRequest(String opId, String requestId, {required String workerId});

  /// Uploads the photo, THEN links it (a row must never point at a missing file).
  Future<void> attachPhoto({
    required String opId,
    required String requestId,
    required String? lineId,
    required String photoId,
    required String localPath,
    required String workerId,
  });

  /// A 10-minute link to one private photo, or null.
  Future<String?> signedUrl(String path);
}

class SupabaseRequestRemote implements RequestRemote {
  SupabaseRequestRemote(this._client);

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
  Future<List<Destination>> destinations() async =>
      _rows(await _client.rpc('pr_destinations').timeout(_readTimeout)).map(Destination.fromRow).toList();

  @override
  Future<List<MyTeam>> myTeams() async => _rows(await _client.rpc('pr_my_teams').timeout(_readTimeout)).map(MyTeam.fromRow).toList();

  @override
  Future<List<CatalogItem>> catalog() async =>
      _rows(await _client.rpc('pr_catalog').timeout(_readTimeout)).map(CatalogItem.fromRow).whereType<CatalogItem>().toList();

  @override
  Future<List<Map<String, dynamic>>> myRequests() async =>
      _rows(await _client.rpc('pr_my_requests', params: {'p_limit': 100}).timeout(_readTimeout));

  @override
  Future<Map<String, dynamic>> submit(String opId, Map<String, dynamic> payload, {required String workerId}) =>
      _write('pr_submit_request', submitParams(opId, payload), workerId);

  @override
  Future<Map<String, dynamic>> changeQuantity(String opId, String lineId, int baseVersion, double quantity, {required String workerId}) =>
      _write('pr_change_quantity', quantityParams(opId, lineId, baseVersion, quantity), workerId);

  @override
  Future<Map<String, dynamic>> cancelLine(String opId, String lineId, {required String workerId}) =>
      _write('pr_cancel_line', cancelLineParams(opId, lineId), workerId);

  @override
  Future<Map<String, dynamic>> cancelRequest(String opId, String requestId, {required String workerId}) =>
      _write('pr_cancel_request', cancelRequestParams(opId, requestId), workerId);

  @override
  Future<void> attachPhoto({
    required String opId,
    required String requestId,
    required String? lineId,
    required String photoId,
    required String localPath,
    required String workerId,
  }) async {
    _sameWorker(workerId);
    final path = requestPhotoPath(workerId: workerId, requestId: requestId, photoId: photoId);
    try {
      await _client.storage
          .from(requestPhotoBucket)
          .upload(path, File(localPath), fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'))
          .timeout(_uploadTimeout);
    } catch (e) {
      if (!isAlreadyUploaded(e)) rethrow;
    }
    // The upload can take a minute: a sign-out and another sign-in meanwhile
    // must not link the photo under someone else.
    _sameWorker(workerId);
    await _client.rpc('pr_attach_photo', params: attachParams(opId, requestId, lineId, path)).timeout(_rpcTimeout);
  }

  @override
  Future<String?> signedUrl(String path) async {
    try {
      return await _client.storage.from(requestPhotoBucket).createSignedUrl(path, 600).timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }
}
