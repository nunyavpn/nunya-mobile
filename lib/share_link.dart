/// Share links to profiles and back: a port of desktop Nunya's `src/share.ts`, which stays the
/// reference. This file is the one owner of import (see CLAUDE.md).
///
/// Share links are written by panels and other clients, not by a spec, so this is forgiving about
/// what it accepts and strict about what it reports: a link it cannot fully understand is rejected
/// with a reason rather than silently turned into a profile that fails later at connect time.
///
/// The transport is the part that goes wrong. A link carries it in `type=` (VLESS) or `net=`
/// (VMess), and `h2` is `http`, `raw` is plain TCP, and a TCP link with `headerType=http` is the
/// HTTP transport wearing TCP's name. Getting this wrong produces a config the core accepts and a
/// tunnel that never passes traffic, so the mapping is explicit and anything else is rejected.
///
/// Not ported yet: wg-quick configs (pasted or written for sharing).
library;

import 'dart:convert';

// Profiles are mutable on purpose: the editor works on a deep copy ([Profile.copy]) and writes
// fields straight into it, as the desktop's does, and closing without saving drops the copy.

class Reality {
  Reality({this.publicKey = '', this.shortId = ''});
  String publicKey, shortId;
  Map<String, Object?> toJson() => {'publicKey': publicKey, 'shortId': shortId};
  static Reality fromJson(Map j) => Reality(
    publicKey: j['publicKey'] as String,
    shortId: j['shortId'] as String,
  );
}

class TlsOptions {
  TlsOptions({
    this.enabled = false,
    this.sni = '',
    this.insecure = false,
    List<String>? alpn,
    this.fingerprint = '',
    this.reality,
  }) : alpn = alpn ?? [];
  bool enabled, insecure;
  String sni, fingerprint;
  List<String> alpn;
  Reality? reality;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sni': sni,
    'insecure': insecure,
    'alpn': alpn,
    'fingerprint': fingerprint,
    'reality': reality?.toJson(),
  };
  static TlsOptions fromJson(Map j) => TlsOptions(
    enabled: j['enabled'] as bool,
    sni: j['sni'] as String,
    insecure: j['insecure'] as bool,
    alpn: (j['alpn'] as List).cast<String>().toList(),
    fingerprint: j['fingerprint'] as String,
    reality: j['reality'] == null
        ? null
        : Reality.fromJson(j['reality'] as Map),
  );
}

enum Protocol {
  vless('VLESS'),
  vmess('VMess'),
  trojan('Trojan'),
  wireguard('WireGuard');

  const Protocol(this.label);

  /// Spelled the way each protocol spells itself: VLESS is an acronym, VMess is not.
  final String label;
}

/// XHTTP runs on Xray; the desktop runs the others on sing-box.
enum TransportKind {
  tcp('TCP'),
  ws('WebSocket'),
  grpc('gRPC'),
  http('HTTP/2'),
  httpupgrade('HTTPUpgrade'),
  quic('QUIC'),
  xhttp('XHTTP');

  const TransportKind(this.label);
  final String label;
}

class Transport {
  Transport({
    this.kind = TransportKind.tcp,
    this.path = '',
    this.host = '',
    this.serviceName = '',
    this.method = '',
    this.maxEarlyData = 0,
    this.earlyDataHeader = '',
    this.mode,
    this.extra,
  });
  TransportKind kind;

  /// ws, http, httpupgrade, xhttp.
  String path;

  /// The Host header (ws, httpupgrade) or the :authority (http).
  String host;

  /// grpc only.
  String serviceName;

  /// http only; empty means the core's default.
  String method;

  /// WebSocket early data in bytes, written into the path as `?ed=2048` by every panel. Left in
  /// the path it is a literal part of the URL and the server does not match it.
  int maxEarlyData;
  String earlyDataHeader;

  /// XHTTP only.
  String? mode;
  Map<String, Object?>? extra;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'path': path,
    'host': host,
    'serviceName': serviceName,
    'method': method,
    'maxEarlyData': maxEarlyData,
    'earlyDataHeader': earlyDataHeader,
    'mode': mode,
    'extra': extra,
  };
  static Transport fromJson(Map j) => Transport(
    kind: TransportKind.values.byName(j['kind'] as String),
    path: j['path'] as String,
    host: j['host'] as String,
    serviceName: j['serviceName'] as String,
    method: j['method'] as String,
    maxEarlyData: j['maxEarlyData'] as int,
    earlyDataHeader: j['earlyDataHeader'] as String,
    mode: j['mode'] as String?,
    extra: (j['extra'] as Map?)?.cast<String, Object?>(),
  );
}

