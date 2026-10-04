/// The splash: the mark, animated, while the app gets ready at launch. A port of desktop Nunya's
/// `views/splash.ts` and its styles.
///
/// It covers the app until the phone has been placed on the map (or the map has no "you" to draw
/// routes from), for at least [_minTime] so the mark is finished before it goes, and at most
/// [_maxTime], since a slow geo lookup must not hold the app hostage. On a network where the
/// lookup will not succeed, a way past it is offered after [_skipAfter].
///
/// The animation is the mark being made: the arch draws itself, the road runs out of the tunnel,
/// rings recede into it, and a light passes over the whole; leaving, it flies into the tunnel as
/// it fades. Under reduced motion it is the finished mark, still. The platform launch screens are
/// painted in the same ground, so the hand-off from the OS is seamless.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _minTime = Duration(milliseconds: 1700);
const _maxTime = Duration(seconds: 20);
const _skipAfter = Duration(seconds: 6);
const _leaveTime = Duration(milliseconds: 450);

/// The mark's silhouette on a 24-unit grid, from desktop Nunya's `views/icons.ts` (traced there
/// by `scripts/trace-mark.py` from design/nonya.png). Copied, not redrawn, so it cannot drift.
const _arch =
    'M11.66 1.00L13.17 1.05 14.76 1.36 15.94 1.77 17.12 2.37 18.25 3.17 19.21 4.08 20.06 5.12 '
    '20.94 6.60 21.57 8.22 21.90 9.65 22.01 10.81 21.93 12.56 21.68 13.77 21.21 15.09 20.56 '
    '16.33 19.59 17.59 19.15 18.00 18.61 17.97 17.31 16.35 17.40 15.94 18.17 14.93 18.58 14.16 '
    '18.99 13.03 19.15 12.21 19.21 11.24 19.10 10.04 18.55 8.20 17.67 6.71 16.44 5.48 15.06 '
    '4.63 14.13 4.27 13.17 4.05 11.66 3.99 10.78 4.10 9.76 4.38 8.61 4.90 7.59 5.59 6.69 6.44 '
    '5.67 7.87 5.20 8.91 4.90 10.06 4.82 10.89 4.87 12.26 5.37 13.96 5.94 15.03 6.80 16.22 6.74 '
    '16.63 5.75 17.78 5.48 18.06 5.26 18.14 4.96 18.11 4.74 17.97 3.69 16.74 2.81 15.20 2.43 '
    '14.18 2.10 12.76 1.99 11.57 2.02 10.37 2.43 8.22 2.87 7.04 3.50 5.83 4.19 4.85 5.06 3.86 '
    '5.94 3.09 7.18 2.26 8.20 1.77 9.49 1.33 10.75 1.08 11.63 1.03Z ';
const _road =
    'M13.19 12.87L13.47 12.98 13.39 13.11 11.96 13.61 11.71 13.80 11.71 13.94 11.85 14.07 12.37 '
    '14.27 14.95 15.01 15.75 15.47 16.02 15.78 16.16 16.11 16.11 16.63 15.83 17.07 13.69 18.88 '
    '13.52 19.24 13.61 19.54 14.13 19.98 14.84 20.34 16.66 21.00 18.61 21.57 18.85 21.68 18.94 '
    '21.87 18.55 22.09 17.64 22.37 15.36 22.81 13.28 23.00 10.81 23.00 8.69 22.78 6.93 22.40 '
    '5.61 21.87 4.90 21.30 4.74 20.94 4.76 20.45 5.15 19.87 5.89 19.29 7.51 18.47 11.52 16.90 '
    '12.37 16.46 12.76 16.13 12.87 15.72 12.62 15.39 11.90 15.01 10.12 14.35 9.95 14.21 9.90 '
    '13.96 10.17 13.69 10.75 13.47 13.17 12.89Z ';

/// The artwork's gradient: cyan at the top left to violet at the bottom right.
const _ink = [Color(0xFF4BCDFD), Color(0xFF2F6FF6), Color(0xFF4428FA)];
const _inkStops = [0.0, .55, 1.0];

/// The tunnel on the mark's grid: the arch's centre, and a radius just inside its inner edge.
const _tunnel = Offset(12, 11);
const _tunnelRadius = 6.4;

/// Rings receding into the tunnel at once; staggered, they read as a steady flow.
const _rings = 4;

/// The traced outlines are polylines: M, then L and pairs of numbers, then Z.
Path _polyline(String d) {
  final numbers = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => double.parse(m[0]!))
      .toList();
  final path = Path()..moveTo(numbers[0], numbers[1]);
  for (var i = 2; i + 1 < numbers.length; i += 2) {
    path.lineTo(numbers[i], numbers[i + 1]);
  }
  return path..close();
}

final _archPath = _polyline(_arch);
final _roadPath = _polyline(_road);

class Splash extends StatefulWidget {
  const Splash({
    super.key,
    required this.ready,
    required this.line,
    required this.onDone,
  });

