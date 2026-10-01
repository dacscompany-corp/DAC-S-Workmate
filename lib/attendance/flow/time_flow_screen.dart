import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/attendance_record.dart';
import '../domain/description_chips.dart';
import '../domain/total_hours.dart';
import '../domain/work_date.dart';
import '../ui/attendance_copy.dart';
import '../ui/attendance_failure_notice.dart';
import '../ui/formats.dart';
import 'time_flow_controller.dart';

/// Why a flow ended without a record, worth telling Home about.
enum FlowExit { cameraPermission }

/// What the camera step is given. The real one is CameraStep; tests use a fake.
class CameraStepArgs {
  const CameraStepArgs({required this.projectName, required this.onTaken, required this.onGiveUp});

  /// Shown in the preview caption, exactly as it will be burned in.
  final String projectName;

  /// The capture, its shutter time, and whether it came from the front camera.
  final void Function(String path, DateTime capturedAt, bool mirrored) onTaken;

  /// The worker declined the camera: leave the flow (Home says why).
  final VoidCallback onGiveUp;
}

typedef CameraStepBuilder = Widget Function(BuildContext context, CameraStepArgs args);

/// Time In is green, Time Out brown: the same screens in two colours.
Color accentFor(TimeDirection d) => d == TimeDirection.timeIn ? WmColors.green : WmColors.brown;

Color _accentTint(TimeDirection d) => d == TimeDirection.timeIn ? WmColors.greenTint : WmColors.brownTint;

/// The headings are QUESTIONS, as the design writes them.
const _titles = {
  FlowStep.pickProject: ('Which project today?', 'Pick the site you are working on.'),
  FlowStep.takePhoto: ('Take your photo', 'Face the camera'),
  FlowStep.checkPhoto: ('Is this photo clear?', 'Check it before you submit'),
  FlowStep.describe: ('What are you working on?', 'Optional — you can skip this'),
};

/// The four-step Time In / Time Out flow and its confirmation. Modal: no tabs
/// while recording — a worker halfway through has one way forward and one back.
class TimeFlowScreen extends StatefulWidget {
  const TimeFlowScreen({
    super.key,
    required this.controller,
    required this.cameraStep,
    required this.onFinished,
    required this.onCancelled,
    required this.openSettings,
  });

  final TimeFlowController controller;
  final CameraStepBuilder cameraStep;
  final VoidCallback onFinished;
  final void Function(FlowExit? reason) onCancelled;
  final void Function(SettingsRoute route) openSettings;

  @override
  State<TimeFlowScreen> createState() => _TimeFlowScreenState();
}

class _TimeFlowScreenState extends State<TimeFlowScreen> {
  late final TextEditingController _note = TextEditingController(text: widget.controller.description);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _back() {
    final c = widget.controller;
    if (c.step == FlowStep.confirmed) {
      widget.onFinished();
    } else if (!c.back()) {
      widget.onCancelled(null);
    }
  }

  void _toggleChip(String chip) {
    widget.controller.toggleChip(chip);
    _note.text = widget.controller.description;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            if (c.step == FlowStep.confirmed) return _Confirmation(controller: c, onDone: widget.onFinished);
            final dark = c.step == FlowStep.takePhoto;
            final (title, subtitle) = _titles[c.step]!;
            return Scaffold(
              backgroundColor: dark ? WmColors.previewBackdrop : Colors.white,
              body: SafeArea(
                child: Column(children: [
                  FlowHeader(
                    direction: c.direction,
                    step: c.stepNumber,
                    title: title,
                    subtitle: subtitle,
                    dark: dark,
                    onBack: _back,
                  ),
                  Expanded(
                    child: switch (c.step) {
                      FlowStep.pickProject => _ProjectStep(controller: c),
                      FlowStep.takePhoto => widget.cameraStep(
                          context,
                          CameraStepArgs(
                            projectName: c.selectedProject?.name ?? '',
                            onTaken: (path, at, mirrored) => c.photoTaken(path, at, mirrored: mirrored),
                            onGiveUp: () => widget.onCancelled(FlowExit.cameraPermission),
                          ),
                        ),
                      FlowStep.checkPhoto => _CheckStep(controller: c),
                      FlowStep.describe =>
                        _DescribeStep(controller: c, note: _note, onToggleChip: _toggleChip, openSettings: widget.openSettings),
                      FlowStep.confirmed => const SizedBox.shrink(),
                    },
                  ),
                ]),
              ),
            );
          },
        ),
      );
}

