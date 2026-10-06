import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_failure.dart';
import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/requests/domain/request_op.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/ui/requests_copy.dart';

import 'request_models_test.dart' show requestDoc;

const site = Destination(projectId: 'f1', projectName: 'Santos Townhouse', workId: 'f1', workName: 'Main Contract', isMain: true);
const pipe = CatalogItem(id: 'c1', kind: ItemKind.material, name: 'PVC pipe', spec: '1/2 in', unit: 'pc', category: 'plumbing');

RequestDraft draft({List<DraftLine>? lines, String? teamId}) => RequestDraft(
      id: 'd1',
      createdAt: DateTime.utc(2026, 10, 5, 1),
      destination: site,
      teamId: teamId,
      lines: lines ?? [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10')],
    );

RemoteLine line({bool conflict = false, bool cancelled = false, List<Portion>? portions}) => RemoteLine(
      id: 'l1',
      position: 0,
      kind: ItemKind.material,
      description: 'PVC pipe',
      unit: 'pc',
      version: 1,
      needed: 10,
      hasConflict: conflict,
      cancelled: cancelled,
      portions: portions ?? [portion()],
    );

Portion portion({bool arranged = false, double pending = 0, String delivery = '2026-10-14'}) => Portion(
      quantity: 10,
      pendingReduction: pending,
      arranged: arranged,
      cutoffAt: DateTime.utc(2026, 10, 10, 4),
      purchaseOn: '2026-10-12',
      deliveryOn: delivery,
    );

RequestOp op(String id, OpKind kind, {String? lineId, int? base, bool failed = false}) => RequestOp(
      opId: id,
      workerId: 'u1',
      kind: kind,
      createdAt: DateTime.utc(2026),
      lineId: lineId,
      baseVersion: base,
      failedPermanently: failed,
    );

void main() {
  group('drafts', () {
    test('a complete draft has no issues and survives a round trip', () {
      final d = draft();
      expect(draftIssues(d), isEmpty);
      final back = RequestDraft.fromJson(d.toJson());
      expect(back.destination, site);
      expect(back.lines.single.catalogItemId, 'c1');
      expect(back.lines.single.quantity, '10');
      expect(back.createdAt, d.createdAt);
    });

    test('every server refusal is caught before sending', () {
      final d = RequestDraft(id: 'd1', createdAt: DateTime.utc(2026), lines: [
        const DraftLine(id: 'a', quantity: '0', urgent: true, memberId: 'u2'),
      ]);
      expect(draftIssues(d), [
        const DraftIssue(DraftIssueKind.noDestination),
        const DraftIssue(DraftIssueKind.noDescription, 0),
        const DraftIssue(DraftIssueKind.noUnit, 0),
        const DraftIssue(DraftIssueKind.badQuantity, 0),
        const DraftIssue(DraftIssueKind.urgentNeedsReason, 0),
        const DraftIssue(DraftIssueKind.urgentNeedsDate, 0),
        const DraftIssue(DraftIssueKind.memberNeedsTeam, 0),
      ]);
      expect(draftIssues(RequestDraft(id: 'd2', createdAt: DateTime.utc(2026), destination: site)),
          [const DraftIssue(DraftIssueKind.noLines)]);
      final many = draft(lines: [for (var i = 0; i < 101; i++) DraftLine.fromCatalog('x$i', pipe).copyWith(quantity: '1')]);
      expect(draftIssues(many), [const DraftIssue(DraftIssueKind.tooManyLines)]);
    });

    test('the payload is exactly pr_submit_request\'s', () {
      final d = draft(teamId: 't1', lines: [
        DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10', memberId: 'u2', memberName: 'Pedro', urgent: true, urgentReason: ' Leak ', neededBy: '2026-10-07'),
        const DraftLine(id: 'x2', kind: ItemKind.tool, description: 'Drill', unit: 'pc', quantity: '1', memberId: 'u2', notes: 'cordless'),
      ]);
      final p = submitPayload(d);
      expect(p['folder_id'], 'f1');
      expect(p['work_id'], 'f1');
      expect(p['team_id'], 't1');
      expect(p['drafted_at'], '2026-10-05T01:00:00.000Z');
      final lines = p['lines'] as List;
      expect(lines[0], {
        'kind': 'material',
        'catalog_item_id': 'c1',
        'description': 'PVC pipe',
        'spec': '1/2 in',
        'unit': 'pc',
        'category': 'plumbing',
        'quantity': 10.0,
        'intended_member_id': 'u2',
        'urgent': true,
        'urgent_reason': 'Leak',
        'needed_by': '2026-10-07',
        'notes': '',
      });
      // A tool carries no intended member (spec §4A) and no catalogue id when unlisted.
      expect((lines[1] as Map).containsKey('intended_member_id'), isFalse);
      expect((lines[1] as Map).containsKey('catalog_item_id'), isFalse);
      expect(submitPayload(draft()).containsKey('team_id'), isFalse);
    });

    test('copyWith can clear what may be cleared', () {
      final l = DraftLine.fromCatalog('x1', pipe).copyWith(memberId: 'u2', neededBy: '2026-10-07');
      final cleared = l.copyWith(catalogItemId: null, memberId: null, neededBy: null);
      expect(cleared.catalogItemId, isNull);
      expect(cleared.memberId, isNull);
      expect(cleared.neededBy, isNull);
      expect(cleared.description, 'PVC pipe');
    });
  });

  group('status', () {
    test('a line reads its most pressing state first', () {
      expect(lineProgress(line(conflict: true)), LineProgress.needsResolution);
      expect(lineProgress(line(cancelled: true, portions: [portion(arranged: true, pending: 10)])), LineProgress.officeChecking);
      expect(lineProgress(line(cancelled: true, portions: [])), LineProgress.cancelled);
      expect(lineProgress(line()), LineProgress.waiting);
      expect(lineProgress(line(portions: [portion(arranged: true), portion()])), LineProgress.partlyArranged);
      expect(lineProgress(line(portions: [portion(arranged: true)])), LineProgress.arranged);
    });

    test('unsent or refused outranks what the server says', () {
      final r = RemoteRequest.fromJson(requestDoc());
      expect(remoteState(r, pending: false, failed: false), SyncState.received);
      expect(remoteState(r, pending: true, failed: false), SyncState.pending);
      expect(remoteState(r, pending: true, failed: true), SyncState.failed);
      final doc = requestDoc();
      (doc['lines'] as List).first['has_conflict'] = true;
      expect(remoteState(RemoteRequest.fromJson(doc), pending: false, failed: false), SyncState.needsResolution);
    });

    test('a closed site refusing an EDIT never says to choose another and send again', () {
      RequestOp refused(OpKind kind, {String? requestId = 'r1', String? draftId}) => RequestOp(
            opId: 'o',
            workerId: 'u1',
            kind: kind,
            createdAt: DateTime.utc(2026),
            requestId: requestId,
            draftId: draftId,
            lineId: 'l1',
            body: const {'quantity': 3, 'local_path': '/p.jpg', 'photo_id': 'p'},
            lastError: 'destinationClosed',
            failedPermanently: true,
          );
      for (final kind in [OpKind.quantity, OpKind.cancelLine, OpKind.cancelRequest, OpKind.photo]) {
        final c = opFailureCopy(refused(kind));
        expect(c.english, isNot(contains('Choose another')), reason: kind.name);
        expect(c.english, contains('office'), reason: kind.name);
        expect(c.tagalog, contains('opisina'), reason: kind.name);
      }
      // The refused draft itself goes back to editing: there, choosing another is the fix.
      final submit = refused(OpKind.submit, requestId: null, draftId: 'd1');
      expect(opFailureCopy(submit).english, requestFailureCopy(RequestFailure.destinationClosed).english);
      final orphan = refused(OpKind.photo, requestId: null, draftId: 'd1');
      expect(opFailureCopy(orphan).english, requestFailureCopy(RequestFailure.destinationClosed).english);
    });

    test('a cancelled request reads Cancelled, not Received', () {
      final r = RemoteRequest.fromJson(requestDoc(status: 'cancelled'));
      expect(remoteState(r, pending: false, failed: false), SyncState.cancelled);
      expect(syncLabel(SyncState.cancelled), 'Cancelled');
      expect(remoteState(r, pending: true, failed: false), SyncState.pending, reason: 'unsent still outranks');
      expect(remoteState(r, pending: false, failed: true), SyncState.failed);
    });

    test('only the requester changes a request', () {
      final mine = RemoteRequest.fromJson(requestDoc());
      final team = RemoteRequest.fromJson(requestDoc(mine: false));
      expect(canChangeLine(mine, mine.lines.single), isTrue);
      expect(canChangeLine(team, team.lines.single), isFalse);
      expect(canCancelRequest(mine), isTrue);
      expect(canCancelRequest(team), isFalse);
      final cancelled = RemoteRequest.fromJson(requestDoc(status: 'cancelled'));
      expect(canCancelRequest(cancelled), isFalse);
      expect(requestClosed(cancelled), isTrue);
    });

    test('calendar dates are read as dates, never shifted', () {
      expect(calendarDay('2026-10-14'), 'Wed 14 Oct');
      expect(calendarDay('2026-10-12'), 'Mon 12 Oct');
      expect(calendarDay('nonsense'), 'nonsense');
    });

    test('the next delivery is the earliest one not yet past (Manila today)', () {
      final r = RemoteRequest.fromJson(requestDoc());
      // 2026-10-14 00:30 Manila = 2026-10-13 16:30 UTC: the 14 Oct delivery is today.
      expect(nextDelivery([r], DateTime.utc(2026, 10, 13, 16, 30)), '2026-10-14');
      expect(nextDelivery([r], DateTime.utc(2026, 10, 15)), '2026-10-21');
      expect(nextDelivery([r], DateTime.utc(2026, 11, 1)), isNull);
      expect(nextDelivery([RemoteRequest.fromJson(requestDoc(status: 'cancelled'))], DateTime.utc(2026, 10, 1)), isNull);
    });
  });

  group('failures', () {
    test('server codes map to failures and decide retrying', () {
      expect(RequestFailure.of(Exception('DESTINATION_CLOSED')), RequestFailure.destinationClosed);
      expect(RequestFailure.of(Exception('NOT_IN_TEAM')), RequestFailure.notInTeam);
      expect(RequestFailure.of(Exception('NOT_TEAM_LEADER')), RequestFailure.notTeamLeader);
      expect(RequestFailure.of(Exception('TOO_MANY_LINES')), RequestFailure.incomplete);
      expect(RequestFailure.of(Exception('NOT_YOUR_REQUEST')), RequestFailure.notYours);
      expect(RequestFailure.of(const SocketException('down')), RequestFailure.noConnection);
      expect(RequestFailure.of(StateError('AUTH_REQUIRED')), RequestFailure.sessionExpired);
      expect(RequestFailure.of(Exception('boom')), RequestFailure.unexpected);
      expect(RequestFailure.destinationClosed.retryable, isFalse);
      expect(RequestFailure.noConnection.retryable, isTrue);
      expect(RequestFailure.photoNotUploaded.retryable, isTrue);
      expect(RequestFailure.fromStored('lineClosed'), RequestFailure.lineClosed);
      expect(RequestFailure.fromStored('PHOTO_MISSING'), RequestFailure.unexpected);
    });

    test('every failure and every draft issue has words', () {
      for (final f in RequestFailure.values) {
        final c = requestFailureCopy(f);
        expect(c.english, isNotEmpty);
        expect(c.tagalog, isNotEmpty);
      }
      for (final k in DraftIssueKind.values) {
        expect(draftIssueText(k), isNotEmpty);
      }
      for (final s in SyncState.values) {
        expect(syncLabel(s), isNotEmpty);
      }
    });
  });

  group('queued edits of one line', () {
    test('a new edit sits on top of the edits still waiting', () {
      final queue = [op('a', OpKind.quantity, lineId: 'l1'), op('b', OpKind.cancelLine, lineId: 'l2'), op('c', OpKind.quantity, lineId: 'l1', failed: true)];
      expect(predictedBase(3, queue, 'l1'), 4);
      expect(predictedBase(3, queue, 'l2'), 4);
      expect(predictedBase(3, queue, 'l9'), 3);
    });

    test('an applied edit hands its version to the next edit only', () {
      final later = [op('b', OpKind.quantity, lineId: 'l1', base: 5), op('c', OpKind.photo), op('d', OpKind.quantity, lineId: 'l1', base: 6)];
      expect(rebaseAfter(later, 'l1', {'status': 'applied', 'version': 7}), {'b': 7});
      expect(rebaseAfter(later, 'l2', {'status': 'applied', 'version': 7}), isEmpty);
      expect(rebaseAfter(const [], 'l1', {'status': 'applied', 'version': 7}), isEmpty);
    });

    test('after a conflict every later edit of that line must conflict too', () {
      final later = [op('b', OpKind.quantity, lineId: 'l1', base: 5), op('d', OpKind.quantity, lineId: 'l1', base: 6)];
      expect(rebaseAfter(later, 'l1', {'status': 'conflict', 'version': 9}), {'b': 0, 'd': 0});
    });

    test('after a refused edit the next edit of that line takes its base', () {
      final refused = op('a', OpKind.quantity, lineId: 'l1', base: 3);
      final later = [op('b', OpKind.quantity, lineId: 'l1', base: 4), op('c', OpKind.quantity, lineId: 'l1', base: 5)];
      expect(rebaseAfterRefusal(later, refused), {'b': 3});
      expect(rebaseAfterRefusal(later, op('x', OpKind.cancelLine, lineId: 'l1')), isEmpty);
      expect(rebaseAfterRefusal(const [], refused), isEmpty);
    });

    test('an op survives the database round trip', () {
      final o = RequestOp(
        opId: 'o1',
        workerId: 'u1',
        kind: OpKind.photo,
        createdAt: DateTime.utc(2026, 10, 5),
        draftId: 'd1',
        linePosition: 2,
        body: const {'local_path': '/p/x.jpg', 'photo_id': 'ph1'},
      );
      final back = RequestOp.fromMap(o.toMap());
      expect(back.kind, OpKind.photo);
      expect(back.localPath, '/p/x.jpg');
      expect(back.photoId, 'ph1');
      expect(back.linePosition, 2);
      expect(back.createdAt, o.createdAt);
    });
  });
}
