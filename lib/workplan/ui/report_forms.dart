import 'dart:io';

import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart';
import '../../requests/data/requests_api.dart';
import '../../requests/domain/remote_request.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/workplan_api.dart';
import '../domain/wp_task.dart';
import '../workplan_services.dart';
import 'workplan_copy.dart';

/// What a note form returns: the text, and a kept photo path or null.
typedef NoteReport = ({String note, String? photo});

/// What the problem form returns.
typedef ProblemReport = ({String kind, String description, String? requestId, String? photo});

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
/// photo where 0093 accepts one. Returns null when the worker backed out —
/// and then any photo taken here is deleted.
class NoteFormScreen extends StatefulWidget {
  const NoteFormScreen({
    super.key,
    required this.services,
    required this.title,
    required this.label,
    required this.submitLabel,
    this.required = false,
    this.allowPhoto = false,
    this.explain,
  });

  final WorkPlanServices services;
  final String title;
  final String label;
  final String submitLabel;
  final bool required;
  final bool allowPhoto;
  final String? explain;

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  final _text = TextEditingController();
  String? _photo;
  bool _photoFailed = false;
  bool _done = false;

  @override
  void dispose() {
    _text.dispose();
    // Backed out: the photo is not owed to anyone.
    final p = _photo;
    if (!_done && p != null) widget.services.api.discardPhoto(p);
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final kept = await _takePhoto(context, widget.services, (f) => _photoFailed = f);
    if (!mounted) {
      if (kept != null) await widget.services.api.discardPhoto(kept);
      return;
    }
    setState(() => _photo = kept ?? _photo);
  }

  void _removePhoto() {
    final p = _photo;
    if (p != null) widget.services.api.discardPhoto(p);
    setState(() => _photo = null);
  }

  @override
  Widget build(BuildContext context) {
    final ok = !widget.required || _text.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
          if (widget.explain != null) ...[Text(widget.explain!, style: const TextStyle(color: WmColors.textMuted)), const SizedBox(height: 12)],
          TextField(
            key: const Key('note-field'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.label),
          ),
          if (widget.allowPhoto) ...[
            const SizedBox(height: 8),
            _PhotoRow(photo: _photo, onAdd: _addPhoto, onRemove: _removePhoto, failed: _photoFailed),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('note-submit'),
            onPressed: ok
                ? () {
                    _done = true;
                    Navigator.of(context).pop<NoteReport>((note: _text.text.trim(), photo: _photo));
                  }
                : null,
            child: Text(widget.submitLabel),
          ),
          const SizedBox(height: 8),
          const Text(savedOnPhoneText, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
      ),
    );
  }
}

/// Report a problem (spec §8): what kind, what is wrong, an optional photo,
/// and — for missing materials or a tool — an optional link to one of the
/// worker's own requests for this project. It never creates a purchase.
class ProblemFormScreen extends StatefulWidget {
  const ProblemFormScreen({super.key, required this.services, required this.task, this.onMakeRequest});

  final WorkPlanServices services;
  final WpTask task;

  /// Opens Requests; null hides the shortcut.
  final VoidCallback? onMakeRequest;

  @override
  State<ProblemFormScreen> createState() => _ProblemFormScreenState();
}

class _ProblemFormScreenState extends State<ProblemFormScreen> {
  final _text = TextEditingController();
  String _kind = wpProblemKinds.first;
  String? _requestId;
  String? _photo;
  bool _photoFailed = false;
  bool _done = false;
  late final Future<List<RemoteRequest>> _requests = _loadRequests();

  /// The worker's open requests for this task's project (0093 accepts only those).
  Future<List<RemoteRequest>> _loadRequests() async {
    final api = widget.services.requests;
    if (api == null) return const [];
    try {
      final RequestsView view = await api.myRequests();
      return [
        for (final r in [for (final e in view.entries) ?e.remote])
          if (r.mine && r.projectId == widget.task.projectId && !r.cancelled) r,
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _text.dispose();
    final p = _photo;
    if (!_done && p != null) widget.services.api.discardPhoto(p);
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final kept = await _takePhoto(context, widget.services, (f) => _photoFailed = f);
    if (!mounted) {
      if (kept != null) await widget.services.api.discardPhoto(kept);
      return;
    }
    setState(() => _photo = kept ?? _photo);
  }

  void _removePhoto() {
    final p = _photo;
    if (p != null) widget.services.api.discardPhoto(p);
    setState(() => _photo = null);
  }

  @override
  Widget build(BuildContext context) {
    final linkable = _kind == 'materials' || _kind == 'tool';
    final ok = _text.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
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
                  if (!(k == 'materials' || k == 'tool')) _requestId = null;
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
            onChanged: (_) => setState(() {}),
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
                      initialValue: _requestId,
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
                      onChanged: (v) => setState(() => _requestId = v),
                    ),
                  if (widget.onMakeRequest != null)
                    TextButton.icon(
                      key: const Key('make-request'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onMakeRequest!();
                      },
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Make a request instead (nothing is sent yet)'),
                    ),
                ]);
              },
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('problem-submit'),
            onPressed: ok
                ? () {
                    _done = true;
                    Navigator.of(context).pop<ProblemReport>(
                        (kind: _kind, description: _text.text.trim(), requestId: linkable ? _requestId : null, photo: _photo));
                  }
                : null,
            child: const Text('Report the problem'),
          ),
          const SizedBox(height: 8),
          const Text(savedOnPhoneText, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
      ),
    );
  }
}
