import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The drawings of the loading and update screens (WorkMate Logo Redesign,
/// "The house builds as the app loads"): the WorkMate house mark, the DAC'S
/// company logo, the worker with the hammer, the crane and the tick bars.
/// All vector, drawn from the mockup's own coordinates; nothing here knows
/// what is being loaded or downloaded.
class WmArtColors {
  static const night = Color(0xFF1D1B20);
  static const ghost = Color(0xFF2E2C31);
  static const tickOff = Color(0xFF3A383D);
  static const paper = Color(0xFFF6F7F4);
  static const mint = Color(0xFFEAF2EC);
  static const gold = Color(0xFFC9A86A);
  static const ink = Color(0xFF1B1B19);
  static const green = Color(0xFF1A5C3A);
  static const greenPaused = Color(0xFF2B4A3A);
  static const vest = Color(0xFF2F7350);
  static const skin = Color(0xFFE0BE95);
  static const boot = Color(0xFF7C5E2A);
  static const greyOnDark = Color(0xFFA9ABA4);
  static const greyOnLight = Color(0xFF6B6B66);
}

Paint _stroke(Color color, double width, {bool round = true}) => Paint()
  ..style = PaintingStyle.stroke
  ..color = color
  ..strokeWidth = width
  ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
  ..strokeJoin = StrokeJoin.round;

Paint _fill(Color color) => Paint()..color = color;

double _span(double p, double from, double length) => ((p - from) / length).clamp(0.0, 1.0);

/// The first [t] (0..1) of [path]'s length, across all its pieces in order.
Path revealPath(Path path, double t) {
  if (t >= 1) return path;
  final out = Path();
  if (t <= 0) return out;
  final pieces = path.computeMetrics().toList();
  var left = pieces.fold<double>(0, (sum, m) => sum + m.length) * t;
  for (final m in pieces) {
    if (left <= 0) break;
    out.addPath(m.extractPath(0, math.min(m.length, left)), Offset.zero);
    left -= m.length;
  }
  return out;
}

void _draw(Canvas canvas, Path path, Color color, double width, double p) {
  // A sliver of a round-capped line is a stray dot: draw nothing until it has begun.
  if (p <= 0.01) return;
  canvas.drawPath(revealPath(path, p), _stroke(color, width));
}

// ---- The WorkMate house mark (100 x 100) ----

final Path _houseRoof = Path()
  ..moveTo(14, 42)
  ..lineTo(14, 36)
  ..lineTo(50, 12)
  ..lineTo(86, 36)
  ..lineTo(86, 42);
final Path _houseBase = Path()
  ..moveTo(14, 60)
  ..lineTo(14, 86)
  ..lineTo(38, 86)
  ..moveTo(62, 86)
  ..lineTo(86, 86)
  ..lineTo(86, 60);
final Path _houseDoor = Path()
  ..moveTo(40, 86)
  ..lineTo(40, 64)
  ..lineTo(60, 64)
  ..lineTo(60, 86);

/// The house mark. [progress] 0..1 builds it: base, then roof, then the gold
/// door; null (or 1) is the finished mark. [ghost] draws the faint outline it
/// builds over.
class HouseMarkPainter extends CustomPainter {
  const HouseMarkPainter({this.progress, this.ink = WmArtColors.mint, this.door = WmArtColors.gold, this.ghost});
  final double? progress;
  final Color ink;
  final Color door;
  final Color? ghost;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    const w = 7.6;
    final p = progress ?? 1;
    if (ghost != null) {
      canvas.drawPath(_houseRoof, _stroke(ghost!, w));
      canvas.drawPath(_houseBase, _stroke(ghost!, w));
    }
    _draw(canvas, _houseBase, ink, w, _span(p, 0, .45));
    _draw(canvas, _houseRoof, ink, w, _span(p, .35, .4));
    _draw(canvas, _houseDoor, door, w * .9, _span(p, .75, .25));
  }

  @override
  bool shouldRepaint(HouseMarkPainter old) =>
      old.progress != progress || old.ink != ink || old.door != door || old.ghost != ghost;
}

// ---- The DAC'S company logo (286 x 164, drawn from y = 8) ----

const double dacsLogoAspect = 164 / 286;

final Path _dacsFloor = Path()
  ..moveTo(80, 153)
  ..lineTo(80, 164)
  ..lineTo(220, 164)
  ..lineTo(220, 153);
final Path _dacsD = Path()
  ..moveTo(80, 72)
  ..lineTo(80, 141)
  ..lineTo(24, 141)
  ..arcToPoint(const Offset(8, 125), radius: const Radius.circular(16))
  ..lineTo(8, 123)
  ..arcToPoint(const Offset(24, 107), radius: const Radius.circular(16))
  ..lineTo(80, 107);
