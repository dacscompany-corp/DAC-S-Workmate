import '../../attendance/domain/attendance_failure.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../domain/request_draft.dart';
import '../domain/request_failure.dart';
import '../domain/request_op.dart';
import '../domain/request_status.dart';

// Screen copy is English; FAILURE copy is bilingual (English, then Tagalog),
// the same rule as Attendance. Where Attendance already has the words, they
// are reused so a worker reads one voice. Everything else here is NEW.

String syncLabel(SyncState s) => switch (s) {
      SyncState.draft => 'Draft',
      SyncState.pending => 'Pending sync',
      SyncState.received => 'Received',
      SyncState.failed => 'Failed',
      SyncState.needsResolution => 'Needs resolution',
      SyncState.cancelled => 'Cancelled',
    };

String lineProgressLabel(LineProgress p) => switch (p) {
      LineProgress.needsResolution => 'Needs resolution',
      LineProgress.officeChecking => 'Office is checking a change',
      LineProgress.cancelled => 'Cancelled',
      LineProgress.waiting => 'Waiting for the office',
      LineProgress.partlyArranged => 'Partly arranged',
      LineProgress.arranged => 'Arranged for purchase',
    };

/// What to do about each draft problem, next to the field.
String draftIssueText(DraftIssueKind k) => switch (k) {
      DraftIssueKind.noDestination => 'Choose the project and the work.',
      DraftIssueKind.noLines => 'Add at least one item.',
      DraftIssueKind.tooManyLines => 'Split this into two requests (100 items at most).',
      DraftIssueKind.noDescription => 'Name the item.',
      DraftIssueKind.noUnit => 'Add the unit (pc, bag, m…).',
      DraftIssueKind.badQuantity => 'Enter a quantity above 0 (up to 3 decimals).',
      DraftIssueKind.urgentNeedsReason => 'Say why it is urgent.',
      DraftIssueKind.urgentNeedsDate => 'Pick the date it is needed by.',
      DraftIssueKind.memberNeedsTeam => 'Choose the team first.',
    };

Bilingual requestFailureCopy(RequestFailure f) => switch (f) {
      RequestFailure.destinationClosed => const Bilingual(
          'That project or job no longer accepts requests. Choose another, then send again.',
          'Hindi na tumatanggap ng request ang project o trabahong iyon. Pumili ng iba, tapos ipadala ulit.'),
      RequestFailure.notInTeam => const Bilingual(
          'You are no longer in that team. Choose another team, or send it as your own request.',
          'Wala ka na sa team na iyon. Pumili ng ibang team, o ipadala bilang sarili mong request.'),
      RequestFailure.notTeamLeader => const Bilingual(
          'Only the team leader can request for another member.',
          'Ang team leader lang ang puwedeng mag-request para sa ibang miyembro.'),
      RequestFailure.badMember => const Bilingual(
          'That member is no longer in the team. Choose someone else.', 'Wala na sa team ang miyembrong iyon. Pumili ng iba.'),
      RequestFailure.badCatalogItem => const Bilingual(
          'An item is no longer in the list. Choose it again or describe it.',
          'Wala na sa listahan ang isang item. Piliin ulit o ilarawan ito.'),
      RequestFailure.incomplete => const Bilingual(
          'Something in this request is incomplete. Check each item, then send again.',
          'May kulang sa request na ito. Suriin ang bawat item, tapos ipadala ulit.'),
      RequestFailure.badQuantity =>
        const Bilingual('Enter a quantity above 0.', 'Maglagay ng dami na higit sa 0.'),
      RequestFailure.urgentNeedsReason => const Bilingual(
          'An urgent item needs a reason and a needed-by date.', 'Kailangan ng dahilan at petsa ang urgent na item.'),
      RequestFailure.lineClosed =>
        const Bilingual('This item is already cancelled.', 'Naka-cancel na ang item na ito.'),
      RequestFailure.notYours => const Bilingual(
          'Only the person who sent this request can change it.', 'Ang nagpadala lang ng request ang puwedeng magbago nito.'),
      RequestFailure.notARequester => failureCopy(AttendanceFailure.notAWorker),
      RequestFailure.appUpdateRequired => failureCopy(AttendanceFailure.appUpdateRequired),
      RequestFailure.sessionExpired => failureCopy(AttendanceFailure.sessionExpired),
      RequestFailure.noConnection => failureCopy(AttendanceFailure.noConnection),
      RequestFailure.photoNotUploaded || RequestFailure.unexpected => failureCopy(AttendanceFailure.unexpected),
    };

/// NEW: a change to a RECEIVED request (a quantity, a cancel, a photo) that a
/// closed project refused. Unlike a draft, there is nothing to choose again:
/// the office sorts it out.
const editDestinationClosedCopy = Bilingual(
  'That project or job is closed for requests, so this change cannot be made from the app. Ask the office.',
  'Sarado na sa request ang project o trabahong iyon, kaya hindi na ito mababago sa app. Magtanong sa opisina.',
);

/// What to say about one refused operation. A refused draft (its submit, or a
/// photo that never had a request to go with) goes back to editing, so the
/// general copy fits; a change to a received request gets its own words.
Bilingual opFailureCopy(RequestOp op) {
  final failure = RequestFailure.fromStored(op.lastError);
  final ofReceived = op.kind != OpKind.submit && op.requestId != null;
  if (failure == RequestFailure.destinationClosed && ofReceived) return editDestinationClosedCopy;
  return requestFailureCopy(failure);
}

/// NEW: an item photo that could not be filed on the phone.
const photoNotKeptCopy = Bilingual('The photo could not be kept. Try again.', 'Hindi naitabi ang litrato. Subukan ulit.');

/// NEW: removing an item from a draft (its photos go with it, for good).
const removeItemTitle = Bilingual('Remove this item?', 'Tanggalin ang item na ito?');
const removeItemBody = Bilingual('Its photos are deleted from this phone.', 'Mabubura rin sa teleponong ito ang mga litrato nito.');
const keepItemLabel = 'Keep · Itira';
const removeItemLabel = 'Remove · Tanggalin';

/// NEW: the lead line over an operation the server refused for good.
const notAcceptedLead = Bilingual('This was not accepted.', 'Hindi ito tinanggap.');

/// NEW: an empty destination list — no project is open, or the account has no
/// company yet (0085 offers nothing to an owner-less account).
const noDestinationsCopy = Bilingual(
  'No project is open for requests right now. If this keeps happening, call the office.',
  'Walang project na bukas para sa request ngayon. Kung palaging ganito, tawagan ang opisina.',
);

const backToDraftsLabel = 'Edit and send again · I-edit at ipadala ulit';
