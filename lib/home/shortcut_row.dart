import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// One Home shortcut (redesign spec §4.7). English only: the Tagalog title
/// stays inside the screen or sheet it opens.
class ShortcutTile {
  const ShortcutTile({required this.id, required this.icon, required this.label, required this.onTap});

  /// The tile's key is 'shortcut-$id'.
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The shortcuts that are shown sit side by side, in order, and share the row
/// equally; a null tile (its feature is off) leaves no gap (owner decision
/// after the 11 Nov 2026 pilot). No tile at all shows nothing.
class ShortcutRow extends StatelessWidget {
  const ShortcutRow({super.key, required this.tiles});

  final List<ShortcutTile?> tiles;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final t in tiles) ?t];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _Tile(tile: shown[i])),
        ],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile});

  final ShortcutTile tile;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('shortcut-${tile.id}'),
          onTap: tile.onTap,
          borderRadius: BorderRadius.circular(14),
          highlightColor: WmColors.inert,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Icon(tile.icon, size: 24, color: WmColors.green),
              const SizedBox(height: 6),
              Text(tile.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: WmColors.textSecondary, height: 1.2)),
            ]),
          ),
        ),
      );
}
