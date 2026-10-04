import 'package:flutter_test/flutter_test.dart';
import 'package:nunya_mobile/main.dart';

void main() {
  testWidgets('the starter does not claim a VPN connection', (tester) async {
    await tester.pumpWidget(const NunyaApp());

    expect(find.text('VPN setup is not available yet.'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
  });
}
