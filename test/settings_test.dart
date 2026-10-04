import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/settings.dart';

void main() {
  test('a bypass entry is classified by its shape, or refused', () {
    expect(classifyBypass('example.com'), BypassKind.domain);
    expect(classifyBypass('*.example.com'), BypassKind.domain);
    expect(classifyBypass('203.0.113.7'), BypassKind.address);
    expect(classifyBypass('203.0.113.0/24'), BypassKind.range);
    for (final bad in [
      '',
      'localhost',
      '300.1.1.1',
      '10.0.0.0/33',
      '10.0.0.0/8/1',
      '-x.com',
    ]) {
      expect(classifyBypass(bad), isNull, reason: bad);
    }
  });

  test('a rule already in the list is not added twice', () {
    final s = Settings();
    expect(s.addBypass(' example.com '), isTrue);
    expect(s.addBypass('example.com'), isFalse);
    expect(s.bypass.single.value, 'example.com');
  });

  test('reset leaves bypass rules alone', () {
    final s = Settings()..addBypass('example.com');
    s.update(() {
      s.dns = 'https://dns.example/dns-query';
      s.blockAds = true;
    });
    s.reset();
    expect((s.dns, s.blockAds), (Settings.defaultDns, false));
    expect(s.bypass, hasLength(1));
  });

  test('a switch that is on without its list says it blocks nothing yet', () {
    final now = DateTime(2026, 10, 5, 12);
    const none = (updatedAt: null, busy: false, error: null);
    expect(
      listLine(false, none, now),
      'the list is downloaded when you turn it on',
    );
    expect(
      listLine(true, none, now),
      'not blocking yet: the list has not been downloaded',
    );
    expect(
      listLine(true, (
        updatedAt: DateTime(2026, 10, 5, 9),
        busy: false,
        error: null,
      ), now),
      'list updated 3 h ago',
    );
  });

  test('the log keeps only its last lines', () {
    final log = AppLog();
    for (var i = 0; i < AppLog.keep + 5; i++) {
      log.add('line $i');
    }
    expect(log.lines, hasLength(AppLog.keep));
    expect(log.lines.first, endsWith('line 5'));
  });
}