final Path _dacsA = Path()
  ..moveTo(94, 141)
  ..lineTo(118, 72)
  ..lineTo(142, 141);
final Path _dacsCs = Path()
  ..moveTo(196, 107)
  ..lineTo(174, 107)
  ..arcToPoint(const Offset(174, 141), radius: const Radius.circular(17), clockwise: false)
  ..lineTo(258, 141)
  ..arcToPoint(const Offset(258, 107), radius: const Radius.circular(17), clockwise: false)
  ..lineTo(219, 107)
  ..arcToPoint(const Offset(219, 72), radius: const Radius.circular(17.5))
  ..lineTo(268, 72);
final Path _dacsRoof = Path()
  ..moveTo(80, 61)
  ..lineTo(80, 48)
  ..lineTo(150, 16)
  ..lineTo(220, 48)
  ..lineTo(220, 61);

/// The DAC'S logo. [progress] 0..1 draws it stroke by stroke and lowers the
/// roof into place; null is the finished logo.
class DacsLogoPainter extends CustomPainter {
  const DacsLogoPainter({this.progress, required this.ink, required this.frame, this.ghost});
  final double? progress;
  final Color ink;
  final Color frame;
  final Color? ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 286;
    canvas.scale(s, s);
    canvas.translate(0, -8);
    const w = 9.0;
    final p = progress ?? 1;
    if (ghost != null) {
      for (final path in [_dacsFloor, _dacsD, _dacsA, _dacsCs, _dacsRoof]) {
        canvas.drawPath(path, _stroke(ghost!, w));
      }
    }
    _draw(canvas, _dacsFloor, frame, w, _span(p, 0, .2));
    _draw(canvas, _dacsD, ink, w, _span(p, .1, .3));
    _draw(canvas, _dacsA, ink, w, _span(p, .3, .25));
    _draw(canvas, _dacsCs, ink, w, _span(p, .4, .4));
    canvas.save();
    canvas.translate(0, (1 - _span(p, .8, .2)) * -10);
    _draw(canvas, _dacsRoof, frame, w, _span(p, .7, .25));
    canvas.restore();
  }

  @override
  bool shouldRepaint(DacsLogoPainter old) =>
      old.progress != progress || old.ink != ink || old.frame != frame || old.ghost != ghost;
}

class DacsLogo extends StatelessWidget {
  const DacsLogo({super.key, required this.width, this.progress, required this.ink, required this.frame, this.ghost});
  final double width;
  final double? progress;
  final Color ink;
  final Color frame;
  final Color? ghost;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, width * dacsLogoAspect),
        painter: DacsLogoPainter(progress: progress, ink: ink, frame: frame, ghost: ghost),
      );
}

// ---- The worker (70 x 100) ----

enum WorkerPose {
  /// Standing, hammer lowered.
  idle,

  /// Swinging the hammer.
  hammering,

  /// Paused: hammer on the shoulder, a pause sign overhead.
  resting,

  /// Done: arms up, hopping.
  celebrating,
}

/// [tick] counts twentieths of a second, as the mockup's clock did; a hammer
/// swing takes sixteen of them.
class WorkerPainter extends CustomPainter {
  const WorkerPainter({required this.tick, required this.pose, this.onLight = false, this.mirrored = false});
  final double tick;
  final WorkerPose pose;

  /// On a light background the shirt is dark; on a dark one it is light.
  final bool onLight;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.scale(size.width / 70, size.height / 100);

    final active = pose == WorkerPose.hammering;
    final celebrate = pose == WorkerPose.celebrating;
    final rest = pose == WorkerPose.resting;
    final ph = active ? (tick % 16) / 16 : 0.0;
    final double angle = celebrate
        ? 92 + 20 * math.sin(tick * 0.5)
        : rest
            ? -96 + 4 * math.sin(tick * 0.15)
            : active
                ? -45 + 80 * (ph < 0.72 ? ph / 0.72 : 1 - (ph - 0.72) / 0.28)
                : 15;
    final double jump = celebrate
        ? -7 * math.sin(tick * 0.32).abs()
        : rest
            ? 1.5 * math.sin(tick * 0.15)
            : 0;
    final hit = active && ph < 0.16;
    final double lean = active && ph < 0.2 ? -4 : 0;

    final shirt = onLight ? WmArtColors.ink : WmArtColors.paper;
    final pants = onLight ? WmArtColors.greyOnLight : WmArtColors.greyOnDark;
    const gold = WmArtColors.gold, skin = WmArtColors.skin, boot = WmArtColors.boot;

    canvas.translate(0, jump);

