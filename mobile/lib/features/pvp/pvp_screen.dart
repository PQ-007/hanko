import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../battle/hero.dart';
import '../battle/sprite_view.dart';

/// Placeholder until the duel stage: the route exists so the tab is real, and
/// your hero squares up against a rival to show what's coming.
class PvpScreen extends ConsumerWidget {
  const PvpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = ref.watch(heroProvider);
    final rival = hero == 'black-knight-a' ? 'knight' : 'black-knight-a';
    return Scaffold(
      appBar: AppBar(title: const Text(T.duelKicker)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  color: HankoColors.arena,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SpriteView(slug: hero, size: 130),
                    const Text('VS',
                        style: TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 18)),
                    SpriteView(slug: rival, size: 130, flip: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(T.multiplayerTitle,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(T.multiplayerDesc,
                  textAlign: TextAlign.center, style: TextStyle(color: context.hk.inkSoft)),
              const SizedBox(height: 14),
              Chip(
                label: const Text(T.comingSoon),
                backgroundColor: context.hk.sealTint,
                side: BorderSide.none,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
