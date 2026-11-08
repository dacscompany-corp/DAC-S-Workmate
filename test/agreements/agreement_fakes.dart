import 'dart:async';
import 'dart:io';

import 'package:workmate/agreements/data/agreements_remote.dart';
import 'package:workmate/agreements/domain/my_agreement.dart';

/// 0113's ll_my_agreements answer, as PostgREST returns it: a fixed agreement
/// on a main project (paid in two payments, one of them split), an Additional
/// Works one, a daily one on a completed project, and one paid over its cap
/// with no progress recorded.
const myAgreementsJson = '''
{"agreements": [
  {"id": "a-main", "project": "Alpha House", "main_project": null, "project_completed": false, "progress_pct": 25,
   "scope": "Masonry works", "trade": "Masonry", "pay_basis": "fixed", "works": [],
   "agreed": 50000, "paid": 20000, "balance": 30000, "ended": false, "ended_at": null,
   "payments": [{"date": "2026-10-08", "amount": 10000, "method": "gcash"},
                {"date": "2026-10-01", "amount": 10000, "method": "cash"}]},
  {"id": "a-aw", "project": "Alpha Additional Works", "main_project": "Alpha House", "project_completed": false,
   "progress_pct": 80, "scope": "Extra wall", "trade": "Masonry", "pay_basis": "fixed", "works": ["Wall", "Coping"],
   "agreed": 8000, "paid": 0, "balance": 8000, "ended": false, "ended_at": null, "payments": []},
  {"id": "a-daily", "project": "Beta House", "main_project": null, "project_completed": true, "progress_pct": null,
   "scope": "Painting", "trade": "", "pay_basis": "daily", "works": [], "agreed": null, "paid": 700, "balance": null,
   "ended": true, "ended_at": "2026-11-03T02:00:00+00:00", "payments": [{"date": "2026-10-21", "amount": 700, "method": null}]},
  {"id": "a-over", "project": "Gamma House", "main_project": null, "project_completed": false, "progress_pct": null,
   "scope": "Tiling", "trade": "Tiling", "pay_basis": "fixed", "works": [], "agreed": 1000, "paid": 1500, "balance": -500,
   "ended": false, "ended_at": null, "payments": [{"date": "2026-10-20", "amount": 1500, "method": "bank_transfer"}]}
]}''';

/// A scripted AgreementsRemote: each call takes the next answer (a list, or an error to throw).
class FakeAgreementsRemote implements AgreementsRemote {
  final answers = <Object>[];
  final asked = <String>[];
  Completer<void>? gate;

  @override
  Future<List<MyAgreement>> mine({required String userId}) async {
    asked.add(userId);
    final g = gate;
    if (g != null) await g.future;
    final a = answers.isEmpty ? const <MyAgreement>[] : answers.removeAt(0);
    if (a is List<MyAgreement>) return a;
    throw a;
  }
}

const noSignal = SocketException('no signal');
final notRequester = Exception('PostgrestException(message: NOT_A_REQUESTER, code: P0001)');
