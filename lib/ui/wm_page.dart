import 'package:flutter/material.dart';

import 'theme.dart';
import 'wm_sheet.dart';

/// A full page in the redesign's look (Phase 3 spec §11): the round back
/// button, a big title, an optional round action on the right, a scrolling
/// body with 20-px sides and an optional footer pinned at the bottom for the
/// main button and its note. Back goes through `maybePop`, so Android Back and
/// any `PopScope` behave as before; the tooltip "Back" keeps `pageBack` working.
class WmPage extends StatelessWidget {
  const WmPage({super.key, required this.title, required this.children, this.action, this.footer});

  final String title;
  final List<Widget> children;

  /// A round button on the right of the title (Delete draft, Remove item).
  final Widget? action;

  /// Pinned under the scrolling body: the main button and its note.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final footer = this.footer;
    return Scaffold(
      backgroundColor: WmColors.canvas,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Tooltip(
                message: 'Back',
                excludeFromSemantics: true,
                child: WmRoundButton(
                  key: const Key('wm-page-back'),
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(header: true, child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2))),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 4), action],
            ]),
          ),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: children)),
          if (footer != null)
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: WmColors.hairline))),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: footer,
            ),
        ]),
      ),
    );
  }
}
