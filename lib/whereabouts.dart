/// Where this phone is, as the internet sees it: ported from desktop Nunya's `geo.rs`
/// (`whereabouts`, `whereabouts_from`) and `main.ts` (`locateHome`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An address and where a geo database puts it. Coordinates rather than a country, because the
/// map draws the user's dot from them, and a country's centroid puts everyone in Russia in Siberia.
class Whereabouts {
  const Whereabouts({
    required this.ip,
    required this.country,
    required this.lat,
    required this.lon,
    this.city,
    this.asn,
    this.org,
  });
  final String ip;

  /// Two-letter country code, uppercase.
  final String country;
  final String? city;
  final double lat, lon;
  final int? asn;
  final String? org;

  /// The country's flag, from its code's regional-indicator letters.
  String get flag =>
      String.fromCharCodes(country.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

/// Endpoints that place the caller. Several because free tiers run out; `api.ip.sb` because it
/// sits behind Cloudflare, which the networks this client is for cannot block wholesale. The
/// desktop's fourth, plain-HTTP `ip-api.com`, is left out: Android refuses cleartext by default.
const placeUrls = [
  'https://ipwho.is/',
  'https://ipinfo.io/json',
  'https://api.ip.sb/geoip',
];

const _timeout = Duration(seconds: 5);

/// Reads whichever endpoint's shape the body is in: three services, three spellings of the same
/// facts, so each fact is looked for by its known names rather than a schema per endpoint.
Whereabouts? whereaboutsFrom(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body.trim());
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final v = decoded;
  // ipwho.is and ip-api answer 200 with a failure inside.
  if (v['success'] == false || v['status'] == 'fail') return null;

  String? text(List<String> keys) {
    for (final k in keys) {
      final s = v[k];
      if (s is String && s.trim().isNotEmpty) return s.trim();
    }
    return null;
  }

  double? number(List<String> keys) {
    for (final k in keys) {
      if (v[k] case final num n) return n.toDouble();
    }
    return null;
  }

  final ip = text(['ip', 'query']);
  if (ip == null || InternetAddress.tryParse(ip) == null) return null;

  final country = text(['country_code', 'countryCode', 'country'])
      ?.toUpperCase();
  if (country == null || !RegExp(r'^[A-Z]{2}$').hasMatch(country)) return null;

  var (lat, lon) = (number(['latitude', 'lat']), number(['longitude', 'lon']));
  if (lat == null || lon == null) {
    // ipinfo: "loc": "lat,lon".
    final loc = text(['loc'])?.split(',');
    if (loc == null || loc.length != 2) return null;
    (lat, lon) = (
      double.tryParse(loc[0].trim()),
      double.tryParse(loc[1].trim()),
    );
    if (lat == null || lon == null) return null;
  }
  if (lat.abs() > 90 || lon.abs() > 180) return null;

  // ipwho.is gives the number and name apart under `connection`, ip.sb under names of its own;
  // ipinfo and ip-api give one string, "AS13335 Cloudflare, Inc.", split here.
  final connection = v['connection'] is Map ? v['connection'] as Map : const {};
  final asString = text(['org', 'as']);
  String? org = [connection['org'], connection['isp']]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .firstOrNull;
  org ??= text(['asn_organization', 'organization', 'isp']);
  if (org == null && asString != null) {
    final name = asString.startsWith('AS')
        ? asString.substring(2).replaceFirst(RegExp(r'^\d*'), '').trim()
        : asString;
    if (name.isNotEmpty) org = name;
  }
  final asn = switch ((connection['asn'], v['asn'])) {
    (final int a, _) => a,
    (_, final int a) => a,
    _ => int.tryParse(
      RegExp(r'^AS(\d+)').firstMatch(asString ?? '')?.group(1) ?? '',
    ),
  };

  return Whereabouts(
    ip: ip,
    country: country,
    city: text(['city']),
    lat: lat,
    lon: lon,
    asn: asn,
    org: org,
  );
}

/// Places this phone by asking every endpoint at once and taking the first answer. On a filtered
/// network a blocked endpoint does not refuse, it hangs until the timeout; asked in turn, two of
/// them would cost ten seconds before a reachable one was even tried.
///
/// "Directly" means over whatever route the OS has: with a VPN up, that is the tunnel, and the
/// answer is the exit. Callers ask only while disconnected.
Future<Whereabouts> locate() {
  final done = Completer<Whereabouts>();
  var pending = placeUrls.length;
  for (final url in placeUrls) {
    _ask(url)
        .then((found) {
          if (!done.isCompleted) done.complete(found);
        })
        .catchError((Object e) {
          if (--pending == 0 && !done.isCompleted) done.completeError(e);
        })
        .ignore();
  }
  return done.future;
}

Future<Whereabouts> _ask(String url) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_timeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
    return whereaboutsFrom(body) ??
        (throw HttpException('$url did not say where'));
  } finally {
    client.close(force: true);
  }
}