  /// Whether what the splash waits for has arrived.
  final bool ready;

  /// What the line says while waiting.
  final String line;
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  Duration now = Duration.zero;
  Duration? leftAt;

  @override
  void initState() {
    super.initState();
    ticker = createTicker((elapsed) {
      setState(() => now = elapsed);
      final gone = leftAt;
      if (gone != null && now - gone >= _leaveTime) {
        ticker.stop();
        widget.onDone();
      } else if (gone == null &&
          ((widget.ready && now >= _minTime) || now >= _maxTime)) {
        leave();
      }
    })..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  void leave() => leftAt ??= now;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.disableAnimationsOf(context);
    final t = now.inMicroseconds / 1e6;
    final gone = leftAt;
    final leaving = gone == null
        ? 0.0
        : ((now - gone).inMicroseconds / _leaveTime.inMicroseconds).clamp(
            0.0,
            1.0,
          );
    // Rising in after the mark has mostly drawn itself, as the desktop's word and line do.
    double rise(double start, double length) => still
        ? 1
        : Curves.ease.transform(((t - start) / length).clamp(0.0, 1.0));
    final word = rise(.9, .6), line = rise(1.1, .5);
    final ink = dark ? const Color(0xFFEAEEF7) : const Color(0xFF101728);
    final muted = dark ? const Color(0xFF8792A9) : const Color(0xFF69738C);

    return Semantics(
      label: 'Nunya is starting',
      liveRegion: true,
      child: Opacity(
        opacity: 1 - leaving,
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.16),
              radius: .58,
              colors: dark
                  ? const [Color(0xFF12243D), Color(0xFF090D1A)]
                  : const [Color(0xFFE4EFFD), Color(0xFFEEF1F7)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  // Leaving, it flies into the tunnel.
                  scale: still
                      ? 1
                      : 1 + .6 * const Cubic(.5, 0, .75, 0).transform(leaving),
                  child: CustomPaint(
                    size: const Size.square(132),
                    painter: _MarkPainter(still ? double.infinity : t),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: word,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - word)),
                    child: Text(
                      'Nunya',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: line,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - line)),
                    child: Text(
                      widget.line,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: muted,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Offered only once the wait has gone on, for a phone that will not be placed.
                SizedBox(
                  height: 40,
                  child: now >= _skipAfter && gone == null
                      ? OutlinedButton(
                          onPressed: () => setState(leave),
                          child: const Text('Continue without it'),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark at [t] seconds into the splash; infinity draws it finished and still.
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t);
  final double t;

  static double _phase(
    double t,
    double start,
    double length, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((t - start) / length).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final ink = Paint()
      ..shader = const LinearGradient(
        colors: _ink,
        stops: _inkStops,
      ).createShader(const Rect.fromLTWH(0, 0, 24, 24));
    final finished = t.isInfinite;

    // Rings receding into the tunnel, beneath the arch and the road so the road runs over them.
    if (!finished) {
      for (var i = 0; i < _rings; i++) {
        final p = ((t - i * 2.6 / _rings) / 2.6) % 1;
        if (t < i * 2.6 / _rings) continue;
        final opacity = p < .15 ? p / .15 * .6 : .6 * (1 - (p - .15) / .85);
        final scale = 1 - .92 * p;
        canvas.drawCircle(
          _tunnel,
          _tunnelRadius * scale,
          Paint()
            ..shader = ink.shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = .3 * scale
            ..color = Colors.white.withValues(alpha: opacity),
        );
      }
    }

    // Each shape is drawn as an outline first, then filled.
    const draw = Cubic(.6, 0, .2, 1);
    for (final (path, drawAt, drawFor, fillAt)
        in <(Path, double, double, double)>[
          (_archPath, 0, 1, .8),
          (_roadPath, .45, .9, 1.1),
        ]) {
      final drawn = finished ? 1.0 : _phase(t, drawAt, drawFor, draw);
      final fill = finished ? 1.0 : _phase(t, fillAt, .5, Curves.ease);
      if (fill > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..shader = ink.shader
            ..color = Colors.white.withValues(alpha: fill),
        );
      }
      if (drawn > 0 && fill < 1) {
        final stroke = Paint()
          ..shader = ink.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = .35
          ..strokeJoin = StrokeJoin.round;
        for (final metric in path.computeMetrics()) {
          canvas.drawPath(metric.extractPath(0, metric.length * drawn), stroke);
        }
      }
    }

    // A light passing over the finished mark, now and then.
    if (!finished && t > 1.6) {
      final p = ((t - 1.6) % 2.8) / 2.8;
      final x = -10 + 40 * math.min(1.0, p / .55).toDouble();
      canvas
        ..save()
        ..clipPath(
          Path()
            ..addPath(_archPath, Offset.zero)
            ..addPath(_roadPath, Offset.zero),
        )
        ..drawRect(
          Rect.fromLTWH(x, 0, 7, 24),
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: .6),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromLTWH(x, 0, 7, 24)),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t;
}
