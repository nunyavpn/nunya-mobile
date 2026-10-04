import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'mock_data.dart';
import 'usage.dart';

enum TunnelStatus { off, connecting, connected, disconnecting, failed }

/// The one owner of connection state. The UI calls [connect]/[disconnect] and
/// renders [status]; it never assumes a press succeeded. This preview fakes
/// the timings. The native bridge will keep this shape and report what
/// VpnService / NEPacketTunnelProvider actually established.
class PreviewTunnel extends ChangeNotifier {
  TunnelStatus status = TunnelStatus.off;
  String? error;
  DateTime? connectedAt;

  /// The server the tunnel was asked to run on; usage is filed under it.
  Server? server;

  /// Bytes carried since the tunnel came up, as the engine's stats report them: cumulative, so a
  /// reader takes differences (see usage.dart). The preview makes them up at a sample rate.
  Counters counters = (uplink: 0, downlink: 0);
  Timer? _traffic;
  final _random = math.Random();

  /// Android's VpnService.prepare consent; the preview asks only once per run.
  bool vpnAllowed = false;
  Timer? _pending;

  void allowVpn() => vpnAllowed = true;

  void connect(Server server) {
    _pending?.cancel();
    this.server = server;
    counters = (uplink: 0, downlink: 0);
    _set(TunnelStatus.connecting);
    _pending = Timer(const Duration(milliseconds: 1600), () {
      if (server.latency == null) {
        _set(TunnelStatus.failed, error: "${server.name} didn't answer");
      } else {
        connectedAt = DateTime.now();
        _set(TunnelStatus.connected);
        _traffic = Timer.periodic(const Duration(seconds: 1), (_) {
          counters = (
            uplink: counters.uplink + 50000 + _random.nextInt(20000),
            downlink: counters.downlink + 2200000 + _random.nextInt(400000),
          );
          notifyListeners();
        });
      }
    });
  }

  void disconnect() {
    _pending?.cancel();
    _set(TunnelStatus.disconnecting);
    _pending = Timer(
      const Duration(milliseconds: 500),
      () => _set(TunnelStatus.off),
    );
  }

  void _set(TunnelStatus next, {String? error}) {
    if (next != TunnelStatus.connected) _traffic?.cancel();
    status = next;
    this.error = error;
    if (next != TunnelStatus.connected) connectedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pending?.cancel();
    _traffic?.cancel();
    super.dispose();
  }
}
