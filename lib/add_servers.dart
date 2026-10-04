/// The Add servers sheet: paste links, scan a QR code, or fill in a form. A port of desktop
/// Nunya's `add-servers-sheet.ts`.
///
/// All three end up in the same place. A QR code is only a link in another form, so reading one
/// puts its text into the Link tab like a paste: one import path to keep honest. Manual entry is
/// the editor's form over a blank profile. What was pasted survives switching tabs, so looking at
/// the QR tab does not cost a paste.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'mock_data.dart';
import 'qr_scan.dart';
import 'server_sheets.dart';
import 'share_link.dart';
import 'tones.dart';

class AddServersSheet extends StatefulWidget {
  const AddServersSheet({super.key, required this.onAdd});
  final ValueChanged<List<Server>> onAdd;

  @override
  State<AddServersSheet> createState() => _AddServersSheetState();
}

enum _Tab { link, qr, manual }

class _AddServersSheetState extends State<AddServersSheet> {
  var tab = _Tab.link;
  final links = TextEditingController();

  /// Under the QR tab: how reading went, or where the image goes (nowhere).
  String qrNote =
      'The code is read on this phone; nothing is kept or sent anywhere.';
  bool qrFailed = false;

  final Profile manual = blankProfile();
  String manualName = '';
  late List<String> manualProblems = profileProblems(manual);

  @override
  void dispose() {
    links.dispose();
    super.dispose();
  }

  /// Appended rather than replacing, so a code can be read on top of links already pasted.
  void readText(String text) => setState(() {
    final before = links.text.trim();
    links.text = before.isEmpty ? text : '$before\n$text';
    tab = _Tab.link;
  });

  Future<void> chooseImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      qrNote = 'Reading…';
      qrFailed = false;
    });
    String? text;
    try {
      text = await readQrImage(await picked.readAsBytes());
    } on Exception {
      text = null;
    }
    if (!mounted) return;
    if (text == null) {
      setState(() {
        qrNote = 'No QR code found in that image. Try a sharper or larger one.';
        qrFailed = true;
      });
    } else {
      readText(text);
    }
  }

  void add(List<Server> servers) {
    Navigator.pop(context);
    widget.onAdd(servers);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = SizedBox(
      width: double.infinity,
      child: SegmentedButton<_Tab>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _Tab.link, label: Text('Link')),
          ButtonSegment(value: _Tab.qr, label: Text('Scan QR')),
          ButtonSegment(value: _Tab.manual, label: Text('Manual')),
        ],
        selected: {tab},
        onSelectionChanged: (v) => setState(() => tab = v.first),
      ),
    );
    return switch (tab) {
      _Tab.link => _linkPane(tabs),
      _Tab.qr => _qrPane(tabs),
      _Tab.manual => _manualPane(tabs),
    };
  }

  Widget _linkPane(Widget tabs) {
    final lines = links.text.split(RegExp(r'\s+')).where((l) => l.isNotEmpty);
    final found = <Server>[];
    final rejected = <(String, String)>[];
    for (final line in lines) {
      try {
        // A subscription is a list of links behind a URL, not a link: its own flow.
        if (RegExp(r'^https?://').hasMatch(line)) {
          throw const FormatException(
            'Subscription URLs are not supported yet',
          );
        }
        found.add(Server(parseShareLink(line)));
      } on FormatException catch (e) {
        // Show the scheme only; the rest of a link is a credential.
        rejected.add((line.split('://').first, e.message));
      }
    }
    return SheetFrame(
      title: 'Add servers',
      body: [
        tabs,
        const SizedBox(height: 16),
        TextField(
          key: const Key('linkField'),
          controller: links,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(fontSize: 16),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'vless://, vmess://, trojan:// or wireguard:// links',
            filled: true,
            fillColor: context.tile,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              tooltip: 'Paste from clipboard',
              icon: const Icon(Icons.content_paste, color: blue),
              onPressed: () async {
                final clip = await Clipboard.getData('text/plain');
                if (clip?.text case final t? when t.trim().isNotEmpty) {
                  readText(t.trim());
                }
              },
            ),
          ),
        ),
        if (found.isNotEmpty || rejected.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'FOUND · ${found.length} SERVER${found.length == 1 ? '' : 'S'}',
            style: _label(context),
          ),
          const SizedBox(height: 6),
          for (final s in found)
            _importRow(context, Icons.dns_outlined, s.name, s.protocol, null),
          for (final (scheme, reason) in rejected)
            _importRow(context, Icons.block, '$scheme link', reason, red),
        ],
      ],
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('addServers'),
          onPressed: found.isEmpty ? null : () => add(found),
          child: Text(found.isEmpty ? 'Add' : 'Add ${found.length}'),
        ),
      ],
    );
  }

  Widget _qrPane(Widget tabs) => SheetFrame(
    title: 'Add servers',
    body: [
      tabs,
      const SizedBox(height: 16),
      // Built only while this tab shows, so the camera is released as soon as it is left.
      QrCameraView(onFound: readText),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: chooseImage,
          icon: const Icon(Icons.image_outlined),
          label: const Text('Choose an image instead'),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        qrNote,
        style: TextStyle(
          fontSize: 12.5,
          color: qrFailed ? red : context.subtle,
        ),
      ),
    ],
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );

  Widget _manualPane(Widget tabs) => SheetFrame(
    title: 'Add servers',
    body: [
      tabs,
      const SizedBox(height: 16),
      NameField('', hint: 'optional', onChanged: (v) => manualName = v),
      ProfileForm(manual, onChanged: (p) => setState(() => manualProblems = p)),
    ],
    // Shown from the start: an empty form is not yet addable, and saying why beats a disabled
    // button with no explanation.
    status: manualProblems.isEmpty ? 'Adds to Personal' : manualProblems.first,
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('addManual'),
        onPressed: manualProblems.isNotEmpty
            ? null
            : () {
                // Something has to be in the list; the address is certain to be filled in.
                final typed = manualName.trim();
                manual.name = typed.isEmpty ? manual.server : typed;
                add([Server(manual.copy())]);
              },
        child: const Text('Add server'),
      ),
    ],
  );
}

/// What manual entry starts from: VLESS over TLS on 443, which is what most servers handed out as
/// a list of settings are. Everything else is empty, so nothing plausible-looking is invented.
Profile blankProfile() => Profile(
  protocol: Protocol.vless,
  name: '',
  server: '',
  port: 443,
  tls: TlsOptions(enabled: true),
);

TextStyle _label(BuildContext context) => TextStyle(
  color: context.subtle,
  fontSize: 11.5,
  fontWeight: FontWeight.w800,
  letterSpacing: .8,
);

Widget _importRow(
  BuildContext context,
  IconData icon,
  String title,
  String detail,
  Color? color,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    children: [
      Icon(icon, size: 19, color: color ?? context.subtle),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              detail,
              style: TextStyle(fontSize: 12, color: color ?? context.subtle),
            ),
          ],
        ),
      ),
    ],
  ),
);
