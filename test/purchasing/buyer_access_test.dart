import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/purchasing/buyer_access.dart';

class FakeBuyerBackend implements BuyerAccessBackend {
  BuyerStatus answer = const BuyerStatus(canBuy: true, companyId: 'o1');
  bool offline = false;
  int asked = 0;

  @override
  Future<BuyerStatus> status(String userId) async {
    asked++;
    if (offline) throw const SocketException('down');
    return answer;
  }
}

void main() {
  late FakeBuyerBackend backend;
  late BuyerAccess access;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBuyerBackend();
    access = BuyerAccess(backend: backend, prefs: await SharedPreferences.getInstance());
  });

  test('the company is the owner for staff, the account itself otherwise (data_owner_id)', () {
    expect(companyOf({'role': 'staff', 'owner_id': 'o1'}, 's1'), 'o1');
    expect(companyOf({'role': 'staff', 'owner_id': null}, 's1'), 's1');
    expect(companyOf({'role': 'owner', 'owner_id': null}, 'o1'), 'o1');
    expect(companyOf(null, 'x1'), 'x1');
  });

  test('online yes: may buy, and the answer and company are kept for offline', () async {
    expect(await access.decide('s1'), BuyerDecision.canBuy);
    expect(access.companyOf('s1'), 'o1');
    backend.offline = true;
    expect(await access.decide('s1'), BuyerDecision.canBuy);
  });

  test('online no, never a buyer on this phone: neverABuyer', () async {
    backend.answer = const BuyerStatus(canBuy: false, companyId: 'o1');
    expect(await access.decide('s1'), BuyerDecision.neverABuyer);
  });

  test('online no after being a buyer here: turnedOff, also offline afterwards (R2)', () async {
    expect(await access.decide('s1'), BuyerDecision.canBuy);
    backend.answer = const BuyerStatus(canBuy: false, companyId: 'o1');
    expect(await access.decide('s1'), BuyerDecision.turnedOff);
    backend.offline = true;
    expect(await access.decide('s1'), BuyerDecision.turnedOff);
  });

  test('turned back on: may buy again', () async {
    await access.letIn('s1');
    backend.answer = const BuyerStatus(canBuy: false, companyId: 'o1');
    expect(await access.decide('s1'), BuyerDecision.turnedOff);
    backend.answer = const BuyerStatus(canBuy: true, companyId: 'o1');
    expect(await access.decide('s1'), BuyerDecision.canBuy);
  });

  test('offline and never told: unknown, never assumed', () async {
    backend.offline = true;
    expect(await access.decide('s1'), BuyerDecision.unknown);
  });

  test('letIn (the sign-in said buyer) lets an offline launch in', () async {
    await access.letIn('s1');
    backend.offline = true;
    expect(await access.decide('s1'), BuyerDecision.canBuy);
  });

  test('markTurnedOff turns a known buyer off, and does nothing for an unknown one', () async {
    await access.markTurnedOff('x9');
    backend.offline = true;
    expect(await access.decide('x9'), BuyerDecision.unknown);
    await access.letIn('s1');
    await access.markTurnedOff('s1');
    expect(await access.decide('s1'), BuyerDecision.turnedOff);
  });

  test('forget leaves nothing behind', () async {
    expect(await access.decide('s1'), BuyerDecision.canBuy);
    await access.forget('s1');
    expect(access.companyOf('s1'), isNull);
    backend.offline = true;
    expect(await access.decide('s1'), BuyerDecision.unknown);
  });
}
