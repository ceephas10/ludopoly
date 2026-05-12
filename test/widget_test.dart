import 'package:flutter_test/flutter_test.dart';
import 'package:ludopoly/main.dart';

void main() {
  testWidgets('app builds', (tester) async {
    await tester.pumpWidget(const LudoPolyApp());
    expect(find.text('Player 1'), findsOneWidget);
  });
}
