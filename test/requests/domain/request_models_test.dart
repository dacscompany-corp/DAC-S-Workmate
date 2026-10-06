import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/domain/quantity.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_models.dart';

/// One pr_my_requests document, as the server sends it (0085 §10).
Map<String, dynamic> requestDoc({
  String id = 'r1',
  String status = 'submitted',
  bool mine = true,
  List<Map<String, dynamic>>? lines,
}) =>
    {
      'id': id,
      'status': status,
      'received_at': '2026-10-05T03:00:00+00:00',
      'drafted_at': '2026-10-05T01:00:00+00:00',
      'note': 'Back gate',
      'mine': mine,
      'requester_name': 'Juan dela Cruz',
      'project_id': 'f1',
      'project_name': 'Santos Townhouse',
      'work_id': 'f1',
      'work_name': 'Main Contract',
      'team_id': null,
      'team_name': null,
      'lines': lines ??
          [
            {
              'id': 'l1',
              'position': 0,
              'kind': 'material',
              'catalog_item_id': 'c1',
              'description': 'PVC pipe',
              'spec': '1/2 in',
              'unit': 'pc',
              'category': 'plumbing',
              'intended_member_id': null,
              'intended_member_name': null,
              'urgent': true,
              'urgent_reason': 'Leak',
              'needed_by': '2026-10-07',
              'notes': '',
              'status': 'open',
              'version': 2,
              'has_conflict': false,
              'needed': 12,
              'portions': [
                {
                  'quantity': 10,
                  'pending_reduction': 0,
                  'arranged': true,
                  'cutoff_at': '2026-10-10T04:00:00+00:00',
                  'purchase_on': '2026-10-12',
                  'delivery_on': '2026-10-14',
                },
                {
                  'quantity': 2.5,
                  'pending_reduction': 0.5,
                  'arranged': false,
                  'cutoff_at': '2026-10-17T04:00:00+00:00',
                  'purchase_on': '2026-10-19',
                  'delivery_on': '2026-10-21',
                },
              ],
            },
          ],
      'photos': [
        {'id': 'ph1', 'line_id': 'l1', 'path': 'u1/r1/ph1.jpg'},
      ],
    };

void main() {
  group('quantities', () {
    test('parseQuantity accepts exactly what the server accepts', () {
      expect(parseQuantity(' 12 '), 12);
      expect(parseQuantity('2.125'), 2.125);
      expect(parseQuantity('1000000'), 1000000);
      expect(parseQuantity('0'), isNull);
      expect(parseQuantity('-1'), isNull);
      expect(parseQuantity('1.2345'), isNull);
      expect(parseQuantity('1000001'), isNull);
      expect(parseQuantity('2.'), isNull);
      expect(parseQuantity('abc'), isNull);
      expect(parseQuantity(''), isNull);
    });

    test('formatQuantity drops trailing zeros and groups thousands', () {
      expect(formatQuantity(10), '10');
      expect(formatQuantity(2.5), '2.5');
      expect(formatQuantity(1.125), '1.125');
      expect(formatQuantity(100), '100');
      expect(formatQuantity(1000000), '1,000,000');
    });
  });

  group('choices', () {
    test('a destination reads both Main Contract and Additional Works rows', () {
      final main = Destination.fromRow({
        'project_id': 'f1',
        'project_name': 'Santos Townhouse',
        'work_id': 'f1',
        'work_name': 'Main Contract',
        'is_main': true,
      });
      final aw = Destination.fromRow({
        'project_id': 'f1',
        'project_name': 'Santos Townhouse',
        'work_id': 'f9',
        'work_name': 'AW-03 Fence',
        'is_main': false,
      });
      expect(main.isMain, isTrue);
      expect(aw.label, 'Santos Townhouse · AW-03 Fence');
      expect(Destination.fromRow(aw.toRow()), aw);
      expect(main == aw, isFalse);
    });

    test('a team carries whether I lead it and its members', () {
      final t = MyTeam.fromRow({
        'team_id': 't1',
        'team_name': 'Masonry A',
        'i_lead': true,
        'members': [
          {'id': 'u1', 'name': 'Juan'},
          {'id': 'u2', 'name': 'Pedro'},
        ],
      });
      expect(t.iLead, isTrue);
      expect(t.members.map((m) => m.name), ['Juan', 'Pedro']);
      expect(MyTeam.fromRow(t.toRow()).members.length, 2);
    });

    test('a catalogue item of an unknown kind is dropped, not guessed', () {
      final pipe = CatalogItem.fromRow({'id': 'c1', 'kind': 'material', 'name': 'PVC pipe', 'spec': '1/2 in', 'unit': 'pc', 'category': 'plumbing'});
      expect(pipe!.label, 'PVC pipe · 1/2 in (pc)');
      expect(CatalogItem.fromRow({'id': 'c2', 'kind': 'food', 'name': 'Rice', 'spec': '', 'unit': 'kg', 'category': ''}), isNull);
      expect(CatalogItem.fromRow(pipe.toRow())!.kind, ItemKind.material);
    });
  });

  group('a received request', () {
    test('parses every field the screens use', () {
      final r = RemoteRequest.fromJson(requestDoc());
      expect(r.title, 'Santos Townhouse · Main Contract');
      expect(r.mine, isTrue);
      expect(r.cancelled, isFalse);
      expect(r.receivedAt, DateTime.utc(2026, 10, 5, 3));
      final l = r.lines.single;
      expect(l.kind, ItemKind.material);
      expect(l.urgent, isTrue);
      expect(l.neededBy, '2026-10-07');
      expect(l.version, 2);
      expect(l.needed, 12);
      expect(l.portions.length, 2);
      expect(l.portions[1].quantity, 2.5);
      expect(l.portions[1].pendingReduction, 0.5);
      expect(l.portions[0].deliveryOn, '2026-10-14');
      expect(r.photos.single.path, 'u1/r1/ph1.jpg');
    });

    test('a cancelled request and a cancelled line read as cancelled', () {
      final doc = requestDoc(status: 'cancelled');
      (doc['lines'] as List).first['status'] = 'cancelled';
      final r = RemoteRequest.fromJson(doc);
      expect(r.cancelled, isTrue);
      expect(r.lines.single.cancelled, isTrue);
    });
  });
}
