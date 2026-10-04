import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/share_link.dart';

Matcher rejects(Object reason) =>
    throwsA(isA<FormatException>().having((e) => e.message, 'message', reason));

void main() {
  test('vless reality link keeps its name, address and security', () {
    final p = parseShareLink(
      'vless://uuid@de2.example.net:443?security=reality&pbk=KEY&sid=ab&type=tcp'
      '&flow=xtls-rprx-vision#DE-2%20Frankfurt',
    );
    expect(
      (p.name, p.server, p.port, p.flow),
      ('DE-2 Frankfurt', 'de2.example.net', 443, 'xtls-rprx-vision'),
    );
    expect((p.tls.reality?.publicKey, p.tls.reality?.shortId), ('KEY', 'ab'));
    expect(describe(p), 'VLESS · Reality');
  });

  test('reality without a public key is rejected', () {
    expect(
      () => parseShareLink('vless://uuid@h.example:443?security=reality'),
      rejects('A Reality link needs a public key (pbk) and this one has none.'),
    );
  });

  test('a TCP link with an HTTP header is the HTTP transport', () {
    final p = parseShareLink(
      'vless://uuid@h.example:443?type=tcp&headerType=http&path=%2Fx',
    );
    expect(p.transport.kind, TransportKind.http);
  });

  test('websocket early data comes out of the path', () {
    final p = parseShareLink(
      'vless://uuid@h.example:443?type=ws&security=tls&path=%2Fws%3Fed%3D2048',
    );
    expect((p.transport.path, p.transport.maxEarlyData), ('/ws', 2048));
  });

  test('an unrunnable transport is rejected, not downgraded to TCP', () {
    expect(
      () => parseShareLink('vless://uuid@h.example:443?type=kcp'),
      rejects('mKCP is not a transport this core can run.'),
    );
  });

  test('trojan takes its password from where vless keeps the UUID', () {
    final p = parseShareLink(
      'trojan://pw@t.example:443?type=ws&security=tls#T',
    );
    expect((p.password, p.uuid, describe(p)), ('pw', '', 'Trojan · TLS · ws'));
  });

  test('vmess base64 JSON is decoded, gRPC service name from path', () {
    final body = base64.encode(
      utf8.encode(
        jsonEncode({
          'ps': 'FR',
          'add': 'fr.example',
          'port': '443',
          'id': 'uuid',
          'net': 'grpc',
          'path': 'tun',
          'tls': 'tls',
        }),
      ),
    );
    final p = parseShareLink('vmess://$body');
    expect(
      (p.name, p.server, p.transport.serviceName, describe(p)),
      ('FR', 'fr.example', 'tun', 'VMess · TLS · grpc'),
    );
  });

  test('wireguard needs the peer key and the interface addresses', () {
    final p = parseShareLink(
      'wireguard://priv@wg.example:51820?publickey=PUB&address=10.0.0.2%2F32&reserved=1,2,3#W',
    );
    expect(p.wireguard?.reserved, [1, 2, 3]);
    expect(describe(p), 'WireGuard · WARP');
    expect(
      () => parseShareLink('wireguard://priv@wg.example:51820?publickey=PUB'),
      throwsA(isA<FormatException>()),
    );
  });

  test('unsupported or broken links give a specific reason', () {
    expect(
      () => parseShareLink('hysteria2://pw@h.example:443'),
      rejects(
        'Hysteria2 is not supported yet — this build runs VLESS, VMess, Trojan and WireGuard.',
      ),
    );
    expect(
      () => parseShareLink('hello'),
      rejects('That does not look like a share link.'),
    );
    expect(
      () => parseShareLink('vless://uuid@h.example:70000'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a link without a port means 443, as on the desktop', () {
    expect(parseShareLink('vless://uuid@h.example?security=none').port, 443);
  });

  test('writing a profile and reading it back gives the same profile', () {
    for (final link in [
      'vless://uuid@de.example:443?type=tcp&security=reality&pbk=K&sid=s&sni=a.com&fp=chrome'
          '&flow=xtls-rprx-vision#DE%201',
      'vless://uuid@[2001:db8::1]:8443?type=ws&security=tls&path=%2Fws%3Fed%3D2048'
          '&host=cdn.example&alpn=h2,http%2F1.1&allowInsecure=1#v6',
      'vmess://uuid@fr.example:443?type=grpc&security=tls&serviceName=tun&encryption=auto#FR',
      'trojan://p%40ss@t.example:443?type=httpupgrade&security=tls&path=%2Fup#T',
      'vless://uuid@x.example:443?type=xhttp&security=tls&path=%2Fx&mode=packet-up#X',
      'wireguard://priv@wg.example:51820?publickey=PUB&address=10.0.0.2%2F32&mtu=1280#W',
    ]) {
      final p = parseShareLink(link);
      expect(
        jsonEncode(parseShareLink(toShareLink(p)).toJson()),
        jsonEncode(p.toJson()),
        reason: link,
      );
    }
  });

  test('an edited copy leaves the original alone', () {
    final p = parseShareLink(
      'vless://uuid@h.example:443?security=tls&alpn=h2#A',
    );
    final draft = p.copy()
      ..port = 8443
      ..tls.alpn.add('h3');
    expect(p.port, 443);
    expect(p.tls.alpn, ['h2']);
    expect(toShareLink(draft), contains(':8443?'));
  });
}
