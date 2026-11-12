import 'dart:io';

import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart';
import '../../requests/data/requests_api.dart';
import '../../requests/domain/remote_request.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
import '../data/workplan_api.dart';
import '../domain/wp_task.dart';
import '../workplan_services.dart';
import 'workplan_copy.dart';

/// What a note form returns: the text, and a kept photo path or null.
typedef NoteReport = ({String note, String? photo});

/// What the problem form returns.
typedef ProblemReport = ({String kind, String description, String? requestId, String? photo});

/// What the worker typed or picked in one report form, kept by the task
/// sheet while it is open (owner decision 12 Nov 2026): leaving a form and
/// coming back shows it again. Send clears it; closing the sheet deletes an
/// unsent photo. Never saved beyond the open sheet.
class ReportDraft {
  String text = '';
  String? photo;

  /// Report a problem only.
  String kind = wpProblemKinds.first;
  String? requestId;
}

/// Takes one photo and files it in app-private storage; null when the worker
/// backed out. A capture that cannot be filed says so.
Future<String?> _takePhoto(BuildContext context, WorkPlanServices services, void Function(bool) onFailure) async {
  final raw = await services.takePhoto(context);
  if (raw == null) return null;
  try {
    final kept = await services.api.keepPhoto(raw);
    onFailure(false);
    return kept;
  } catch (_) {
    onFailure(true);
    return null;
  } finally {
    try {
      File(raw).deleteSync();
    } catch (_) {}
  }
}

/// The photo row of a form: Add photo, or the photo with Remove.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.photo, required this.onAdd, required this.onRemove, required this.failed});

  final String? photo;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = photo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (p == null)
        OutlinedButton.icon(key: const Key('add-photo'), onPressed: onAdd, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Add a photo (optional)'))
      else
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(p), width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 72, height: 72, color: WmColors.inert)),
          ),
          const SizedBox(width: 12),
          TextButton(key: const Key('remove-photo'), onPressed: onRemove, child: const Text('Remove photo')),
        ]),
      if (failed) ...[
        const SizedBox(height: 8),
        FailureNotice(english: photoNotKeptCopy.english, tagalog: photoNotKeptCopy.tagalog),
      ],
    ]);
  }
}

/// A short note (progress, report done, a leader's check), with an optional
/// photo where 0093 accepts one. The task sheet keeps what was typed while it
/// is open and deletes an unsent photo when it closes.
class NoteForm extends StatefulWidget {
  const NoteForm({
    super.key,
    required this.services,
    required this.title,
    required this.label,
    required this.submitLabel,
    required this.taskTitle,
    required this.draft,
    required this.onSubmit,
    required this.onLeave,
    this.required = false,
    this.allowPhoto = false,
    this.explain,
  });

  final WorkPlanServices services;
  final String title;
  final String label;
  final String submitLabel;

  /// The task this report is about, shown above the fields.
  final String taskTitle;

  /// What was typed here before, kept by the task sheet while it is open.
  final ReportDraft draft;

  /// The worker tapped the send button: the sheet queues it. Never called on back-out.
  final ValueChanged<NoteReport> onSubmit;

  /// Back to the task (the sheet's back arrow).
  final VoidCallback onLeave;
  final bool required;
  final bool allowPhoto;
  final String? explain;

  @override
  State<NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<NoteForm> {
  late final _text = TextEditingController(text: widget.draft.text);
  late String? _photo = widget.draft.photo;
  bool _photoFailed = false;

  @override
  void dispose() {
    // The draft and its photo belong to the task sheet, which deletes an unsent photo when it closes.
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final kept = await _takePhoto(context, widget.services, (f) => _photoFailed = f);
    if (!mounted) {
      if (kept != null) await widget.services.api.discardPhoto(kept);
      return;
    }
    setState(() => _photo = kept ?? _photo);
    widget.draft.photo = _photo;
  }

  void _removePhoto() {
    final p = _photo;
    if (p != null) widget.services.api.discardPhoto(p);
    setState(() => _photo = null);
    widget.draft.photo = null;
  }

  @override
  Widget build(BuildContext context) {
    final ok = !widget.required || _text.text.trim().isNotEmpty;
    return WmSheetFrame(
      title: widget.title,
      onBack: widget.onLeave,
      tall: true,
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        WmSheetButton(
          key: const Key('note-submit'),
          label: widget.submitLabel,
          icon: Icons.send,
          onPressed: ok
              ? () {
                  widget.onSubmit((note: _text.text.trim(), photo: _photo));
                }
              : null,
        ),
        const WmSheetNote(savedOnPhoneText),
      ]),
      children: [
        Text(widget.taskTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (widget.explain != null) ...[const SizedBox(height: 4), Text(widget.explain!, style: const TextStyle(color: WmColors.textMuted))],
        const SizedBox(height: 12),
        TextField(
          key: const Key('note-field'),
          controller: _text,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          onChanged: (v) {
            widget.draft.text = v;
            setState(() {});
          },
          decoration: InputDecoration(labelText: widget.label),
        ),
        if (widget.allowPhoto) ...[
          const SizedBox(height: 8),
          _PhotoRow(photo: _photo, onAdd: _addPhoto, onRemove: _removePhoto, failed: _photoFailed),
        ],
      ],
    );
  }
}

