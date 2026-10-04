import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/usage.dart';

void main() {
  test('a counter reset counts the new reading whole, never negative', () {
    expect(
      advance((uplink: 100, downlink: 1000), (uplink: 150, downlink: 1600)),
      (up: 50, down: 600),
    );
    expect(
      advance((uplink: 100, downlink: 1000), (uplink: 30, downlink: 200)),
      (up: 30, down: 200),
    );
  });

  test('traffic is filed by local day and totalled', () {
    final h = <String, Bytes>{};
    addUsage(h, DateTime(2026, 10, 3, 23, 59), (up: 1, down: 10));
    addUsage(h, DateTime(2026, 10, 4, 0, 1), (up: 2, down: 20));
    addUsage(h, DateTime(2026, 10, 4, 9), (up: 3, down: 30));
    expect(h, {
      '2026-10-03': (up: 1, down: 10),
      '2026-10-04': (up: 5, down: 50),
    });
    expect(total([h]), (up: 6, down: 60));
    expect(total([h], '2026-10-04'), (up: 5, down: 50));
    expect(firstDay([h]), '2026-10-03');
  });

  test('the chart has every day, quiet ones as zero', () {
    final h = {'2026-10-02': (up: 1, down: 2)};
    final days = lastDays([h], 3, DateTime(2026, 10, 4, 8));
    expect(days.map((d) => (d.day, d.down)), [
      ('2026-10-02', 2),
      ('2026-10-03', 0),
      ('2026-10-04', 0),
    ]);
  });

  test('the chart tops out at a round size', () {
    const mb = 1024 * 1024;
    expect(niceCeiling(0), mb);
    expect(niceCeiling(430 * mb), 500 * mb);
    expect(niceCeiling(990 * mb), 1024 * mb);
    expect(size(1536), '1.50 KB');
  });
}