    if (celebrate && tick % 8 < 5) {
      canvas.drawPath(
          Path()
            ..moveTo(16, 8)
            ..lineTo(11, 1)
            ..moveTo(38, 4)
            ..lineTo(38, -5)
            ..moveTo(60, 8)
            ..lineTo(65, 1)
            ..moveTo(4, 22)
            ..lineTo(-4, 22)
            ..moveTo(72, 22)
            ..lineTo(80, 22),
          _stroke(gold, 3));
    }
    if (rest) {
      // The pause sign, gently pulsing.
      canvas.save();
      final pulse = tick % 24 < 12 ? 1.0 : 0.9;
      canvas.translate(38, 0);
      canvas.scale(pulse, pulse);
      canvas.translate(-38, 0);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(26, -12, 24, 20), const Radius.circular(6)), _fill(gold));
      for (final x in const [32.5, 39.5]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, -7, 4, 10), const Radius.circular(1)), _fill(WmArtColors.ink));
      }
      canvas.restore();
    }

    // Legs and boots.
    canvas.drawPath(
        Path()
          ..moveTo(37, 64)
          ..lineTo(33, 89)
          ..moveTo(43, 64)
          ..lineTo(49, 89),
        _stroke(pants, 9));
    canvas.drawPath(
        Path()
          ..moveTo(35, 94)
          ..lineTo(27, 94)
          ..moveTo(51, 94)
          ..lineTo(43, 94),
        _stroke(boot, 6.5));

    // Body, leaning into the swing from the hips.
    canvas.save();
    _rotateAbout(canvas, lean, 40, 64);
    canvas.drawLine(const Offset(45, 41), celebrate ? const Offset(54, 27) : const Offset(51, 56), _stroke(shirt, 6.5));
    canvas.drawCircle(celebrate ? const Offset(54.5, 25) : const Offset(51.5, 58), 3.6, _fill(skin));
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(31, 34, 17, 33), const Radius.circular(6.5)), _fill(WmArtColors.vest));
    final stripe = _stroke(gold, 2.6, round: false);
    canvas.drawLine(const Offset(31.5, 49), const Offset(47.5, 49), stripe);
    canvas.drawLine(const Offset(31.5, 56), const Offset(47.5, 56), stripe);
    canvas.drawRect(const Rect.fromLTWH(35.5, 29, 6, 7), _fill(skin));
    canvas.drawCircle(const Offset(38, 24.5), 7.8, _fill(skin));
    // Hard hat: a dome and its brim.
    canvas.drawPath(
        Path()
          ..moveTo(28.5, 22.5)
          ..arcToPoint(const Offset(48.1, 22.5), radius: const Radius.circular(9.8))
          ..close(),
        _fill(gold));
    canvas.drawLine(const Offset(24.5, 22.5), const Offset(49, 22.5), _stroke(gold, 3.6));

    // The hammer arm, swinging from the shoulder.
    canvas.save();
    _rotateAbout(canvas, angle, 36, 41);
    canvas.drawLine(const Offset(22, 40), const Offset(21, 20), _stroke(boot, 3.8));
    canvas.drawLine(const Offset(14.5, 20), const Offset(28, 20), _stroke(shirt, 7.5));
    canvas.drawLine(const Offset(36, 41), const Offset(24, 39.5), _stroke(shirt, 6.5));
    canvas.drawCircle(const Offset(22.5, 39.5), 3.8, _fill(skin));
    canvas.restore();
    canvas.restore();

    if (hit) {
      canvas.drawPath(
          Path()
            ..moveTo(5, 30)
            ..lineTo(0, 24)
            ..moveTo(3, 38)
            ..lineTo(-6, 38)
            ..moveTo(6, 46)
            ..lineTo(1, 52),
          _stroke(gold, 3));
    }
  }

  static void _rotateAbout(Canvas canvas, double degrees, double x, double y) {
    if (degrees == 0) return;
    canvas.translate(x, y);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-x, -y);
  }

  @override
  bool shouldRepaint(WorkerPainter old) =>
      old.tick != tick || old.pose != pose || old.onLight != onLight || old.mirrored != mirrored;
}

// ---- The crane (100 x 84) ----

final Path _craneFrame = Path()
  ..moveTo(24, 80)
  ..lineTo(24, 8)
  ..moveTo(12, 80)
  ..lineTo(36, 80)
  ..moveTo(6, 18)
  ..lineTo(92, 18)
  ..moveTo(24, 8)
  ..lineTo(8, 18)
  ..moveTo(24, 8)
  ..lineTo(58, 18)
  ..moveTo(24, 30)
  ..lineTo(32, 18);

