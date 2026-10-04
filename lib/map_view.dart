/// The world map behind Home, ported from desktop Nunya's `src/views/map.ts` at the commit the
/// phone design was drawn from (ea1944d), including its narrow-screen behaviour. Keep the two in
/// step: same projection, colours, label rule, pins and route.
///
/// The borders are Natural Earth's (public domain), via `world-atlas`, shipped in `design/map`.
/// Nothing is fetched from a map server: a tile service would learn the address of every user of
/// a VPN client each time they looked at the map. 1:110m is drawn at world scale and 1:50m from
/// [_detailZoom]; a phone is always past that, so it reads 1:50m almost at once.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Equirectangular, cropped top and bottom. Projecting the full -90..90 would stretch latitude
// about 2.5x and the continents stop being recognisable.
const _latTop = 75.0;
const _latBottom = -55.0;
const _latSpan = _latTop - _latBottom;
const _minZoom = 1.0;
const _maxZoom = 14.0;
const _detailZoom = 2.5;
const _labelZoom = 2.2;

/// Narrower than this the whole world is too small to read a city on. There the map does not
/// zoom out past [_narrowZoom], nor past where the world fills the height; it cannot be dragged
/// beyond the world's top or bottom; and until the user moves it, it keeps itself centred on the
/// route, or on the device before there is one.
const _narrow = 640.0;
const _narrowZoom = 4.0;

/// Server dots are drawn this much larger than the desktop's 9px, which is sized for a mouse.
const _dotScale = 1.5;

/// Half the 56px finger target around a tappable dot.
const _tapRadius = 28.0;

class MapPin {
  const MapPin(
    this.lon,
    this.lat, {
    this.label,
    this.active = false,
    this.home = false,
    this.here = false,
    this.labelBelow = false,
    this.key,
  });
  final double lon, lat;
  final String? label;

  /// The exit of a running tunnel: the large pulsing green dot.
  final bool active;

  /// The device itself: a ring, not a dot, so it is never mistaken for a server.
  final bool home;

  /// With [home]: the tunnel is down, so this is where traffic actually comes from.
  final bool here;
  final bool labelBelow;

  /// Makes the dot tappable. The map does not know what a dot stands for; it hands the key back
  /// through [MapView.onPick] and the caller decides, which keeps servers out of this file.
  final Object? key;
}

class _Palette {
  const _Palette(bool dark)
    : sunk = dark ? const Color(0xFF0C1222) : const Color(0xFFE9EDF5),
      land = dark ? const Color(0xFF1C263C) : const Color(0xFFD3D9E5),
      border = dark ? const Color(0xFF0C1222) : const Color(0xFFF5F7FB),
      label = dark ? const Color(0xFF6D7892) : const Color(0xFF7A849B),
      surface = dark ? const Color(0xFF111829) : const Color(0xFFFFFFFF),
      ink = dark ? const Color(0xFFEAEEF7) : const Color(0xFF101728),
      ink2 = dark ? const Color(0xFFC3CBDC) : const Color(0xFF39435C),
      line2 = dark ? const Color(0xFF2E3A56) : const Color(0xFFC7CEDE),
      brandGlow = dark ? const Color(0x662E90FA) : const Color(0x472E90FA),
      liveGlow = dark ? const Color(0x6B17B978) : const Color(0x4D17B978);
  final Color sunk, land, border, label, surface, ink, ink2, line2;
  final Color brandGlow, liveGlow;
  static const line = Color(0xFF2E90FA);
  static const live = Color(0xFF17B978);
}

// ---------------------------------------------------------------- the borders

class _Label {
  const _Label(this.name, this.x, this.y, this.width);
  final String name;
  final double x, y, width;
}

class _Borders {
  _Borders(this.path, this.labels);

  /// Every country's rings in one path, in degree space: x = lon + 180, y = _latTop - lat.
  final Path path;
  final List<_Label> labels;
}

/// Decoded off the UI thread: flat x,y rings (already shifted copies for antimeridian rings)
/// and labels. A `Path` cannot cross isolates, so it is built from these on return.
typedef _Decoded = (List<Float64List>, List<_Label>);

