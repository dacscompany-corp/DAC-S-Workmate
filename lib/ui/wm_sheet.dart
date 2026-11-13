import 'package:flutter/material.dart';

import 'theme.dart';

/// Dragged down further than this, the sheet closes when let go (spec §8.1).
const wmSheetCloseDrag = 110.0;

/// A flick down faster than this (logical px/s) closes it too.
const _closeVelocity = 700.0;

/// Opens a WorkMate sheet; [builder] returns a [WmSheetFrame]. Android Back,
/// a tap outside, the × button or dragging the header down closes it.
Future<T?> showWmSheet<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: const Color(0x6B0F110F),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 340), curve: Cubic(0.2, 0.8, 0.2, 1)),
      builder: builder,
    );

/// The sheet's chrome: grab handle, title (and Tagalog), optional back
/// arrow, close button, a scrolling body and an optional white footer.
class WmSheetFrame extends StatefulWidget {
  const WmSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.tall = false,
    required this.children,
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Shows a round back arrow (a form opened from another sheet).
  final VoidCallback? onBack;

  /// 92 % of the screen whatever the content; otherwise as tall as the content.
  final bool tall;
  final List<Widget> children;
  final Widget? footer;

  @override
  State<WmSheetFrame> createState() => _WmSheetFrameState();
}

class _WmSheetFrameState extends State<WmSheetFrame> {
  double _dy = 0;
  bool _dragging = false;

  void _drag(DragUpdateDetails d) => setState(() {
        _dragging = true;
        _dy = (_dy + d.delta.dy).clamp(0, double.infinity).toDouble();
      });

  void _springBack() => setState(() {
        _dragging = false;
        _dy = 0;
      });

  Future<void> _release(DragEndDetails d) async {
    if (_dy > wmSheetCloseDrag || (d.primaryVelocity ?? 0) > _closeVelocity) {
      final route = ModalRoute.of(context);
      await Navigator.of(context).maybePop();
      // maybePop returns true even when a PopScope refuses the close, so ask
      // the route whether it is still the current one. A refused close (unsaved
      // input guarded below) leaves the sheet where it was: spring it back. A
      // real pop slides out from where it is, so it is not reset.
      if (mounted && (route?.isCurrent ?? true)) _springBack();
      return;
    }
    _springBack();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    final footer = widget.footer;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _dy, 0),
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: WmColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Color(0x24000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: Column(
          mainAxisSize: widget.tall ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              key: const Key('wm-sheet-handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _drag,
              onVerticalDragEnd: _release,
              onVerticalDragCancel: _springBack,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Column(children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: WmColors.textFaint, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.onBack case final back?) ...[
                      WmRoundButton(key: const Key('wm-sheet-back'), icon: Icons.arrow_back, label: 'Back', onTap: back),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitle, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(width: 4),
                    WmRoundButton(key: const Key('wm-sheet-close'), icon: Icons.close, label: 'Close', onTap: _close),
                  ]),
                ]),
              ),
            ),
            Flexible(
              fit: widget.tall ? FlexFit.tight : FlexFit.loose,
              child: ListView(
                shrinkWrap: !widget.tall,
                padding: EdgeInsets.fromLTRB(20, 6, 20, 20 + (footer == null ? safeBottom : 0)),
                children: widget.children,
              ),
            ),
            if (footer != null)
              Container(
                // A tall footer (a refusal over the button, large text) scrolls in
                // its share of the room above the keyboard.
                constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .45),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: WmColors.border))),
                child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + safeBottom), child: footer),
              ),
          ],
        ),
      ),
    );
  }
}

/// The round 36-px button of the sheets and pages, with a 48-px tap area.
class WmRoundButton extends StatelessWidget {
  const WmRoundButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        // 36 px to look at, 48 px to hit (Phase 2 spec §9).
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            type: MaterialType.transparency,
            child: InkResponse(
              onTap: onTap,
              radius: 24,
              child: Center(
                child: Ink(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: WmColors.inert, shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: WmColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
      );
}

/// A sheet's main button (min height 56, green; grey and inert with no action).
class WmSheetButton extends StatelessWidget {
  const WmSheetButton({super.key, required this.label, required this.icon, required this.onPressed, this.tagalog, this.busy = false});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tagalog;

  /// A spinner instead of the label, and no second tap.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tagalog = this.tagalog;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: WmColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: busy ? WmColors.green : WmColors.textDisabled,
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22),
                const SizedBox(width: 8),
                Flexible(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
              ]),
              if (tagalog != null)
                Text(tagalog, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xBFFFFFFF))),
            ]),
    );
  }
}

/// A short line under a sheet's main button (Phase 2 spec §9): muted, or
/// brown when it says why the button is locked.
class WmSheetNote extends StatelessWidget {
  const WmSheetNote(this.text, {super.key, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: TextStyle(fontSize: 13, color: warning ? WmColors.brown : WmColors.textMuted)),
      );
}
