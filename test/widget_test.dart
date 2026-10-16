import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_connect_mobile/main.dart';

void main() {
  testWidgets('App loads and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OmniConnectApp()));
    await tester.pumpAndSettle();

    expect(find.text('OmniConnect'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
