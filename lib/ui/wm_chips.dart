import 'package:flutter/material.dart';

import 'theme.dart';

/// A filter chip with a count. My Work (Today · Upcoming · Waiting · Done) and
/// Requests (All · Drafts · Pending sync · Needs attention) both use it, so the
/// two tabs cannot drift apart (redesign Phase 3 spec §7).
class WmCountChip extends StatelessWidget {
  const WmCountChip({super.key, required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
            color: selected ? WmColors.text : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: selected ? WmColors.text : WmColors.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                height: 38,
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : WmColors.textSecondary)),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0x33FFFFFF) : WmColors.inert,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    // Centred without growing: a Container `alignment` would
                    // stretch the bubble to the chip's full height.
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text('$count',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1, color: selected ? Colors.white : WmColors.textSecondary)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      );
}

/// A white rounded button with a green icon and label (Meeting notes, My
/// proposals, Find previous item). [busy] shows a spinner and ignores taps.
class WmPillButton extends StatelessWidget {
  const WmPillButton({super.key, required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: busy,
        child: Material(
            color: Colors.white,
            shape: const StadiumBorder(side: BorderSide(color: WmColors.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: busy ? null : onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (busy)
                    const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    Icon(icon, size: 20, color: WmColors.green),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WmColors.green))),
                ]),
              ),
            ),
          ),
      );
}

/// One horizontal row of chips that runs to the screen edges while its first
/// chip lines up with the page's 20-px side padding. Put it straight into a
/// list whose side padding is 20.
class WmChipRow extends StatelessWidget {
  const WmChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: LayoutBuilder(
          builder: (context, box) => OverflowBox(
            maxWidth: box.maxWidth + 40,
            minWidth: box.maxWidth + 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  children[i],
                ],
              ]),
            ),
          ),
        ),
      );
}

/// A choice chip without a count (Team, Material / Tool, the Find previous
/// filters): the same look as [WmCountChip] (Phase 3 spec §11).
class WmChoiceChip extends StatelessWidget {
  const WmChoiceChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? WmColors.text : Colors.white,
          shape: StadiumBorder(side: BorderSide(color: selected ? WmColors.text : WmColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Hugs its label (a Container `alignment` would stretch the chip
              // to the full width); still fills its share inside an Expanded.
              child: Center(
                widthFactor: 1,
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : WmColors.textSecondary)),
              ),
            ),
          ),
        ),
      );
}

/// A switch of a few equal choices: a grey track, the chosen one white
/// (History's Week / Month, the Tools sheet's Mine / Team / My records).
/// Each segment is (value, label, key); its key sits on the tappable segment.
class WmSegmented<T> extends StatelessWidget {
  const WmSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<(T value, String label, Key? segmentKey)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: WmColors.inert, borderRadius: BorderRadius.circular(999)),
        child: Row(children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(segments[i].$1, segments[i].$2, segments[i].$3)),
          ],
        ]),
      );

  Widget _segment(T value, String label, Key? segmentKey) {
    final chosen = value == selected;
    return Semantics(
      key: segmentKey,
      button: true,
      selected: chosen,
      child: Material(
        color: chosen ? Colors.white : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onChanged(value),
          child: SizedBox(
            height: 38,
            child: Center(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: chosen ? FontWeight.w800 : FontWeight.w600,
                    color: chosen ? WmColors.text : WmColors.textMuted,
                  )),
            ),
          ),
        ),
      ),
    );
  }
}
