import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wm_build_art.dart';

/// Shown while WorkMate checks the account at start-up ("The house builds as
/// the app loads"). The drawing loops for as long as the check takes: start-up
/// is one step with no measurable progress, so this screen shows no
/// percentage and no step count, only what the app is really doing.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, required this.versionName, this.status = 'Checking your account…'});
  final String versionName;
  final String status;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  /// One build of the house, then a short hold on the finished mark.
  static const _buildSeconds = 3.6, _holdSeconds = 1.4;

  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 5000))..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
        fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2, color: WmArtColors.greyOnDark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: WmArtColors.night,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 30),
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final seconds = _clock.value * (_buildSeconds + _holdSeconds);
                final built = seconds >= _buildSeconds;
                final load = built ? 1.0 : Curves.easeInOut.transform(seconds / _buildSeconds);
                final tick = (_clock.lastElapsedDuration?.inMicroseconds ?? 0) / 50000;
                return Column(children: [
                  DacsLogo(
                      width: 96, progress: load, ink: WmArtColors.paper, frame: WmArtColors.gold, ghost: WmArtColors.ghost),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      // The house, with the worker hammering at its right edge.
                      Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: SizedBox(
                          width: 168,
                          height: 168,
                          child: Stack(clipBehavior: Clip.none, children: [
                            CustomPaint(
                                size: const Size.square(168),
                                painter: HouseMarkPainter(progress: load, ghost: WmArtColors.ghost)),
                            Positioned(
                              left: 136,
                              top: 29,
                              width: 84,
                              height: 120,
                              child: CustomPaint(
                                  painter: WorkerPainter(
                                      tick: tick, pose: built ? WorkerPose.idle : WorkerPose.hammering)),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text('WorkMate',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: -0.5, color: WmArtColors.paper)),
                      const SizedBox(height: 6),
                      const Text("DAC'S BUILDING DESIGN SERVICES",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 3.5, color: WmArtColors.gold)),
                    ]),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(widget.status,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: WmArtColors.paper)),
                  ),
                  const SizedBox(height: 14),
                  TickBar(
                      count: 32,
                      fraction: load,
                      height: 18,
                      gap: 4,
                      on: WmArtColors.mint,
                      off: WmArtColors.tickOff,
                      edge: WmArtColors.gold),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('PLEASE WAIT', style: mono),
                    Text('V ${widget.versionName}', style: mono),
                  ]),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
