import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/auth/worker_profile.dart';

void main() {
  group('eligibilityOf — the rule attendance-signin and the RPCs enforce', () {
    test('worker and teamLeader are allowed', () {
      expect(eligibilityOf('worker', 'active'), Eligibility.allowed);
      expect(eligibilityOf('teamLeader', 'active'), Eligibility.allowed);
    });
    test('a missing status counts as active (coalesce(status, active))', () {
      expect(eligibilityOf('worker', null), Eligibility.allowed);
    });
    test('an inactive worker is refused as inactive', () {
      expect(eligibilityOf('worker', 'inactive'), Eligibility.accountInactive);
    });
    test('staff, owner, client and null are not workers', () {
      for (final r in ['staff', 'owner', 'client', null]) {
        expect(eligibilityOf(r, 'active'), Eligibility.notAWorker, reason: '$r');
      }
    });
  });

  group('display', () {
    const juan = WorkerProfile(
        id: 'u1', email: 'juan@x.com', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42);
    test('worker id label', () {
      expect(juan.workerIdLabel, 'W-0042');
      expect(const WorkerProfile(id: 'u').workerIdLabel, '--');
    });
    test('initials, first name and position line', () {
      expect(juan.initials, 'JD');
      expect(juan.firstName, 'Juan');
      expect(juan.positionAndId, 'Mason · W-0042');
    });
    test('falls back to the email, then "Worker"', () {
      expect(const WorkerProfile(id: 'u', email: 'pedro@x.com').firstName, 'pedro');
      expect(const WorkerProfile(id: 'u').firstName, 'Worker');
      expect(const WorkerProfile(id: 'u', email: 'pedro@x.com').initials, 'P');
    });
    test('blank position is left out', () {
      expect(const WorkerProfile(id: 'u', position: '  ', workerNo: 7).positionAndId, 'W-0007');
    });
  });

  test('row round-trip', () {
    final row = {
      'id': 'u1', 'email': 'a@b.c', 'display_name': 'A B', 'position': 'Mason',
      'worker_no': 3, 'role': 'worker', 'status': 'active',
    };
    expect(WorkerProfile.fromRow(row).toRow(), row);
  });
}
