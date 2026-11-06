import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/tools/domain/tool_failure.dart';
import 'package:workmate/tools/domain/tool_models.dart';
import 'package:workmate/tools/domain/tool_submission.dart';

import 'server_answers.dart';

List<Map<String, dynamic>> rows(String json) => [for (final r in jsonDecode(json) as List<dynamic>) Map<String, dynamic>.from(r as Map)];
Map<String, dynamic> doc(String json) => Map<String, dynamic>.from(jsonDecode(json) as Map);

void main() {
  group('0111 answers, exactly as the server sends them', () {
    test('My tools: number, item, details, project, days, and my open reports', () {
      final mine = rows(myToolsJson).map(PhoneTool.fromJson).toList();
      expect(mine.map((t) => t.label), ['TOOL-0001', 'TOOL-0004']);
      final t = mine.first;
      expect([t.name, t.details, t.folderName, t.holderName, t.days, t.isIssued], ['Grinder', 'Blue handle', 'House', 'Amy (W-0001)', 0, true]);
      expect(t.condition, ToolCondition.good);
      expect(t.myOpenProblems, [ProblemKind.broken]);
      expect(t.since, DateTime.parse(rows(myToolsJson).first['since'] as String), reason: 'the server\'s own time, as sent');
      expect(t.since!.isUtc, isTrue);
      expect([mine[1].lostPending, mine[1].isIssued, mine[1].myOpenProblems], [true, false, isEmpty]);
    });

    test('a tool keeps the server\'s own answer, for the saved copy', () {
      final raw = rows(myToolsJson).first;
      expect(PhoneTool.fromJson(raw).raw, raw);
      expect(jsonEncode(PhoneTool.fromJson(raw).raw), jsonEncode(raw));
    });

    test('one tool\'s history while they had it', () {
      final t = PhoneTool.fromJson(doc(myToolJson));
      expect(t.records.single.kind, 'issue');
      expect(t.records.single.folderName, 'House');
      expect(t.records.single.at, DateTime.parse((doc(myToolJson)['records'] as List).first['at'] as String));
      expect(t.records.single.at!.microsecond, isNot(0), reason: 'microseconds kept');
    });

    test('a tool they passed on: its history, with nobody\'s custody now', () {
      final t = PhoneTool.fromJson(doc(myToolPassedOnJson));
      expect([t.state, t.holderName, t.folderName, t.held], [null, null, null, false]);
      expect(t.records.map((r) => [r.kind, r.toName]), [['handover', 'Ben (W-0002)'], ['issue', null]]);
    });

    test('Team tools, the tool found by its number, the choices and the request lines', () {
      expect(rows(teamToolsJson).map(PhoneTool.fromJson).map((t) => t.holderName).toSet(), {'Amy (W-0001)', 'Ben (W-0002)'});
      expect(PhoneTool.fromJson(doc(teamToolJson)).records, hasLength(1));
      final found = FoundTool.fromJson(doc(findJson));
      expect([found.label, found.name, found.details], ['TOOL-0003', 'Grinder', 'Spare']);
      final c = TeamChoices.fromJson(doc(choicesJson));
      expect(c.members.map((m) => m.name), ['Amy (W-0001)', 'Ben (W-0002)', 'Cal (W-0003)', 'Dee (W-0004)']);
      expect([c.projects.single.name, c.projects.single.main], ['House', true]);
      final l = rows(requestLinesJson).map(ToolRequestLine.fromJson).single;
      expect([l.description, l.unit, l.requesterName, l.stillToFill, l.boughtForThisTool], ['Grinder', 'pc', 'Amy', 1, false]);
    });

    test('a leader\'s own records, and which they can still undo', () {
      final r = rows(myRecordsJson).map(LeaderRecord.fromJson).toList();
      expect(r.first.kind, 'return');
      expect(r.first.canReverse, isFalse, reason: 'its Retire request came after');
      expect(r.map((x) => x.label).toSet(), {'TOOL-0001', 'TOOL-0002', 'TOOL-0003'});
      expect(r.any((x) => x.canReverse), isTrue);
    });

    test('nothing the phone reads carries money, a purchase, a note or a photo', () {
      final forbidden = RegExp('amount|price|cost|peso|purchase|note|photo|receipt');
      void keys(Object? o) {
        if (o is List) o.forEach(keys);
        if (o is Map) {
          for (final k in o.keys) {
            expect(forbidden.hasMatch(k as String), isFalse, reason: k);
            keys(o[k]);
          }
        }
      }

      for (final j in [myToolsJson, myToolJson, myToolPassedOnJson, teamToolsJson, teamToolJson, findJson, choicesJson, requestLinesJson, myRecordsJson]) {
        keys(jsonDecode(j));
      }
    });
  });

  group('refusals', () {
    PostgrestException refusal(String code) => PostgrestException(message: code, code: 'P0001');

    test('every code a worker or a leader can be given has its own meaning', () {
      const expected = {
        'TOOLS_OFF': ToolFailure.toolsOff,
        'NOT_A_REQUESTER': ToolFailure.notCrew,
        'NOT_LEADER': ToolFailure.notLeader,
        'NOT_YOUR_TEAM': ToolFailure.notYourTeam,
        'NOT_YOUR_TOOL': ToolFailure.notYourTool,
        'TOOL_NOT_AVAILABLE': ToolFailure.notAvailable,
        'NOT_AVAILABLE': ToolFailure.notAvailable,
        'NOT_ISSUED': ToolFailure.notIssued,
        'NEEDS_REPAIR': ToolFailure.needsRepair,
        'SAME_HOLDER': ToolFailure.sameHolder,
        'REQUEST_NEEDS_OFFICE': ToolFailure.requestNeedsOffice,
        'BAD_REQUEST_LINK': ToolFailure.badRequestLink,
        'NOT_A_TOOL_LINE': ToolFailure.badRequestLink,
        'ITEM_MISMATCH': ToolFailure.badRequestLink,
        'UNIT_MISMATCH': ToolFailure.badRequestLink,
        'LINE_CLOSED': ToolFailure.lineClosed,
        'BAD_PERSON': ToolFailure.badPerson,
        'PERSON_REQUIRED': ToolFailure.badPerson,
        'BAD_PROJECT': ToolFailure.badProject,
        'PROJECT_COMPLETED': ToolFailure.projectCompleted,
        'BAD_CONDITION': ToolFailure.badCondition,
        'BAD_KIND': ToolFailure.badKind,
        'ALREADY_REPORTED': ToolFailure.alreadyReported,
        'NOT_YOURS': ToolFailure.notYours,
        'LATER_RECORDS': ToolFailure.laterRecords,
        'BAD_STATE': ToolFailure.badState,
        'NOT_FOUND': ToolFailure.notFound,
        'BAD_NOTE': ToolFailure.badNote,
        'REASON_REQUIRED': ToolFailure.reasonRequired,
        'OP_CANCELLED': ToolFailure.opCancelled,
        'BAD_OP': ToolFailure.unexpected,
        'APP_UPDATE_REQUIRED': ToolFailure.appUpdateRequired,
        'AUTH_REQUIRED': ToolFailure.sessionExpired,
      };
      for (final e in expected.entries) {
        expect(ToolFailure.of(refusal(e.key)), e.value, reason: e.key);
      }
    });

    test('whole codes only: NOT_YOUR_TOOL is not NOT_YOURS, TOOL_NOT_AVAILABLE is not read twice', () {
      expect(ToolFailure.of(refusal('NOT_YOUR_TOOL')), ToolFailure.notYourTool);
      expect(ToolFailure.of(refusal('NOT_YOURS')), ToolFailure.notYours);
    });

    test('no signal is "no connection"; anything unknown is "unexpected", never a guess', () {
      for (final e in [const SocketException('x'), TimeoutException('x')]) {
        expect(ToolFailure.of(e), ToolFailure.noConnection);
      }
      expect(ToolFailure.of(refusal('SOMETHING_NEW')), ToolFailure.unexpected);
      expect(ToolFailure.of(const FormatException('garbled')), ToolFailure.unexpected);
    });

    test('a lost answer is unsure; every server "no" is not', () {
      expect(ToolFailure.values.where((f) => f.uncertain).toSet(), {ToolFailure.noConnection, ToolFailure.unexpected});
    });

    test('every refusal has English and Tagalog wording', () {
      for (final f in ToolFailure.values) {
        final c = toolFailureCopy(f);
        expect(c.english.trim(), isNotEmpty, reason: f.name);
        expect(c.tagalog.trim(), isNotEmpty, reason: f.name);
      }
    });
  });

  group('a saved submission', () {
    final now = DateTime.utc(2026, 11, 6, 2);

    test('the writes the phone makes, by their server function', () {
      expect(ToolWrite.values.map((w) => w.fn),
          ['tl_team_issue', 'tl_team_handover', 'tl_team_return', 'tl_team_reverse', 'tl_report_problem']);
      expect(ToolWrite.byFn('tl_team_return'), ToolWrite.giveBack);
      expect(ToolWrite.byFn('tl_issue'), isNull, reason: 'the office\'s own functions are never called from the phone');
    });

    test('a payload never travels without its own operation id', () {
      expect(() => ToolSubmission.create(opId: 'a', userId: 'u1', write: ToolWrite.issue, params: {'p_op': 'b'}, summary: '', now: now),
          throwsArgumentError);
      expect(ToolSubmission.fromJson({'op_id': 'a', 'user_id': 'u1', 'fn': 'tl_team_issue', 'payload': '{"p_op":"b"}', 'created_at': '2026-11-06T02:00:00Z'}),
          isNull);
    });

    test('kept word for word through the settings file', () {
      final s = ToolSubmission.create(
          opId: 'op1', userId: 'u1', write: ToolWrite.report, params: {'p_op': 'op1', 'p_tool': 't1', 'p_kind': 'broken', 'p_note': ''},
          summary: 'TOOL-0001 · reported broken', now: now).sentAt(now);
      final back = ToolSubmission.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>)!;
      expect([back.opId, back.userId, back.write, back.payload, back.summary, back.sends], ['op1', 'u1', ToolWrite.report, s.payload, s.summary, 1]);
    });
  });
}
