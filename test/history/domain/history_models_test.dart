import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/history/domain/history_failure.dart';
import 'package:workmate/history/domain/history_models.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_failure.dart';
import 'package:workmate/requests/domain/request_models.dart';

import '../history_samples.dart';

const site = Destination(projectId: 'f1', projectName: 'Barlin Residence', workId: 'f1', workName: 'Main Contract', isMain: true);

void main() {
  group('dates', () {
    test('an exact day, "around" a month, or Date unknown — never shifted a day', () {
      expect(historyDateLabel('2026-10-03', 'exact'), '3 Oct 2026');
      expect(historyDateLabel('2026-08-01', 'approximate'), 'around Aug 2026');
      expect(historyDateLabel(null, 'unknown'), 'Date unknown');
      expect(historyDateLabel(null, 'exact'), 'Date unknown');
      expect(historyDateLabel('2026-13-01', 'exact'), 'Date unknown');
    });
  });

  group('search results', () {
    test('a card reads the 0090 shape, with its latest visible entry', () {
      final page = HistoryPage.fromJson({'items': [cardJson()], 'has_more': true});
      expect(page.hasMore, isTrue);
      expect(page.fromSaved, isFalse);
      final c = page.items.single;
      expect([c.id, c.name, c.spec, c.unit, c.brand, c.coverPath], ['i1', 'Outlet', '2-gang', 'pc', 'Omni', 'o1/i1/p1.jpg']);
      expect(c.aliases, ['saksakan']);
      expect(c.latest!.summary, 'Latest: Requested · 3 Oct 2026 · Barlin Residence');
    });

    test('a kind this build does not know is left out, not shown broken', () {
      final page = HistoryPage.fromJson({'items': [cardJson(kind: 'vehicle'), cardJson(id: 'i2')], 'has_more': false});
      expect(page.items.map((c) => c.id), ['i2']);
    });

    test('an item with no visible history has no latest line', () {
      final j = cardJson()..['latest'] = null;
      expect(HistoryCard.fromJson(j)!.latest, isNull);
    });
  });

  group('one item', () {
    test('photos cover first, entries newest first, labels and quantities as sent', () {
      final item = HistoryItem.fromJson(itemJson())!;
      expect(item.photos.first.isCover, isTrue);
      expect(item.entries.map((e) => e.key), ['request_line:l1', 'reference:r1']);
      expect(item.entries.first.quantity, 6);
      expect(item.entries.last.quantity, isNull);
      expect(historyDateLabel(item.entries.last.date, item.entries.last.datePrecision), 'around Aug 2026');
    });

    test('saved and read back unchanged (the offline copy)', () {
      final item = HistoryItem.fromJson(itemJson())!;
      final back = HistoryItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>)!;
      expect(back.toJson(), item.toJson());
    });

    test('its offline card shows the cover and the newest entry', () {
      final card = HistoryItem.fromJson(itemJson())!.toCard();
      expect(card.coverPath, 'o1/i1/p1.jpg');
      expect(card.latest!.entryId, 'l1');
    });
  });

  group('Request Again', () {
    final item = HistoryItem.fromJson(itemJson())!;

    test('the pick carries the item and the entry — never a quantity', () {
      final pick = HistoryPick.of(item, item.entries.last);
      final line = DraftLine.fromHistory('x1', pick);
      expect([line.catalogItemId, line.description, line.spec, line.unit, line.category], ['i1', 'Outlet', '2-gang', 'pc', 'electrical']);
      expect([line.refKind, line.refId, line.refCoverPath], ['reference', 'r1', 'o1/i1/p1.jpg']);
      expect(line.quantity, '', reason: 'the worker types the quantity');
      expect(line.fromHistory, isTrue);
    });

    test('the link survives saving and reopening the draft', () {
      final line = DraftLine.fromHistory('x1', HistoryPick.of(item, item.entries.first));
      final back = DraftLine.fromJson(jsonDecode(jsonEncode(line.toJson())) as Map<String, dynamic>);
      expect([back.refKind, back.refId, back.refCoverPath], ['request_line', 'l1', 'o1/i1/p1.jpg']);
    });

    test('the link is sent with the line; a plain line sends none', () {
      final linked = DraftLine.fromHistory('x1', HistoryPick.of(item, item.entries.first)).copyWith(quantity: '4');
      const plain = DraftLine(id: 'x2', description: 'Sand', unit: 'bag', quantity: '2');
      final d = RequestDraft(id: 'd1', createdAt: DateTime.utc(2026, 10, 9), destination: site, lines: [linked, plain]);
      final lines = (submitPayload(d)['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines[0]['ref_kind'], 'request_line');
      expect(lines[0]['ref_id'], 'l1');
      expect(lines[0].containsKey('ref_cover_path'), isFalse, reason: 'the cover is for the screen only');
      expect(lines[1].containsKey('ref_kind'), isFalse);
      expect(lines[1].containsKey('ref_id'), isFalse);
    });

    test('withoutRef drops the whole link', () {
      final line = DraftLine.fromHistory('x1', HistoryPick.of(item, item.entries.first)).withoutRef();
      expect([line.refKind, line.refId, line.refCoverPath], [null, null, null]);
      expect(line.catalogItemId, 'i1');
    });
  });

  group('failures', () {
    test('server codes map to what the worker is told', () {
      expect(HistoryFailure.of(Exception('HISTORY_NOT_AVAILABLE')), HistoryFailure.notAvailable);
      expect(HistoryFailure.of(Exception('NOT_A_REQUESTER')), HistoryFailure.notARequester);
      expect(HistoryFailure.of(const HistoryUnavailable(HistoryFailure.savedTooOld)), HistoryFailure.savedTooOld);
      expect(HistoryFailure.of(Exception('boom')), HistoryFailure.unexpected);
      expect(RequestFailure.of(Exception('BAD_REFERENCE')), RequestFailure.badReference);
    });
  });
}
