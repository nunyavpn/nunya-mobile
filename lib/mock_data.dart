import 'dart:math' as math;

import 'share_link.dart';
import 'usage.dart';

/// A server: the profile the engine will connect with, plus what the list shows about it.
class Server {
  Server(
    this.profile, {
    this.flag = '🌐',
    String? city,
    this.latency,
    this.group = 'Personal',
    this.cdn = false,
    this.location,
    Usage? usage,
  }) : city = city ?? profile.server,
       usage = usage ?? {};

  /// The connection settings, edited as structured data and written out as a link only when
  /// shared (see share_link.dart).
  final Profile profile;
  final String flag, city, group;
  final int? latency;
  final bool cdn;

  /// (longitude, latitude) of the exit, when known; imported servers have none until measured.
  final (double, double)? location;

  /// Traffic by day, kept on the server so it lives exactly as long as the server does.
  final Usage usage;

  String get name => profile.name;
  String get host => profile.server;
  int get port => profile.port;
  String get protocol => describe(profile);

  /// The same server with an edited profile. Its history stays; a new address is a different
  /// place, so the measured latency and exit go with the old one, as on the desktop.
  Server withProfile(Profile edited) {
    final moved = edited.server != host || edited.port != port;
    return Server(
      edited,
      flag: moved ? '🌐' : flag,
      city: moved ? null : city,
      latency: moved ? null : latency,
      group: group,
      cdn: moved ? false : cdn,
      location: moved ? null : location,
      usage: usage,
    );
  }
}

const aurora = 'Aurora Networks';

Server _sample(
  String link,
  String flag,
  String city,
  int? latency,
  (double, double) location, {
  String group = 'Personal',
  bool cdn = false,
}) => Server(
  parseShareLink(link),
  flag: flag,
  city: city,
  latency: latency,
  group: group,
  cdn: cdn,
  location: location,
);

/// Sample servers, from links in the forms panels write, so editing and sharing them exercises
/// the same parser and writer an imported server does. Addresses are example.net and keys fake.
List<Server> sampleServers(DateTime now) {
  const id = '6a1f3c2e-9d4b-4e8a-b7c1-0f2d3e4a5b6c';
  const reality =
      'security=reality&pbk=Zx3vYq0sJ8H2kP5mN7bR1tW4uE6iO9aL2cF0dG3hK8s'
      '&sid=6ba85179e30d4fc2&sni=www.microsoft.com&fp=chrome';
  final servers = [
    _sample(
      'vless://$id@de1.example.net:443?type=tcp&$reality&flow=xtls-rprx-vision#DE-1%20Frankfurt',
      '🇩🇪',
      'Frankfurt',
      24,
      (8.68, 50.11),
    ),
    _sample(
      'vless://$id@nl2.example.net:443?type=ws&security=tls&path=%2Fws%3Fed%3D2048'
          '&host=nl2.example.net&sni=nl2.example.net#NL-2%20Amsterdam',
      '🇺🇸',
      'Ashburn · via NL',
      138,
      (-77.49, 39.04),
      cdn: true,
    ),
    // No latency: the preview tunnel fails on it, to show the error state.
    _sample(
      'vless://$id@ir1.example.net:80?type=tcp&security=none#IR-1%20Tehran',
      '🇮🇷',
      'Tehran',
      null,
      (51.39, 35.69),
    ),
    _sample(
      'vless://$id@fi1.example.net:443?type=tcp&$reality#FI-1%20Helsinki',
      '🇫🇮',
      'Helsinki',
      31,
      (24.94, 60.17),
      group: aurora,
    ),
    // A second Helsinki exit, so its map dot holds more than one server.
    _sample(
      'vless://$id@fi2.example.net:443?type=ws&security=tls&path=%2Fstream'
          '&sni=fi2.example.net#FI-2%20Helsinki',
      '🇫🇮',
      'Helsinki',
      52,
      (24.94, 60.17),
      group: aurora,
      cdn: true,
    ),
    _sample(
      'vless://$id@se1.example.net:443?type=tcp&$reality#SE-1%20Stockholm',
      '🇸🇪',
      'Stockholm',
      44,
      (18.07, 59.33),
      group: aurora,
    ),
    _sample(
      'trojan://sample-password@gb3.example.net:443?type=ws&path=%2Ftr'
          '&sni=gb3.example.net#GB-3%20London',
      '🇬🇧',
      'London',
      71,
      (-0.13, 51.51),
      group: aurora,
      cdn: true,
    ),
    _sample(
      'vmess://$id@fr2.example.net:443?type=grpc&security=tls&serviceName=tun'
          '&sni=fr2.example.net&encryption=auto#FR-2%20Paris',
      '🇫🇷',
      'Paris',
      96,
      (2.35, 48.86),
      group: aurora,
    ),
    _sample(
      'vless://$id@ch1.example.net:443?type=tcp&$reality#CH-1%20Zurich',
      '🇨🇭',
      'Zurich',
      112,
      (8.54, 47.37),
      group: aurora,
    ),
  ];
  // A month of sample history for the servers that answer, seeded by name so it is the same each
  // run. The usage sheet says these numbers are simulated.
  for (final s in servers.where((s) => s.latency != null)) {
    final random = math.Random(s.name.hashCode);
    for (var back = 29; back >= 0; back--) {
      if (random.nextDouble() < .35) continue;
      final down = (random.nextDouble() * 900 * 1024 * 1024).round();
      addUsage(s.usage, DateTime(now.year, now.month, now.day - back, 12), (
        up: down ~/ (18 + random.nextInt(20)),
        down: down,
      ));
    }
  }
  return servers;
}
