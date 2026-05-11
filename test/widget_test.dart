import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bb_planet_desktop/app/app.dart';

void main() {
  testWidgets('renders operator login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChatOpsDesktopApp()));
    await tester.pumpAndSettle();

    expect(find.text('BB Planet Chat Ops'), findsOneWidget);
    expect(find.text('Operator account'), findsOneWidget);
  });
}
