import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'hero.dart';
import 'sprite_view.dart';
import 'sprites.dart';

/// Pick the fighter used in Monster Hunt and across the app's artwork.
Future<void> showHeroPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _HeroPicker(),
  );
}

class _HeroPicker extends ConsumerWidget {
  const _HeroPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(heroProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(T.heroPickerTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Text(T.heroPickerHint, style: TextStyle(color: HankoColors.inkSoft)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final slug in playerRoster)
                Material(
                  color: slug == current ? HankoColors.sealTint : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: slug == current ? HankoColors.seal : HankoColors.lineSoft,
                      width: slug == current ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(heroProvider.notifier).choose(slug);
                      Navigator.of(context).pop();
                    },
                    child: Center(child: SpriteView(slug: slug, size: 76)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