/// What a WireGuard peer needs and nothing else does; kept apart because none of it means
/// anything to VLESS or VMess.
class WireguardOptions {
  WireguardOptions({
    this.privateKey = '',
    this.peerPublicKey = '',
    List<String>? localAddress,
    List<int>? reserved,
    this.mtu = 0,
    this.keepalive = 0,
  }) : localAddress = localAddress ?? [],
       reserved = reserved ?? [];
  String privateKey, peerPublicKey;

  /// The interface's own addresses, as CIDRs. WireGuard has no DHCP; the peer assigns these.
  List<String> localAddress;

  /// Cloudflare WARP's client identifier: three bytes, or empty for an ordinary peer.
  List<int> reserved;
  int mtu;

  /// Seconds between keepalives, or 0 to leave it to the core.
  int keepalive;

  Map<String, Object?> toJson() => {
    'privateKey': privateKey,
    'peerPublicKey': peerPublicKey,
    'localAddress': localAddress,
    'reserved': reserved,
    'mtu': mtu,
    'keepalive': keepalive,
  };
  static WireguardOptions fromJson(Map j) => WireguardOptions(
    privateKey: j['privateKey'] as String,
    peerPublicKey: j['peerPublicKey'] as String,
    localAddress: (j['localAddress'] as List).cast<String>().toList(),
    reserved: (j['reserved'] as List).cast<int>().toList(),
    mtu: j['mtu'] as int,
    keepalive: j['keepalive'] as int,
  );
}

class Profile {
  Profile({
    required this.protocol,
    required this.name,
    required this.server,
    required this.port,
    this.uuid = '',
    this.flow = '',
    this.security = '',
    this.alterId = 0,
    this.password = '',
    TlsOptions? tls,
    Transport? transport,
    this.wireguard,
  }) : tls = tls ?? TlsOptions(),
       transport = transport ?? Transport();
  Protocol protocol;
  String name, server;
  int port;
  String uuid;

  /// VLESS only: `xtls-rprx-vision` or empty.
  String flow;

  /// VMess only: the cipher, `auto` unless the link says otherwise.
  String security;

  /// VMess only. Non-zero selects the pre-AEAD scheme, which modern servers do not use.
  int alterId;

  /// Trojan only: the credential, which sits where VLESS and VMess put a UUID.
  String password;
  TlsOptions tls;
  Transport transport;
  WireguardOptions? wireguard;

  Map<String, Object?> toJson() => {
    'protocol': protocol.name,
    'name': name,
    'server': server,
    'port': port,
    'uuid': uuid,
    'flow': flow,
    'security': security,
    'alterId': alterId,
    'password': password,
    'tls': tls.toJson(),
    'transport': transport.toJson(),
    'wireguard': wireguard?.toJson(),
  };

  static Profile fromJson(Map j) => Profile(
    protocol: Protocol.values.byName(j['protocol'] as String),
    name: j['name'] as String,
    server: j['server'] as String,
    port: j['port'] as int,
    uuid: j['uuid'] as String,
    flow: j['flow'] as String,
    security: j['security'] as String,
    alterId: j['alterId'] as int,
    password: j['password'] as String,
    tls: TlsOptions.fromJson(j['tls'] as Map),
    transport: Transport.fromJson(j['transport'] as Map),
    wireguard: j['wireguard'] == null
        ? null
        : WireguardOptions.fromJson(j['wireguard'] as Map),
  );

  /// A deep copy, so an edit that is not saved changes nothing.
  Profile copy() => fromJson(jsonDecode(jsonEncode(toJson())) as Map);
}

FormatException _fail(String message) => FormatException(message);

const _supported = [
  Protocol.vless,
  Protocol.vmess,
  Protocol.trojan,
  Protocol.wireguard,
];