/// TopoJSON stores each border once, as a shared, delta-encoded "arc" neighbours both refer to.
/// Decoding it is a few dozen lines, less to trust than a library for a format this settled.
_Decoded _decode(String raw) {
  final topo = jsonDecode(raw) as Map<String, dynamic>;
  final transform = topo['transform'] as Map<String, dynamic>;
  final scale = (transform['scale'] as List).cast<num>();
  final shift = (transform['translate'] as List).cast<num>();
  final arcs = [
    for (final raw in topo['arcs'] as List)
      () {
        var x = 0, y = 0;
        return [
          for (final d in raw as List)
            (
              (x += (d as List)[0] as int) * scale[0] + shift[0] + 180.0,
              _latTop - ((y += d[1] as int) * scale[1] + shift[1]),
            ),
        ];
      }(),
  ];

  // An arc index `~i` is arc `i` walked backwards. A ring crossing the antimeridian (Russia's far
  // east, Fiji) jumps edge to edge between neighbouring points, drawn as a line across the world;
  // so longitudes are unwrapped into one run that may pass 360°, and such a ring is drawn a second
  // time a world's width over. The clip to the band shows each half on its own side.
  List<(double, double)> ring(List indices) {
    final points = <(double, double)>[];
    for (final i in indices.cast<int>()) {
      final arc = i < 0 ? arcs[~i].reversed.toList() : arcs[i];
      for (var (x, y) in points.isEmpty ? arc : arc.skip(1)) {
        if (points.isNotEmpty) {
          final px = points.last.$1;
          while (x - px > 180) {
            x -= 360;
          }
          while (x - px < -180) {
            x += 360;
          }
        }
        points.add((x, y));
      }
    }
    return points;
  }

  final rings = <Float64List>[];
  final labels = <_Label>[];
  final countries =
      ((topo['objects'] as Map)['countries'] as Map)['geometries'] as List;
  for (final g in countries.cast<Map>()) {
    if (g['type'] == null) continue;
    final polygons = g['type'] == 'Polygon' ? [g['arcs']] : g['arcs'] as List;
    // The label goes on the country's largest piece — mainland France, not French Guiana.
    var best = (area: 0.0, x: 0.0, y: 0.0, width: 0.0);
    for (final polygon in polygons.cast<List>()) {
      for (var r = 0; r < polygon.length; r++) {
        final points = ring(polygon[r] as List);
        if (points.length < 3) continue;
        var (x0, y0, x1, y1) = (
          double.infinity,
          double.infinity,
          -double.infinity,
          -double.infinity,
        );
        for (final (x, y) in points) {
          x0 = math.min(x0, x);
          y0 = math.min(y0, y);
          x1 = math.max(x1, x);
          y1 = math.max(y1, y);
        }
        for (final s in [0.0, if (x1 > 360) -360.0, if (x0 < 0) 360.0]) {
          final flat = Float64List(points.length * 2);
          for (var i = 0; i < points.length; i++) {
            flat[i * 2] = points[i].$1 + s;
            flat[i * 2 + 1] = points[i].$2;
          }
          rings.add(flat);
        }
        if (r != 0) continue; // holes do not host labels
        final area = (x1 - x0) * (y1 - y0);
        // A centre pushed off the map by an unwrapped ring is brought back onto it.
        final cx = (((x0 + x1) / 2) % 360 + 360) % 360;
        if (area > best.area) {
          best = (area: area, x: cx, y: (y0 + y1) / 2, width: x1 - x0);
        }
      }
    }
    final name = (g['properties'] as Map?)?['name'] as String?;
    if (name != null && best.area > 0) {
      labels.add(_Label(name, best.x, best.y, best.width));
    }
  }
  return (rings, labels);
}

Future<_Borders> _load(String asset) async {
  final (rings, labels) = await compute(
    _decode,
    await rootBundle.loadString(asset),
  );
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final flat in rings) {
    path.addPolygon([
      for (var i = 0; i < flat.length; i += 2) Offset(flat[i], flat[i + 1]),
    ], true);
  }
  return _Borders(path, labels);
}

// Loaded once per app run, shared by every MapView.
final _coarse = _load('design/map/countries-110m.json');
Future<_Borders>? _fine;

