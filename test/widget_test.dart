import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/main.dart';

void main() {
  testWidgets('preview connection asks first and never claims a running VPN', (
    tester,
  ) async {
    await tester.pumpWidget(const NunyaApp(splash: false));
    expect(find.text('DEMO · NO VPN'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pumpAndSettle();
    expect(find.text('Allow the VPN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('allowVpn')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connecting…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Preview connected'), findsOneWidget);
    expect(
      find.textContaining('Simulation only · VPN inactive'),
      findsOneWidget,
    );
    expect(find.text("You're protected"), findsNothing);

    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('a server that does not answer shows the failure', (
    tester,
  ) async {
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.tap(find.text('Servers'));
    await tester.pump();
    await tester.tap(find.text('IR-1 Tehran'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allowVpn')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text("Couldn't connect"), findsOneWidget);
    expect(find.textContaining("didn't answer"), findsOneWidget);
  });

  testWidgets('search filters servers and selection updates home', (
    tester,
  ) async {
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.tap(find.text('Servers'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('serverSearch')), 'Zurich');
    await tester.pump();
    expect(find.text('CH-1 Zurich'), findsOneWidget);
    expect(find.text('FI-1 Helsinki'), findsNothing);
    await tester.tap(find.text('CH-1 Zurich'));
    await tester.pump();
    expect(find.text('CH-1 Zurich'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('pasted share links are added to the list', (tester) async {
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.tap(find.text('Servers'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add servers'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('linkField')),
      'trojan://pw@t.example:443#My%20Trojan\nhysteria2://x@h.example:1',
    );
    await tester.pump();
    expect(
      find.textContaining('Hysteria2 is not supported yet'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('addServers')));
    await tester.pumpAndSettle();
    expect(find.text('My Trojan'), findsOneWidget);
  });

  testWidgets('the connection sheet drags open and back closed', (
    tester,
  ) async {
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show more'), findsOneWidget);
    await tester.drag(find.text('Not connected'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show less'), findsOneWidget);
    await tester.drag(find.text('Not connected'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show more'), findsOneWidget);
  });

  Future<void> openActions(WidgetTester tester, String server) async {
    await tester.tap(find.text('Servers'));
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Actions for $server'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for $server'));
    await tester.pumpAndSettle();
  }

  testWidgets('edit changes the config, and a missing field blocks Save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NunyaApp(splash: false));
    await openActions(tester, 'DE-1 Frankfurt');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('field:UUID')), '');
    await tester.pump();
    expect(find.text('A UUID is required.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('saveServer')))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const ValueKey('field:UUID')), 'new-id');
    await tester.enterText(find.byKey(const ValueKey('field:Port')), '8443');
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveServer')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Actions for DE-1 Frankfurt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('de1.example.net:8443'), findsOneWidget);
  });

  testWidgets('share shows the link written from the profile', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NunyaApp(splash: false));
    await openActions(tester, 'GB-3 London');
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('trojan://sample-password@gb3.example.net:443'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Anyone who has it can use the server'),
      findsOneWidget,
    );
  });

  testWidgets('usage shows a server\'s history and clears it on confirm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NunyaApp(splash: false));
    await openActions(tester, 'FI-1 Helsinki');
    await tester.tap(find.text('Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Last 30 days'), findsOneWidget);
    await tester.tap(find.text('Clear history'));
    await tester.pump();
    expect(find.textContaining('The config stays.'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.textContaining('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets(
    'a server entered by hand is added once its required fields are in',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NunyaApp(splash: false));
      await tester.tap(find.text('Servers'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add servers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      expect(find.text('An address is required.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field:Address')),
        'my.example.org',
      );
      await tester.pump();
      expect(find.text('A UUID is required.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('field:UUID')),
        'some-uuid',
      );
      await tester.pump();
      expect(find.text('Adds to Personal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('addManual')));
      await tester.pumpAndSettle();
      // Named by its address, since no name was typed.
      expect(find.text('my.example.org'), findsWidgets);
    },
  );

  testWidgets('bypass rules are added by typing and counted on the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.tap(find.text('Bypass rules'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('bypassField')),
      'bank.example',
    );
    await tester.pump();
    expect(find.text('domain'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addBypass')));
    await tester.pump();
    expect(find.text('bank.example'), findsOneWidget);
    expect(find.text('YOUR RULES · 1 RULE'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('settings lock while connected, and the log says what happened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const NunyaApp(splash: false));
    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allowVpn')));
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Disconnect to change settings.'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);

    await tester.tap(find.text('Diagnostics'));
    // Not pumpAndSettle: the connected map's exit pulse never settles.
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.textContaining('connected to FI-1 Helsinki (preview'),
      findsOneWidget,
    );
    expect(find.text('engine: not in this preview'), findsOneWidget);
  });

  testWidgets(
    'a quick connect tile is marked when its server is the selected one',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const NunyaApp(splash: false));
      // FI-1 Helsinki is selected at start; DE-1 Frankfurt (24 ms) is the fastest.
      expect(find.byKey(const ValueKey('quick:Fastest')), findsOneWidget);
      await tester.tap(find.text('Fastest'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('quick:Fastest:selected')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the splash covers the launch, and offers a way past a slow lookup',
    (tester) async {
      await tester.pumpWidget(const NunyaApp());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Nunya'), findsOneWidget);
      expect(find.text('Continue without it'), findsNothing);

      // The lookup cannot succeed in a test, so the way past it appears.
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Continue without it'), findsOneWidget);
      await tester.tap(find.text('Continue without it'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Nunya'), findsNothing);
      expect(find.text('Not connected'), findsOneWidget);
    },
  );
}
