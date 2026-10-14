import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calling_app/main.dart';
import 'package:calling_app/services/sip_service.dart';

void main() {
  testWidgets('shows the login screen when not signed in',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SipService().restoreConfig(null);

    await tester.pumpWidget(const CallingApp());
    await tester.pump();

    expect(find.text('Sign in with your SIP extension'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
