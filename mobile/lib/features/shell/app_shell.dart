import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'action_sheet.dart';

/// Four tabs around a center action button.
///
/// Each tab is its own go_router branch, so switching tabs keeps its scroll
/// position and navigation stack. The center slot is a NavigationBar
/// destination drawn as a raised button; selecting it opens the action sheet
/// and never becomes the selected tab.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _center = 2;

  int get _navIndex => shell.currentIndex < _center ? shell.currentIndex : shell.currentIndex + 1;

  void _onSelect(BuildContext context, WidgetRef ref, int navIndex) {
    if (navIndex == _center) {
      showActionSheet(context, ref);
      return;
    }
    final branch = navIndex < _center ? navIndex : navIndex - 1;
    // Tapping the current tab again pops it back to its root, the usual
    // bottom-nav convention.
    shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => _onSelect(context, ref, i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: T.navHome,
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: T.navStats,
          ),
          NavigationDestination(
            icon: _CenterButton(),
            label: '',
            tooltip: T.navActions,
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_kabaddi_outlined),
            selectedIcon: Icon(Icons.sports_kabaddi),
            label: T.navPvp,
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: T.navLibrary,
          ),
        ],
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: HankoColors.seal,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: HankoColors.sealDark.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.add, color: Colors.white, size: 30),
    );
  }
}
