import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/workplan/domain/wp_task.dart';

/// One task as 0093 wp_task_doc sends it to a worker. Override any field.
Map<String, dynamic> taskDoc({
  String id = 't1',
  String title = 'Wall prep',
  String status = 'not_started',
  String role = 'responsible',
  int version = 1,
  int? ackVersion,
  bool blocked = false,
  bool canCheck = false,
  bool sentBack = false,
  String? start = '2026-10-14',
  String? end = '2026-10-16',
  List<Map<String, dynamic>> blockers = const [],
  List<Map<String, dynamic>> waitingFor = const [],
  List<Map<String, dynamic>> history = const [],
  List<Map<String, dynamic>> photos = const [],
  String folder = 'f1',
}) =>
    {
      'id': id,
      'meeting_id': 'm1',
      'title': title,
      'instructions': 'Skim coat the master bedroom.',
      'folder_id': folder,
      'project_name': 'Barlin Residence',
      'work_id': folder,
      'work_name': 'Main Contract',
      'team_id': 'tm1',
      'team_name': 'Team pilot B',
      'status': status,
      'sent_back': sentBack,
      'blocked': blocked,
      'planned_start': start,
      'planned_end': end,
      'version': version,
      'version_at': '2026-10-14T01:00:00+00:00',
      'published_at': '2026-10-14T01:00:00+00:00',
      'completed_at': status == 'completed' ? '2026-10-15T09:00:00+00:00' : null,
      'updated_at': '2026-10-14T01:00:00+00:00',
      'responsible': {'id': 'u1', 'name': 'John Tapales'},
      'helpers': [
        {'id': 'u2', 'name': 'Danilo Tapales'},
      ],
      'blockers': blockers,
      'waiting_for': waitingFor,
      'photos': photos,
      'history': history,
      'my_role': role,
      'my_ack_version': ackVersion,
      'can_check': canCheck,
    };

WpTask task0([Map<String, dynamic>? doc]) => WpTask.fromJson(doc ?? taskDoc())!;

Map<String, dynamic> noteDoc({String id = 'm1', int version = 1}) => {
      'meeting_id': id,
      'title': 'Site meeting',
      'held_on': '2026-10-14',
      'version': version,
      'shared_notes': 'Skim coat first, then cabinets.',
      'change_note': '',
      'published_at': '2026-10-14T02:00:00+00:00',
    };

Map<String, dynamic> proposalDoc({String id = 'p1', String status = 'sent', String? reason}) => {
      'id': id,
      'title': 'Fix the gate',
      'project_name': 'Barlin Residence',
      'work_name': 'Main Contract',
      'proposed_at': '2026-10-13T02:00:00+00:00',
      'status': status,
      'reason': reason,
      'decided_at': status == 'sent' ? null : '2026-10-14T02:00:00+00:00',
    };

const barlin = Destination(projectId: 'f1', projectName: 'Barlin Residence', workId: 'f1', workName: 'Main Contract', isMain: true);
const pilotB = MyTeam(id: 'tm1', name: 'Team pilot B', iLead: true, members: [TeamMember(id: 'u1', name: 'John Tapales')]);
const otherTeam = MyTeam(id: 'tm2', name: 'Masonry A', iLead: false, members: []);
