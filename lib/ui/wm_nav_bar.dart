import 'package:flutter/material.dart';

import 'theme.dart';

/// The bottom bar (redesign spec §7.1): Flutter's NavigationBar, themed in
/// workMateTheme(), with a thin line on top. Both shells use it.
class WmNavBar extends StatelessWidget {
  const WmNavBar({super.key, required this.selectedIndex, required this.onDestinationSelected, required this.destinations});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const Key('wm-nav-bar'),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: WmColors.border))),
        child: NavigationBar(selectedIndex: selectedIndex, onDestinationSelected: onDestinationSelected, destinations: destinations),
      );
}

/// A red count bubble with a white ring at the icon's top right; nothing at 0.
class RingBadge extends StatelessWidget {
  const RingBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      Positioned(
        top: -7,
        right: -12,
        child: Container(
          key: const Key('ring-badge-bubble'),
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WmColors.danger,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1)),
        ),
      ),
    ]);
  }
}