/// The protocols this build runs, written out for a rejection message, derived rather than
/// spelled so it cannot fall behind [_supported].
String _supportedNames() {
  final names = _supported.map((p) => p.label).toList();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// Schemes worth naming in an error, so a rejection says what the link is rather than "unknown".
const _knownSchemes = {
  'ss': 'Shadowsocks',
  'ssr': 'ShadowsocksR',
  'hysteria': 'Hysteria',
  'hysteria2': 'Hysteria2',
  'hy2': 'Hysteria2',
  'tuic': 'TUIC',
  'snell': 'Snell',
  'juicity': 'Juicity',
  'socks': 'SOCKS',
  'socks5': 'SOCKS',
  'http': 'HTTP',
  'https': 'HTTPS',
};

/// Link transport names to the core's. `kcp` and `meek` are deliberately absent: a link carrying
/// one is rejected rather than quietly downgraded to TCP, which would connect to the wrong thing.
const _transports = {
  '': TransportKind.tcp,
  'tcp': TransportKind.tcp,
  'raw': TransportKind.tcp,
  'none': TransportKind.tcp,
  'ws': TransportKind.ws,
  'websocket': TransportKind.ws,
  'grpc': TransportKind.grpc,
  'http': TransportKind.http,
  'h2': TransportKind.http,
  'h3': TransportKind.http,
  'httpupgrade': TransportKind.httpupgrade,
  'quic': TransportKind.quic,
  'xhttp': TransportKind.xhttp,
  'splithttp': TransportKind.xhttp,
};

const _unrunnable = {'kcp': 'mKCP', 'mkcp': 'mKCP', 'meek': 'meek'};

/// Pulls `?ed=N` out of a WebSocket path; the header name is the one every implementation agreed
/// on without it ever being written down.
({String path, int maxEarlyData, String earlyDataHeader}) _splitEarlyData(
  String rawPath,
) {
  final at = rawPath.indexOf('?');
  if (at < 0) return (path: rawPath, maxEarlyData: 0, earlyDataHeader: '');
  final params = Uri.splitQueryString(rawPath.substring(at + 1));
  final ed = int.tryParse(params['ed'] ?? '') ?? 0;
  if (ed <= 0) return (path: rawPath, maxEarlyData: 0, earlyDataHeader: '');
  return (
    path: rawPath.substring(0, at),
    maxEarlyData: ed,
    earlyDataHeader: (params['eh'] ?? '').isEmpty
        ? 'Sec-WebSocket-Protocol'
        : params['eh']!,
  );
}

/// Xray ignores unknown JSON keys, so they are refused here first.
const _xhttpExtra = {
  'host',
  'path',
  'mode',
  'headers',
  'xPaddingBytes',
  'noGRPCHeader',
  'noSSEHeader', //
  'scMaxEachPostBytes',
  'scMinPostsIntervalMs',
  'scMaxBufferedPosts',
  'scStreamUpServerSecs',
  'xmux',
};
const _xhttpXmux = {
  'maxConcurrency', 'maxConnections', 'cMaxReuseTimes', 'hMaxRequestTimes', //
  'hMaxReusableSecs', 'hKeepAlivePeriod',
};
const xhttpModes = ['auto', 'packet-up', 'stream-up', 'stream-one'];

Map<String, Object?> parseXhttpExtra(Object? raw) {
  var extra = raw;
  if (raw is String) {
    try {
      extra = jsonDecode(raw.isEmpty ? '{}' : raw);
    } on FormatException {
      throw _fail('XHTTP extra must be a JSON object.');
    }
  }
  if (extra is! Map) throw _fail('XHTTP extra must be a JSON object.');
  for (final key in extra.keys) {
    if (!_xhttpExtra.contains(key)) {
      throw _fail('XHTTP extra option "$key" is not supported.');
    }
  }
  final xmux = extra['xmux'];
  if (extra.containsKey('xmux')) {
    if (xmux is! Map) throw _fail('XHTTP xmux must be a JSON object.');
    for (final key in xmux.keys) {
      if (!_xhttpXmux.contains(key)) {
        throw _fail('XHTTP xmux option "$key" is not supported.');
      }
    }
  }
  return extra.cast<String, Object?>();
}

void validateXhttp(Transport t) {
  if (!xhttpModes.contains(t.mode ?? 'auto')) {
    throw _fail('XHTTP mode "${t.mode}" is not supported.');
  }
  parseXhttpExtra(t.extra ?? const {});
}

/// Builds the transport from the fields a link carries, whichever syntax it used to carry them.
Transport _transportFrom({
  required String kind,
  String? headerType,
  String? path,
  String? host,
  String? serviceName,
  String? method,
  String? mode,
  Object? extra,
}) {
  final named = kind.trim().toLowerCase();
  final unrunnable = _unrunnable[named];
  if (unrunnable != null) {
    throw _fail('$unrunnable is not a transport this core can run.');
  }
  final known = _transports[named];
  if (known == null) {
    throw _fail('Transport "$kind" is not one this build knows.');
  }

  // A TCP link with an HTTP header is the HTTP transport; the link just does not say so.
  final t = Transport(
    kind:
        known == TransportKind.tcp && (headerType ?? '').toLowerCase() == 'http'
        ? TransportKind.http
        : known,
  );
  final firstHost = (host ?? '').split(',').first.trim();
  final orRoot = (path ?? '').isEmpty ? '/' : path!;

  switch (t.kind) {
    case TransportKind.xhttp:
      t
        ..path = orRoot
        ..host = host ?? ''
        ..mode = (mode ?? '').isEmpty ? 'auto' : mode
        ..extra = parseXhttpExtra(extra ?? const <String, Object?>{});
      validateXhttp(t);
    case TransportKind.ws:
      final split = _splitEarlyData(orRoot);
      t
        ..path = split.path.isEmpty ? '/' : split.path
        ..host = firstHost
        ..maxEarlyData = split.maxEarlyData
        ..earlyDataHeader = split.earlyDataHeader;
    case TransportKind.grpc:
      // Panels put the service name in `serviceName`; the VMess JSON form has only `path`.
      final name = (serviceName ?? '').isNotEmpty ? serviceName! : path ?? '';
      t.serviceName = name.replaceFirst(RegExp('^/'), '');
    case TransportKind.http:
      t
        ..path = orRoot
        ..host = firstHost
        ..method = method ?? '';
    case TransportKind.httpupgrade:
      t
        ..path = orRoot
        ..host = firstHost;
    case TransportKind.quic || TransportKind.tcp:
      break;
  }
  return t;
}

TlsOptions _tlsFrom(
  String security, {
  String? sni,
  String? host,
  String? alpn,
  String? fp,
  String? pbk,
  String? sid,
  bool insecure = false,
}) {
  final kind = security.trim().toLowerCase();
  if (kind == 'reality' && (pbk ?? '').isEmpty) {
    // Without the server's public key a Reality handshake cannot even be attempted, and the
    // failure at connect time is opaque. Better to say so now.
    throw _fail(
      'A Reality link needs a public key (pbk) and this one has none.',
    );
  }
  return TlsOptions(
    enabled: kind == 'tls' || kind == 'reality' || kind == 'xtls',
    // Falling back to the transport host matches every other client: a link that sets only
    // `host` for a CDN expects it to be the SNI too.
    sni: (sni ?? '').isNotEmpty ? sni! : host ?? '',
    insecure: insecure,
    alpn: (alpn ?? '')
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList(),
    fingerprint: fp ?? '',
    reality: kind == 'reality'
        ? Reality(publicKey: pbk!, shortId: sid ?? '')
        : null,
  );
}

int _port(Object? value, [int fallback = 443]) {
  final raw = value == null || value == '' ? '$fallback' : '$value';
  final n = int.tryParse(raw);
  if (n == null || n < 1 || n > 65535) throw _fail('Port $value is not valid.');
  return n;
}

/// `1`, `true` and `yes` all appear in the wild for the same flag.
bool _truthy(String? value) =>
    const {'1', 'true', 'yes'}.contains((value ?? '').trim().toLowerCase());

String _decode(String encoded) {
  try {
    return Uri.decodeComponent(encoded);
  } on ArgumentError {
    return encoded;
  }
}

Uri _parseUri(String link) {
  try {
    return Uri.parse(link);
  } on FormatException {
    throw _fail('The link is malformed and could not be read.');
  }
}

/// The `protocol://uuid@host:port?params#name` form: VLESS always, Trojan with a password where
/// the UUID goes, and VMess when a panel writes the newer link instead of the base64 blob.
Profile _parseUrlForm(String link, Protocol protocol) {
  final url = _parseUri(link);
  final credential = _decode(url.userInfo);
  if (credential.isEmpty) {
    throw _fail(
      protocol == Protocol.trojan
          ? 'The Trojan link has no password before the @.'
          : 'The link has no UUID before the @.',
    );
  }
  final server = url.host;
  if (server.isEmpty) throw _fail('The link has no server address.');

  final q = url.queryParameters;
  final security = q['security'] ?? (q['tls'] == '1' ? 'tls' : 'none');
  final transport = _transportFrom(
    kind: q['type'] ?? q['net'] ?? 'tcp',
    headerType: q['headerType'],
    path: q['path'],
    host: q['host'],
    serviceName: q['serviceName'],
    method: q['method'],
    mode: q['mode'],
    extra: q['extra'],
  );

  if (transport.kind == TransportKind.xhttp) {
    if (protocol == Protocol.vless && (q['flow'] ?? '').isNotEmpty) {
      throw _fail('XHTTP requires VLESS flow to be empty.');
    }
    if (protocol == Protocol.vless &&
        q.containsKey('encryption') &&
        q['encryption'] != 'none') {
      throw _fail(
        'XHTTP VLESS encryption is not supported; encryption must be none.',
      );
    }
    if (protocol == Protocol.vmess &&
        (int.tryParse(q['alterId'] ?? '0') ?? 0) != 0) {
      throw _fail('XHTTP requires VMess AEAD (alterId 0).');
    }
  }

  final tls = _tlsFrom(
    security,
    sni: q['sni'],
    host: transport.host.isEmpty ? null : transport.host,
    alpn: q['alpn'],
    fp: q['fp'],
    pbk: q['pbk'],
    sid: q['sid'],
    insecure: _truthy(q['allowInsecure']) || _truthy(q['insecure']),
  );

  final name = _decode(url.fragment);
  return Profile(
    protocol: protocol,
    name: name.isEmpty ? server : name,
    server: server,
    port: _port(url.hasPort ? url.port : null),
    uuid: protocol == Protocol.trojan ? '' : credential,
    password: protocol == Protocol.trojan ? credential : '',
    flow: protocol == Protocol.vless ? q['flow'] ?? '' : '',
    security: protocol == Protocol.vmess
        ? ((q['encryption'] ?? '').isEmpty ? 'auto' : q['encryption']!)
        : '',
    alterId: protocol == Protocol.vmess
        ? int.tryParse(q['alterId'] ?? '') ?? 0
        : 0,
    tls: tls,
    transport: transport,
  );
}

/// Base64 that may be URL-safe and may have had its padding stripped.
String _decodeBase64(String raw) {
  final normal = raw
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      .replaceAll(RegExp(r'\s'), '');
  try {
    return utf8.decode(base64.decode(base64.normalize(normal)));
  } on FormatException {
    throw _fail('The VMess link is not valid base64.');
  }
}

/// The v2rayN form: `vmess://` then base64 of a flat JSON object. Every field arrives as a string
/// or a number depending on which tool wrote it, so nothing here trusts the type it is given.
Profile _parseVmessJson(String body) {
  final Map raw;
  try {
    raw = jsonDecode(_decodeBase64(body)) as Map;
  } on FormatException catch (e) {
    if (e.message == 'The VMess link is not valid base64.') rethrow;
    throw _fail('The VMess link does not contain readable JSON.');
  } on TypeError {
    throw _fail('The VMess link does not contain readable JSON.');
  }
  String str(String key) => raw[key] == null ? '' : '${raw[key]}';

  final server = str('add');
  if (server.isEmpty) {
    throw _fail('The VMess link has no server address (add).');
  }
  final uuid = str('id');
  if (uuid.isEmpty) throw _fail('The VMess link has no UUID (id).');

  final transport = _transportFrom(
    kind: str('net').isEmpty ? 'tcp' : str('net'),
    headerType: str('type'),
    mode: str('mode'),
    extra: raw['extra'],
    path: str('path'),
    host: str('host'),
    // The JSON form has no serviceName; gRPC puts it in `path`.
    serviceName: str('net').toLowerCase() == 'grpc' ? str('path') : null,
  );
  if (transport.kind == TransportKind.xhttp &&
      (int.tryParse(str('aid')) ?? 0) != 0) {
    throw _fail('XHTTP requires VMess AEAD (alterId 0).');
  }

  final tls = _tlsFrom(
    str('tls').isEmpty ? 'none' : str('tls'),
    sni: str('sni'),
    host: transport.host.isNotEmpty ? transport.host : str('host'),
    alpn: str('alpn'),
    fp: str('fp'),
    insecure: _truthy(str('allowInsecure')) || _truthy(str('skip-cert-verify')),
  );

  return Profile(
    protocol: Protocol.vmess,
    name: str('ps').isEmpty ? server : str('ps'),
    server: server,
    port: _port(str('port')),
    uuid: uuid,
    security: str('scy').isEmpty ? 'auto' : str('scy'),
    alterId: int.tryParse(str('aid')) ?? 0,
    tls: tls,
    transport: transport,
  );
}

/// `wireguard://privateKey@host:port?publickey=…&address=…`. `reserved` is Cloudflare WARP's
/// client id; wrong, the server drops the handshake rather than refusing it, so the tunnel comes
/// up and passes nothing.
Profile _parseWireguard(String link) {
  final url = _parseUri(link);
  final privateKey = _decode(url.userInfo);
  if (privateKey.isEmpty) {
    throw _fail('The WireGuard link has no private key before the @.');
  }
  final server = url.host;
  if (server.isEmpty) throw _fail('The link has no server address.');

  final q = url.queryParameters;
  final peer = q['publickey'] ?? q['publicKey'] ?? q['pbk'] ?? '';
  if (peer.isEmpty) {
    throw _fail(
      "A WireGuard link needs the peer's public key and this one has none.",
    );
  }
  final addresses = (q['address'] ?? q['ip'] ?? '')
      .split(',')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();
  if (addresses.isEmpty) {
    throw _fail(
      'A WireGuard link needs the addresses assigned to the interface (address=…) and this one '
      'has none.',
    );
  }
  final name = _decode(url.fragment);
  return Profile(
    protocol: Protocol.wireguard,
    name: name.isEmpty ? server : name,
    server: server,
    port: _port(url.hasPort ? url.port : null),
    tls: _tlsFrom('none'),
    wireguard: WireguardOptions(
      privateKey: privateKey,
      peerPublicKey: peer,
      localAddress: addresses,
      reserved: _parseReserved(q['reserved']),
      mtu: int.tryParse(q['mtu'] ?? '') ?? 0,
      keepalive: int.tryParse(q['keepalive'] ?? '') ?? 0,
    ),
  );
}

/// WARP's three-byte client id, written either as numbers or as base64.
List<int> _parseReserved(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return [];
  if (RegExp(r'^\d+(\s*,\s*\d+)*$').hasMatch(value)) {
    return value
        .split(',')
        .map((n) => int.parse(n.trim()))
        .where((n) => n >= 0 && n <= 255)
        .toList();
  }
  try {
    return base64.decode(
      base64.normalize(value.replaceAll('-', '+').replaceAll('_', '/')),
    );
  } on FormatException {
    // Neither is not worth failing the whole link over: an ordinary peer has none.
    return [];
  }
}

Profile parseShareLink(String raw) {
  final link = raw.trim();
  final at = link.indexOf('://');
  if (at <= 0) throw _fail('That does not look like a share link.');
  final scheme = link.substring(0, at).toLowerCase();

  // A marker the subscription reader emits for an entry whose outbounds dial through each other:
  // the protocol is one this build runs, it is the topology that is not.
  if (scheme == 'chain') {
    throw _fail(
      'This entry chains two proxies together, like WARP-over-WARP. This build runs a single hop.',
    );
  }
  final protocol = Protocol.values.where((p) => p.name == scheme).firstOrNull;
  if (protocol == null || !_supported.contains(protocol)) {
    final known = _knownSchemes[scheme];
    throw _fail(
      known != null
          ? '$known is not supported yet — this build runs ${_supportedNames()}.'
          : '"$scheme" is not a protocol this build knows.',
    );
  }
  return switch (protocol) {
    Protocol.wireguard => _parseWireguard(link),
    Protocol.trojan => _parseUrlForm(link, Protocol.trojan),
    // Both forms are in circulation. The URL one always has an @; the base64 blob never does.
    Protocol.vmess =>
      link.contains('@')
          ? _parseUrlForm(link, Protocol.vmess)
          : _parseVmessJson(link.substring(at + 3)),
    Protocol.vless => _parseUrlForm(link, Protocol.vless),
  };
}

/// Writes a profile back out as a share link: the inverse of [parseShareLink], whose contract is
/// that `parseShareLink(toShareLink(p))` gives back `p` — which is why WebSocket early data goes
/// back into the path it was lifted out of. Generated when shared, never kept from the paste, so
/// an edit made since import is what gets shared.
String toShareLink(Profile p) {
  final name = p.name.isEmpty ? '' : '#${Uri.encodeComponent(p.name)}';
  // An IPv6 literal needs brackets, or the port cannot be told from the address.
  final host = p.server.contains(':') && !p.server.startsWith('[')
      ? '[${p.server}]'
      : p.server;
  String query(Map<String, String> q) => Uri(queryParameters: q).query;

  if (p.protocol == Protocol.wireguard) {
    final wg = p.wireguard;
    if (wg == null) return 'wireguard://$host:${p.port}$name';
    final q = {
      'publickey': wg.peerPublicKey,
      if (wg.localAddress.isNotEmpty) 'address': wg.localAddress.join(','),
      if (wg.reserved.isNotEmpty) 'reserved': wg.reserved.join(','),
      if (wg.mtu != 0) 'mtu': '${wg.mtu}',
      if (wg.keepalive != 0) 'keepalive': '${wg.keepalive}',
    };
    return 'wireguard://${Uri.encodeComponent(wg.privateKey)}@$host:${p.port}?${query(q)}$name';
  }

  final t = p.transport;
  final q = <String, String>{
    'type': t.kind.name,
    'security': p.tls.reality != null
        ? 'reality'
        : p.tls.enabled
        ? 'tls'
        : 'none',
  };
  switch (t.kind) {
    case TransportKind.xhttp:
      validateXhttp(t);
      q['path'] = t.path.isEmpty ? '/' : t.path;
      if (t.host.isNotEmpty) q['host'] = t.host;
      q['mode'] = t.mode ?? 'auto';
      if (t.extra?.isNotEmpty ?? false) q['extra'] = jsonEncode(t.extra);
    case TransportKind.ws:
      q['path'] = t.maxEarlyData != 0
          ? '${t.path}?ed=${t.maxEarlyData}'
          : t.path;
      if (t.host.isNotEmpty) q['host'] = t.host;
    case TransportKind.httpupgrade:
      q['path'] = t.path;
      if (t.host.isNotEmpty) q['host'] = t.host;
    case TransportKind.http:
      q['path'] = t.path;
      if (t.host.isNotEmpty) q['host'] = t.host;
      if (t.method.isNotEmpty) q['method'] = t.method;
    case TransportKind.grpc:
      if (t.serviceName.isNotEmpty) q['serviceName'] = t.serviceName;
    case TransportKind.tcp || TransportKind.quic:
      break;
  }
  if (p.tls.enabled) {
    if (p.tls.sni.isNotEmpty) q['sni'] = p.tls.sni;
    if (p.tls.fingerprint.isNotEmpty) q['fp'] = p.tls.fingerprint;
    if (p.tls.alpn.isNotEmpty) q['alpn'] = p.tls.alpn.join(',');
    if (p.tls.insecure) q['allowInsecure'] = '1';
    if (p.tls.reality case final r?) {
      q['pbk'] = r.publicKey;
      if (r.shortId.isNotEmpty) q['sid'] = r.shortId;
    }
  }
  if (p.protocol == Protocol.vless && p.flow.isNotEmpty) q['flow'] = p.flow;
  if (p.protocol == Protocol.vmess) {
    q['encryption'] = p.security.isEmpty ? 'auto' : p.security;
    if (p.alterId != 0) q['alterId'] = '${p.alterId}';
  }
  final credential = Uri.encodeComponent(
    p.protocol == Protocol.trojan ? p.password : p.uuid,
  );
  return '${p.protocol.name}://$credential@$host:${p.port}?${query(q)}$name';
}

/// How a profile is described in the list and on the connection sheet: one implementation, so
/// the "Reality or TLS or neither" ladder is not grown separately per view.
String describe(Profile p) {
  // WireGuard has no TLS layer to report the absence of; whether the peer is WARP is the fact
  // worth saying, and the reserved client id is the only reliable sign of it.
  if (p.protocol == Protocol.wireguard) {
    return (p.wireguard?.reserved.isNotEmpty ?? false)
        ? 'WireGuard · WARP'
        : 'WireGuard';
  }
  final security = p.tls.reality != null
      ? 'Reality'
      : p.tls.enabled
      ? 'TLS'
      : 'no TLS';
  // TCP is the default and saying so adds nothing.
  return p.transport.kind == TransportKind.tcp
      ? '${p.protocol.label} · $security'
      : '${p.protocol.label} · $security · ${p.transport.kind.name}';
}
