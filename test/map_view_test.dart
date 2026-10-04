import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/map_view.dart';

void main() {
  testWidgets('tapping near a dot picks it, tapping open map does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    Object? picked;
    // With a home pin and no route, a phone-width map centres on the home.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapView(
          dark: false,
          onPick: (key) => picked = key,
          pins: const [MapPin(10, 50, home: true, key: 'here')],
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(MapView));

    await tester.tapAt(centre + const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked, isNull);

    // Within the 44px finger target, though well off the dot itself.
    await tester.tapAt(centre + const Offset(15, 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked, 'here');
  });
}
