import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../update/apk_installer.dart';
import '../update/app_release.dart';
import '../update/app_update_repository.dart';
import '../update/download_rate.dart';
import 'failure_notice.dart';
import 'theme.dart';
import 'wm_build_art.dart';

/// Full-screen and not dismissible: every published release is required and
/// the server refuses older builds anyway. This is the explanation.
///
/// The layout is the "Downloading" screen of the WorkMate Logo Redesign. Every
/// figure on it is real: the percentage, megabytes, speed and time left come
/// from the one APK being downloaded, and the three steps (Download, Check the
/// file, Install) are what the app actually does with it.
class UpdateOverlay extends StatefulWidget {
  const UpdateOverlay({super.key, required this.release, required this.updates, required this.installer});
  final AppRelease release;
  final AppUpdateRepository updates;
  final InstallGateway installer;

  @override
  State<UpdateOverlay> createState() => _UpdateOverlayState();
}

class _UpdateOverlayState extends State<UpdateOverlay> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// How much of the file is on the phone (0..1); kept while paused.
  double _fraction = 0;

  /// A download call is running (it may be winding down after PAUSE).
  bool _downloading = false;
  bool _paused = false;
  DownloadPause? _pause;
  DownloadReady? _ready;
  UpdateFailure? _failure;
  bool _needsPermission = false;
  bool _installing = false;

  // The drawings' clock, in twentieths of a second. [_work] stands still while
  // nothing is downloading, so the crane and the hammer stop with the download.
  late final Ticker _ticker;
  Duration _lastFrame = Duration.zero;
  double _tick = 0, _work = 0;
  double _resumedAt = -99, _celebrateUntil = -1;

  final _rate = DownloadRate();
  final _sinceStart = Stopwatch();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    WidgetsBinding.instance.addObserver(this);
    _showSaved();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A download this screen started stops with it; what arrived is kept.
    _pause?.request();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the "Install unknown apps" switch.
    // Continue only if the switch is now on; otherwise stay here. Settings
    // opens from the ALLOW INSTALLS button alone.
    if (state == AppLifecycleState.resumed && _needsPermission) _install(fromResume: true);
  }

  bool get _celebrating => _ready != null && _tick < _celebrateUntil;

  void _onFrame(Duration elapsed) {
    final step = (elapsed - _lastFrame).inMicroseconds / 50000;
    _lastFrame = elapsed;
    if (!mounted) return;
    setState(() {
      _tick += step;
      if (_downloading && !_paused) _work += step;
    });
    _syncTicker();
  }

  /// The drawings move only while there is something to show: a download
  /// running, the paused worker resting, or the short cheer when it is done.
  void _syncTicker() {
    final wanted = _downloading || _paused || _celebrating;
    if (wanted && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!wanted && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Shows what an unfinished download already saved on this phone, so a
  /// reopened app or a failed try never reads 0% while the part is kept.
  Future<void> _showSaved() async {
    final saved = await _saved();
    if (!mounted || _downloading || _ready != null || saved <= 0) return;
    setState(() => _fraction = saved);
  }

  /// What is saved, in whole percents as the download itself reports them.
  Future<double> _saved() async {
    try {
      return ((await widget.updates.savedFraction(widget.release)) * 100).floor() / 100;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    final pause = DownloadPause();
    setState(() {
      if (_paused) _resumedAt = _tick;
      _failure = null;
      _paused = false;
      _downloading = true;
      _pause = pause;
    });
    _rate.reset();
    _sinceStart
      ..reset()
      ..start();
    _syncTicker();
    DownloadResult result;
    try {
      result = await widget.updates.download(widget.release, (p) {
        _rate.add(_sinceStart.elapsedMilliseconds, (p * widget.release.sizeBytes).round());
        if (mounted) setState(() => _fraction = p);
      }, pause: pause);
    } catch (_) {
      result = DownloadFailed(UpdateFailure.downloadFailed);
    }
    _sinceStart.stop();
    // Read before the screen changes, so a failure never shows 0% for a moment.
    final saved = result is DownloadFailed ? await _saved() : 0.0;
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _pause = null;
      switch (result) {
        case DownloadReady():
          _ready = result;
          _paused = false;
          _fraction = 1;
          _celebrateUntil = _tick + 48;
        case DownloadPaused():
          _paused = true;
        case DownloadFailed(:final reason):
          _failure = reason;
          _paused = false;
          _fraction = saved;
      }
    });
    _syncTicker();
  }

  /// Shows paused at once; the download call ends a moment later, and RESUME
  /// waits for that so two downloads never write the same file.
  void _pauseDownload() {
    if (!_downloading || _paused) return;
    setState(() => _paused = true);
    _pause?.request();
  }

  void _failDownload() {
    if (!mounted) return;
    setState(() {
      _ready = null;
      _needsPermission = false;
      _failure = UpdateFailure.downloadFailed;
      _fraction = 0;
    });
    _syncTicker();
  }

  Future<void> _install({bool fromResume = false}) async {
    final ready = _ready;
    if (ready == null || _installing) return;
    _installing = true;
    try {
      // The cache may have been cleared since the download; installing a
      // missing file would only fail inside the OS. Download again instead.
      if (!ready.file.existsSync()) return _failDownload();
      if (!await widget.installer.canInstall()) {
        if (!mounted) return;
        setState(() => _needsPermission = true);
        if (!fromResume) await widget.installer.openInstallPermission();
        return;
      }
      if (!mounted) return;
      setState(() => _needsPermission = false);
      await widget.installer.install(ready.file);
    } catch (_) {
      _failDownload();
    } finally {
      _installing = false;
    }
  }

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
        // The step rows have set heights for the worker to climb between.
        maxScaleFactor: 1.2,
        child: Builder(builder: _content),
      );

  Widget _content(BuildContext context) {
    final r = widget.release;
    final done = _ready != null;
    final working = (_downloading || _paused) && !done;

    final String label;
    final VoidCallback? action;
    var primary = true;
    if (_paused && !done) {
      label = 'RESUME DOWNLOAD';
      action = _downloading ? null : _download;
    } else if (_downloading) {
      label = 'PAUSE';
      action = _pauseDownload;
      primary = false;
    } else if (_needsPermission) {
      label = 'ALLOW INSTALLS';
      action = _install;
    } else if (done) {
      label = 'INSTALL';
      action = _install;
    } else if (_failure != null) {
      label = 'TRY AGAIN';
      action = _download;
    } else {
      // Part of this update is already on the phone from an earlier try.
      label = _fraction > 0 ? 'CONTINUE DOWNLOAD' : 'UPDATE NOW!';
      action = _download;
    }

    final String note;
    if (_needsPermission) {
      note = "Allow DAC'S WorkMate to install updates. Turn on the switch, then come back here.";
    } else if (done) {
      note = 'Tap Install on the next screen.';
    } else if (working) {
      note = 'Keep the app open. Your attendance records are safe.';
    } else if (_fraction > 0) {
      note = 'Part of the update is saved on this phone. It continues from there.';
    } else {
      note = 'A new version is released, please update to get new features';
    }

    return Material(
      color: WmColors.canvas,
      child: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(r),
                const SizedBox(height: 18),
                _progressCard(done: done, working: working),
                const SizedBox(height: 18),
                _steps(context, done: done, working: working),
                if (r.releaseNotes != null) ...[
                  const SizedBox(height: 18),
                  const Text("WHAT'S NEW", style: monoLabel),
                  const SizedBox(height: 6),
                  Text(r.releaseNotes!, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_needsPermission)
                const Text('One more step',
                    textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              // Above the button, never scrolled out of sight.
              if (_failure != null)
                FailureNotice(english: _failure!.english, tagalog: _failure!.tagalog)
              else
                Text(note,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: WmArtColors.greyOnLight)),
              const SizedBox(height: 12),
              _button(label, action, primary: primary),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _button(String label, VoidCallback? action, {required bool primary}) {
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
    const text = TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: .5);
    return primary
        ? FilledButton(
            onPressed: action,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: shape, textStyle: text),
            child: Text(label))
        : OutlinedButton(
            onPressed: action,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: WmColors.green,
                side: const BorderSide(color: WmColors.green, width: 2),
                shape: shape,
                textStyle: text),
            child: Text(label));
  }

  Widget _header(AppRelease r) => Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: WmColors.green, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: const CustomPaint(size: Size.square(32), painter: HouseMarkPainter()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WorkMate update', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Version ${r.versionName} · ${formatMb(r.sizeBytes)} MB',
                style: const TextStyle(fontSize: 13, color: WmArtColors.greyOnLight)),
          ]),
        ),
        const SizedBox(width: 12),
        const DacsLogo(width: 72, ink: WmArtColors.ink, frame: WmArtColors.green),
      ]);

  Widget _progressCard({required bool done, required bool working}) {
    final paused = _paused && !done;
    final size = widget.release.sizeBytes;
    final String chip;
    if (done) {
      chip = 'READY TO INSTALL';
    } else if (paused) {
      chip = 'PAUSED';
    } else if (_downloading) {
      chip = 'DOWNLOADING';
    } else if (_failure != null) {
      chip = _fraction > 0 ? 'NOT FINISHED' : 'NOT DOWNLOADED';
    } else {
      chip = _fraction > 0 ? 'NOT FINISHED' : 'NEW UPDATE';
    }
    final speed = _downloading && !paused ? _rate.bytesPerSecond : null;
    final left = _downloading && !paused ? _rate.secondsLeft(((1 - _fraction) * size).round()) : null;
    final String eta;
    if (done) {
      eta = 'COMPLETE';
    } else if (paused) {
      eta = 'ON HOLD';
    } else {
      eta = left == null ? '' : formatTimeLeft(left);
    }
    const mono = TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: 12, color: WmArtColors.mint);

    return AnimatedScale(
      // Sinks a little while paused, and bounces back on resume.
      scale: paused ? 0.965 : (_downloading && _tick - _resumedAt < 7 ? 1.03 : 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
            color: paused ? WmArtColors.greenPaused : WmColors.green, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(999)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(chip,
                      style: const TextStyle(
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: Color(0xFF5E4720))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(speed == null ? '' : formatSpeed(speed), style: mono),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${(_fraction * 100).round()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 84,
                          height: .9,
                          letterSpacing: -3,
                          color: WmArtColors.paper,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(width: 6),
                  const Text('%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: WmArtColors.gold)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 104, height: 88, child: CustomPaint(painter: CranePainter(work: _work, done: done))),
          ]),
          const SizedBox(height: 16),
          TickBar(
              count: 40,
              fraction: _fraction,
              height: 22,
              gap: 3,
              // The filled bars blink slowly while paused.
              on: paused && _tick % 20 < 10 ? const Color(0xFFB9CDBF) : WmArtColors.paper,
              off: WmArtColors.vest,
              edge: WmArtColors.gold),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${formatMb(_fraction * size)} / ${formatMb(size)} MB', style: mono)),
            ),
            const SizedBox(width: 8),
            Text(eta, style: mono),
          ]),
        ]),
      ),
    );
  }

  /// The three things the app does with the update, with the worker on the
  /// ladder beside whichever one is under way.
  Widget _steps(BuildContext context, {required bool done, required bool working}) {
    final paused = _paused && !done;
    final size = widget.release.sizeBytes;
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final rowHeight = 72.0 * scale, activeHeight = 94.0 * scale;

    final hammering = working && !paused;
    final steps = [
      _Step(
        name: 'Download',
        detail: !done && _fraction > 0
            ? '${formatMb(_fraction * size)} of ${formatMb(size)} MB'
            : '${formatMb(size)} MB',
        fraction: done ? 1 : _fraction,
        done: done,
        active: working,
        status: done
            ? 'DONE'
            : !working
                ? (_fraction > 0 ? 'SAVED' : 'WAITING')
                : paused
                    ? 'PAUSED'
                    : '${(_fraction * 100).round()}%',
        bigStatus: hammering,
      ),
      _Step(
        name: 'Check the file',
        detail: 'Not damaged',
        fraction: done ? 1 : 0,
        done: done,
        active: false,
        status: done ? 'DONE' : 'WAITING',
      ),
      _Step(
        name: 'Install',
        detail: 'Version ${widget.release.versionName}',
        fraction: 0,
        done: false,
        active: done,
        status: done ? 'READY' : 'WAITING',
      ),
    ];
    final at = done ? 2 : 0;
    var top = 8.0;
    for (var i = 0; i < at; i++) {
      top += (steps[i].active ? activeHeight : rowHeight) + 4;
    }
    final workerTop = top + (steps[at].active ? activeHeight : rowHeight) / 2 - 29;
    final pose = _celebrating
        ? WorkerPose.celebrating
        : paused
            ? WorkerPose.resting
            : hammering
                ? WorkerPose.hammering
                : WorkerPose.idle;

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: WmColors.border), borderRadius: BorderRadius.circular(24)),
      child: Stack(clipBehavior: Clip.none, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(46, 8, 8, 8),
          child: Column(children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              _stepRow(i, steps[i], height: steps[i].active ? activeHeight : rowHeight, hammering: hammering && i == 0),
            ],
          ]),
        ),
        const Positioned(left: 12, top: 10, bottom: 10, width: 28, child: CustomPaint(painter: LadderPainter())),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: const Cubic(.5, 0, .2, 1),
          left: 4,
          top: workerTop,
          width: 56,
          height: 80,
          child: IgnorePointer(
            child: CustomPaint(
                painter: WorkerPainter(
                    tick: pose == WorkerPose.hammering ? _work : _tick, pose: pose, onLight: true, mirrored: true)),
          ),
        ),
      ]),
    );
  }

  Widget _stepRow(int index, _Step s, {required double height, required bool hammering}) {
    final beat = _work % 16;
    final struck = hammering && beat < 2;
    // The marker shakes with each hammer blow.
    final shake = hammering && beat < 4 ? const [4.0, -3.0, 2.0, -1.0][beat.floor()] : 0.0;
    final fg = s.done
        ? WmColors.green
        : s.active
            ? const Color(0xFF5E4720)
            : WmArtColors.greyOnLight;

    final List<Bar> bricks;
    const n = 16;
    if (s.done) {
      bricks = List.filled(n, (height: 6.0, color: WmColors.green));
    } else if (!s.active) {
      bricks = List.filled(n, (height: 6.0, color: const Color(0xFFECEDE8)));
    } else {
      final filled = (s.fraction * n).floor();
      final wave = (_work * 0.55) % (filled + 5);
      bricks = [
        for (var k = 0; k < n; k++)
          if (k < filled)
            hammering && (k - wave).abs() < 1.3
                ? (height: 16.0, color: WmArtColors.gold)
                : (height: 10.0, color: WmArtColors.boot)
          else if (k == filled)
            (height: 10.0, color: hammering && _work % 8 < 4 ? WmArtColors.gold : const Color(0xFFD9C9A6))
          else
            (height: 10.0, color: const Color(0xFFE9E0CC)),
      ];
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
          color: s.active ? WmColors.brownTint : Colors.transparent, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(shake, shake * 0.4, 0)
            ..rotateZ(shake * 2.5 * 3.1415926 / 180)
            ..scaleByDouble(s.active ? 1.08 : 1.0, s.active ? 1.08 : 1.0, 1, 1),
          child: SizedBox(
            width: 42,
            height: 42,
            child: CustomPaint(
              painter: StepNodePainter(
                  fraction: s.fraction, active: s.active, done: s.done, flash: struck, spin: s.active ? _work * 5 : 0),
              child: Center(
                child: Text(s.done ? '✓' : '0${index + 1}',
                    style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontWeight: FontWeight.w700,
                        fontSize: struck ? 17 : 13,
                        color: s.done ? Colors.white : fg)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.15)),
                  Text(s.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.15, color: WmArtColors.greyOnLight)),
                ]),
              ),
              const SizedBox(width: 10),
              Text(s.status,
                  style: s.bigStatus
                      ? TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          height: 1,
                          letterSpacing: -0.5,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()])
                      : TextStyle(
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: fg)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: s.active ? 16 : 6,
              child: CustomPaint(painter: BarsPainter(bars: bricks, gap: 3, radius: 3)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Step {
  const _Step({
    required this.name,
    required this.detail,
    required this.fraction,
    required this.done,
    required this.active,
    required this.status,
    this.bigStatus = false,
  });
  final String name;
  final String detail;
  final double fraction;
  final bool done;
  final bool active;
  final String status;

  /// The live percentage is shown large; every other status is a small label.
  final bool bigStatus;
}
