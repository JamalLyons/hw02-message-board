import 'package:flutter_test/flutter_test.dart';
import 'package:hw02_message_board/screens/splash_screen.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('splash shows title and progress while initializing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.byKey(const Key('splash-title')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('splash shows error and retry on init failure', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          error: 'Firebase failed to start',
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('Firebase failed to start'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
