// What 0090's worker RPCs return, as the phone receives it (JSON).

Map<String, dynamic> cardJson({
  String id = 'i1',
  String kind = 'material',
  String name = 'Outlet',
  bool active = true,
  String? cover = 'o1/i1/p1.jpg',
  Map<String, dynamic>? latest,
}) =>
    {
      'id': id,
      'kind': kind,
      'name': name,
      'spec': '2-gang',
      'unit': 'pc',
      'category': 'electrical',
      'brand': 'Omni',
      'aliases': ['saksakan'],
      'active': active,
      'cover_path': cover,
      'latest': latest ??
          {
            'entry_kind': 'request_line',
            'entry_id': 'l1',
            'label': 'Requested',
            'project_id': 'f1',
            'project_name': 'Barlin Residence',
            'work_id': 'f1',
            'work_name': 'Main Contract',
            'date': '2026-10-03',
            'date_precision': 'exact',
          },
    };

Map<String, dynamic> entryJson({
  String kind = 'request_line',
  String id = 'l1',
  String label = 'Requested',
  String projectId = 'f1',
  String project = 'Barlin Residence',
  String work = 'Main Contract',
  String? date = '2026-10-03',
  String precision = 'exact',
  num? quantity = 6,
  String? description,
  String? note,
}) =>
    {
      'entry_kind': kind,
      'entry_id': id,
      'label': label,
      'project_id': projectId,
      'project_name': project,
      'work_id': projectId,
      'work_name': work,
      'date': date,
      'date_precision': precision,
      'quantity': quantity,
      'unit': kind == 'request_line' ? 'pc' : null,
      'description': description,
      'note': note,
      'retired': false,
      'requester_name': null,
    };

Map<String, dynamic> itemJson({
  String id = 'i1',
  bool active = true,
  List<Map<String, dynamic>>? photos,
  List<Map<String, dynamic>>? entries,
}) =>
    {
      'id': id,
      'kind': 'material',
      'name': 'Outlet',
      'spec': '2-gang',
      'unit': 'pc',
      'category': 'electrical',
      'brand': 'Omni',
      'aliases': ['saksakan'],
      'active': active,
      'photos': photos ??
          [
            {'id': 'p1', 'path': 'o1/$id/p1.jpg', 'is_cover': true, 'status': 'approved'},
            {'id': 'p2', 'path': 'o1/$id/p2.jpg', 'is_cover': false, 'status': 'approved'},
          ],
      'entries': entries ??
          [
            entryJson(),
            entryJson(kind: 'reference', id: 'r1', label: 'Historical reference', date: '2026-08-01', precision: 'approximate',
                quantity: null, description: 'Kitchen outlets', note: 'old Messenger photo'),
          ],
    };
