// The Timeline's comp-tab strip: one pill per composition in the snapshot, with
// the current-time readout on the right (07-UI-SPEC §4 top row). Clicking a pill
// fronts that comp. The pill styling is a local copy of the dock's tab pills
// (three-state fill), not an import of the dock's private widgets.

import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../widgets/controls.dart';

/// The strip of composition pills plus the playhead time readout. Shown only
/// when at least one comp is present; the panel draws its placeholder otherwise.
class CompTabStrip extends StatelessWidget {
  final AppStateStub app;
  const CompTabStrip({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final comps = app.compositions;
    final frontId = app.frontCompIdResolved;
    final comp = app.frontComp;
    final fps = comp?.fps.fps ?? 0;
    final seconds = fps > 0 ? app.previewFrame / fps : 0.0;
    return Container(
      height: 28,
      color: t.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: comps.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('No composition open', style: t.small),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in comps)
                        Padding(
                          padding: const EdgeInsets.only(right: 3, top: 3, bottom: 3),
                          child: _CompPill(
                            label: c.name,
                            selected: c.id == frontId,
                            onTap: () => app.frontCompSelect(c.id),
                          ),
                        ),
                    ],
                  ),
          ),
          if (comp != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'f${app.previewFrame} · ${seconds.toStringAsFixed(2)}s',
                style: t.small.copyWith(fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }
}

/// One comp pill — the dock's three-state tab styling, copied locally: a
/// selected pill fills `surface3` with an accent underline; idle pills are bare
/// and brighten on hover.
class _CompPill extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CompPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CompPill> createState() => _CompPillState();
}

class _CompPillState extends State<_CompPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scope = ThemeScope.of(context);
    final t = scope.theme;
    final fill = widget.selected
        ? t.surface3
        : _hover
            ? t.surface4
            : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: animationDuration(scope.animationLevel),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(t.tokens.controlRadius),
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? t.accent : const Color(0x00000000),
                width: 1.5,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: widget.selected ? t.bodyPrimary : t.body,
          ),
        ),
      ),
    );
  }
}
