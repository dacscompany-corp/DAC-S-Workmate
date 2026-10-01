import '../domain/attendance_failure.dart';
import '../domain/work_date.dart';

/// Words in both languages: English first, then Tagalog.
class Bilingual {
  const Bilingual(this.english, this.tagalog);
  final String english;
  final String tagalog;
}

// Screen copy is English; FAILURE copy is bilingual — the moments something
// goes wrong are the ones where a worker most needs their own language. Every
// string below is DACS Attendance's own (res/values/strings.xml), so a worker
// switching apps reads the same words, except the ones marked NEW.

Bilingual failureCopy(AttendanceFailure f) => switch (f) {
      AttendanceFailure.alreadyTimedIn => const Bilingual('You already timed in today.', 'Naka-Time In ka na ngayong araw.'),
      AttendanceFailure.notTimedIn =>
        const Bilingual('You have not timed in today yet.', 'Hindi ka pa naka-Time In ngayong araw.'),
      AttendanceFailure.alreadyComplete =>
        const Bilingual('Today is already finished.', 'Tapos na ang record mo ngayong araw.'),
      AttendanceFailure.timeOutBeforeTimeIn => const Bilingual(
          'Your phone clock looks wrong. Tell the office.', 'Mali ang oras ng telepono mo. Sabihin sa opisina.'),
      AttendanceFailure.deviceClockWrong => const Bilingual(
          'Your phone clock is ahead. Fix the time, then try again.', 'Mauna ang oras ng telepono mo. Ayusin muna ang oras.'),
      AttendanceFailure.shiftTooLong => const Bilingual('This shift is too long to record. Tell the office.',
          'Masyadong mahaba ang shift na ito. Sabihin sa opisina.'),
      AttendanceFailure.projectUnavailable => const Bilingual(
          'That project is no longer available. Pick another.', 'Wala na ang project na iyon. Pumili ng iba.'),
      AttendanceFailure.noOwnerAssigned => const Bilingual('Your account is not linked to a company yet. Call the office.',
          'Hindi pa naka-link ang account mo. Tawagan ang opisina.'),
      AttendanceFailure.accountInactive => const Bilingual(
          'This account is turned off. Call the office.', 'Naka-off ang account na ito. Tawagan ang opisina.'),
      AttendanceFailure.notAWorker => const Bilingual('This is not a worker account.', 'Hindi ito worker account.'),
      AttendanceFailure.outsideRadius => const Bilingual(
          'You are too far from the project to record attendance. Move closer to the site and try again.',
          'Masyado kang malayo sa proyekto para makapagtala. Lumapit sa site at subukan ulit.'),
      AttendanceFailure.mockLocation => const Bilingual(
          'This phone is reporting a fake location. Turn off any mock location app, then try again.',
          'Nagre-report ang telepono na ito ng pekeng lokasyon. I-off ang anumang mock location app, tapos subukan ulit.'),
      AttendanceFailure.locationPermissionDenied => const Bilingual(
          'Attendance needs your location. Turn on Location permission for this app in Settings.',
          'Kailangan ng lokasyon mo para makapagtala. I-on ang Location permission para sa app na ito sa Settings.'),
      AttendanceFailure.locationDisabled => const Bilingual(
          'Turn on Location on your phone to record attendance. Swipe down and tap Location, then try again.',
          'I-on ang Location sa telepono mo para makapagtala. Mag-swipe pababa, i-tap ang Location, tapos subukan ulit.'),
      AttendanceFailure.projectGeofenceUnavailable => const Bilingual(
          'This project has no location set yet. Tell your admin — it cannot be fixed from the app.',
          'Wala pang nakatakdang lokasyon ang proyektong ito. Sabihan ang admin — hindi ito maaayos mula sa app.'),
      AttendanceFailure.appUpdateRequired => const Bilingual(
          'This app is out of date. Ask the office for the new version — your saved record will be sent after you update.',
          'Luma na ang app na ito. Humingi sa opisina ng bagong bersyon — maipapadala ang naka-save mong record pagkatapos mag-update.'),
      AttendanceFailure.sessionExpired => const Bilingual('Please log in again.', 'Mag-log in ulit.'),
      AttendanceFailure.noConnection =>
        const Bilingual('No signal right now. Try again in a moment.', 'Walang signal ngayon. Subukan ulit mamaya.'),
      AttendanceFailure.unexpected => const Bilingual('Something went wrong. Try again.', 'May nasira. Subukan ulit.'),
    };

/// Retrying helps only when the refusal was about the connection or the
/// moment, not the state of the day. A button that cannot work teaches the
/// worker the app is broken.
bool worthRetrying(AttendanceFailure f) => switch (f) {
      AttendanceFailure.noConnection ||
      AttendanceFailure.unexpected ||
      AttendanceFailure.deviceClockWrong ||
      // Walking a few metres into the open is exactly the fix for these two.
      AttendanceFailure.outsideRadius ||
      AttendanceFailure.projectGeofenceUnavailable ||
      // The phone-wide switch is two taps away; the retry then succeeds.
      AttendanceFailure.locationDisabled =>
        true,
      _ => false,
    };

/// The two refusals a worker can fix in Settings — on DIFFERENT screens.
enum SettingsRoute { appPermissions, locationSwitch }

SettingsRoute? settingsRouteFor(AttendanceFailure f) => switch (f) {
      AttendanceFailure.locationPermissionDenied => SettingsRoute.appPermissions,
      AttendanceFailure.locationDisabled => SettingsRoute.locationSwitch,
      _ => null,
    };

/// A refused queue row stores its failure's name; anything else (PHOTO_MISSING,
/// PROJECT_RETIRED, an older build's code) reads as "something went wrong".
AttendanceFailure failureFromStored(String? lastError) =>
    AttendanceFailure.values.asNameMap()[lastError] ?? AttendanceFailure.unexpected;

String _half(TimeDirection d) => d == TimeDirection.timeIn ? 'Time In' : 'Time Out';

/// Home, after the worker declined the camera. DACS Attendance's words for
/// Time In; the Time Out wording is NEW (the old app said "Time In" for both).
Bilingual flowCancelledByCamera(TimeDirection d) => Bilingual(
      '${_half(d)} was not recorded. The camera permission is off, and the photo is the proof of attendance.',
      'Hindi naitala ang ${_half(d)}. Naka-off ang camera permission, at ang litrato ang patunay ng pasok.',
    );

/// NEW: the line over a submission the server refused for good, so no worker
/// believes a refused day was recorded.
Bilingual refusedLead(TimeDirection d, String day) =>
    Bilingual('Your ${_half(d)} on $day was not accepted.', 'Hindi tinanggap ang ${_half(d)} mo noong $day.');

const retryLabel = 'TRY AGAIN';
const openSettingsLabel = 'Open Settings · Buksan ang Settings';
const notNowLabel = 'Not now · Sa ibang pagkakataon';
const dismissLabel = 'Dismiss · Isara';

/// The design's four. Tapping one is the point: this screen is used
/// one-handed, outdoors, often with gloves on.
const descriptionChipOptions = ['Block A', 'Masonry', 'Concrete pouring', 'Site clearing'];
