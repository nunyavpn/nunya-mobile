import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'add_servers.dart';
import 'map_view.dart';
import 'mock_data.dart';
import 'server_sheets.dart';
import 'settings.dart';
import 'settings_sheets.dart';
import 'share_link.dart';
import 'usage.dart';
import 'splash.dart';
import 'tones.dart';
import 'tunnel.dart';
import 'whereabouts.dart';

void main() =>
    runApp(const NunyaApp(whereAmI: _screenshots ? _sampleLocation : locate));

/// A build for README screenshots (`--dart-define=NUNYA_SCREENSHOTS=true`) places the phone in
/// Milan, at a documentation address (RFC 5737), so a published picture never shows where the
/// person taking it is.
const _screenshots = bool.fromEnvironment('NUNYA_SCREENSHOTS');

Future<Whereabouts> _sampleLocation() async => const Whereabouts(
  ip: '203.0.113.7',
  country: 'IT',
  city: 'Milan',
  lat: 45.46,
  lon: 9.19,
  asn: 64500,
  org: 'Example Telecom',
);

class NunyaApp extends StatelessWidget {
  const NunyaApp({super.key, this.splash = true, this.whereAmI = locate});

  /// Off in widget tests, which drive the app itself rather than wait out a launch.
  final bool splash;

  /// How the phone is placed; a stand-in where there is no network, as in the screenshot tool.
  final Future<Whereabouts> Function() whereAmI;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nunya Preview',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: NunyaHome(splash: splash, whereAmI: whereAmI),
  );
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ground = dark ? const Color(0xFF0D1424) : const Color(0xFFF7F9FA);
  final surface = dark ? const Color(0xFF172235) : Colors.white;
  final ink = dark ? const Color(0xFFF6F8FD) : const Color(0xFF162033);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: ground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      surface: surface,
      onSurface: ink,
    ),
    textTheme: ThemeData(brightness: brightness).textTheme
        .apply(bodyColor: ink, displayColor: ink, fontFamily: 'Roboto'),
  );
}

class NunyaHome extends StatefulWidget {
  const NunyaHome({super.key, this.splash = true, this.whereAmI = locate});
  final bool splash;
  final Future<Whereabouts> Function() whereAmI;
  @override
  State<NunyaHome> createState() => _NunyaHomeState();
}

class _NunyaHomeState extends State<NunyaHome> {
  int tab = 0;
  late bool splashing = widget.splash;
  // The Home sheet's open/closed heights come from its content, measured after
  // layout, so they follow text size and state instead of guessed fractions.
  final sheet = DraggableScrollableController();
  final peekKey = GlobalKey(), fullKey = GlobalKey();
  double peek = 0, full = 0;
  double sheetMin = .5, sheetMax = .83;
  final settings = Settings();
  final log = AppLog();
  final servers = sampleServers(DateTime.now());
  late Server selected = servers.firstWhere((s) => s.group == aurora);
  Server? recent;
  final uses = <Server, int>{};
  String search = '';
  final tunnel = PreviewTunnel();
  late final Timer clock;

  /// This phone's public address and place, from a geo-IP lookup; null until one answers.
  Whereabouts? home;

  /// The tunnel's counters at the last reading; each reading files the difference.
  Counters lastCounters = (uplink: 0, downlink: 0);

  /// The status last logged, so the log gets one line per change rather than per counter tick.
  TunnelStatus loggedStatus = TunnelStatus.off;
  int homeTries = 0;
  Timer? homeRetry;

