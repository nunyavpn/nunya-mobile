class MockServer {
  const MockServer(
    this.name,
    this.flag,
    this.city,
    this.protocol,
    this.latency, {
    this.cdn = false,
  });
  final String name, flag, city, protocol;
  final int? latency;
  final bool cdn;
}

const personalServers = <MockServer>[
  MockServer('DE-1 Frankfurt', '🇩🇪', 'Frankfurt', 'VLESS · Reality', 24),
  MockServer(
    'NL-2 Amsterdam',
    '🇺🇸',
    'Ashburn · via NL',
    'VLESS · TLS · ws',
    138,
    cdn: true,
  ),
  MockServer('IR-1 Tehran', '🇮🇷', 'Tehran', 'VLESS · no TLS', null),
];

const auroraServers = <MockServer>[
  MockServer('FI-1 Helsinki', '🇫🇮', 'Helsinki', 'VLESS · Reality', 31),
  MockServer('SE-1 Stockholm', '🇸🇪', 'Stockholm', 'VLESS · Reality', 44),
  MockServer(
    'GB-3 London',
    '🇬🇧',
    'London',
    'VLESS · TLS · ws',
    71,
    cdn: true,
  ),
  MockServer('FR-2 Paris', '🇫🇷', 'Paris', 'VMess · TLS · grpc', 96),
  MockServer('CH-1 Zurich', '🇨🇭', 'Zurich', 'VLESS · Reality', 112),
];

const allServers = <MockServer>[...personalServers, ...auroraServers];
