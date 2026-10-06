/// What a worker chooses from when building a request (0085 pr_destinations,
/// pr_my_teams, pr_catalog). Names only — the server never sends contact
/// details or money to a worker.
library;

enum ItemKind {
  material('material', 'Material'),
  tool('tool', 'Tool');

  const ItemKind(this.wire, this.label);

  /// The value the server stores (pr_lines.kind).
  final String wire;
  final String label;

  static ItemKind? parse(String? value) => values.where((k) => k.wire == value).firstOrNull;
}

/// One place a request can be for: a Project Control project's Main Contract,
/// or one of its own open Additional Works jobs.
class Destination {
  const Destination({
    required this.projectId,
    required this.projectName,
    required this.workId,
    required this.workName,
    required this.isMain,
  });

  factory Destination.fromRow(Map<String, dynamic> row) => Destination(
        projectId: row['project_id'] as String,
        projectName: row['project_name'] as String,
        workId: row['work_id'] as String,
        workName: row['work_name'] as String,
        isMain: row['is_main'] == true,
      );

  final String projectId;
  final String projectName;
  final String workId;
  final String workName;
  final bool isMain;

  /// "Santos Townhouse · Main Contract".
  String get label => '$projectName · $workName';

  Map<String, dynamic> toRow() => {
        'project_id': projectId,
        'project_name': projectName,
        'work_id': workId,
        'work_name': workName,
        'is_main': isMain,
      };

  @override
  bool operator ==(Object other) => other is Destination && other.projectId == projectId && other.workId == workId;

  @override
  int get hashCode => Object.hash(projectId, workId);
}

class TeamMember {
  const TeamMember({required this.id, required this.name});

  factory TeamMember.fromRow(Map<String, dynamic> row) => TeamMember(id: row['id'] as String, name: row['name'] as String);

  final String id;
  final String name;

  Map<String, dynamic> toRow() => {'id': id, 'name': name};
}

/// A team the worker is a current member of. [iLead] is the server's answer
/// to "role teamLeader AND the current leader of THIS team" (spec §3).
class MyTeam {
  const MyTeam({required this.id, required this.name, required this.iLead, required this.members});

  factory MyTeam.fromRow(Map<String, dynamic> row) => MyTeam(
        id: row['team_id'] as String,
        name: row['team_name'] as String,
        iLead: row['i_lead'] == true,
        members: [
          for (final m in (row['members'] as List<dynamic>? ?? const []))
            TeamMember.fromRow(Map<String, dynamic>.from(m as Map)),
        ],
      );

  final String id;
  final String name;
  final bool iLead;
  final List<TeamMember> members;

  Map<String, dynamic> toRow() => {
        'team_id': id,
        'team_name': name,
        'i_lead': iLead,
        'members': [for (final m in members) m.toRow()],
      };
}

/// One defined item: name + spec + unit. A different size or unit is a
/// different item.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.spec,
    required this.unit,
    required this.category,
  });

  /// Null for a kind this build does not know: offering it would fail at send.
  static CatalogItem? fromRow(Map<String, dynamic> row) {
    final kind = ItemKind.parse(row['kind'] as String?);
    if (kind == null) return null;
    return CatalogItem(
      id: row['id'] as String,
      kind: kind,
      name: row['name'] as String,
      spec: (row['spec'] as String?) ?? '',
      unit: row['unit'] as String,
      category: (row['category'] as String?) ?? '',
    );
  }

  final String id;
  final ItemKind kind;
  final String name;
  final String spec;
  final String unit;
  final String category;

  /// "PVC pipe · 1/2 in (pc)".
  String get label => spec.isEmpty ? '$name ($unit)' : '$name · $spec ($unit)';

  Map<String, dynamic> toRow() => {
        'id': id,
        'kind': kind.wire,
        'name': name,
        'spec': spec,
        'unit': unit,
        'category': category,
      };
}
