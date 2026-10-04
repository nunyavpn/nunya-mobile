/// The sheets behind the Settings tab's rows: Bypass rules, DNS, Diagnostics, Support and About.
/// Ported from desktop Nunya's `views/bypass.ts`, `views/settings.ts` (DNS, log level),
/// `views/diagnostics.ts`, `views/support.ts` with `support.ts`; on a phone each panel is a sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'server_sheets.dart';
import 'settings.dart';
import 'tones.dart';
import 'tunnel.dart';

/// This build's version, as in pubspec.yaml.
const appVersion = '0.1.0';

// ---------------------------------------------------------------- bypass

/// Split tunnelling reduced to one list: keep *these* out of the tunnel. A chip names what was
/// typed before it is added, so there is no type picker to get wrong.
class BypassSheet extends StatefulWidget {
  const BypassSheet(this.settings, {super.key, required this.locked});
  final Settings settings;
  final bool locked;

  @override
  State<BypassSheet> createState() => _BypassSheetState();
}

class _BypassSheetState extends State<BypassSheet> {
  final field = TextEditingController();

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void commit() {
    if (widget.settings.addBypass(field.text)) field.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.settings, field]),
    builder: (context, _) {
      final rules = widget.settings.bypass;
      final kind = classifyBypass(field.text);
      return SheetFrame(
        title: 'Bypass rules',
        body: [
          Text(
            'Anything matching a rule below leaves on your normal connection. Everything else '
            'goes through the tunnel.',
            style: TextStyle(color: context.subtle, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (widget.locked)
            const LockedNote()
          else
            TextField(
              key: const Key('bypassField'),
              controller: field,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 16),
              onSubmitted: (_) => commit(),
              decoration: _fieldDecoration(
                context,
                hint: 'Domain, address or range',
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chip(context, kind?.name ?? '—', on: kind != null),
                    IconButton(
                      key: const Key('addBypass'),
                      tooltip: 'Add rule',
                      onPressed: kind == null ? null : commit,
                      icon: const Icon(Icons.add_circle, color: blue),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'ALWAYS BYPASSED'),
          _ruleRow(
            context,
            Icons.lock_outline,
            'Your local network',
            // Not a rule anyone chose: it is how the tunnel is built.
            alwaysDirect.join(' · '),
          ),
          const SizedBox(height: 14),
          _sectionLabel(
            context,
            'YOUR RULES · ${rules.length} RULE${rules.length == 1 ? '' : 'S'}',
          ),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nothing is bypassed yet. Everything goes through the tunnel.',
                style: TextStyle(color: context.subtle),
              ),
            ),
          for (final rule in rules)
            _ruleRow(
              context,
              rule.kind == BypassKind.domain
                  ? Icons.public
                  : Icons.lan_outlined,
              rule.value,
              rule.kind.name,
              onRemove: widget.locked
                  ? null
                  : () => widget.settings.removeBypass(rule),
            ),
        ],
        actions: [_done(context)],
      );
    },
  );

  Widget _ruleRow(
    BuildContext context,
    IconData icon,
    String title,
    String detail, {
    VoidCallback? onRemove,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 19, color: context.subtle),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                detail,
                style: TextStyle(color: context.subtle, fontSize: 12),
              ),
            ],
          ),
        ),
        if (onRemove != null)
          IconButton(
            tooltip: 'Remove $title',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- dns

/// The resolver. Committed on Save rather than per keystroke: a half-typed URL is not a setting.
class DnsSheet extends StatefulWidget {
  const DnsSheet(this.settings, {super.key, required this.locked});
  final Settings settings;
  final bool locked;

  @override
  State<DnsSheet> createState() => _DnsSheetState();
}

class _DnsSheetState extends State<DnsSheet> {
  late final field = TextEditingController(text: widget.settings.dns);

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'DNS',
    body: [
      Text('Resolver', style: const TextStyle(fontWeight: FontWeight.w700)),
      // VPN-only, so this is always true; the desktop says otherwise only in proxy mode.
      Text(
        'Queries resolve inside the tunnel. A DNS-over-HTTPS URL, or an address.',
        style: TextStyle(color: context.subtle, fontSize: 12.5),
      ),
      const SizedBox(height: 8),
      if (widget.locked)
        const LockedNote()
      else ...[
        TextField(
          key: const Key('dnsField'),
          controller: field,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 16),
          decoration: _fieldDecoration(context),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => field.text = Settings.defaultDns,
            child: const Text('Use the default (Cloudflare)'),
          ),
        ),
      ],
    ],
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('saveDns'),
        onPressed: widget.locked
            ? null
            : () {
                final value = field.text.trim();
                widget.settings.update(
                  () => widget.settings.dns = value.isEmpty
                      ? Settings.defaultDns
                      : value,
                );
                Navigator.pop(context);
              },
        child: const Text('Save'),
      ),
    ],
  );
}

