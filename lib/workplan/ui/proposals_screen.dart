import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../attendance/ui/status_pill.dart';
import '../../requests/domain/request_models.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/workplan_api.dart';
import '../domain/wp_failure.dart';
import '../domain/wp_task.dart';
import 'my_work_controller.dart';
import 'workplan_copy.dart';
import 'workplan_widgets.dart';

/// A team leader's own proposals (spec §15, decided 13 October 2026): Sent
/// (still an office draft), Published, or Declined with the office's reason.
/// A proposal is never live by itself: the office edits, publishes or declines it.
class ProposalsScreen extends StatelessWidget {
  const ProposalsScreen({super.key, required this.controller});

  final MyWorkController controller;

  Future<void> _propose(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProposeFormScreen(controller: controller)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My proposals')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final view = controller.view;
              return RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                  FilledButton.icon(
                    key: const Key('propose'),
                    onPressed: () => _propose(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Propose a task'),
                  ),
                  const SizedBox(height: 8),
                  const Text('The office reviews each proposal. Nothing reaches the team until the office publishes it.',
                      style: TextStyle(color: WmColors.textMuted)),
                  const SizedBox(height: 12),
                  for (final op in view.pendingProposals)
                    WpBox(children: [
                      Row(children: [
                        Expanded(child: Text((op.body['title'] as String?) ?? '', style: const TextStyle(fontWeight: FontWeight.w800))),
                        const StatusPill.brown('Pending sync'),
                      ]),
                      Text('${op.body['where'] ?? ''} · Team ${op.body['team_name'] ?? ''}', style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
                    ]),
                  if (view.proposals.isEmpty && view.pendingProposals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('No proposals in the last 90 days.', textAlign: TextAlign.center, style: TextStyle(color: WmColors.textMuted)),
                    ),
                  for (final p in view.proposals)
                    WpBox(key: Key('proposal-${p.id}'), children: [
                      Row(children: [
                        Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                        _StatePill(p.state),
                      ]),
                      Text('${p.where} · sent ${dayMonth(p.proposedAt)}', style: const TextStyle(color: WmColors.textMuted, fontSize: 13)),
                      if (p.reason != null && p.reason!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Office: ${p.reason}', style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w700)),
                      ],
                      if (p.state == WpProposalState.published)
                        const Text('If you are on it, it is in My Work.', style: TextStyle(color: WmColors.green, fontSize: 13)),
                    ]),
                ]),
              );
            },
          ),
        ),
      );
}

class _StatePill extends StatelessWidget {
  const _StatePill(this.state);
  final WpProposalState state;

  @override
  Widget build(BuildContext context) => switch (state) {
        WpProposalState.published => StatusPill.green(proposalStateLabel(state)),
        WpProposalState.sent => StatusPill.brown(proposalStateLabel(state)),
        WpProposalState.declined || WpProposalState.cancelled =>
          StatusPill(proposalStateLabel(state), background: WmColors.dangerTint, foreground: WmColors.danger),
      };
}

/// Propose a task for a team this leader currently leads, on an open project.
class ProposeFormScreen extends StatefulWidget {
  const ProposeFormScreen({super.key, required this.controller});

  final MyWorkController controller;

  @override
  State<ProposeFormScreen> createState() => _ProposeFormScreenState();
}

class _ProposeFormScreenState extends State<ProposeFormScreen> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  late Future<WpChoices> _choices = widget.controller.api.choices();
  MyTeam? _team;
  Destination? _destination;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final team = _team, destination = _destination;
    if (team == null || destination == null || _title.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.controller.act((a) => a.propose(team: team, destination: destination, title: _title.text, details: _details.text));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Propose a task')),
        body: SafeArea(
          child: FutureBuilder<WpChoices>(
            future: _choices,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final choices = snap.data;
              if (choices == null) {
                final copy = wpFailureCopy(WpFailure.of(snap.error ?? StateError('no choices')));
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: FailureNotice(
                    english: copy.english,
                    tagalog: copy.tagalog,
                    actions: [noticeAction(retryLabel, () => setState(() => _choices = widget.controller.api.choices()))],
                  ),
                );
              }
              if (choices.teams.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('You are not leading a team right now, so you cannot propose tasks.', style: TextStyle(color: WmColors.textMuted)),
                );
              }
              _team ??= choices.teams.length == 1 ? choices.teams.single : null;
              final ok = _team != null && _destination != null && _title.text.trim().isNotEmpty && !_sending;
              return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
                DropdownButtonFormField<MyTeam>(
                  key: const Key('propose-team'),
                  initialValue: _team,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Team'),
                  items: [for (final t in choices.teams) DropdownMenuItem(value: t, child: Text(t.name))],
                  onChanged: (t) => setState(() => _team = t),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Destination>(
                  key: const Key('propose-destination'),
                  initialValue: _destination,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Project and work'),
                  items: [
                    for (final d in choices.destinations) DropdownMenuItem(value: d, child: Text(d.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (d) => setState(() => _destination = d),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('propose-title'),
                  controller: _title,
                  maxLength: 200,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Task title'),
                ),
                TextField(
                  key: const Key('propose-details'),
                  controller: _details,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'Details (optional)'),
                ),
                const SizedBox(height: 12),
                FilledButton(key: const Key('propose-send'), onPressed: ok ? _send : null, child: const Text('Send to the office')),
                if (choices.fromCache) ...[
                  const SizedBox(height: 8),
                  const Text('No signal: these lists are the ones this phone saved.', style: TextStyle(fontSize: 12.5, color: WmColors.brown)),
                ],
                const SizedBox(height: 8),
                const Text(savedOnPhoneText, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
              ]);
            },
          ),
        ),
      );
}
