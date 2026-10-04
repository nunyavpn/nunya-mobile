/// The app's settings and its log, each with one owner that widgets send changes to. Ported from
/// desktop Nunya's `store.ts` (settings, bypass rules), `blocking.ts` and the log the desktop's
/// Diagnostics panel shows.
///
/// The phone is VPN-only, so the desktop's proxy settings (mode, port, LAN, system proxy) have no
/// counterpart. Its tunnel settings (stack, MTU, address, strict route, IPv6) wait for the native
/// tunnel, since what they mean depends on VpnService and the packet tunnel extension.
///
/// Kept in memory for now, like the servers. They persist together once protected storage lands.
library;

import 'package:flutter/foundation.dart';

enum BypassKind { domain, address, range }

class BypassRule {
  const BypassRule(this.kind, this.value);
  final BypassKind kind;
  final String value;
}

/// Ranges the tunnel already leaves alone, shown so nobody re-adds them and wonders why nothing
/// changed.
const alwaysDirect = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16',
];

enum LogLevel { error, info, debug }

class Settings extends ChangeNotifier {
  static const defaultDns = 'https://1.1.1.1/dns-query';

  /// Resolver for names that are not bypassed. Queries go through the tunnel.
  String dns = defaultDns;
  LogLevel logLevel = LogLevel.info;

  /// Off: a third party's list deciding what may load is something to opt into, and a site it
  /// breaks should not be a mystery to someone who never turned it on.
  bool blockAds = false, blockTrackers = false;

  /// Traffic that leaves on the normal connection. Deliberately no inverse ("only these through
  /// the VPN"): two directions means reading every rule twice, and the inverse quietly turns a
  /// tunnel back into a proxy.
  final List<BypassRule> bypass = [];

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  /// False when the value does not classify, or is already a rule.
  bool addBypass(String raw) {
    final value = raw.trim();
    final kind = classifyBypass(value);
    if (kind == null || bypass.any((r) => r.value == value)) return false;
    update(() => bypass.add(BypassRule(kind, value)));
    return true;
  }

  void removeBypass(BypassRule rule) => update(() => bypass.remove(rule));

  /// Everything back as it ships. Bypass rules are the user's list, not a setting, so they stay.
  void reset() => update(() {
    dns = defaultDns;
    logLevel = LogLevel.info;
    blockAds = false;
    blockTrackers = false;
  });
}

/// One field for three kinds: a slash makes it a range, four dotted numbers an address, anything
/// else a domain. Null is what keeps the Add button disabled.
BypassKind? classifyBypass(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.contains('/')) {
    final [address, bits, ...rest] = [...value.split('/'), ''];
    final prefix = int.tryParse(bits);
    final ok =
        rest.every((r) => r.isEmpty) &&
        _isIPv4(address) &&
        prefix != null &&
        prefix >= 0 &&
        prefix <= 32;
    return ok ? BypassKind.range : null;
  }
  if (_isIPv4(value)) return BypassKind.address;
  // A domain, optionally with the wildcard prefix people copy out of other clients.
  final bare = value.startsWith('*.') ? value.substring(2) : value;
  // The last label must have a letter: no TLD is all digits, so "300.1.1.1" is a mistyped address,
  // not a domain. (The desktop's check lets it through as a domain that matches nothing.)
  final tld = bare.split('.').last;
  if (!RegExp('[a-z]', caseSensitive: false).hasMatch(tld)) return null;
  return RegExp(
        r'^(?!-)[a-z0-9-]+(\.[a-z0-9-]+)+$',
        caseSensitive: false,
      ).hasMatch(bare)
      ? BypassKind.domain
      : null;
}

bool _isIPv4(String value) {
  final parts = value.split('.');
  return parts.length == 4 &&
      parts.every(
        (p) => RegExp(r'^\d{1,3}$').hasMatch(p) && int.parse(p) <= 255,
      );
}

/// Where a block list stands: on disk since when, being fetched, or failed.
typedef ListState = ({DateTime? updatedAt, bool busy, String? error});

/// What a blocking switch's row says about its list. A switch can be on while blocking nothing —
/// its list is left out until downloaded — and the row says so rather than letting "on" stand for
/// a promise nobody is keeping.
String listLine(bool on, ListState state, DateTime now) {
  if (state.busy) {
    return state.updatedAt == null
        ? 'downloading the list…'
        : 'updating the list…';
  }
  final updatedAt = state.updatedAt;
  if (updatedAt == null) {
    if (!on) return 'the list is downloaded when you turn it on';
    return state.error != null
        ? 'not blocking yet: the list could not be downloaded (${state.error}); it is tried '
              'again through the tunnel when you connect'
        : 'not blocking yet: the list has not been downloaded';
  }
  final age = 'list updated ${_ago(now.difference(updatedAt))}';
  // A stale list still blocks; a failed refresh is worth a mention, not an alarm.
  return state.error != null
      ? '$age; the last update failed (${state.error})'
      : age;
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
}

/// What the app has done, for Diagnostics. Lines name servers, never their addresses' secrets:
/// nothing here may carry a credential, a share link or a subscription URL, because people paste
/// logs into public issues.
class AppLog extends ChangeNotifier {
  /// Enough to cover a session's story without growing without bound.
  static const keep = 500;
  final lines = <String>[];

  void add(String line) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if (lines.length > keep) lines.removeRange(0, lines.length - keep);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}