// ---------------------------------------------------------------- diagnostics

/// What the app and the engine actually said, the state of the pieces, and the config the engine
/// is given. A real screen rather than a debug hatch: someone who can answer "what did it say"
/// can file a report worth reading.
class DiagnosticsSheet extends StatefulWidget {
  const DiagnosticsSheet({
    super.key,
    required this.settings,
    required this.log,
    required this.tunnel,
  });
  final Settings settings;
  final AppLog log;
  final PreviewTunnel tunnel;

  @override
  State<DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<DiagnosticsSheet> {
  bool showConfig = false;
  bool copied = false;
  Timer? reset;

  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.settings, widget.log, widget.tunnel]),
    builder: (context, _) {
      final s = widget.settings;
      final status = widget.tunnel.status;
      final lines = widget.log.lines;
      return SheetFrame(
        title: 'Diagnostics',
        body: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Said plainly rather than shown as "not running": there is nothing to run yet.
              _badge('engine: not in this preview', ok: false),
              _badge(
                'tunnel: ${switch (status) {
                  TunnelStatus.off => 'off',
                  TunnelStatus.connecting => 'connecting (preview)',
                  TunnelStatus.connected => 'connected (preview)',
                  TunnelStatus.disconnecting => 'disconnecting (preview)',
                  TunnelStatus.failed => 'failed (preview)',
                }}',
                ok: status != TunnelStatus.failed,
              ),
              _badge('storage: memory only', ok: false),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Log level',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            "the engine's; debug is very noisy",
            style: TextStyle(color: context.subtle, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          SegmentedButton<LogLevel>(
            showSelectedIcon: false,
            segments: [
              for (final l in LogLevel.values)
                ButtonSegment(value: l, label: Text(l.name)),
            ],
            selected: {s.logLevel},
            onSelectionChanged: (v) => s.update(() => s.logLevel = v.first),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _pill(showConfig ? 'Show log' : 'Show config', () {
                setState(() => showConfig = !showConfig);
              }),
              const SizedBox(width: 6),
              _pill('Clear log', lines.isEmpty ? null : widget.log.clear),
              const SizedBox(width: 6),
              _pill(
                copied ? 'Copied' : 'Copy log',
                lines.isEmpty ? null : copyLog,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 160, maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.tile,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              reverse: !showConfig, // the newest line in view, as a log is read
              child: SelectableText(
                showConfig
                    ? 'No config yet: the engine that would be given one is not built into this '
                          'preview.'
                    : lines.isEmpty
                    ? 'Nothing logged yet.'
                    : lines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
        actions: [_done(context)],
      );
    },
  );

  Future<void> copyLog() async {
    await Clipboard.setData(ClipboardData(text: widget.log.lines.join('\n')));
    setState(() => copied = true);
    reset?.cancel();
    reset = Timer(
      const Duration(milliseconds: 1600),
      () => mounted ? setState(() => copied = false) : null,
    );
  }

  Widget _badge(String text, {required bool ok}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (ok ? green : amber).withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: ok ? green : amber,
      ),
    ),
  );

  Widget _pill(String text, VoidCallback? onPressed) => Expanded(
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      onPressed: onPressed,
      child: Text(text, maxLines: 1),
    ),
  );
}

// ---------------------------------------------------------------- support

