import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/purchasing/data/purchasing_remote.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';

/// A server refusal as supabase-js reports it.
PostgrestException refusal(String code) => PostgrestException(message: code, code: 'P0001');

/// The Saturday-noon Manila cutoffs of 24 Oct and 31 Oct 2026, in UTC.
final thisWeek = PurBatch(id: 'b1', cutoffAt: DateTime.utc(2026, 10, 24, 4), purchaseOn: '2026-10-26');
final nextWeek = PurBatch(id: 'b2', cutoffAt: DateTime.utc(2026, 10, 31, 4), purchaseOn: '2026-11-02');

/// Wednesday 21 Oct 2026, 10:00 Manila.
final wednesday = DateTime.utc(2026, 10, 21, 2);

PurPortion portion(String id, {String batch = 'b1', double still = 10, String? buyer, bool mine = false, bool arranged = false}) => PurPortion(
      id: id,
      batchId: batch,
      quantity: still,
      stillToBuy: still,
      buyerId: buyer,
      buyerName: buyer == null ? null : (mine ? 'Ana' : 'Ben'),
      mine: mine,
      arranged: arranged,
    );

ShoppingLine cement({List<PurPortion>? portions}) => ShoppingLine(
      lineId: 'l1',
      requestId: 'r1',
      description: 'Cement',
      spec: '40 kg',
      unit: 'bag',
      projectId: 'f1',
      projectName: 'Barlin Residence',
      workId: 'f1',
      workName: 'Main Contract',
      requesterName: 'Juan',
      needed: 10,
      stillToBuy: 10,
      portions: portions ?? [portion('p1')],
    );

const barlin = PurDestination(folderId: 'f1', name: 'Barlin Residence', works: [PurWork(folderId: 'f9', name: 'AW-02 Fence')]);
const zzHardware = Supplier(id: 's1', name: 'ZZ Hardware', branch: 'Malolos');

/// A PurchasingRemote whose every answer the test sets, recording every call.
class FakePurchasingRemote implements PurchasingRemote {
  List<PurBatch> batchList = [thisWeek, nextWeek];
  List<ShoppingLine> lines = [cement()];
  List<PurDestination> dests = [barlin];
  List<Supplier> supplierList = [zzHardware];
  List<Map<String, dynamic>> mine = [];
  Map<String, dynamic> detail = {'id': 'pu1', 'status': 'recorded'};
  String companyId = 'o1';

  /// Thrown by every read while set.
  Object? readError;

  /// Thrown by the next write (then cleared), or every write while [writeErrorSticky].
  Object? writeError;
  bool writeErrorSticky = false;

  /// Thrown by the next upload (then cleared).
  Object? uploadError;

  final calls = <String>[];
  final uploads = <String>[];
  final recorded = <Map<String, dynamic>>[];
  final recordOps = <String>[];

  void _read() {
    if (readError != null) throw readError!;
  }

  void _write() {
    final e = writeError;
    if (e == null) return;
    if (!writeErrorSticky) writeError = null;
    throw e;
  }

  @override
  Future<List<PurBatch>> batches() async {
    _read();
    return batchList;
  }

  @override
  Future<List<ShoppingLine>> shoppingList() async {
    _read();
    return lines;
  }

  @override
  Future<List<PurDestination>> destinations() async {
    _read();
    return dests;
  }

  @override
  Future<List<Supplier>> suppliers() async {
    _read();
    return supplierList;
  }

  @override
  Future<String> company(String userId) async {
    _read();
    calls.add('company');
    return companyId;
  }

  @override
  Future<Map<String, dynamic>> assign(String portionId, String? buyerId, double? quantity, {required String userId}) async {
    calls.add('assign:$portionId:$buyerId:$quantity');
    _write();
    return {'portion_id': portionId, 'changed': true};
  }

  @override
  Future<Map<String, dynamic>> setArranged(String portionId, bool arranged, {required String userId}) async {
    calls.add('arranged:$portionId:$arranged');
    _write();
    return {'portion_id': portionId, 'arranged': arranged};
  }

  @override
  Future<List<Map<String, dynamic>>> myPurchases() async {
    _read();
    return mine;
  }

  @override
  Future<Map<String, dynamic>> purchase(String id) async {
    _read();
    return detail;
  }

  @override
  Future<Map<String, dynamic>> record(String opId, Map<String, dynamic> body, {required String userId}) async {
    calls.add('record:$opId');
    _write();
    recordOps.add(opId);
    recorded.add(body);
    return {'purchase_id': 'pu${recorded.length}'};
  }

  @override
  Future<Map<String, dynamic>> correct(String opId, String purchaseId, Map<String, dynamic> body, String reason, {required String userId}) async {
    calls.add('correct:$opId:$purchaseId:$reason');
    _write();
    recorded.add(body);
    return {'purchase_id': purchaseId};
  }

  @override
  Future<Map<String, dynamic>> requestChange(String opId, String purchaseId, Map<String, dynamic> body, String reason,
      {required String userId}) async {
    calls.add('owner:$opId:$purchaseId:$reason');
    _write();
    recorded.add(body);
    return {'request_id': 'cr1', 'status': 'pending'};
  }

  @override
  Future<String> uploadReceipt({required String path, required String localPath, required String companyId, required String userId}) async {
    final e = uploadError;
    if (e != null) {
      uploadError = null;
      throw e;
    }
    uploads.add(path);
    return 'https://x.supabase.co/storage/v1/object/public/uploads/$path';
  }

  @override
  Future<Uint8List?> receipt(String url) async {
    calls.add('receipt:$url');
    return Uint8List.fromList([1, 2, 3]);
  }
}