// ---------------------------------------------------------------- the map

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.dark,
    this.pins = const [],
    this.route = const [],
    this.covered = 0,
    this.onPick,
  });
  final bool dark;
  final List<MapPin> pins;

  /// The path traffic takes, as (lon, lat): the device, then each server, the exit last.
  final List<(double, double)> route;

  /// Height the connection sheet covers at the bottom; the map centres in what is left.
  final double covered;
  final ValueChanged<Object>? onPick;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  _Borders? coarse, fine;
  // The whole world fitted to the pane: its left, top and pixels per degree at zoom 1.
  var base = (x: 0.0, y: 0.0, perDegree: 1.0);
  // The view on top of it: a zoom, and the pane offset that zoom is taken from.
  var view = (k: 1.0, x: 0.0, y: 0.0);
  var size = Size.zero;

  /// The user has zoomed or dragged; a narrow map stops following the route.
  bool steered = false;
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  Offset? lastFocal;
  double lastScale = 1;

  @override
  void initState() {
    super.initState();
    _coarse.then((b) => mounted ? setState(() => coarse = b) : null);
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  /// The nearest tappable dot within [_tapRadius]: a fingertip, not a dot, is the target. Nearest
  /// wins when two dots' targets overlap, as neighbouring European cities' do.
  void pick(Offset tap) {
    final onPick = widget.onPick;
    if (onPick == null) return;
    final s = base.perDegree * view.k;
    MapPin? best;
    var bestDistance = _tapRadius;
    for (final pin in widget.pins.where((p) => p.key != null)) {
      final at = Offset(
        view.x + view.k * base.x + s * (pin.lon + 180),
        view.y + view.k * base.y + s * (_latTop - pin.lat),
      );
      final d = (at - tap).distance;
      if (d <= bestDistance) (best, bestDistance) = (pin, d);
    }
    if (best != null) onPick(best.key!);
  }

  bool get narrow => size.width > 0 && size.width < _narrow;
  double get scale => base.perDegree * view.k;
  double get floor => size.height - widget.covered;

  double get minZoom {
    if (!narrow) return _minZoom;
    // Zoomed until the world fills the height left above the sheet.
    final band = _latSpan * base.perDegree;
    return math.max(_narrowZoom, band > 0 ? floor / band : _narrowZoom);
  }

  void fitBase() {
    final w =
        size.width * 1.06; // a touch of bleed past the edges at the widest view
    final h = w * (_latSpan / 360);
    final free = math.max(floor, h);
    base = (x: (size.width - w) / 2, y: (free - h) / 2, perDegree: w / 360);
  }

  /// Centres on the middle of the route while connected, else the device, else the world.
  void follow() {
    final route = widget.route;
    final home = widget.pins.where((p) => p.home).firstOrNull;
    final (lon, lat) = route.length > 1
        ? (
            (route.first.$1 + route.last.$1) / 2,
            (route.first.$2 + route.last.$2) / 2,
          )
        : home != null
        ? (home.lon, home.lat)
        : (0.0, (_latTop + _latBottom) / 2);
    final k = minZoom;
    view = (
      k: k,
      x: size.width / 2 - k * (base.x + base.perDegree * (lon + 180)),
      y: floor / 2 - k * (base.y + base.perDegree * (_latTop - lat)),
    );
  }

  /// Keeps the world on screen: an edge can be dragged to the middle of the view, never past it.
  void clamp() {
    final k = view.k;
    final left = k * base.x;
    final right = k * (base.x + 360 * base.perDegree);
    final top = k * base.y;
    final bottom = k * (base.y + _latSpan * base.perDegree);
    final x = math.min(
      math.max(view.x, size.width / 2 - right),
      size.width / 2 - left,
    );
    // A narrow map fills its height, and its edges stop at the pane's.
    final y = narrow
        ? math.min(math.max(view.y, floor - bottom), -top)
        : math.min(math.max(view.y, floor / 2 - bottom), floor / 2 - top);
    view = k == 1 ? (k: 1, x: 0, y: 0) : (k: k, x: x, y: y);
  }

  /// Zooms about a point, keeping whatever is under it there.
  void zoomAt(double factor, Offset at) {
    steered = true;
    final k = (view.k * factor).clamp(minZoom, _maxZoom).toDouble();
    if (k == view.k) return;
    final r = k / view.k;
    view = (
      k: k,
      x: at.dx - (at.dx - view.x) * r,
      y: at.dy - (at.dy - view.y) * r,
    );
    moved();
  }

  void panBy(Offset d) {
    steered = true;
    view = (k: view.k, x: view.x + d.dx, y: view.y + d.dy);
    moved();
  }

  void moved() {
    clamp();
    loadFine();
    setState(() {});
  }

  void loadFine() {
    if (view.k < _detailZoom || fine != null) return;
    (_fine ??= _load(
      'design/map/countries-50m.json',
    )).then((b) => mounted ? setState(() => fine = b) : null);
  }

  @override
  Widget build(BuildContext context) {
    final routing = widget.route.length > 1;
    final animate =
        widget.pins.any((p) => p.active) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !pulse.isAnimating) pulse.repeat();
    if (!animate && pulse.isAnimating) pulse.reset();
    return LayoutBuilder(
      builder: (context, box) {
        size = box.biggest;
        fitBase();
        clamp();
        if (minZoom > _minZoom && (!steered || view.k < minZoom)) follow();
        loadFine();
        return GestureDetector(
          onScaleStart: (d) {
            lastFocal = d.localFocalPoint;
            lastScale = 1;
          },
          // What is under the fingers stays under them: the map follows their midpoint, and
          // zooms about it by how far they spread.
          onScaleUpdate: (d) {
            panBy(d.localFocalPoint - (lastFocal ?? d.localFocalPoint));
            if (d.pointerCount > 1 && lastScale > 0) {
              zoomAt(d.scale / lastScale, d.localFocalPoint);
            }
            lastFocal = d.localFocalPoint;
            lastScale = d.scale;
          },
          // No double-tap zoom, unlike the desktop's double-click: it would hold every single tap
          // back ~300ms to rule out a second, and a dot tap that lags reads as a miss. Pinch zooms.
          onTapUp: (d) => pick(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: _MapPainter(
              borders: (view.k >= _detailZoom ? fine : null) ?? coarse,
              palette: _Palette(widget.dark),
              base: base,
              view: view,
              pins: widget.pins,
              route: widget.route,
              routing: routing,
              pulse: pulse,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- drawing

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.borders,
    required this.palette,
    required this.base,
    required this.view,
    required this.pins,
    required this.route,
    required this.routing,
    required this.pulse,
  }) : super(repaint: pulse);
  final _Borders? borders;
  final _Palette palette;
  final ({double x, double y, double perDegree}) base;
  final ({double k, double x, double y}) view;
  final List<MapPin> pins;
  final List<(double, double)> route;
  final bool routing;
  final Animation<double> pulse;

  double get scale => base.perDegree * view.k;
  double sx(double x) => view.x + view.k * base.x + scale * x;
  double sy(double y) => view.y + view.k * base.y + scale * y;
  Offset at(double lon, double lat) => Offset(sx(lon + 180), sy(_latTop - lat));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(palette.sunk, BlendMode.src);
    final b = borders;
    if (b != null) {
      canvas
        ..save()
        ..translate(sx(0), sy(0))
        ..scale(scale)
        // The band: one world wide, cropped at the kept latitudes. Antarctica, the far Arctic and
        // the shifted copies of antimeridian rings are cut here.
        ..clipRect(const Rect.fromLTWH(0, 0, 360, _latSpan))
        ..drawPath(b.path, Paint()..color = palette.land)
        ..drawPath(
          b.path,
          Paint()
            ..color = palette.border
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            // Constant on screen, whatever the zoom: neighbours read as separate at world scale,
            // and a small country never disappears up close.
            ..strokeWidth = math.min(1.1, .5 + view.k * .08) / scale,
        )
        ..restore();
      if (view.k >= _labelZoom) _labels(canvas, size, b.labels);
    }
    _route(canvas);
    _pins(canvas, size);
  }

  static final _textCache = <String, TextPainter>{};

  TextPainter _text(
    String text,
    double fontSize,
    FontWeight weight,
    Color color,
  ) => _textCache.putIfAbsent(
    '$text|$fontSize|${weight.value}|${color.toARGB32()}',
    () => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  /// Country names where there is room: a name that does not fit its country is left out.
  void _labels(Canvas canvas, Size size, List<_Label> labels) {
    final fontSize = view.k >= 5 ? 12.0 : 11.0;
    for (final l in labels) {
      final x = sx(l.x), y = sy(l.y);
      if (x < -50 || x > size.width + 50 || y < -20 || y > size.height + 20) {
        continue;
      }
      final tp = _text(l.name, fontSize, FontWeight.w600, palette.label);
      if (tp.width + 8 > l.width * scale) continue;
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  /// One arc per leg, bowed upward by its length, dashed, with a chevron halfway and a head
  /// just short of the far end, so it reads *from* the user *to* the exit.
  void _route(Canvas canvas) {
    final paint = Paint()
      ..color = _Palette.line.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var i = 1; i < route.length; i++) {
      final a = at(route[i - 1].$1, route[i - 1].$2);
      final b = at(route[i].$1, route[i].$2);
      final length = (b - a).distance;
      if (length < 6) continue;
      final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - length * .3);
      final curve = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(c.dx, c.dy, b.dx, b.dy);
      for (final metric in curve.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 9) {
          canvas.drawPath(metric.extractPath(d, d + 5), paint);
        }
      }
      // B(t) and the direction B'(t) of the quadratic.
      (Offset, double) point(double t) => (
        a * ((1 - t) * (1 - t)) + c * (2 * (1 - t) * t) + b * (t * t),
        math.atan2(
          2 * (1 - t) * (c.dy - a.dy) + 2 * t * (b.dy - c.dy),
          2 * (1 - t) * (c.dx - a.dx) + 2 * t * (b.dx - c.dx),
        ),
      );
      _arrow(canvas, point(.5), 5);
      if (length > 40) _arrow(canvas, point(1 - math.min(.2, 14 / length)), 7);
    }
  }

  void _arrow(Canvas canvas, (Offset, double) p, double s) {
    canvas
      ..save()
      ..translate(p.$1.dx, p.$1.dy)
      ..rotate(p.$2)
      ..drawPath(
        Path()
          ..moveTo(s, 0)
          ..lineTo(-s * .8, -s * .75)
          ..lineTo(-s * .35, 0)
          ..lineTo(-s * .8, s * .75)
          ..close(),
        Paint()..color = _Palette.line.withValues(alpha: .9),
      )
      ..restore();
  }

  void _pins(Canvas canvas, Size size) {
    final p = palette;
    void dot(Offset o, double r, Color c) =>
        canvas.drawCircle(o, r, Paint()..color = c);
    // Servers first, then the user, then the exit on top, as the desktop's stacking reads.
    final ordered = [
      ...pins.where((x) => !x.active && !x.home),
      ...pins.where((x) => x.home),
      ...pins.where((x) => x.active),
    ];
    for (final pin in ordered) {
      final o = at(pin.lon, pin.lat);
      if (o.dx < -20 ||
          o.dx > size.width + 20 ||
          o.dy < -20 ||
          o.dy > size.height + 20) {
        continue;
      }
      double diameter;
      if (pin.active) {
        diameter = 15;
        final t = Curves.easeOut.transform(pulse.value);
        canvas.drawCircle(
          o,
          6.5 * (1 + 2.6 * t),
          Paint()
            ..color = _Palette.live.withValues(alpha: .85 * (1 - t))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * (1 + 2.6 * t),
        );
        dot(o, 11.5, p.liveGlow);
        dot(o, 7.5, p.surface);
        dot(o, 5.5, _Palette.live);
      } else if (pin.home && pin.here && !routing) {
        diameter = 16;
        dot(o, 15, const Color(0x14000000));
        dot(o, 10, p.surface);
        dot(o, 8, p.ink);
        dot(o, 4.5, p.surface);
      } else if (pin.home) {
        diameter = 14;
        dot(o, 9, p.surface);
        dot(o, 7, routing ? p.ink : p.ink2);
        dot(o, routing ? 3 : 3.5, p.surface);
      } else {
        // While a route is drawn, every dot not on it steps back.
        final s = (routing ? .75 : 1.0) * _dotScale;
        final fade = routing ? .4 : 1.0;
        diameter = 9 * s;
        dot(o, 5.5 * s, p.brandGlow.withValues(alpha: p.brandGlow.a * fade));
        dot(o, 4.5 * s, p.surface.withValues(alpha: fade));
        dot(o, 2.5 * s, _Palette.line.withValues(alpha: fade));
      }
      final label = pin.label;
      if (label != null) _pinLabel(canvas, o, diameter, label, pin.labelBelow);
    }
  }

  void _pinLabel(
    Canvas canvas,
    Offset o,
    double diameter,
    String text,
    bool below,
  ) {
    final tp = _text(text, 10.5, FontWeight.w700, palette.ink);
    final w = tp.width + 16, h = tp.height + 6;
    final top = below ? o.dy + diameter / 2 + 9 : o.dy - diameter / 2 - 9 - h;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(o.dx - w / 2, top, w, h),
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(box, Paint()..color = palette.surface)
      ..drawRRect(
        box,
        Paint()
          ..color = palette.line2
          ..style = PaintingStyle.stroke,
      );
    tp.paint(canvas, Offset(o.dx - tp.width / 2, top + 3));
  }

  // The parent rebuilds pins and route as new lists on every frame; comparing them costs about
  // what repainting does.
  @override
  bool shouldRepaint(_MapPainter old) => true;
}