/// Back, the TIME IN / TIME OUT pill, "Step N of 4", the bar, and the question.
class FlowHeader extends StatelessWidget {
  const FlowHeader({
    super.key,
    required this.direction,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.dark = false,
  });

  final TimeDirection direction;
  final int step;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(direction);
    final fg = dark ? Colors.white : WmColors.text;
    final muted = dark ? Colors.white60 : WmColors.textMuted;
    final timeIn = direction == TimeDirection.timeIn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(key: const Key('flow-back'), tooltip: 'Back', onPressed: onBack, icon: Icon(Icons.arrow_back, color: fg)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: dark ? Colors.white12 : _accentTint(direction),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(timeIn ? Icons.south_west : Icons.north_east, size: 14, color: dark ? Colors.white : accent),
              const SizedBox(width: 5),
              Text(timeIn ? 'TIME IN' : 'TIME OUT', style: monoLabel.copyWith(color: dark ? Colors.white : accent)),
            ]),
          ),
          const Spacer(),
          Text('Step $step of 4', style: monoLabel.copyWith(color: muted, letterSpacing: 0.4)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: step / 4,
                minHeight: 5,
                color: dark ? Colors.white : accent,
                backgroundColor: dark ? Colors.white24 : WmColors.hairline,
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 14, color: muted)),
          ]),
        ),
      ]),
    );
  }
}

class _ProjectStep extends StatelessWidget {
  const _ProjectStep({required this.controller});
  final TimeFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final failure = c.failure;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
          if (c.loadingProjects)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
          else if (failure != null)
            AttendanceFailureNotice(failure: failure, onRetry: c.loadProjects)
          else if (c.projects.isEmpty)
            const Text('No projects are listed. Call the office.',
                style: TextStyle(fontSize: 15, color: WmColors.textSecondary))
          else
            for (final p in c.projects) ...[
              _ProjectTile(
                project: p,
                selected: p.key == c.selectedKey,
                direction: c.direction,
                onTap: () => c.selectProject(p.key),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 6),
          const Text('If your project is missing, tell the admin.',
              style: TextStyle(fontSize: 13, color: WmColors.textMeta)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accentFor(c.direction)),
          onPressed: c.selectedProject == null ? null : c.confirmProject,
          child: const Text('NEXT · TAKE PHOTO'),
        ),
      ),
    ]);
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.selected, required this.direction, required this.onTap});
  final AttendanceProject project;
  final bool selected;
  final TimeDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(direction);
    return Material(
      color: selected ? _accentTint(direction) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? accent : WmColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: selected ? accent : WmColors.canvas, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.apartment, color: selected ? Colors.white : WmColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(project.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: WmColors.text)),
                const Text('Active', style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? accent : WmColors.textFaint),
          ]),
        ),
      ),
    );
  }
}

/// A capture as the worker saw it in the preview: front-camera shots mirrored.
class CapturedPhotoView extends StatelessWidget {
  const CapturedPhotoView({super.key, required this.photo});
  final CapturedPhoto photo;

  @override
  Widget build(BuildContext context) => Transform.flip(
        flipX: photo.mirrored,
        child: Image.file(
          File(photo.path),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: WmColors.inert),
        ),
      );
}

