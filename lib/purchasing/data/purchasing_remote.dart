import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../buyer_access.dart';
import '../domain/pur_models.dart';

/// Receipts live in the private `uploads` bucket under `purchases/` (0097):
/// only those who may buy in that company read or write them.
const receiptBucket = 'uploads';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 30);
const _uploadTimeout = Duration(seconds: 60);

/// The storage path inside a stored receipt link (the web's storagePathOf).
String? receiptPathOf(String url) {
  final m = RegExp(r'/storage/v1/object/public/uploads/([^?#"\s]+)').firstMatch(url);
  return m == null ? null : Uri.decodeComponent(m.group(1)!);
}

/// A retry after the row or the file already landed: "already there" is success.
bool isDuplicate(Object error) {
  if (error is PostgrestException && error.code == '23505') return true;
  if (error is StorageException) {
    return error.statusCode == '409' || error.message.toLowerCase().contains('exists') || error.message.contains('Duplicate');
  }
  final text = error.toString().toLowerCase();
  return text.contains('23505') || text.contains('duplicate key');
}

abstract class PurchasingRemote {
  Future<List<PurBatch>> batches();

  /// Every open request line with something still to buy, every batch.
  Future<List<ShoppingLine>> shoppingList();
  Future<List<PurDestination>> destinations();
  Future<List<Supplier>> suppliers();

  /// The company the signed-in account files under (data_owner_id()).
  Future<String> company(String userId);

  // Every write files under the CURRENT session: if it is not [userId], it
  // throws AUTH_REQUIRED instead of acting for another account.

  /// Claim ([buyerId] = me), or release ([buyerId] null). [quantity] null = all of it.
  Future<Map<String, dynamic>> assign(String portionId, String? buyerId, double? quantity, {required String userId});
  Future<Map<String, dynamic>> setArranged(String portionId, bool arranged, {required String userId});
  Future<List<Map<String, dynamic>>> myPurchases();
  Future<Map<String, dynamic>> purchase(String id);
  Future<Map<String, dynamic>> record(String opId, Map<String, dynamic> body, {required String userId});
  Future<Map<String, dynamic>> correct(String opId, String purchaseId, Map<String, dynamic> body, String reason, {required String userId});
  Future<Map<String, dynamic>> requestChange(String opId, String purchaseId, Map<String, dynamic> body, String reason,
      {required String userId});

  /// The ledger row, THEN the file (0089: a file never exists without one).
  /// Returns the link stored on the purchase.
  Future<String> uploadReceipt({required String path, required String localPath, required String companyId, required String userId});

  /// The receipt's bytes, read as the buyer (never a signed link: 0097), or null.
  Future<Uint8List?> receipt(String url);
}

class SupabasePurchasingRemote implements PurchasingRemote {
  SupabasePurchasingRemote(this._client);

  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(Object? result) =>
      [for (final r in (result as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

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

  @override
  Future<List<PurBatch>> batches() async => _rows(await _read('pr_office_batches')).map(PurBatch.fromJson).toList();

  @override
  Future<List<ShoppingLine>> shoppingList() async => _rows(await _read('pur_shopping_list', {'p_batch': null, 'p_folder': null, 'p_scope': 'open'}))
      .map(ShoppingLine.fromJson)
      .toList();

  @override
  Future<List<PurDestination>> destinations() async => _rows(await _read('pur_destinations')).map(PurDestination.fromJson).toList();

  @override
  Future<List<Supplier>> suppliers() async => _rows(await _read('pur_suppliers')).map(Supplier.fromJson).toList();

  @override
  Future<String> company(String userId) async {
    _same(userId);
    final row = await _client.from('profiles').select('id,role,owner_id').eq('id', userId).maybeSingle().timeout(_readTimeout);
    return companyOf(row, userId);
  }

  @override
  Future<Map<String, dynamic>> assign(String portionId, String? buyerId, double? quantity, {required String userId}) =>
      _write('pur_assign_portion', {'p_portion': portionId, 'p_buyer': buyerId, 'p_quantity': quantity, 'p_note': null}, userId);

  @override
  Future<Map<String, dynamic>> setArranged(String portionId, bool arranged, {required String userId}) =>
      _write('pr_office_set_arranged', {'p_portion': portionId, 'p_arranged': arranged}, userId);

  @override
  Future<List<Map<String, dynamic>>> myPurchases() async => _rows(await _read('pur_my_purchases', {'p_days': 60}));

  @override
  Future<Map<String, dynamic>> purchase(String id) async => Map<String, dynamic>.from(await _read('pur_purchase', {'p_purchase': id}) as Map);

  @override
  Future<Map<String, dynamic>> record(String opId, Map<String, dynamic> body, {required String userId}) =>
      _write('pur_record', {'p_op': opId, 'p_body': body}, userId);

  @override
  Future<Map<String, dynamic>> correct(String opId, String purchaseId, Map<String, dynamic> body, String reason, {required String userId}) =>
      _write('pur_correct', {'p_op': opId, 'p_purchase': purchaseId, 'p_body': body, 'p_reason': reason}, userId);

  @override
  Future<Map<String, dynamic>> requestChange(String opId, String purchaseId, Map<String, dynamic> body, String reason,
          {required String userId}) =>
      _write('pur_request_change', {'p_op': opId, 'p_purchase': purchaseId, 'p_kind': 'correct', 'p_body': body, 'p_reason': reason}, userId);

  @override
  Future<String> uploadReceipt({required String path, required String localPath, required String companyId, required String userId}) async {
    _same(userId);
    try {
      await _client.from('receipt_uploads').insert({'path': path, 'owner_id': companyId, 'kind': 'purchase'}).timeout(_readTimeout);
    } catch (e) {
      if (!isDuplicate(e)) rethrow;
    }
    try {
      await _client.storage
          .from(receiptBucket)
          .upload(path, File(localPath), fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'))
          .timeout(_uploadTimeout);
    } catch (e) {
      if (!isDuplicate(e)) rethrow;
    }
    return _client.storage.from(receiptBucket).getPublicUrl(path);
  }

  @override
  Future<Uint8List?> receipt(String url) async {
    final path = receiptPathOf(url);
    if (path == null) return null;
    try {
      return await _client.storage.from(receiptBucket).download(path).timeout(_uploadTimeout);
    } catch (_) {
      return null;
    }
  }
}
