import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Natural Earth borders, shipped offline in design/map through world-atlas (public domain).
Future<List<List<Offset>>> loadMapRings() async {
  final map = jsonDecode(
    await rootBundle.loadString('design/map/countries-110m.json'),
  ) as Map<String, dynamic>;
  final transform = map['transform'] as Map<String, dynamic>;
  final scale = (transform['scale'] as List).cast<num>();
  final shift = (transform['translate'] as List).cast<num>();
  final arcs = (map['arcs'] as List).map((raw) {
    var x = 0, y = 0;
    return (raw as List).map((delta) {
      x += (delta as List)[0] as int;
      y += delta[1] as int;
      return Offset(
        (x * scale[0] + shift[0]).toDouble(),
        (y * scale[1] + shift[1]).toDouble(),
      );
    }).toList();
  }).toList();
  final countries =
      ((map['objects'] as Map)['countries'] as Map)['geometries'] as List;
  final rings = <List<Offset>>[];
  for (final country in countries) {
    final geometry = country as Map;
    if (geometry['type'] == null) continue;
    final polygons = geometry['type'] == 'Polygon'
        ? [geometry['arcs']]
        : geometry['arcs'] as List;
    for (final polygon in polygons) {
      for (final rawRing in polygon as List) {
        final ring = <Offset>[];
        for (final rawIndex in rawRing as List) {
          final index = rawIndex as int;
          final points = index < 0 ? arcs[~index].reversed : arcs[index];
          ring.addAll(ring.isEmpty ? points : points.skip(1));
        }
        if (ring.length > 2) rings.add(ring);
      }
    }
  }
  return rings;
}

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.dark,
    required this.previewConnected,
  });
  final bool dark, previewConnected;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late final Future<List<List<Offset>>> rings = loadMapRings();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<List<Offset>>>(
    future: rings,
    builder: (context, snapshot) => LayoutBuilder(
      builder: (context, bounds) {
        final size = Size(bounds.maxWidth, bounds.maxHeight);
        return InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: CustomPaint(
            size: size,
            painter: _MapPainter(
              snapshot.data ?? [],
              widget.dark,
              widget.previewConnected,
            ),
          ),
        );
      },
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.rings, this.dark, this.connected);
  final List<List<Offset>> rings;
  final bool dark, connected;

  Offset _project(Offset geo, Size size) => Offset(
    (geo.dx + 33) / 101 * size.width,
    (76 - geo.dy) / 61 * size.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(
      dark ? const Color(0xFF101B2A) : const Color(0xFFE8F0F2),
      ui.BlendMode.src,
    );
    final land = Paint()
      ..color = dark ? const Color(0xFF263247) : const Color(0xFFD3DFDF)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = dark ? const Color(0xFF39475B) : const Color(0xFFB9C9CB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (final ring in rings) {
      final path = Path()
        ..moveTo(_project(ring.first, size).dx, _project(ring.first, size).dy);
      for (final point in ring.skip(1)) {
        final p = _project(point, size);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, land);
      canvas.drawPath(path, border);
    }
    for (final item in const [
      ('United Kingdom', -3.0, 54.0),
      ('Germany', 10.5, 51.0),
      ('France', 2.0, 46.5),
      ('Italy', 12.6, 42.8),
      ('Sweden', 15.0, 62.0),
      ('Finland', 25.0, 64.0),
      ('Spain', -4.0, 40.0),
      ('Türkiye', 34.5, 39.0),
    ]) {
      final at = _project(Offset(item.$2, item.$3), size);
      final tp = TextPainter(
        text: TextSpan(
          text: item.$1.toUpperCase(),
          style: TextStyle(
            fontSize: 8,
            letterSpacing: .6,
            color: dark ? const Color(0xFF8496AA) : const Color(0xFF83999C),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
    final home = _project(const Offset(9.19, 45.46), size);
    final exit = _project(const Offset(24.94, 60.17), size);
    if (connected) {
      final route = Path()
        ..moveTo(home.dx, home.dy)
        ..lineTo(exit.dx, exit.dy);
      canvas.drawPath(
        route,
        Paint()
          ..color = const Color(0xFF21B680)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    for (final pin in [home, exit]) {
      canvas.drawCircle(pin, 9, Paint()..color = const Color(0x5524B981));
      canvas.drawCircle(pin, 4.5, Paint()..color = const Color(0xFF21B680));
      canvas.drawCircle(pin, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.rings != rings || old.dark != dark || old.connected != connected;
}