class _CheckStep extends StatelessWidget {
  const _CheckStep({required this.controller});
  final TimeFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox.expand(child: CapturedPhotoView(photo: c.photo!)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accentFor(c.direction)),
            onPressed: c.acceptPhoto,
            child: const Text('YES, USE THIS PHOTO'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: c.retake,
            child: const Text('Retake photo', style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.textSecondary)),
          ),
        ]),
      ),
    ]);
  }
}

class _DescribeStep extends StatelessWidget {
  const _DescribeStep({required this.controller, required this.note, required this.onToggleChip, required this.openSettings});
  final TimeFlowController controller;
  final TextEditingController note;
  final void Function(String chip) onToggleChip;
  final void Function(SettingsRoute route) openSettings;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final failure = c.failure;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 56, height: 56, child: CapturedPhotoView(photo: c.photo!)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Photo taken', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(c.selectedProject?.name ?? '', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          const Text('TAP ONE', style: monoLabel),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final chip in descriptionChipOptions)
              _NoteChip(
                label: chip,
                selected: isChipSelected(c.description, chip),
                direction: c.direction,
                onTap: () => onToggleChip(chip),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Or type your own', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('note'),
            controller: note,
            onChanged: c.setDescription,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Gate 2, delivery came'),
          ),
          if (failure != null) ...[
            const SizedBox(height: 16),
            AttendanceFailureNotice(failure: failure, onRetry: c.submit, onOpenSettings: openSettings),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton(
          key: const Key('submit'),
          style: FilledButton.styleFrom(backgroundColor: accentFor(c.direction)),
          onPressed: c.submitting ? null : c.submit,
          child: c.submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(c.direction == TimeDirection.timeIn ? 'SUBMIT TIME IN' : 'SUBMIT TIME OUT'),
        ),
      ),
    ]);
  }
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.label, required this.selected, required this.direction, required this.onTap});
  final String label;
  final bool selected;
  final TimeDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(direction);
    return Material(
      color: selected ? _accentTint(direction) : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? accent : WmColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: selected ? accent : WmColors.textSecondary)),
        ),
      ),
    );
  }
}

/// The confirmation. A worker walks away from this screen and cannot check it
/// again until the record reaches the server, so it repeats every fact just
/// filed under their name.
class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.controller, required this.onDone});
  final TimeFlowController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final accent = accentFor(c.direction);
    final timeIn = c.direction == TimeDirection.timeIn;
    final photo = c.photo!;
    final saved = c.saved!;
    final note = c.description.trim();
    final rows = <(String, String, bool)>[
      (timeIn ? 'Time in' : 'Time out', clockTime(photo.capturedAt), true),
      ('Date', shortDate(photo.capturedAt), false),
      ('Project', c.selectedProject?.name ?? '—', false),
      ('Note', note.isEmpty ? '—' : note, false),
      if (!timeIn) ('Total hours', formatMinutes(saved.totalMinutes), true),
    ];
    return Scaffold(
      backgroundColor: accent,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 32, 20, 20), children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.check, size: 40, color: accent),
                ),
              ),
              const SizedBox(height: 18),
              Text(timeIn ? 'All done!' : 'Day complete!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text(timeIn ? 'Your Time In has been recorded' : 'Your Time Out has been recorded',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Colors.white70)),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  for (final (label, value, mono) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 13.5, color: WmColors.textMuted))),
                        Expanded(
                          child: Text(
                            value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: WmColors.text,
                              fontFamily: mono ? 'IBM Plex Mono' : null,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  if (saved.pending) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: WmColors.greenTint, borderRadius: BorderRadius.circular(999)),
                      child: const Text('Saved on your phone',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: WmColors.green)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 18),
              Text(
                timeIn ? 'When you head home, time out and pick your project again.' : 'Thank you. See you tomorrow.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: Colors.white),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: accent),
              onPressed: onDone,
              child: const Text('BACK TO HOME'),
            ),
          ),
        ]),
      ),
    );
  }
}
