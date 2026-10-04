import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/whereabouts.dart';

void main() {
  test('reads ipwho.is, with the network under connection', () {
    final w = whereaboutsFrom(
      '{"success":true,"ip":"203.0.113.7","country_code":"IT","city":"Milan",'
      '"latitude":45.46,"longitude":9.19,"connection":{"asn":3269,"org":"Telecom Italia"}}',
    )!;
    expect(
      (w.ip, w.country, w.city, w.asn, w.org),
      ('203.0.113.7', 'IT', 'Milan', 3269, 'Telecom Italia'),
    );
    expect(w.flag, '🇮🇹');
  });

  test('reads ipinfo, splitting loc and the AS string', () {
    final w = whereaboutsFrom(
      '{"ip":"198.51.100.2","city":"Berlin","country":"DE","loc":"52.52,13.40",'
      '"org":"AS3320 Deutsche Telekom AG"}',
    )!;
    expect(
      (w.lat, w.lon, w.asn, w.org),
      (52.52, 13.40, 3320, 'Deutsche Telekom AG'),
    );
  });

  test('reads ip.sb', () {
    final w = whereaboutsFrom(
      '{"ip":"2001:db8::1","country_code":"NL","latitude":52.37,"longitude":4.89,'
      '"asn":1136,"asn_organization":"KPN B.V."}',
    )!;
    expect((w.country, w.asn, w.org), ('NL', 1136, 'KPN B.V.'));
  });

  test('a failure inside a 200, or a body without a place, is no answer', () {
    expect(whereaboutsFrom('{"success":false,"message":"limit"}'), isNull);
    expect(whereaboutsFrom('{"ip":"203.0.113.7","country_code":"IT"}'), isNull);
    expect(
      whereaboutsFrom('{"ip":"not-an-ip","country_code":"IT","lat":1,"lon":1}'),
      isNull,
    );
    expect(whereaboutsFrom('<html>rate limited</html>'), isNull);
  });
}
