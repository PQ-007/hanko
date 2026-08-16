import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('without --dart-define config, the app says so instead of crashing',
      (tester) async {
    // Tests run without --dart-define-from-file, so Config.isConfigured is
    // false and Supabase is never initialised. The app has to survive that and
    // explain itself, rather than throwing out of main() with a null client —
    // which is exactly what a first-time contributor will hit.
    await tester.pumpWidget(const HankoApp());

    expect(find.textContaining('Missing Supabase config'), findsOneWidget);
    expect(find.textContaining('env.json'), findsWidgets);
  });
}
