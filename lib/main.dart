import 'package:flutter/material.dart';

import 'map_view.dart';
import 'mock_data.dart';

void main() => runApp(const NunyaApp());

const green = Color(0xFF16B77D);
const blue = Color(0xFF2487F3);
const red = Color(0xFFE84D5B);

class NunyaApp extends StatelessWidget {
  const NunyaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nunya Preview',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const NunyaHome(),
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
  const NunyaHome({super.key});
  @override
  State<NunyaHome> createState() => _NunyaHomeState();
}

class _NunyaHomeState extends State<NunyaHome> {
  int tab = 0;
  bool previewConnected = false;
  bool expanded = false;
  bool adBlock = true;
  bool antiTracker = false;
  MockServer selected = auroraServers.first;
  String search = '';

  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get surface => dark ? const Color(0xFF172235) : Colors.white;
  Color get subtle => dark ? const Color(0xFF9AABBE) : const Color(0xFF66778A);
  Color get line => dark ? const Color(0xFF29374B) : const Color(0xFFE2E9EC);
  Color get tile => dark ? const Color(0xFF1A283B) : const Color(0xFFF4F7F8);

  void notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );

  void toggleConnection() {
    setState(() => previewConnected = !previewConnected);
    notice('Preview only · no VPN tunnel is running');
  }

  void chooseServer(MockServer server) {
    setState(() {
      selected = server;
      tab = 0;
    });
    notice('Selected ${server.name} · preview data');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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

  Widget _home() => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        Positioned.fill(
          child: MapView(dark: dark, previewConnected: previewConnected),
        ),
        Positioned(top: 10, left: 16, child: _chip()),
        Positioned(top: 10, right: 16, child: _demoBadge()),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .83),
            child: SingleChildScrollView(child: _connectionSheet()),
          ),
        ),
      ],
    ),
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
            color: previewConnected ? green : subtle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          previewConnected ? 'Preview on' : 'Off',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
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

  Widget _connectionSheet() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 24,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => expanded = !expanded),
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
                    previewConnected ? 'Preview connected' : 'Not connected',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: previewConnected ? green : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    previewConnected
                        ? 'Simulation only · VPN inactive'
                        : 'Choose a server, then preview',
                    style: TextStyle(color: subtle, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => expanded = !expanded),
              icon: Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: subtle,
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
                        'Aurora Networks · ${selected.protocol}',
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
            onPressed: toggleConnection,
            style: FilledButton.styleFrom(
              backgroundColor: previewConnected ? red : green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.power_settings_new, size: 20),
            label: Text(
              previewConnected ? 'End preview' : 'Preview connection',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (!expanded && !previewConnected) ...[
          const SizedBox(height: 22),
          _sectionLabel('QUICK CONNECT'),
          const SizedBox(height: 9),
          Row(
            children: [
              _quick(Icons.bolt, 'Fastest', personalServers.first),
              const SizedBox(width: 8),
              _quick(Icons.bar_chart, 'Most used', auroraServers.first),
              const SizedBox(width: 8),
              _quick(Icons.history, 'Recent', auroraServers[1]),
            ],
          ),
        ],
        if (expanded || previewConnected) ...[
          const SizedBox(height: 20),
          _sectionLabel('TRAFFIC · SAMPLE'),
          const SizedBox(height: 9),
          Row(
            children: [
              _stat(
                'Down',
                previewConnected ? '2.31 MB/s' : '0 B/s',
                Icons.arrow_downward,
              ),
              const SizedBox(width: 9),
              _stat(
                'Up',
                previewConnected ? '58.4 KB/s' : '0 B/s',
                Icons.arrow_upward,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionLabel('CONNECTION · SAMPLE'),
          const SizedBox(height: 9),
          _fact('Exit', '${selected.flag} ${selected.city} · Example Hosting'),
          _fact('IPv4', '192.0.2.4'),
          _fact('IPv6', '2001:db8::24'),
          _fact('Protocol', selected.protocol),
        ],
      ],
    ),
  );

  Widget _stateIcon(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: (previewConnected ? green : blue).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(
      previewConnected ? Icons.verified_user_outlined : Icons.shield_outlined,
      color: previewConnected ? green : blue,
      size: 26,
    ),
  );

  Widget _quick(IconData icon, String title, MockServer server) => Expanded(
    child: InkWell(
      onTap: () => chooseServer(server),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 75,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: tile,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: blue, size: 18),
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
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: subtle),
            ),
          ],
        ),
      ),
    ),
  );

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
                previewConnected ? 'Preview connected' : 'Not connected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: previewConnected ? green : null,
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
            onPressed: toggleConnection,
            style: FilledButton.styleFrom(
              backgroundColor: previewConnected ? red : green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: Text(previewConnected ? 'End' : 'Preview'),
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
            if (_matching(personalServers).isNotEmpty) ...[
              _serverGroup('Personal', '3 servers · added by hand'),
              ..._matching(personalServers).map(_serverRow),
            ],
            if (_matching(auroraServers).isNotEmpty) ...[
              _serverGroup(
                'Aurora Networks',
                '12 servers · updated 2 h ago',
                refresh: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
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
              ),
              ..._matching(auroraServers).map(_serverRow),
            ],
            if (_matching(allServers).isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    'No matching servers',
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

  List<MockServer> _matching(List<MockServer> servers) => servers
      .where(
        (s) => '${s.name} ${s.city} ${s.protocol}'.toLowerCase().contains(
          search.toLowerCase(),
        ),
      )
      .toList();

  Widget _serverGroup(String title, String subtitle, {bool refresh = false}) =>
      Padding(
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
            if (refresh)
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

  Widget _serverRow(MockServer server) {
    final active = selected == server;
    return Container(
      color: active ? green.withValues(alpha: dark ? .14 : .09) : null,
      child: InkWell(
        onTap: () => chooseServer(server),
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

  Widget _settings() => ListView(
    children: [
      _title('Settings'),
      _sectionLabel('CONNECTION', inset: true),
      _settingsCard([
        _setting(
          Icons.public,
          'Bypass rules',
          'Leave on your normal connection',
          '4',
          () => _infoSheet(
            'Bypass rules',
            'Four sample rules are shown in this design. No routing is active.',
          ),
        ),
      ]),
      _sectionLabel('BLOCKING', inset: true),
      _settingsCard([
        _switchSetting(
          Icons.block,
          'Ad blocker',
          'List updated 3 h ago · sample',
          adBlock,
          (v) => setState(() => adBlock = v),
        ),
        _switchSetting(
          Icons.visibility_off_outlined,
          'Anti-tracker',
          'Downloaded when you turn it on · sample',
          antiTracker,
          (v) => setState(() => antiTracker = v),
        ),
      ]),
      _sectionLabel('APP', inset: true),
      _settingsCard([
        _setting(
          Icons.cloud_outlined,
          'DNS',
          'https://1.1.1.1/dns-query',
          '',
          () => _infoSheet(
            'DNS',
            'Sample DNS setting. No DNS requests are changed.',
          ),
        ),
        _setting(
          Icons.monitor_heart_outlined,
          'Diagnostics',
          'Log, config, engine',
          '',
          () => _infoSheet(
            'Diagnostics',
            'There is no VPN engine in this preview.',
          ),
        ),
        _setting(
          Icons.favorite_border,
          'Support Nunya',
          null,
          '',
          () => _infoSheet(
            'Support Nunya',
            'Support links will be added with the production app.',
          ),
        ),
        _setting(
          Icons.info_outline,
          'About',
          '0.1.0 · UI preview',
          '',
          () => _infoSheet(
            'About Nunya',
            'Flutter UI preview with sample data. No VPN tunnel is installed.',
          ),
        ),
      ]),
      const SizedBox(height: 20),
    ],
  );

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
    ValueChanged<bool> onChanged,
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
        Switch(
          value: value,
          onChanged: (v) {
            onChanged(v);
            notice('Preview setting only');
          },
        ),
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

  void _actionsSheet(MockServer server) => _sheet(
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
                    'example.net:443 · ${server.protocol}',
                    style: TextStyle(color: subtle, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _action(Icons.power_settings_new, 'Select and preview', () {
          Navigator.pop(context);
          chooseServer(server);
        }),
        _action(Icons.refresh, 'Check', () {
          Navigator.pop(context);
          notice('Sample latency: ${server.latency ?? '—'}');
        }),
        _action(Icons.bar_chart, 'Usage', () {
          Navigator.pop(context);
          _infoSheet('Usage', 'Sample usage data only.');
        }),
        _action(Icons.share_outlined, 'Share', () {
          Navigator.pop(context);
          notice('Sharing is unavailable in the preview');
        }),
        _action(Icons.edit_outlined, 'Edit', () {
          Navigator.pop(context);
          notice('Editing is unavailable in the preview');
        }),
        Divider(color: line),
        _action(Icons.delete_outline, 'Delete…', () {
          Navigator.pop(context);
          notice('Sample servers cannot be deleted');
        }, color: red),
      ],
    ),
  );

  void _addSheet() {
    var method = 0;
    _sheet(
      StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add servers',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(
                          ['Link', 'Scan QR', 'Manual'][i],
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: method == i,
                        onSelected: (_) => setSheetState(() => method = i),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: tile,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    [
                      Icons.content_paste,
                      Icons.qr_code_scanner,
                      Icons.edit_note,
                    ][method],
                    color: blue,
                    size: 30,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      'Paste from clipboard',
                      'Scan a QR code',
                      'Enter server details',
                    ][method],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Preview only · import is not available yet',
                    style: TextStyle(fontSize: 11, color: subtle),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  notice('Import is unavailable in the preview');
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
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

  void _infoSheet(String title, String body) => _sheet(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(body, style: TextStyle(color: subtle, height: 1.5)),
        const SizedBox(height: 18),
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

  void _sheet(Widget child) => showModalBottomSheet<void>(
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
