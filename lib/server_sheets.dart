/// The sheets a server row's ⋯ opens: Share, Usage and Edit. Ported from desktop Nunya's
/// `share-server.ts`, `sheets.ts` (`openUsage`) with `views/usage.ts`, and `edit-server.ts` with
/// `editor.ts`; on a phone each desktop dialog is a sheet from the bottom.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import 'mock_data.dart';
import 'share_link.dart';
import 'tones.dart';
import 'usage.dart';

// ---------------------------------------------------------------- share

/// A link and its QR code, with a copy button. The link is generated from the profile rather
/// than kept from whatever was pasted, so an edit made since import is what gets shared. It says
/// plainly that this is the credential: a QR code on screen looks like a harmless picture, and
/// anyone who photographs it can use the server exactly as the user does.
///
/// Not yet: a WireGuard server shared as a wg-quick config, which the official WireGuard apps
/// need; it is shared as a link until wg-quick is ported.
class ShareServerSheet extends StatefulWidget {
  const ShareServerSheet(this.server, {super.key});
  final Server server;

  @override
  State<ShareServerSheet> createState() => _ShareServerSheetState();
}

class _ShareServerSheetState extends State<ShareServerSheet> {
  bool copied = false;
  Timer? reset;

  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final String link;
    try {
      link = toShareLink(server.profile);
    } on FormatException catch (e) {
      return SheetFrame(
        title: 'Share server',
        body: [Text("Can't write a link for this server: ${e.message}")],
        actions: [_done(context)],
      );
    }
    return SheetFrame(
      title: 'Share server',
      body: [
        Text(
          '${server.name} · ${server.protocol}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Center(child: QrCodeView(link, size: 248)),
        const SizedBox(height: 12),
        _note(
          context,
          // Nunya first: it is the client this link is written for.
          'Import it in Nunya on another device, or scan it with a client that reads share links.',
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.tile,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            link,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        _note(
          context,
          "The link contains this server's credentials. Anyone who has it can use the server.",
          warn: true,
        ),
      ],
      actions: [
        _done(context),
        FilledButton(
          key: const Key('copyLink'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            setState(() => copied = true);
            reset?.cancel();
            reset = Timer(
              const Duration(milliseconds: 1600),
              () => mounted ? setState(() => copied = false) : null,
            );
          },
          child: Text(copied ? 'Copied' : 'Copy link'),
        ),
      ],
    );
  }
}

/// Always dark on white, in both themes: many scanners cannot read an inverted code.
class QrCodeView extends StatelessWidget {
  const QrCodeView(this.text, {super.key, this.size = 232});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Medium correction: a share link is long, and M keeps the code at a density a camera reads
    // off another screen, while surviving glare and a slightly cropped frame.
    final image = QrImage(
      QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
    );
    return Semantics(
      label: 'QR code of the share link',
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const border = 2; // quiet zone, in modules
    final n = image.moduleCount;
    final unit = size.width / (n + border * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = Colors.white,
    );
    final dark = Paint()..color = Colors.black;
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          // A hair over one module, so antialiasing leaves no seams between neighbours.
          path.addRect(
            Rect.fromLTWH(
              (x + border) * unit,
              (y + border) * unit,
              unit + .3,
              unit + .3,
            ),
          );
        }
      }
    }
    canvas.drawPath(path, dark);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

// ---------------------------------------------------------------- usage

/// Days the chart covers, and the window the headline total is for.
const chartDays = 30;

/// One server's traffic: totals, a daily chart, and clearing. It repaints on [live] — the tunnel —
/// so the numbers climb while it runs. Clearing asks in the footer rather than in a second sheet,
/// and says what goes: the history, never the server.
class UsageSheet extends StatefulWidget {
  const UsageSheet(this.server, {super.key, required this.live});
  final Server server;
  final Listenable live;

  @override
  State<UsageSheet> createState() => _UsageSheetState();
}

