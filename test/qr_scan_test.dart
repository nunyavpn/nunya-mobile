import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/qr_scan.dart';
import 'package:qr/qr.dart';

/// [text] drawn as a QR code the way the Share sheet draws it: [scale] pixels a module, a
/// two-module quiet zone, dark on light unless [inverted].
(Int8List, int) render(String text, {int scale = 4, bool inverted = false}) {
  final image = QrImage(
    QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final side = (image.moduleCount + 4) * scale;
  final luma = Int8List(side * side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final (my, mx) = (y ~/ scale - 2, x ~/ scale - 2);
      final inside =
          my >= 0 &&
          mx >= 0 &&
          my < image.moduleCount &&
          mx < image.moduleCount;
      final dark = inside && image.isDark(my, mx);
      luma[y * side + x] = (dark != inverted) ? 0 : 255;
    }
  }
  return (luma, side);
}

void main() {
  const link =
      'vless://6a1f3c2e-9d4b-4e8a-b7c1-0f2d3e4a5b6c@de1.example.net:443?type=tcp'
      '&security=reality&pbk=Zx3vYq0sJ8H2kP5mN7bR1tW4uE6iO9aL2cF0dG3hK8s&sid=6ba85179e30d4fc2'
      '&sni=www.microsoft.com&fp=chrome&flow=xtls-rprx-vision#DE-1%20Frankfurt';

  test('a share link drawn as a QR code reads back as the same link', () {
    final (luma, side) = render(link);
    expect(decodeQrLuma(luma, side, side), link);
  });

  test('a light-on-dark code, as screenshotted from a dark app, reads too', () {
    final (luma, side) = render(link, inverted: true);
    expect(decodeQrLuma(luma, side, side), link);
  });

  test('an image without a code reads as nothing', () {
    expect(decodeQrLuma(Int8List(200 * 200), 200, 200), isNull);
  });
}
