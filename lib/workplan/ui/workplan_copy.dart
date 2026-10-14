import '../../attendance/domain/attendance_failure.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../domain/wp_failure.dart';
import '../domain/wp_op.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';

// Screen copy is English; FAILURE copy is bilingual (English, then Tagalog),
// the same rule as Attendance and Requests. Where those already have the
// words, they are reused so a worker reads one voice.

String statusLabel(WpStatus s, {bool sentBack = false}) => switch (s) {
      WpStatus.notStarted => 'Not started',
      WpStatus.inProgress => sentBack ? 'Sent back' : 'In progress',
      WpStatus.reportedDone => 'Reported done',
      WpStatus.leaderChecked => 'Checked by leader',
      WpStatus.completed => 'Completed',
    };

String roleLabel(WpRole r) => switch (r) {
      WpRole.responsible => 'Responsible',
      WpRole.helper => 'Helper',
      WpRole.leader => 'Team leader',
    };

String groupLabel(WpGroup g) => switch (g) {
      WpGroup.today => 'Today',
      WpGroup.upcoming => 'Upcoming',
      WpGroup.waiting => 'Waiting',
      WpGroup.done => 'Done (last 14 days)',
    };

String problemKindLabel(String kind) => switch (kind) {
      'materials' => 'Materials',
      'tool' => 'Tool',
      'preparation' => 'Preparation',
      _ => 'Other',
    };

String proposalStateLabel(WpProposalState s) => switch (s) {
      WpProposalState.sent => 'Sent',
      WpProposalState.published => 'Published',
      WpProposalState.declined => 'Declined',
      WpProposalState.cancelled => 'Cancelled',
    };

/// What a queued or refused operation was, for its line on the task.
String opLabel(WpOp op) => switch (op.kind) {
      WpOpKind.acknowledge => "I've read this",
      WpOpKind.start => 'Start work',
      WpOpKind.progress => 'Progress report',
      WpOpKind.blocker => 'Problem report',
      WpOpKind.done => 'Report done',
      WpOpKind.check => 'Check this work',
      WpOpKind.propose => 'Proposal: ${(op.body['title'] as String?) ?? ''}',
      WpOpKind.photo => 'A photo',
    };

const lockBlockedText = 'Waiting: the problems and earlier tasks below must be cleared by the office first.';
const lockMustReadText = 'Read the task first: tap "I\'ve read this".';

String lockText(WpLock l) => switch (l) {
      WpLock.blocked => lockBlockedText,
      WpLock.mustRead => lockMustReadText,
    };

Bilingual wpFailureCopy(WpFailure f) => switch (f) {
      WpFailure.notAssigned => const Bilingual(
          'You are no longer on this task, or the office took it back. Ask the office.',
          'Wala ka na sa task na ito, o binawi ito ng opisina. Magtanong sa opisina.'),
      WpFailure.notResponsible => const Bilingual(
          'Only the person responsible for this task can do that.', 'Ang responsable lang sa task na ito ang puwedeng gumawa niyan.'),
      WpFailure.badState => const Bilingual(
          'The task changed meanwhile, so this no longer applies. Pull down to see it now.',
          'Nagbago ang task habang naghihintay, kaya hindi na ito puwede. Hilahin pababa para makita ang bago.'),
      WpFailure.taskBlocked => const Bilingual(
          'This task is still waiting: a problem or an earlier task must be cleared by the office first.',
          'Naghihintay pa ang task na ito: kailangan munang ayusin ng opisina ang problema o ang naunang task.'),
      WpFailure.notAcknowledged => const Bilingual(
          'The office changed this task. Read the new version, tap "I\'ve read this", then try again.',
          'Binago ng opisina ang task na ito. Basahin ang bago, pindutin ang "I\'ve read this", tapos subukan ulit.'),
      WpFailure.noteRequired => const Bilingual('Write a short note first.', 'Sumulat muna ng maikling paliwanag.'),
      WpFailure.badRequest => const Bilingual(
          'That request is not for this project. Report the problem again without it.',
          'Hindi para sa project na ito ang request na iyon. I-report ulit ang problema nang wala ito.'),
      WpFailure.ownWork => const Bilingual(
          'You cannot check work you are part of. The office checks it.',
          'Hindi mo puwedeng i-check ang trabahong kasama ka. Ang opisina ang magche-check.'),
      WpFailure.notLeader => const Bilingual(
          'Only the current leader of this team can do that.', 'Ang kasalukuyang leader lang ng team ang puwedeng gumawa niyan.'),
      WpFailure.badDestination => const Bilingual(
          'That project or job is closed. Choose another, then send again.',
          'Sarado na ang project o trabahong iyon. Pumili ng iba, tapos ipadala ulit.'),
      WpFailure.titleRequired => const Bilingual('Give the task a title.', 'Lagyan ng pamagat ang task.'),
      WpFailure.notARequester => failureCopy(AttendanceFailure.notAWorker),
      WpFailure.appUpdateRequired => failureCopy(AttendanceFailure.appUpdateRequired),
      WpFailure.sessionExpired => failureCopy(AttendanceFailure.sessionExpired),
      WpFailure.noConnection => failureCopy(AttendanceFailure.noConnection),
      WpFailure.photoNotUploaded || WpFailure.unexpected => failureCopy(AttendanceFailure.unexpected),
    };

/// A photo the phone could not send (its file is gone, or its report was refused).
const photoNotSentCopy = Bilingual('A photo could not be sent.', 'Hindi naipadala ang isang litrato.');

Bilingual opFailureCopy(WpOp op) {
  if (op.kind == WpOpKind.photo && (op.lastError == 'PHOTO_MISSING' || op.lastError == 'PHOTO_ORPHAN')) return photoNotSentCopy;
  return wpFailureCopy(WpFailure.fromStored(op.lastError));
}

/// The lead line over an operation the server refused for good.
const notAcceptedLead = Bilingual('This was not accepted.', 'Hindi ito tinanggap.');

const photoNotKeptCopy = Bilingual('The photo could not be kept. Try again.', 'Hindi naitabi ang litrato. Subukan ulit.');

/// Shown under the form while the phone has no signal.
const savedOnPhoneText = 'Saved on this phone. It is sent as soon as there is signal.';