class _UsageSheetState extends State<UsageSheet> {
  bool confirming = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.live,
    builder: (context, _) {
      final server = widget.server;
      final histories = [server.usage];
      final now = DateTime.now();
      final series = lastDays(histories, chartDays, now);
      final since = firstDay(histories);
      final recorded = total(histories);
      return SheetFrame(
        title: 'Usage',
        body: [
          Text.rich(
            TextSpan(
              text: server.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
              children: [
                TextSpan(
                  text: ' · ${server.group}',
                  style: TextStyle(
                    color: context.subtle,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (since == null)
            Text(
              'Nothing recorded yet. Usage is counted while the tunnel runs on this config.',
              style: TextStyle(color: context.subtle),
            )
          else ...[
            Row(
              children: [
                _summary(
                  context,
                  'Last $chartDays days',
                  total(histories, series.first.day),
                ),
                const SizedBox(width: 10),
                _summary(context, 'Since ${shortDate(since)}', recorded),
              ],
            ),
            const SizedBox(height: 16),
            UsageChart(series, now: now),
            const SizedBox(height: 8),
            Row(
              children: [
                _legend(context, 1, 'Download'),
                const SizedBox(width: 16),
                _legend(context, .42, 'Upload'),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _note(
            context,
            "Counted on this device from the tunnel's own counters, never sent anywhere, and kept "
            'for as long as the config is in your list.',
          ),
          const SizedBox(height: 6),
          _note(
            context,
            'Preview: no tunnel runs yet, so these numbers are simulated.',
            warn: true,
          ),
        ],
        status: confirming && since != null
            ? 'Clears ${size(recorded.up + recorded.down)} recorded since ${shortDate(since)}. '
                  'The config stays.'
            : null,
        actions: confirming && since != null
            ? [
                OutlinedButton(
                  onPressed: () => setState(() => confirming = false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: red),
                  onPressed: () => setState(() {
                    server.usage.clear();
                    confirming = false;
                  }),
                  child: const Text('Clear'),
                ),
              ]
            : [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: red),
                  onPressed: since == null
                      ? null
                      : () => setState(() => confirming = true),
                  child: const Text('Clear history'),
                ),
                _done(context),
              ],
      );
    },
  );

  Widget _summary(BuildContext context, String label, Bytes bytes) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.subtle, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            size(bytes.up + bytes.down),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            '↓ ${size(bytes.down)} · ↑ ${size(bytes.up)}',
            style: TextStyle(color: context.subtle, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );

  Widget _legend(BuildContext context, double opacity, String label) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _brandFill.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: context.subtle, fontSize: 12)),
    ],
  );
}

const _brandFill = Color(0xFF2E90FA);

/// "Sep 21" from a day key.
String shortDate(String day) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final [_, m, d] = day.split('-').map(int.parse).toList();
  return '${months[m - 1]} $d';
}

/// Stacked daily bars, download under upload, over a scale topping out at a round number. A day
/// is tapped (not hovered, on a phone) to read its numbers, quiet days included.
class UsageChart extends StatefulWidget {
  const UsageChart(this.series, {super.key, required this.now});
  final List<({String day, int up, int down})> series;
  final DateTime now;

  @override
  State<UsageChart> createState() => _UsageChartState();
}