/// The only two ways to donate, from a short fixed list a user can check a request against: the
/// people this client is for are exactly those a "donate to Nunya" message from anywhere else
/// would be aimed at. Kept in step with desktop Nunya's `support.ts`.
///
/// A channel not set up yet is shown as coming and offers nothing to pay. A placeholder is never
/// a made-up address: a string that merely looks valid can belong to a stranger.
typedef Wallet = ({String coin, String network, String? address});

const buyMeACoffee = (url: 'https://buymeacoffee.com/in_alie', live: false);
const wallets = <Wallet>[
  (coin: 'USDT', network: 'TRON (TRC-20)', address: null),
  (coin: 'BTC', network: 'Bitcoin', address: null),
  (coin: 'TON', network: 'TON', address: null),
];

class SupportSheet extends StatelessWidget {
  const SupportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final open = buyMeACoffee.live || wallets.any((w) => w.address != null);
    return SheetFrame(
      title: 'Support Nunya',
      body: [
        const Text(
          'Nunya is free and open source. If it keeps you connected, you can help keep it going.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        _sectionLabel(context, 'BUY ME A COFFEE'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            // Opening a page needs a browser handoff, added with the first live channel.
            onPressed: null,
            icon: const Icon(Icons.coffee_outlined),
            label: Text(buyMeACoffee.live ? 'Buy me a coffee' : 'Coming soon'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "The page isn't open yet.",
          style: TextStyle(color: context.subtle, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        _sectionLabel(context, 'CRYPTO'),
        for (final w in wallets)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.tile,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  w.coin,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    w.network,
                    style: TextStyle(color: context.subtle, fontSize: 12.5),
                  ),
                ),
                Text(
                  'Address coming soon',
                  style: TextStyle(color: context.subtle, fontSize: 12.5),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          open
              ? "These are the only ways to donate to Nunya. Anyone asking for payment in Nunya's "
                    "name anywhere else is not us. A donation is a gift to the project; it doesn't "
                    'change how the app works for you.'
              : "Donations aren't open yet. When they are, these will be the only ways to donate "
                    "to Nunya — anyone asking for payment in Nunya's name before then, or anywhere "
                    'else, is not us.',
          style: TextStyle(color: context.subtle, fontSize: 12.5, height: 1.4),
        ),
      ],
      actions: [_done(context)],
    );
  }
}

// ---------------------------------------------------------------- about

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'About Nunya',
    body: [
      const Text(
        'Nunya $appVersion · preview',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'A VPN client for Android and iOS, the phone companion of the Nunya desktop app. This '
        "preview has the app's screens with sample servers; it does not start a VPN or route "
        'any traffic yet.',
        style: TextStyle(color: context.subtle, height: 1.45),
      ),
      const SizedBox(height: 14),
      _fact(context, 'License', 'GPL-3.0'),
      _fact(context, 'Source', 'github.com/nunyavpn/nunya-mobile'),
      // F-Droid builds from source and updates it; there is no in-app updater to trust.
      _fact(context, 'Updates', 'through F-Droid'),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Nunya',
            applicationVersion: appVersion,
          ),
          child: const Text('Open-source licenses'),
        ),
      ),
    ],
    actions: [_done(context)],
  );

  Widget _fact(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(color: context.subtle)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- shared

/// Settings are read when the tunnel starts, so a change while it runs would do nothing until the
/// next connect, or look applied when it is not. They are locked while connected, and say so.
class LockedNote extends StatelessWidget {
  const LockedNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: amber.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'Disconnect to change settings.',
      style: TextStyle(color: amber, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _done(BuildContext context) => OutlinedButton(
  onPressed: () => Navigator.pop(context),
  child: const Text('Done'),
);

Widget _sectionLabel(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    color: context.subtle,
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: .8,
  ),
);

Widget _chip(BuildContext context, String text, {required bool on}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on ? blue.withValues(alpha: .12) : context.line,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: on ? blue : context.subtle,
        ),
      ),
    );

InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hint,
  Widget? suffix,
}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: context.tile,
  suffixIcon: suffix,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
);