/// Report a problem (spec §8): what kind, what is wrong, an optional photo,
/// and — for missing materials or a tool — an optional link to one of the
/// worker's own requests for this project. It never creates a purchase.
class ProblemForm extends StatefulWidget {
  const ProblemForm({
    super.key,
    required this.services,
    required this.task,
    required this.draft,
    required this.onSubmit,
    required this.onLeave,
    this.onMakeRequest,
  });

  final WorkPlanServices services;
  final WpTask task;

  /// What was typed here before, kept by the task sheet while it is open.
  final ReportDraft draft;

  /// The worker tapped the send button: the sheet queues it. Never called on back-out.
  final ValueChanged<ProblemReport> onSubmit;

  /// Back to the task (the sheet's back arrow).
  final VoidCallback onLeave;

  /// Opens Requests; null hides the shortcut.
  final VoidCallback? onMakeRequest;

  @override
  State<ProblemForm> createState() => _ProblemFormState();
}

class _ProblemFormState extends State<ProblemForm> {
  late final _text = TextEditingController(text: widget.draft.text);
  late String _kind = widget.draft.kind;
  late String? _requestId = widget.draft.requestId;
  late String? _photo = widget.draft.photo;
  bool _photoFailed = false;
  late final Future<List<RemoteRequest>> _requests = _loadRequests();

  /// Ids of the requests this form listed: only those may be sent as a link.
  Set<String> _listed = const {};

  /// The worker's open requests for this task's project (0093 accepts only those).
  Future<List<RemoteRequest>> _loadRequests() async {
    final api = widget.services.requests;
    if (api == null) return const [];
    try {
      final RequestsView view = await api.myRequests();
      final found = [
        for (final r in [for (final e in view.entries) ?e.remote])
          if (r.mine && r.projectId == widget.task.projectId && !r.cancelled) r,
      ];
      _listed = {for (final r in found) r.id};
      return found;
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    // The draft and its photo belong to the task sheet, which deletes an unsent photo when it closes.
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final kept = await _takePhoto(context, widget.services, (f) => _photoFailed = f);
    if (!mounted) {
      if (kept != null) await widget.services.api.discardPhoto(kept);
      return;
    }
    setState(() => _photo = kept ?? _photo);
    widget.draft.photo = _photo;
  }

  void _removePhoto() {
    final p = _photo;
    if (p != null) widget.services.api.discardPhoto(p);
    setState(() => _photo = null);
    widget.draft.photo = null;
  }

  @override
  Widget build(BuildContext context) {
    final linkable = _kind == 'materials' || _kind == 'tool';
    final ok = _text.text.trim().isNotEmpty;
    return WmSheetFrame(
      title: 'Report a problem',
      onBack: widget.onLeave,
      tall: true,
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        WmSheetButton(
          key: const Key('problem-submit'),
          label: 'Report the problem',
          icon: Icons.send,
          onPressed: ok
              ? () {
                  widget.onSubmit((kind: _kind, description: _text.text.trim(), requestId: linkable && _listed.contains(_requestId) ? _requestId : null, photo: _photo));
                }
              : null,
        ),
        const WmSheetNote(savedOnPhoneText),
      ]),
      children: [
        Text(widget.task.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'The task waits until the office checks and clears the problem. Reporting it does not order anything.',
          style: TextStyle(color: WmColors.textMuted),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in wpProblemKinds)
            ChoiceChip(
              key: Key('kind-$k'),
              label: Text(problemKindLabel(k)),
              selected: _kind == k,
              onSelected: (_) => setState(() {
                _kind = k;
                widget.draft.kind = k;
                if (!(k == 'materials' || k == 'tool')) {
                  _requestId = null;
                  widget.draft.requestId = null;
                }
              }),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          key: const Key('problem-field'),
          controller: _text,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          onChanged: (v) {
            widget.draft.text = v;
            setState(() {});
          },
          decoration: const InputDecoration(labelText: 'What is the problem?'),
        ),
        const SizedBox(height: 8),
        _PhotoRow(photo: _photo, onAdd: _addPhoto, onRemove: _removePhoto, failed: _photoFailed),
        if (linkable) ...[
          const SizedBox(height: 16),
          const Text('Is there already a request for it?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          FutureBuilder<List<RemoteRequest>>(
            future: _requests,
            builder: (context, snap) {
              final list = snap.data ?? const <RemoteRequest>[];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (list.isEmpty)
                  const Text('No open request of yours for this project.', style: TextStyle(color: WmColors.textMuted))
                else
                  DropdownButtonFormField<String?>(
                    key: const Key('problem-request'),
                    initialValue: list.any((r) => r.id == _requestId) ? _requestId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Link to a request'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No link')),
                      for (final r in list)
                        DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.title} · ${r.lines.length} item${r.lines.length == 1 ? '' : 's'} · ${dayMonth(r.receivedAt)}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      widget.draft.requestId = v;
                      setState(() => _requestId = v);
                    },
                  ),
                if (widget.onMakeRequest != null)
                  TextButton.icon(
                    key: const Key('make-request'),
                    onPressed: () {
                      widget.onLeave();
                      widget.onMakeRequest!();
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Make a request instead (nothing is sent yet)'),
                  ),
              ]);
            },
          ),
        ],
      ],
    );
  }
}
