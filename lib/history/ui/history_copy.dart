import '../../attendance/domain/attendance_failure.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../domain/history_failure.dart';

// Screen copy is English; FAILURE copy is bilingual (English, then Tagalog),
// the same rule as Attendance and Requests. Shared failures reuse their words.

const findPreviousTitle = 'Find previous item';
const requestAgainLabel = 'REQUEST THIS ITEM AGAIN';
const requestAgainShort = 'Request again';
const notListedTitle = 'No longer listed — ask the office';
const noMatchesText = 'No matches. Try other words, or clear the filters.';
const noPhotoText = 'No photo yet';

/// "Can't connect — showing saved results from 9 Oct, 10:42"
String savedBanner(String when) => 'Can\'t connect — showing saved results from $when. They may be out of date.';

Bilingual historyFailureCopy(HistoryFailure f) => switch (f) {
      HistoryFailure.notAvailable => const Bilingual(
          'History isn\'t available for this item. The office may have switched it off for this project.',
          'Walang makitang history para sa item na ito. Maaaring pinatay ito ng opisina para sa project na ito.'),
      HistoryFailure.savedTooOld => const Bilingual(
          'This phone\'s copy is more than 14 days old. Connect to the internet to refresh it.',
          'Mahigit 14 na araw na ang kopya sa teleponong ito. Kumonekta sa internet para ma-refresh.'),
      HistoryFailure.noConnection => failureCopy(AttendanceFailure.noConnection),
      HistoryFailure.sessionExpired => failureCopy(AttendanceFailure.sessionExpired),
      HistoryFailure.notARequester => const Bilingual(
          'You don\'t have access to this. Ask the office.', 'Wala kang access dito. Magtanong sa opisina.'),
      HistoryFailure.appUpdateRequired => failureCopy(AttendanceFailure.appUpdateRequired),
      HistoryFailure.unexpected => failureCopy(AttendanceFailure.unexpected),
    };