class _UsageChartState extends State<UsageChart> {
  int? picked;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final shown = picked == null ? null : series[picked!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 16,
          child: shown == null
              ? null
              : Text(
                  '${shortDate(shown.day)} · ↓ ${size(shown.down)} · ↑ ${size(shown.up)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onTapDown: (d) {
              const left = 50.0;
              final slot = (box.maxWidth - left) / series.length;
              final i = ((d.localPosition.dx - left) / slot).floor();
              setState(() => picked = i < 0 || i >= series.length ? null : i);
            },
            child: CustomPaint(
              size: Size(box.maxWidth, 164),
              painter: _ChartPainter(
                series,
                today: dayKey(widget.now),
                picked: picked,
                line: context.line,
                label: context.subtle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(
    this.series, {
    required this.today,
    this.picked,
    required this.line,
    required this.label,
  });
  final List<({String day, int up, int down})> series;
  final String today;
  final int? picked;
  final Color line, label;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 50.0, top = 10.0, bottom = 136.0;
    final peak = series.fold(0, (m, d) => math.max(m, d.up + d.down));
    final ceiling = niceCeiling(peak);
    const plot = bottom - top;
    final slot = (size.width - left) / series.length;
    final bar = math.max(2.0, slot * .64);
    double y(num bytes) => bottom - bytes / ceiling * plot;
    // A day that moved anything gets at least a sliver, or kilobytes against gigabytes vanish.
    double height(int bytes) =>
        bytes > 0 ? math.max(1.5, bytes / ceiling * plot) : 0;

    void text(String s, Offset at, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 10, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = switch (align) {
        TextAlign.right => at.dx - tp.width,
        TextAlign.center => at.dx - tp.width / 2,
        _ => at.dx,
      };
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    for (final f in [0.0, .5, 1.0]) {
      final at = y(ceiling * f);
      canvas.drawLine(
        Offset(left, at),
        Offset(size.width, at),
        Paint()..color = line,
      );
      if (f > 0) {
        text(
          _roundSize(ceiling * f),
          Offset(left - 6, at),
          align: TextAlign.right,
        );
      }
    }
    for (var i = 0; i < series.length; i++) {
      final d = series[i];
      final x = left + i * slot + (slot - bar) / 2;
      final faded = picked != null && picked != i;
      final down = height(d.down), up = height(d.up);
      final fill = _brandFill.withValues(alpha: faded ? .45 : 1);
      if (i == picked || d.day == today) {
        canvas.drawRect(
          Rect.fromLTWH(left + i * slot, top, slot, plot),
          Paint()..color = line.withValues(alpha: .5),
        );
      }
      if (down > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, bottom - down, bar, down),
            const Radius.circular(1),
          ),
          Paint()..color = fill,
        );
      }
      if (up > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, bottom - down - up, bar, up),
            const Radius.circular(1),
          ),
          Paint()..color = fill.withValues(alpha: fill.a * .42),
        );
      }
    }
    // The first day, the middle and today: enough to place any bar without crowding the axis.
    final middle = series.length ~/ 2;
    double centre(int i) => left + i * slot + slot / 2;
    text(shortDate(series.first.day), Offset(left, size.height - 8));
    text(
      shortDate(series[middle].day),
      Offset(centre(middle), size.height - 8),
      align: TextAlign.center,
    );
    text('Today', Offset(size.width, size.height - 8), align: TextAlign.right);
  }

  /// A gridline's label, with no decimals: the ceiling is a round number by construction.
  String _roundSize(double bytes) =>
      size(bytes).replaceFirst(RegExp(r'\.0+ '), ' ');

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

// ---------------------------------------------------------------- frame

/// A sheet's title, scrolling body and a footer of actions at thumb height.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.status,
  });
  final String title;
  final List<Widget> body;
  final List<Widget> actions;

  /// A line over the actions: the first problem in a form, or what a confirmation will do.
  final String? status;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
      const SizedBox(height: 6),
      Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body,
          ),
        ),
      ),
      if (status case final s?) ...[
        const SizedBox(height: 12),
        Text(s, style: TextStyle(color: context.subtle, fontSize: 12.5)),
      ],
      const SizedBox(height: 14),
      Row(
        children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              flex: i == actions.length - 1 ? 2 : 1,
              child: SizedBox(height: 48, child: a),
            ),
          ],
        ],
      ),
    ],
  );
}

Widget _done(BuildContext context) => OutlinedButton(
  onPressed: () => Navigator.pop(context),
  child: const Text('Done'),
);

