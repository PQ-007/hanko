import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/battle/sprite_view.dart';
import 'package:mobile/features/battle/sprites.dart';

// SpriteView steps frames on a timer instead of an AnimationController, so a
// sprite on screen no longer drives a frame on every vsync. These pin what
// the controller used to guarantee — battle and duel advance on
// onOneShotEnd — and the point of the change: an idling sprite leaves the
// app idle between frames.
void main() {
  const slug = defaultPlayerCharacter;

  Future<void> warm(WidgetTester tester, String state) async {
    // Decode every clip for real, outside fake time, before anything mounts.
    // A sprite preloads its character's other clips, and a load started on
    // fake time never finishes — the cache would hand that stuck future to
    // the next test.
    await tester.runAsync(() => Future.wait(spriteFrames[slug]!.keys.map((s) => SpriteSheets.load(slug, s))));
  }

  // The sheet's future completed in real time, so the widget's await on it
  // resumes only once real time runs; then pump to build with it.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Widget host(Widget child) => Directionality(textDirection: TextDirection.ltr, child: Center(child: child));

  testWidgets('a one-shot ends once, at the end of its clip', (tester) async {
    expect(framesOf(slug, 'attack01'), greaterThan(1));
    await warm(tester, 'attack01');
    var ended = 0;
    await tester.pumpWidget(host(SpriteView(slug: slug, state: 'attack01', onOneShotEnd: () => ended++)));
    await settle(tester);

    await tester.pump(const Duration(milliseconds: oneShotMs - 30));
    expect(ended, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(ended, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(ended, 1, reason: 'held on its last frame, not replayed');
  });

  testWidgets('replayKey restarts the same clip', (tester) async {
    await warm(tester, 'attack01');
    var ended = 0;
    Widget sprite(int key) =>
        host(SpriteView(slug: slug, state: 'attack01', replayKey: key, onOneShotEnd: () => ended++));
    await tester.pumpWidget(sprite(0));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: oneShotMs + 30));
    expect(ended, 1);

    await tester.pumpWidget(sprite(1));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: oneShotMs + 30));
    expect(ended, 2);
  });

  testWidgets('paused while TickerMode is off, resumes when on', (tester) async {
    await warm(tester, 'attack01');
    var ended = 0;
    Widget sprite(bool on) => host(TickerMode(
          enabled: on,
          child: SpriteView(slug: slug, state: 'attack01', onOneShotEnd: () => ended++),
        ));
    await tester.pumpWidget(sprite(false));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: oneShotMs * 3));
    expect(ended, 0);

    await tester.pumpWidget(sprite(true));
    await tester.pump(const Duration(milliseconds: oneShotMs + 30));
    expect(ended, 1);
  });

  testWidgets('an idling sprite schedules no frames between steps', (tester) async {
    expect(framesOf(slug, 'idle'), greaterThan(1));
    await warm(tester, 'idle');
    await tester.pumpWidget(host(const SpriteView(slug: slug)));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);

    // ...but does draw again when its frame changes.
    // Advance time without drawing, so the request is still pending.
    await tester.binding.delayed(Duration(milliseconds: loopMs ~/ framesOf(slug, 'idle') + 5));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}
