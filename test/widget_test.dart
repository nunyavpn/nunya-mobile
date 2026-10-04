import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/main.dart';

void main() {
  testWidgets('preview connection never claims a running VPN', (tester) async {
    await tester.pumpWidget(const NunyaApp());
    expect(find.text('DEMO · NO VPN'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pump();
    expect(find.text('Preview connected'), findsOneWidget);
    expect(find.text('Simulation only · VPN inactive'), findsOneWidget);
    expect(find.text("You're protected"), findsNothing);
  });

  testWidgets('search filters mock servers and selection updates home', (
    tester,
  ) async {
    await tester.pumpWidget(const NunyaApp());
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
}