/// The crane on the green card. [work] is the working clock (it stands still
/// while paused); [done] sets the load down.
class CranePainter extends CustomPainter {
  const CranePainter({required this.work, required this.done});
  final double work;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 100, size.height / 84);
    canvas.translate((size.width - 100 * s) / 2, size.height - 84 * s);
    canvas.scale(s, s);
    final drop = done ? 46.0 : 8 + 34 * (0.5 - 0.5 * math.cos(work * 0.12));
    final tx = done ? 66.0 : 66 + 8 * math.sin(work * 0.06);
    final y = 18 + drop;
    canvas.drawPath(_craneFrame, _stroke(WmArtColors.mint, 4));
    canvas.drawLine(Offset(tx, 18), Offset(tx, y), _stroke(WmArtColors.mint, 2.5));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx - 8, y, 16, 12), const Radius.circular(2)), _fill(WmArtColors.gold));
    canvas.drawLine(const Offset(52, 80), const Offset(96, 80), _stroke(WmArtColors.vest, 4));
  }

  @override
  bool shouldRepaint(CranePainter old) => old.work != work || old.done != done;
}

// ---- Tick and brick bars ----

/// A ruler of [count] bars filled up to [fraction]; every fourth bar is full
/// height. The bar the fill has just reached is [edge].
class TickBar extends StatelessWidget {
  const TickBar({
    super.key,
    required this.count,
    required this.fraction,
    required this.height,
    required this.gap,
    required this.on,
    required this.off,
    required this.edge,
  });
  final int count;
  final double fraction;
  final double height;
  final double gap;
  final Color on;
  final Color off;
  final Color edge;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: BarsPainter(
            gap: gap,
            radius: 2,
            bars: [
              for (var i = 0; i < count; i++)
                (
                  height: i % 4 == 0 ? height : (height * 0.6).roundToDouble(),
                  color: (i + 0.5) / count <= fraction
                      ? on
                      : i / count <= fraction
                          ? edge
                          : off,
                ),
            ],
          ),
        ),
      );
}

typedef Bar = ({double height, Color color});

/// Equal-width bars standing on the bottom edge.
class BarsPainter extends CustomPainter {
  const BarsPainter({required this.bars, required this.gap, required this.radius});
  final List<Bar> bars;
  final double gap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final w = (size.width - gap * (bars.length - 1)) / bars.length;
    if (w <= 0) return;
    for (var i = 0; i < bars.length; i++) {
      final h = math.min(bars[i].height, size.height);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(i * (w + gap), size.height - h, w, h), Radius.circular(radius)),
          _fill(bars[i].color));
    }
  }

  @override
  bool shouldRepaint(BarsPainter old) {
    if (old.gap != gap || old.radius != radius || old.bars.length != bars.length) return true;
    for (var i = 0; i < bars.length; i++) {
      if (old.bars[i] != bars[i]) return true;
    }
    return false;
  }
}

/// The ladder beside the steps: two rails and a rung every 17.
class LadderPainter extends CustomPainter {
  const LadderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _fill(WmArtColors.boot);
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - 3, 0, 3, size.height), paint);
    for (var y = 14.0; y + 3 <= size.height; y += 17) {
      canvas.drawRect(Rect.fromLTWH(3, y, size.width - 6, 3), paint);
    }
  }

  @override
  bool shouldRepaint(LadderPainter old) => false;
}

/// A step's round marker: grey while waiting, a gold ring filling with the
/// step's progress (and a turning dashed ring inside) while it runs, solid
/// green when done.
class StepNodePainter extends CustomPainter {
  const StepNodePainter({required this.fraction, required this.active, required this.done, required this.flash, required this.spin});
  final double fraction;
  final bool active;
  final bool done;

  /// The hammer just landed: the centre flashes.
  final bool flash;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
        c, r, _fill(done ? WmArtColors.green : active ? const Color(0xFFE3D6BC) : const Color(0xFFE6E7E1)));
    if (active && !done && fraction > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), true,
          _fill(WmArtColors.boot));
    }
    final inner = r * 32 / 42;
    canvas.drawCircle(c, inner, _fill(done ? WmArtColors.green : flash ? const Color(0xFFE9D9B4) : Colors.white));
    if (active && !done) {
      final dash = _stroke(WmArtColors.boot, 2, round: false);
      final ring = Rect.fromCircle(center: c, radius: inner - 3);
      const dashes = 12;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(ring, spin * math.pi / 180 + i * 2 * math.pi / dashes, math.pi / dashes, false, dash);
      }
    }
  }

  @override
  bool shouldRepaint(StepNodePainter old) =>
      old.fraction != fraction || old.active != active || old.done != done || old.flash != flash || old.spin != spin;
}