Widget _note(BuildContext context, String text, {bool warn = false}) => Text(
  text,
  style: TextStyle(
    fontSize: 12.5,
    height: 1.4,
    color: warn ? amber : context.subtle,
    fontWeight: warn ? FontWeight.w600 : null,
  ),
);

/// Opens a sheet the height of its content, up to most of the screen, lifted over the keyboard.
Future<T?> showServerSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: context.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );

// ---------------------------------------------------------------- edit

/// A form over the profile, not a text box over a share link: changing a port by finding it
/// between an `@` and a `?` makes the user the parser, and a typo there does not fail — it
/// produces a different server. The name sits apart because it is not part of the connection,
/// and renaming is the edit people make most often.
///
/// Works on a deep copy, so closing without saving changes nothing. A structural choice (the
/// protocol, the transport, the security layer) decides which fields exist, so it rebuilds the
/// form; every other field writes straight into the copy, so a rebuild never loses what was typed.
class EditServerSheet extends StatefulWidget {
  const EditServerSheet(this.server, {super.key, required this.onSave});
  final Server server;
  final ValueChanged<Profile> onSave;

  @override
  State<EditServerSheet> createState() => _EditServerSheetState();
}

class _EditServerSheetState extends State<EditServerSheet> {
  late final Profile draft = widget.server.profile.copy();
  late String name = draft.name;
  late List<String> found = profileProblems(draft);

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'Edit server',
    body: [
      NameField(name, onChanged: (v) => name = v),
      ProfileForm(draft, onChanged: (p) => setState(() => found = p)),
    ],
    status: found.isEmpty ? 'Changes apply on save' : found.first,
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('saveServer'),
        onPressed: found.isNotEmpty
            ? null
            : () {
                draft.name = name.trim().isEmpty ? draft.name : name.trim();
                widget.onSave(draft);
                Navigator.pop(context);
              },
        child: const Text('Save'),
      ),
    ],
  );
}

/// The name, apart from the form because it is not part of the connection.
class NameField extends StatelessWidget {
  const NameField(
    this.initial, {
    super.key,
    required this.onChanged,
    this.hint,
  });
  final String initial;
  final String? hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const ValueKey('field:Name'),
    initialValue: initial,
    style: const TextStyle(fontSize: 16),
    decoration: InputDecoration(
      labelText: 'Name',
      hintText: hint,
      filled: true,
      fillColor: context.tile,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    onChanged: onChanged,
  );
}

/// What stops [p] from being saved: only what makes the server unreachable, not a schema check.
/// A wrong SNI is a mistake the user can see and fix; a missing UUID is a config the engine will
/// refuse.
List<String> profileProblems(Profile p, {String extraError = ''}) => [
  if (p.server.trim().isEmpty) 'An address is required.',
  if (p.port < 1 || p.port > 65535) 'The port must be between 1 and 65535.',
  if (p.protocol == Protocol.wireguard) ...[
    if (p.wireguard!.privateKey.trim().isEmpty) 'A private key is required.',
    if (p.wireguard!.peerPublicKey.trim().isEmpty)
      "The peer's public key is required.",
    if (p.wireguard!.localAddress.isEmpty)
      'WireGuard has no DHCP: the interface addresses have to be stated.',
  ] else if (p.protocol == Protocol.trojan) ...[
    if (p.password.trim().isEmpty) 'A password is required.',
  ] else if (p.uuid.trim().isEmpty)
    'A UUID is required.',
  if (p.protocol != Protocol.wireguard &&
      p.tls.reality != null &&
      p.tls.reality!.publicKey.trim().isEmpty)
    "Reality cannot be attempted without the server's public key.",
  if (p.protocol != Protocol.wireguard &&
      p.transport.kind == TransportKind.xhttp) ...[
    ?_xhttpProblem(p.transport),
    if (p.protocol == Protocol.vless && p.flow.isNotEmpty)
      'XHTTP requires Flow to be none.',
    if (p.protocol == Protocol.vmess && p.alterId != 0)
      'XHTTP requires Alter ID to be 0.',
    if (extraError.isNotEmpty) extraError,
  ],
];

