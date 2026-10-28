import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/stock/data/stock_pending_store.dart';
import 'package:workmate/stock/data/stock_remote.dart';
import 'package:workmate/stock/domain/stock_models.dart';
import 'package:workmate/stock/domain/stock_submission.dart';

/// The stock server, as the phone sees it, in memory: what each call was
/// sent, and canned answers or refusals. Like `pur_ops`, an operation id it
/// has recorded is answered again with the first answer (and `replayed`),
/// whatever the payload — which is why the phone never changes one. A
/// cancelled id (pur_op_cancel) is refused OP_CANCELLED, as 0106's lock does.
class FakeStockRemote implements StockRemote {
  FakeStockRemote({
    this.statusAnswer = const StockStatus(enabled: true, canRecord: true),
    StockOverview? overview,
    StockChoices? choices,
    Map<String, List<StockRequestLine>>? requestLines,
    Map<String, List<StockLine>>? projectLines,
  })  : overviewAnswer = overview ?? const StockOverview(),
        choicesAnswer = choices ?? const StockChoices(),
        requestLinesAnswer = requestLines ?? {},
        projectLinesAnswer = projectLines ?? {};

  StockStatus statusAnswer;
  StockOverview overviewAnswer;
  StockChoices choicesAnswer;
  Map<String, List<StockRequestLine>> requestLinesAnswer;
  Map<String, List<StockLine>> projectLinesAnswer;

  /// Thrown by reads (until cleared) / by the next write before it records.
  Object? failReads;
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
  int statusCalls = 0;
  int overviewCalls = 0;
  int checks = 0;
  int cancels = 0;

  Future<T> _read<T>(T value) async {
    final f = failReads;
    if (f != null) throw f;
    return value;
  }

  @override
  Future<Map<String, dynamic>> write(StockWrite w, Map<String, dynamic> params, {required String userId}) async {
    final op = params['p_op'] as String;
    attempts.add((op, jsonEncode(params)));
    final f = failNextWrite;
    if (f != null) {
      failNextWrite = null;
      throw f;
    }
    if (cancelled.contains('$userId:$op')) throw PostgrestException(message: 'OP_CANCELLED', code: 'P0001');
    final i = writes.indexWhere((x) => x.$2['p_op'] == op && x.$3 == userId);
    final answer = {'record_id': 'rec-${i < 0 ? writes.length + 1 : i + 1}', 'cost_moves': const <String>[]};
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

  @override
  Future<StockStatus> status() {
    statusCalls++;
    return _read(statusAnswer);
  }

  @override
  Future<StockOverview> overview() {
    overviewCalls++;
    return _read(overviewAnswer);
  }

  @override
  Future<StockChoices> choices() => _read(choicesAnswer);

  @override
  Future<List<StockRequestLine>> requestLines(String folderId) => _read(requestLinesAnswer[folderId] ?? const []);

  @override
  Future<List<StockLine>> projectLines(String folderId) => _read(projectLinesAnswer[folderId] ?? const []);
}

/// Tests only (R104): stock submissions kept in memory. The app always keeps
/// them in the phone's settings file (PrefsStockPendingStore).
class MemoryStockPendingStore implements StockPendingStore {
  List<StockSubmission> _all = [];

  @override
  Future<StockPendingLoad> load() async => StockPendingLoad(readable: List.of(_all));

  @override
  Future<void> save(List<StockSubmission> readable) async => _all = List.of(readable);

  @override
  Future<void> dropUnreadable(String userId, String opId) async {}
}

// ── sample answers, as 0104/0105 send them ──

const cement = StockItemChoice(itemId: 'item-cement', name: 'Cement', spec: 'Portland', unit: 'bag');
const wire = StockItemChoice(itemId: 'item-wire', name: 'Tie wire', unit: 'piece');
const barlin = StockProject(folderId: 'f-barlin', name: 'Barlin Residence');
const sulit = StockProject(folderId: 'f-sulit', name: 'Sulit');
const oldJob = StockProject(folderId: 'f-old', name: 'Old Fence', completed: true);

const sampleChoices = StockChoices(items: [cement, wire], projects: [oldJob, barlin, sulit]);

StockOverview sampleOverview() => StockOverview.fromJson({
      'items': [
        {
          'item_id': 'item-cement', 'name': 'Cement', 'spec': 'Portland', 'unit': 'bag', 'total': 14,
          'places': [
            {'location_id': 'l-wh', 'name': 'Warehouse', 'kind': 'warehouse', 'folder_id': null, 'quantity': 10},
            {'location_id': 'l-b', 'name': 'Barlin Residence', 'kind': 'site', 'folder_id': 'f-barlin', 'quantity': 4},
          ],
        },
      ],
      'awaiting': [
        {
          'purchase_id': 'p-1', 'line_no': 1, 'destination': 'warehouse', 'item_name': 'Cement', 'unit': 'bag', 'quantity': 20,
          'purchase_date': '2026-10-20', 'bought_by_name': 'Juan', 'received': 12, 'not_delivered': 0, 'awaiting': 8, 'entered': 12,
          'match': {'item_id': 'item-cement', 'item_name': 'Cement', 'item_unit': 'bag', 'per': 20, 'covers': 20, 'auto': false},
        },
        {
          'purchase_id': 'p-2', 'line_no': 1, 'destination': 'warehouse', 'item_name': 'Wire box', 'unit': 'box', 'quantity': 3,
          'purchase_date': '2026-10-21', 'bought_by_name': 'Ana', 'received': 0, 'not_delivered': 0, 'awaiting': 3, 'entered': 0, 'match': null,
        },
      ],
      'recent': [
        {
          'id': 'r-issue', 'kind': 'issue', 'status': 'done', 'item_id': 'item-cement', 'item_name': 'Cement', 'item_unit': 'bag',
          'from_name': 'Warehouse', 'to_name': 'Barlin Residence', 'quantity': 4, 'on': '2026-10-26', 'recorded_by': 'u-staff',
          'recorded_by_name': 'Ana', 'recorded_at': '2026-10-26T02:00:00Z', 'reversed': false, 'returnable': 4,
          'request_description': 'Cement for slab',
          'costs': [
            {'id': 'c-1', 'kind': 'assign', 'status': 'pending', 'reversed': false, 'quantity': 4, 'value': 400, 'estimate': 412},
          ],
        },
        {
          'id': 'r-old', 'kind': 'issue', 'status': 'done', 'item_id': 'item-cement', 'item_name': 'Cement', 'item_unit': 'bag',
          'from_name': 'Warehouse', 'to_name': 'Sulit', 'quantity': 2, 'on': '2026-10-24', 'recorded_by': 'u-staff',
          'recorded_by_name': 'Ana', 'recorded_at': '2026-10-24T02:00:00Z', 'reversed': false, 'returnable': 0, 'costs': [],
          'unplanned_reason': 'gate',
        },
        {
          'id': 'r-receive', 'kind': 'receive', 'status': 'done', 'item_id': null, 'line_item': 'Cement', 'line_unit': 'bag',
          'from_name': null, 'to_name': 'Warehouse', 'quantity': 12, 'on': '2026-10-25', 'recorded_by': 'u-buyer',
          'recorded_by_name': 'Juan', 'recorded_at': '2026-10-25T02:00:00Z', 'reversed': false, 'returnable': null, 'costs': [],
        },
      ],
    });
