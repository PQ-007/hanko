import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/confirm_dialog.dart';
import 'package:mobile/core/strings.dart';
import 'package:mobile/core/theme.dart';

void main() {
  // Pumps a button that opens the dialog and records what it resolved to.
  Future<List<bool>> open(WidgetTester tester, Brightness b) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildHankoTheme(b),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => results.add(
              await askConfirm(context, title: 'Багц устгах уу?', body: 'body', danger: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  for (final b in Brightness.values) {
    testWidgets('confirm resolves true ($b)', (tester) async {
      final r = await open(tester, b);
      expect(find.text('Багц устгах уу?'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      await tester.tap(find.text(T.delete));
      await tester.pumpAndSettle();
      expect(r, [true]);
    });
  }

  testWidgets('cancel resolves false', (tester) async {
    final r = await open(tester, Brightness.light);
    await tester.tap(find.text(T.cancel));
    await tester.pumpAndSettle();
    expect(r, [false]);
  });

  testWidgets('tapping outside resolves false', (tester) async {
    final r = await open(tester, Brightness.light);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(r, [false]);
    expect(find.text('Багц устгах уу?'), findsNothing);
  });
}