String? _xhttpProblem(Transport t) {
  try {
    validateXhttp(t);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// The fields of a profile, edited in place in [draft]: the edit sheet passes a deep copy, so
/// closing without saving changes nothing, and manual entry a blank profile. A structural choice
/// (the protocol, the transport, the security layer) decides which fields exist, so it rebuilds
/// the form; every other field writes straight into the draft, so a rebuild never loses what was
/// typed. [onChanged] gets the problems after every edit, for the footer's Save and its line.
class ProfileForm extends StatefulWidget {
  const ProfileForm(this.draft, {super.key, required this.onChanged});
  final Profile draft;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

const _vmessCiphers = ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none'];

/// Order is preference order in the handshake, so the order they are tapped on in is kept.
const _alpns = ['h2', 'http/1.1', 'h3'];

/// uTLS fingerprints the engine implements: a list rather than free text, because a misspelling
/// does not fail — the engine falls back and the handshake quietly imitates the wrong client.
const _fingerprints = [
  '',
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  'random',
];

class _ProfileFormState extends State<ProfileForm> {
  Profile get draft => widget.draft;
  late String extraText = jsonEncodeOrEmpty(draft.transport.extra);
  String extraError = '';

  static String jsonEncodeOrEmpty(Map<String, Object?>? extra) =>
      extra == null || extra.isEmpty ? '' : jsonEncode(extra);

  /// Every edit goes through here, so the footer's problem line is always current.
  void edit(VoidCallback change) {
    setState(change);
    widget.onChanged(profileProblems(draft, extraError: extraError));
  }

  /// Switching protocol keeps everything the new one can still use: address, port and TLS are
  /// properties of where the server is, not how it authenticates. Protocol-specific fields are
  /// kept rather than cleared; both the link writer and the config builder emit them only for
  /// their own protocol, and clearing would discard a setting for anyone clicking through.
  void setProtocol(Protocol protocol) => edit(() {
    draft.protocol = protocol;
    if (protocol == Protocol.wireguard) draft.wireguard ??= WireguardOptions();
    if (protocol == Protocol.vmess && draft.security.isEmpty) {
      draft.security = 'auto';
    }
  });

  /// The Reality keys are dropped rather than kept aside: a stale public key reappearing when
  /// someone toggles back through the control is worse than retyping it.
  void setSecurity(String kind) => edit(() {
    draft.tls.enabled = kind != 'none';
    draft.tls.reality = kind == 'reality'
        ? (draft.tls.reality ?? Reality())
        : null;
  });

  @override
  Widget build(BuildContext context) {
    final p = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _group('Server', [
          _choice(
            'Protocol',
            null,
            {for (final x in Protocol.values) x: x.label},
            p.protocol,
            setProtocol,
          ),
          _text(
            'Address',
            'hostname or IP',
            p.server,
            (v) => p.server = v.trim(),
          ),
          _number('Port', null, p.port, (v) => p.port = v),
        ]),
        ..._credentials(),
        if (p.protocol != Protocol.wireguard) ...[_transport(), _security()],
      ],
    );
  }

  List<Widget> _credentials() {
    final p = draft;
    if (p.protocol == Protocol.wireguard) {
      final wg = p.wireguard!;
      return [
        _group('Keys', [
          _text(
            'Private key',
            "this device's key",
            wg.privateKey,
            (v) => wg.privateKey = v.trim(),
          ),
          _text(
            'Peer public key',
            "the server's key",
            wg.peerPublicKey,
            (v) => wg.peerPublicKey = v.trim(),
          ),
        ]),
        _group('Interface', [
          _text(
            'Addresses',
            'comma separated, with prefix length',
            wg.localAddress.join(', '),
            (v) => wg.localAddress = [
              for (final a in v.split(','))
                if (a.trim().isNotEmpty) a.trim(),
            ],
          ),
          _text(
            'Reserved',
            "Cloudflare WARP's client id; leave empty otherwise",
            wg.reserved.join(', '),
            (v) => wg.reserved = [
              for (final n in v.split(','))
                if (int.tryParse(n.trim()) case final b?
                    when b >= 0 && b <= 255)
                  b,
            ],
          ),
          _number('MTU', '0 leaves it to the core', wg.mtu, (v) => wg.mtu = v),
          _number(
            'Keepalive',
            'seconds; 0 to disable',
            wg.keepalive,
            (v) => wg.keepalive = v,
          ),
        ]),
      ];
    }
    if (p.protocol == Protocol.trojan) {
      return [
        _group('Credentials', [
          _text('Password', null, p.password, (v) => p.password = v),
        ]),
      ];
    }
    return [
      _group('Credentials', [
        _text('UUID', null, p.uuid, (v) => p.uuid = v.trim()),
        if (p.protocol == Protocol.vless)
          _choice(
            'Flow',
            'XTLS Vision, where the server offers it',
            const {'': 'none', 'xtls-rprx-vision': 'vision'},
            p.flow,
            (v) => edit(() => p.flow = v),
          ),
        if (p.protocol == Protocol.vmess) ...[
          _choice(
            'Cipher',
            null,
            {for (final c in _vmessCiphers) c: c},
            p.security.isEmpty ? 'auto' : p.security,
            (v) => edit(() => p.security = v),
          ),
          _number(
            'Alter ID',
            '0 unless the server is pre-AEAD, which modern ones are not',
            p.alterId,
            (v) => p.alterId = v,
          ),
        ],
      ]),
    ];
  }

  Widget _transport() {
    final t = draft.transport;
    return _group('Transport', [
      _choice(
        'Type',
        null,
        {for (final k in TransportKind.values) k: k.label},
        t.kind,
        (v) => edit(() {
          t.kind = v;
          if (v == TransportKind.xhttp) t.mode ??= 'auto';
        }),
      ),
      ...switch (t.kind) {
        TransportKind.ws => [
          _text('Path', null, t.path, (v) => t.path = v),
          _text(
            'Host header',
            'defaults to the address',
            t.host,
            (v) => t.host = v,
          ),
          _number(
            'Early data',
            '0 to disable',
            t.maxEarlyData,
            (v) => t.maxEarlyData = v,
          ),
        ],
        TransportKind.xhttp => [
          _text('Path', null, t.path.isEmpty ? '/' : t.path, (v) => t.path = v),
          _text(
            'Host',
            'defaults to the server name',
            t.host,
            (v) => t.host = v,
          ),
          _choice(
            'Mode',
            null,
            {for (final m in xhttpModes) m: m},
            t.mode ?? 'auto',
            (v) => edit(() => t.mode = v),
          ),
          _text(
            'Extra (JSON)',
            'headers, padding, upload limits and xmux; empty means defaults',
            extraText,
            (v) {
              extraText = v;
              try {
                t.extra = parseXhttpExtra(v);
                extraError = '';
              } on FormatException catch (e) {
                extraError = e.message;
              }
            },
          ),
        ],
        TransportKind.httpupgrade => [
          _text('Path', null, t.path, (v) => t.path = v),
          _text(
            'Host header',
            'defaults to the address',
            t.host,
            (v) => t.host = v,
          ),
        ],
        TransportKind.http => [
          _text('Path', null, t.path, (v) => t.path = v),
          _text('Host', 'the :authority', t.host, (v) => t.host = v),
          _text(
            'Method',
            "empty means the core's default",
            t.method,
            (v) => t.method = v,
          ),
        ],
        TransportKind.grpc => [
          _text('Service name', null, t.serviceName, (v) => t.serviceName = v),
        ],
        TransportKind.tcp || TransportKind.quic => [
          Text(
            'Nothing to configure for this transport.',
            style: TextStyle(color: context.subtle, fontSize: 12.5),
          ),
        ],
      },
    ]);
  }

  Widget _security() {
    final tls = draft.tls;
    final kind = tls.reality != null
        ? 'reality'
        : tls.enabled
        ? 'tls'
        : 'none';
    // A link can carry a fingerprint this list does not name; it is shown rather than left with
    // nothing selected, which would read as "none".
    final fingerprints = [
      ..._fingerprints,
      if (!_fingerprints.contains(tls.fingerprint)) tls.fingerprint,
    ];
    return _group('Security', [
      _choice(
        'Layer',
        null,
        const {'none': 'None', 'tls': 'TLS', 'reality': 'Reality'},
        kind,
        setSecurity,
      ),
      if (kind != 'none') ...[
        _text(
          'SNI',
          'the name presented in the handshake',
          tls.sni,
          (v) => tls.sni = v.trim(),
        ),
        _choice(
          'Fingerprint',
          'which client the handshake imitates',
          {for (final f in fingerprints) f: f.isEmpty ? 'none' : f},
          tls.fingerprint,
          (v) => edit(() => tls.fingerprint = v),
        ),
      ],
      if (kind == 'tls') ...[
        _field(
          'ALPN',
          'in order of preference: the order you tap them in · none lets the core decide',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in [
                ...tls.alpn,
                ..._alpns.where((a) => !tls.alpn.contains(a)),
              ])
                FilterChip(
                  label: Text(
                    tls.alpn.contains(a) ? '${tls.alpn.indexOf(a) + 1}. $a' : a,
                  ),
                  selected: tls.alpn.contains(a),
                  showCheckmark: false,
                  onSelected: (on) =>
                      edit(() => on ? tls.alpn.add(a) : tls.alpn.remove(a)),
                ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Allow insecure',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'accepts any certificate — only for a server you control',
          ),
          value: tls.insecure,
          onChanged: (v) => edit(() => tls.insecure = v),
        ),
      ],
      if (tls.reality case final r?) ...[
        _text(
          'Public key',
          "the server's Reality key",
          r.publicKey,
          (v) => r.publicKey = v.trim(),
        ),
        _text('Short ID', null, r.shortId, (v) => r.shortId = v.trim()),
      ],
    ]);
  }

  // ---------------------------------------------------------------- controls

  Widget _group(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: context.subtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
        for (final row in rows)
          Padding(padding: const EdgeInsets.only(top: 10), child: row),
      ],
    ),
  );

  Widget _field(String title, String? hint, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (hint != null)
        Text(hint, style: TextStyle(color: context.subtle, fontSize: 12)),
      const SizedBox(height: 6),
      control,
    ],
  );

  /// Keyed by its title, so a structural rebuild never hands one field's text to another.
  Widget _text(
    String title,
    String? hint,
    String value,
    ValueChanged<String> onChanged,
  ) => _field(
    title,
    hint,
    TextFormField(
      key: ValueKey('field:$title'),
      initialValue: value,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 16), // 16, so the page never zooms
      decoration: _decoration(),
      onChanged: (v) => edit(() => onChanged(v)),
    ),
  );

  /// An unreadable number becomes 0, which the problems list (or the engine's default) covers.
  Widget _number(
    String title,
    String? hint,
    int value,
    ValueChanged<int> onChanged,
  ) => _field(
    title,
    hint,
    TextFormField(
      key: ValueKey('field:$title'),
      initialValue: '$value',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 16),
      decoration: _decoration(),
      onChanged: (v) => edit(() => onChanged(int.tryParse(v) ?? 0)),
    ),
  );

  Widget _choice<T>(
    String title,
    String? hint,
    Map<T, String> options,
    T value,
    ValueChanged<T> onChanged,
  ) => _field(
    title,
    hint,
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final MapEntry(key: option, value: label) in options.entries)
          ChoiceChip(
            label: Text(label),
            selected: option == value,
            showCheckmark: false,
            onSelected: (_) => onChanged(option),
          ),
      ],
    ),
  );

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: context.tile,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