  @override
  void initState() {
    super.initState();
    settings.addListener(() => setState(() {}));
    tunnel.addListener(() {
      // Placed while connected the answer would be the exit, so a failed launch lookup is
      // retried once the tunnel is down again.
      if (status == TunnelStatus.off && home == null) locateHome();
      if (tunnel.server case final running? when connected) {
        addUsage(
          running.usage,
          DateTime.now(),
          advance(lastCounters, tunnel.counters),
        );
      }
      lastCounters = tunnel.counters;
      if (status != loggedStatus) {
        loggedStatus = status;
        final name = tunnel.server?.name ?? 'the server';
        log.add(switch (status) {
          TunnelStatus.connecting => '[tunnel] connecting to $name (preview)',
          TunnelStatus.connected =>
            '[tunnel] connected to $name (preview, no traffic routed)',
          TunnelStatus.disconnecting => '[tunnel] disconnecting',
          TunnelStatus.off => '[tunnel] off',
          TunnelStatus.failed => '[tunnel] could not connect: ${tunnel.error}',
        });
      }
      setState(() {});
    });
    locateHome();
    // Re-render the connected duration; derived from connectedAt, not counted.
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (status == TunnelStatus.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    clock.cancel();
    homeRetry?.cancel();
    tunnel.dispose();
    settings.dispose();
    log.dispose();
    sheet.dispose();
    super.dispose();
  }

  /// Waits before looking again after a failure, growing to the last and staying there: the
  /// services are blocked on some networks, not always the same ones minute to minute, and a
  /// phone with no network must not ask every second.
  static const homeRetryWaits = [1500, 3000, 6000, 12000, 30000, 60000];

  Future<void> locateHome() async {
    if (homeRetry != null || status != TunnelStatus.off) return;
    try {
      final found = await widget.whereAmI();
      if (!mounted || status != TunnelStatus.off) return;
      setState(() => home = found);
      // The place, not the address: logs end up pasted into public issues.
      log.add('[ui] this phone is in ${found.city ?? found.country}');
      homeTries = 0;
    } catch (e) {
      if (!mounted) return;
      if (homeTries == 0) {
        log.add("[ui] could not find this phone's location: $e");
      }
      final wait =
          homeRetryWaits[math.min(homeTries, homeRetryWaits.length - 1)];
      setState(
        () => homeTries++,
      ); // the splash's line says how the search is going
      homeRetry = Timer(Duration(milliseconds: wait), () {
        homeRetry = null;
        locateHome();
      });
    }
  }

  TunnelStatus get status => tunnel.status;
  bool get connected => status == TunnelStatus.connected;
  bool get active =>
      status == TunnelStatus.connecting || status == TunnelStatus.connected;

  Color get stateColor => switch (status) {
    TunnelStatus.connected => green,
    TunnelStatus.connecting || TunnelStatus.disconnecting => amber,
    TunnelStatus.failed => red,
    TunnelStatus.off => blue,
  };

  String get headline => switch (status) {
    TunnelStatus.off => 'Not connected',
    TunnelStatus.connecting => 'Connecting…',
    TunnelStatus.connected => 'Preview connected',
    TunnelStatus.disconnecting => 'Disconnecting…',
    TunnelStatus.failed => "Couldn't connect",
  };

  String get detail => switch (status) {
    TunnelStatus.off => 'Choose a server, then preview',
    TunnelStatus.connecting => 'Starting the tunnel · preview',
    TunnelStatus.connected => 'Simulation only · VPN inactive · $elapsed',
    TunnelStatus.disconnecting => 'Stopping the tunnel · preview',
    TunnelStatus.failed => '${tunnel.error} · preview',
  };

  String get elapsed {
    final d = DateTime.now().difference(tunnel.connectedAt ?? DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  bool get dark => context.dark;
  Color get surface => context.surface;
  Color get subtle => context.subtle;
  Color get line => context.line;
  Color get tile => context.tile;

  void notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );

  void toggleConnection() => active ? tunnel.disconnect() : connectTo(selected);

  Future<void> connectTo(Server server) async {
    // Explain before the OS consent dialog; a refusal here costs nothing.
    if (!tunnel.vpnAllowed) {
      if (await _consentSheet() != true) return;
      tunnel.allowVpn();
    }
    setState(() {
      selected = server;
      recent = server;
      uses[server] = (uses[server] ?? 0) + 1;
    });
    tunnel.connect(server);
  }

  void chooseServer(Server server) {
    setState(() {
      selected = server;
      tab = 0;
    });
    // Switching servers while on moves the tunnel, as on the desktop.
    if (active) connectTo(server);
  }

  /// An edit saved: the server takes its new profile, and a tunnel running on it is rebuilt,
  /// since it is still running against the old settings.
  void saveServer(Server old, Profile edited) {
    final next = old.withProfile(edited);
    final live = selected == old && active;
    replaceServer(old, next);
    if (live) tunnel.connect(next);
    notice('Saved ${next.name}');
    log.add('[ui] edited ${next.name}');
  }

  void replaceServer(Server old, Server next) => setState(() {
    servers[servers.indexOf(old)] = next;
    if (selected == old) selected = next;
    if (recent == old) recent = next;
    uses[next] = uses.remove(old) ?? 0;
  });

  void deleteServer(Server server) {
    if (selected == server && active) tunnel.disconnect();
    setState(() {
      servers.remove(server);
      uses.remove(server);
      if (recent == server) recent = null;
      if (selected == server && servers.isNotEmpty) selected = servers.first;
    });
    notice('Deleted ${server.name}');
    log.add('[ui] deleted ${server.name}');
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      _app(),
      // Over everything until the phone is placed, as the desktop's covers its window.
      if (splashing)
        Positioned.fill(
          child: Splash(
            ready: home != null,
            line: homeTries == 0
                ? 'Finding where you are…'
                : homeTries == 1
                ? 'Finding where you are — the first try did not answer…'
                : 'Still looking for where you are…',
            onDone: () => setState(() => splashing = false),
          ),
        ),
    ],
  );

  Widget _app() => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [_home(), _servers(), _settings()],
            ),
          ),
          if (tab != 0) _miniConnection(),
          _navigation(),
        ],
      ),
    ),
  );

  Widget _navigation() => Container(
    decoration: BoxDecoration(
      color: surface,
      border: Border(top: BorderSide(color: line)),
    ),
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    child: SizedBox(
      height: 64,
      child: Row(
        children: [
          _navItem(0, Icons.shield_outlined, 'Home'),
          _navItem(1, Icons.public, 'Servers'),
          _navItem(2, Icons.tune, 'Settings'),
        ],
      ),
    ),
  );

  Widget _navItem(int index, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => setState(() => tab = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: tab == index ? blue.withValues(alpha: .12) : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: tab == index ? blue : subtle, size: 22),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tab == index ? blue : subtle,
            ),
          ),
        ],
      ),
    ),
  );

  bool get expanded => sheet.isAttached && sheet.size > sheetMin + .01;

  void toggleSheet() => sheet.animateTo(
    expanded ? sheetMin : sheetMax,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );

  void _measure() {
    double height(GlobalKey key) =>
        (key.currentContext?.findRenderObject() as RenderBox?)?.size.height ??
        0;
    final p = height(peekKey), f = height(fullKey);
    if (mounted && (p != peek || f != full)) {
      setState(() {
        peek = p;
        full = f;
      });
    }
  }

  Widget _home() => LayoutBuilder(
    builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      final room = constraints.maxHeight;
      final wasExpanded = expanded;
      final oldMin = sheetMin;
      sheetMax = full == 0 ? .83 : (full / room).clamp(.2, .83);
      sheetMin = peek == 0 ? sheetMax : (peek / room).clamp(.1, sheetMax);
      // A closed sheet keeps its old size when its content changes (e.g. Quick
      // connect hides once connected); put it back at the new closed height.
      if (sheetMin != oldMin && !wasExpanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (sheet.isAttached) sheet.jumpTo(sheetMin);
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: MapView(
              dark: dark,
              covered: peek,
              onPick: (key) => key == homeKey
                  ? _homeSheet()
                  : pickPlace(key as (double, double)),
              pins: [
                for (final (lon, lat) in places.keys)
                  if (selected.location != (lon, lat))
                    MapPin(lon, lat, key: (lon, lat)),
                if (home case final me?)
                  MapPin(
                    me.lon,
                    me.lat,
                    key: homeKey,
                    home: true,
                    here: !connected,
                    label: connected ? null : 'You · ${me.city ?? me.country}',
                  ),
                if (selected.location case (final lon, final lat))
                  MapPin(
                    lon,
                    lat,
                    key: (lon, lat),
                    label: selected.city,
                    active: connected,
                  ),
              ],
              route: [
                if ((home, selected.location) case (final me?, final exit?)
                    when connected) ...[
                  (me.lon, me.lat),
                  exit,
                ],
              ],
            ),
          ),
          Positioned(top: 10, left: 16, child: _chip()),
          Positioned(top: 10, right: 16, child: _demoBadge()),
          DraggableScrollableSheet(
            controller: sheet,
            initialChildSize: sheetMin,
            minChildSize: sheetMin,
            maxChildSize: sheetMax,
            snap: true,
            builder: (context, scroll) => Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .12),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scroll,
                physics: const ClampingScrollPhysics(),
                child: _connectionSheet(),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _chip() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .1), blurRadius: 14),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status == TunnelStatus.off ? subtle : stateColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(switch (status) {
          TunnelStatus.connected => 'Preview on',
          TunnelStatus.connecting => 'Connecting',
          TunnelStatus.disconnecting => 'Stopping',
          TunnelStatus.failed => 'Failed',
          TunnelStatus.off => 'Off',
        }, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _demoBadge() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Center(
      child: Text(
        'DEMO · NO VPN',
        style: TextStyle(
          color: subtle,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    ),
  );

  Widget _connectionSheet() => Padding(
    key: fullKey,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: peekKey,
          padding: const EdgeInsets.only(bottom: 22),
          child: _sheetPeek(),
        ),
        _sheetDetails(),
        const SizedBox(height: 22),
      ],
    ),
  );

  Widget _sheetPeek() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: toggleSheet,
        child: SizedBox(
          height: 30,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
      Row(
        children: [
          _stateIcon(52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: status == TunnelStatus.off ? null : stateColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(detail, style: TextStyle(color: subtle, fontSize: 13)),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: sheet,
            builder: (context, _) => IconButton(
              onPressed: toggleSheet,
              tooltip: expanded ? 'Show less' : 'Show more',
              icon: Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: subtle,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      InkWell(
        onTap: () => setState(() => tab = 1),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tile,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Text(selected.flag, style: const TextStyle(fontSize: 25)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${selected.group} · ${selected.protocol}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtle, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              _ping(selected.latency),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: subtle),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton.icon(
          key: const Key('connectionButton'),
          onPressed: status == TunnelStatus.disconnecting
              ? null
              : toggleConnection,
          style: FilledButton.styleFrom(
            backgroundColor: switch (status) {
              TunnelStatus.connected => red,
              TunnelStatus.connecting => amber,
              _ => green,
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: active && !connected
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.power_settings_new, size: 20),
          label: Text(switch (status) {
            TunnelStatus.connected => 'End preview',
            TunnelStatus.connecting => 'Cancel',
            TunnelStatus.disconnecting => 'Disconnecting…',
            TunnelStatus.failed => 'Try again',
            TunnelStatus.off => 'Preview connection',
          }, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
      if (!connected && servers.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionLabel('QUICK CONNECT'),
        const SizedBox(height: 9),
        Row(
          children: [
            _quick(Icons.bolt, 'Fastest', _fastest),
            const SizedBox(width: 8),
            _quick(Icons.bar_chart, 'Most used', _mostUsed),
            const SizedBox(width: 8),
            _quick(Icons.history, 'Recent', recent),
          ],
        ),
      ],
    ],
  );

  Widget _sheetDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionLabel('TRAFFIC · SAMPLE'),
      const SizedBox(height: 9),
      Row(
        children: [
          _stat(
            'Down',
            connected ? '2.31 MB/s' : '0 B/s',
            Icons.arrow_downward,
          ),
          const SizedBox(width: 9),
          _stat('Up', connected ? '58.4 KB/s' : '0 B/s', Icons.arrow_upward),
        ],
      ),
      const SizedBox(height: 18),
      _sectionLabel('CONNECTION · SAMPLE'),
      const SizedBox(height: 9),
      _fact('Exit', '${selected.flag} ${selected.city} · Example Hosting'),
      _fact('Server', '${selected.host}:${selected.port}'),
      _fact('IPv4', '192.0.2.4'),
      _fact('IPv6', '2001:db8::24'),
      _fact('Protocol', selected.protocol),
    ],
  );

  Widget _stateIcon(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: stateColor.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(
      switch (status) {
        TunnelStatus.connected => Icons.verified_user_outlined,
        TunnelStatus.failed => Icons.gpp_maybe_outlined,
        _ => Icons.shield_outlined,
      },
      color: stateColor,
      size: 26,
    ),
  );

  Server? get _fastest => _fastestOf(servers);

  /// The fastest server that answered; an untested or unreachable one is not "fastest".
  Server? _fastestOf(List<Server> list) => list
      .where((s) => s.latency != null)
      .fold<Server?>(
        null,
        (best, s) => best == null || s.latency! < best.latency! ? s : best,
      );

  Server? get _mostUsed => uses.isEmpty
      ? null
      : uses.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  /// A tile whose server is the selected one is marked as the list's selected row is: the same
  /// server can be Fastest, Most used and Recent at once, and all three then say so.
  Widget _quick(IconData icon, String title, Server? server) {
    final picked = server != null && server == selected;
    return Expanded(
      child: InkWell(
        onTap: server == null ? null : () => chooseServer(server),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          key: ValueKey('quick:$title${picked ? ':selected' : ''}'),
          height: 75,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: picked ? green.withValues(alpha: dark ? .14 : .09) : tile,
            border: Border.all(
              color: picked ? green : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                picked ? Icons.check_circle : icon,
                color: picked ? green : blue,
                size: 18,
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                server?.name ?? 'None yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: subtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String title, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: blue),
              const SizedBox(width: 5),
              Text(title, style: TextStyle(color: subtle, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: TextStyle(color: subtle, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _miniConnection() => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    decoration: BoxDecoration(
      color: surface,
      border: Border(top: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        _stateIcon(40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: status == TunnelStatus.off ? null : stateColor,
                ),
              ),
              Text(
                '${selected.name} · no VPN',
                style: TextStyle(color: subtle, fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: FilledButton(
            onPressed: status == TunnelStatus.disconnecting
                ? null
                : toggleConnection,
            style: FilledButton.styleFrom(
              backgroundColor: switch (status) {
                TunnelStatus.connected => red,
                TunnelStatus.connecting => amber,
                _ => green,
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: Text(switch (status) {
              TunnelStatus.connected => 'End',
              TunnelStatus.connecting => 'Cancel',
              TunnelStatus.disconnecting => 'Stopping',
              _ => 'Preview',
            }),
          ),
        ),
      ],
    ),
  );

  Widget _servers() => Column(
    children: [
      _title(
        'Servers',
        action: IconButton.filled(
          onPressed: _addSheet,
          icon: const Icon(Icons.add),
          tooltip: 'Add servers',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: TextField(
          key: const Key('serverSearch'),
          onChanged: (value) => setState(() => search = value),
          decoration: InputDecoration(
            hintText: 'Search name, country or city',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: tile,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final group in {for (final s in servers) s.group})
              if (_matching(group).isNotEmpty) ...[
                _serverGroup(group, _groupSummary(group)),
                if (group == aurora) _usageBar(),
                ..._matching(group).map(_serverRow),
              ],
            if (servers.every((s) => _matching(s.group).isEmpty))
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    servers.isEmpty
                        ? 'No servers yet · tap + to add'
                        : 'No matching servers',
                    style: TextStyle(color: subtle),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ],
  );

  String _groupSummary(String group) {
    final n = servers.where((s) => s.group == group).length;
    return '$n server${n == 1 ? '' : 's'} · '
        '${group == aurora ? 'sample subscription' : 'added by hand'}';
  }

  Widget _usageBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: .62,
            minHeight: 5,
            backgroundColor: line,
            color: blue,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '310 GB of 500 GB · resets Oct 22 · sample',
          style: TextStyle(color: subtle, fontSize: 11),
        ),
      ],
    ),
  );

  List<Server> _matching(String group) => servers
      .where(
        (s) =>
            s.group == group &&
            '${s.name} ${s.city} ${s.protocol}'.toLowerCase().contains(
              search.toLowerCase(),
            ),
      )
      .toList();

  Widget _serverGroup(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 5),
    child: Row(
      children: [
        Icon(Icons.keyboard_arrow_down, size: 19, color: subtle),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(subtitle, style: TextStyle(color: subtle, fontSize: 11)),
            ],
          ),
        ),
        if (title == aurora)
          IconButton(
            onPressed: () =>
                notice('Sample subscription · no update performed'),
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh group',
          ),
        IconButton(
          onPressed: () => notice('Group actions are a preview'),
          icon: const Icon(Icons.more_horiz, size: 22),
          tooltip: '$title actions',
        ),
      ],
    ),
  );

  /// The map key of the user's own dot; no server place can equal it.
  static const homeKey = #home;

  /// The details behind the user's dot: who websites see while there is no tunnel.
  void _homeSheet() {
    final me = home;
    if (me == null) return;
    final network = [
      me.org,
      if (me.asn != null) 'AS${me.asn}',
    ].nonNulls.join(' · ');
    _sheet(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(me.flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [me.city, me.country].nonNulls.join(', '),
                      style: TextStyle(color: subtle, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fact('Public IP', me.ip),
          _fact('ISP', network.isEmpty ? 'unknown' : network),
          _fact('City', me.city ?? 'unknown'),
          _fact('Country', me.country),
          const SizedBox(height: 6),
          // Measured with the tunnel down and kept while it is up: who the user is *without* it.
          // The preview routes nothing, so it says so rather than the desktop's "websites see the
          // exit instead".
          Text(
            connected
                ? 'Measured before connecting. The preview routes nothing, so '
                      'websites still see this.'
                : 'What websites see while you are not connected.',
            style: TextStyle(color: subtle, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  /// Servers by where they exit, one map dot each: a city routinely has several.
  Map<(double, double), List<Server>> get places {
    final byPlace = <(double, double), List<Server>>{};
    for (final s in servers) {
      if (s.location case final at?) (byPlace[at] ??= []).add(s);
    }
    return byPlace;
  }

  /// A dot with one server picks it, as on the desktop. With several, picking by the dot would be
  /// a coin toss, so they rise in a sheet: on a phone the desktop's card over the map is a sheet.
  void pickPlace((double, double) place) {
    final here = places[place] ?? const <Server>[];
    if (here.length == 1) return chooseServer(here.single);
    if (here.isEmpty) return;
    final best = _fastestOf(here);
    _sheet(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            here.first.city,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            '${here.length} servers',
            style: TextStyle(color: subtle, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: best == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      chooseServer(best);
                    },
              icon: const Icon(Icons.bolt, size: 20),
              label: Text(
                best == null ? 'None answered' : 'Fastest · ${best.name}',
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final server in here)
            _serverRow(
              server,
              onTap: () {
                Navigator.pop(context);
                chooseServer(server);
              },
            ),
        ],
      ),
    );
  }

  Widget _serverRow(Server server, {VoidCallback? onTap}) {
    final active = selected == server;
    return Container(
      color: active ? green.withValues(alpha: dark ? .14 : .09) : null,
      child: InkWell(
        onTap: onTap ?? () => chooseServer(server),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
          child: Row(
            children: [
              Text(server.flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (server.cdn) ...[
                          const SizedBox(width: 5),
                          Text(
                            'CDN CF',
                            style: TextStyle(
                              fontSize: 9,
                              color: blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${server.city} · ${server.protocol}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: subtle),
                    ),
                  ],
                ),
              ),
              _ping(server.latency),
              IconButton(
                onPressed: () => _actionsSheet(server),
                icon: const Icon(Icons.more_horiz, size: 22),
                tooltip: 'Actions for ${server.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ping(int? ms) => Text(
    ms == null ? '—' : '$ms ms',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: ms == null
          ? subtle
          : ms < 80
          ? green
          : const Color(0xFFDBA63A),
    ),
  );

  /// Settings are read when the tunnel starts, so they are locked while it runs (see LockedNote).
  bool get settingsLocked =>
      status != TunnelStatus.off && status != TunnelStatus.failed;

  void _settingsSheet(Widget sheet) => showServerSheet<void>(context, sheet);

  Widget _settings() {
    final locked = settingsLocked;
    // The preview fetches no block lists, so neither switch is ever blocking anything yet.
    const noList = (updatedAt: null, busy: false, error: null);
    final now = DateTime.now();
    return ListView(
      children: [
        _title('Settings'),
        if (locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const Expanded(child: LockedNote()),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: tunnel.disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ),
        _sectionLabel('CONNECTION', inset: true),
        _settingsCard([
          _setting(
            Icons.public,
            'Bypass rules',
            'Leave on your normal connection',
            '${settings.bypass.length}',
            () => _settingsSheet(BypassSheet(settings, locked: locked)),
          ),
          _setting(
            Icons.cloud_outlined,
            'DNS',
            settings.dns,
            '',
            () => _settingsSheet(DnsSheet(settings, locked: locked)),
          ),
        ]),
        _sectionLabel('BLOCKING', inset: true),
        _settingsCard([
          _switchSetting(
            Icons.block,
            'Ad blocker',
            'ad networks · ${listLine(settings.blockAds, noList, now)}',
            settings.blockAds,
            locked ? null : (v) => settings.update(() => settings.blockAds = v),
          ),
          _switchSetting(
            Icons.visibility_off_outlined,
            'Anti-tracker',
            'tracking built into systems, devices and apps · '
                '${listLine(settings.blockTrackers, noList, now)}',
            settings.blockTrackers,
            locked
                ? null
                : (v) => settings.update(() => settings.blockTrackers = v),
          ),
        ]),
        // VPN-only, so this is always the coverage; the desktop says otherwise in proxy mode.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Text(
            'Applies to everything on this phone while connected.',
            style: TextStyle(color: subtle, fontSize: 11.5),
          ),
        ),
        _sectionLabel('APP', inset: true),
        _settingsCard([
          _setting(
            Icons.monitor_heart_outlined,
            'Diagnostics',
            'Log, config, engine',
            '',
            () => _settingsSheet(
              DiagnosticsSheet(settings: settings, log: log, tunnel: tunnel),
            ),
          ),
          _setting(
            Icons.favorite_border,
            'Support Nunya',
            null,
            '',
            () => _settingsSheet(const SupportSheet()),
          ),
          _setting(
            Icons.info_outline,
            'About',
            '$appVersion · preview',
            '',
            () => _settingsSheet(const AboutSheet()),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: OutlinedButton(
            // Bypass rules are the user's list, not a setting, so they survive this.
            onPressed: locked
                ? null
                : () {
                    settings.reset();
                    notice('Settings reset to defaults');
                  },
            child: const Text('Reset to defaults'),
          ),
        ),
      ],
    );
  }

  Widget _title(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -.8,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _sectionLabel(String label, {bool inset = false}) => Padding(
    padding: EdgeInsets.fromLTRB(
      inset ? 18 : 0,
      inset ? 15 : 0,
      0,
      inset ? 8 : 0,
    ),
    child: Text(
      label,
      style: TextStyle(
        color: subtle,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    ),
  );

  Widget _settingsCard(List<Widget> rows) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: surface,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) Divider(height: 1, indent: 54, color: line),
        ],
      ],
    ),
  );

  Widget _setting(
    IconData icon,
    String title,
    String? subtitle,
    String value,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(13, 14, 12, 14),
      child: Row(
        children: [
          _settingsIcon(icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: subtle)),
                ],
              ],
            ),
          ),
          Text(value, style: TextStyle(fontSize: 12, color: subtle)),
          Icon(Icons.chevron_right, size: 18, color: subtle),
        ],
      ),
    ),
  );

  Widget _switchSetting(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
    child: Row(
      children: [
        _settingsIcon(icon),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 11, color: subtle)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );

  Widget _settingsIcon(IconData icon) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: blue.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, color: blue, size: 17),
  );

  void _actionsSheet(Server server) => _sheet(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(server.flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${server.host}:${server.port} · ${server.protocol}',
                    style: TextStyle(color: subtle, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _action(Icons.power_settings_new, 'Connect', () {
          Navigator.pop(context);
          setState(() => tab = 0);
          connectTo(server);
        }),
        _action(Icons.refresh, 'Check', () {
          Navigator.pop(context);
          notice(
            server.latency == null
                ? 'No answer from ${server.name} · sample'
                : '${server.name}: ${server.latency} ms · sample',
          );
        }),
        _action(Icons.bar_chart, 'Usage', () {
          Navigator.pop(context);
          showServerSheet<void>(context, UsageSheet(server, live: tunnel));
        }),
        _action(Icons.share_outlined, 'Share', () {
          Navigator.pop(context);
          showServerSheet<void>(context, ShareServerSheet(server));
        }),
        _action(Icons.edit_outlined, 'Edit', () {
          Navigator.pop(context);
          showServerSheet<void>(
            context,
            EditServerSheet(server, onSave: (p) => saveServer(server, p)),
          );
        }),
        Divider(color: line),
        _action(Icons.delete_outline, 'Delete…', () {
          Navigator.pop(context);
          _deleteDialog(server);
        }, color: red),
      ],
    ),
  );

  Future<void> _deleteDialog(Server server) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${server.name}?'),
        content: Text(
          selected == server && active
              ? 'You are connected through it. Nunya disconnects first.'
              : 'You can add it again from its share link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) deleteServer(server);
  }

  void _addSheet() => showServerSheet<void>(
    context,
    AddServersSheet(
      onAdd: (added) {
        setState(() => servers.insertAll(0, added));
        notice('Added ${added.length} · kept in memory only');
        log.add('[ui] added ${added.map((s) => s.name).join(', ')}');
      },
    ),
  );

  Future<bool?> _consentSheet() {
    final os = Theme.of(context).platform == TargetPlatform.iOS
        ? 'iOS'
        : 'Android';
    Widget fact(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: blue),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: subtle, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
    return _sheet<bool>(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shield_outlined, color: blue),
          ),
          const SizedBox(height: 16),
          const Text(
            'Allow the VPN',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'To carry every app on this phone through the tunnel, $os has to '
            'let Nunya set up a VPN. It asks you once.',
            style: TextStyle(color: subtle, height: 1.45, fontSize: 15),
          ),
          Divider(height: 28, color: line),
          fact(
            Icons.check,
            '$os asks, not Nunya.',
            "The next screen is the system's own; you can turn it off in "
                'Settings any time.',
          ),
          fact(
            Icons.visibility_off_outlined,
            'Nothing leaves this phone.',
            'No account, no telemetry. Your servers stay on the device.',
          ),
          fact(
            Icons.science_outlined,
            'This build is a preview.',
            'Continue skips the system screen; no VPN is set up yet.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const Key('allowVpn'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) => ListTile(
    leading: Icon(icon, size: 21, color: color ?? subtle),
    title: Text(
      title,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
    ),
    onTap: onTap,
  );

  Future<T?> _sheet<T>(Widget child) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}
