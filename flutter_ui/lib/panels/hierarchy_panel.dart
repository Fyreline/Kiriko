// The composition hierarchy panel (phase F4; K-102, the AE-style composition
// flowchart in its simplest tree form): a read-only indented tree of the front
// composition — its layers, with precomp layers expandable to reveal the
// layers of the composition they nest.
//
// In plain terms: complex projects nest compositions inside one another (a
// layer can *be* another composition). This panel shows that nesting as an
// indented, foldable outline. It is a viewer, not an editor: clicking a layer
// row selects it; it changes nothing. This is the simple tree form of the
// future node-graph flowchart.
//
// Note on nesting resolution: snapshot v2 tags a precomp layer only as
// `kind:"precomp"` — it does not carry the nested comp's id — so we resolve the
// nested comp by matching the layer's name against the project's compositions.
// Snapshot v3 should carry the source-comp id, at which point this matches by
// id (and comp-scoped selection becomes possible). Cycle-guarded by comp name.

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../icons/icons.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';

class HierarchyPanel extends StatefulWidget {
  final AppStateStub app;
  const HierarchyPanel({super.key, required this.app});

  @override
  State<HierarchyPanel> createState() => _HierarchyPanelState();
}

class _HierarchyPanelState extends State<HierarchyPanel> {
  /// Explicit twirl state per row path; absent means "the default for its
  /// depth" (open for the first level, closed deeper — matching the egui panel).
  final Map<String, bool> _twirl = {};

  bool _isOpen(String path, int depth) => _twirl[path] ?? (depth < 2);

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final comps = widget.app.compositions;
        // The front comp: the tab the Timeline/Viewer front, else the first.
        final frontId = widget.app.frontCompIdResolved;
        CompTabInfo? front;
        for (final c in comps) {
          if (c.id == frontId) {
            front = c;
            break;
          }
        }
        front ??= comps.isEmpty ? null : comps.first;
        if (front == null) {
          return _emptyHint(t);
        }
        // A name → composition index for resolving nested precomp layers.
        final byName = <String, CompTabInfo>{};
        for (final c in comps) {
          byName.putIfAbsent(c.name, () => c);
        }

        final rows = <Widget>[];
        // The comp header row.
        rows.add(_CompHeaderRow(name: front.name));
        _appendLayers(
          rows,
          comp: front.comp,
          byName: byName,
          depth: 1,
          path: front.id,
          visited: {front.name},
          theme: t,
        );
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: rows,
        );
      },
    );
  }

  Widget _emptyHint(LumitTheme t) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            'Open a composition to see its layers and the compositions nested '
            'inside it.',
            style: t.small,
            textAlign: TextAlign.center,
          ),
        ),
      );

  /// Append one composition's layers, indented to [depth]. Precomp layers fold
  /// open to their nested composition's layers; [visited] breaks any cycle so
  /// the walk always terminates.
  void _appendLayers(
    List<Widget> rows, {
    required BridgeComp comp,
    required Map<String, CompTabInfo> byName,
    required int depth,
    required String path,
    required Set<String> visited,
    required LumitTheme theme,
  }) {
    if (comp.layers.isEmpty) {
      rows.add(_MutedRow(depth: depth, text: 'no layers'));
      return;
    }
    for (final layer in comp.layers) {
      final (icon, tint) = _layerStyle(layer.kind, theme);
      final selected = widget.app.selectedLayer == layer.id;
      final rowPath = '$path/${layer.id}';
      final isPrecomp = layer.kind == BridgeLayerKind.precomp;
      final nested = isPrecomp ? byName[layer.name] : null;
      final open = isPrecomp && _isOpen(rowPath, depth);
      rows.add(_LayerRow(
        icon: icon,
        tint: tint,
        name: layer.name,
        depth: depth,
        selected: selected,
        twirlOpen: isPrecomp ? open : null,
        twirlKey: isPrecomp ? ValueKey<String>('twirl-${layer.id}') : null,
        onTwirl: isPrecomp
            ? () => setState(() => _twirl[rowPath] = !open)
            : null,
        onTap: () => widget.app.selectLayer(layer.id),
      ));
      if (open) {
        if (nested == null) {
          rows.add(_MutedRow(
            depth: depth + 1,
            text: 'nested comp not found in project',
          ));
        } else if (visited.contains(nested.name)) {
          rows.add(_MutedRow(
            depth: depth + 1,
            text: '… recursive nesting',
            warn: true,
          ));
        } else {
          _appendLayers(
            rows,
            comp: nested.comp,
            byName: byName,
            depth: depth + 1,
            path: rowPath,
            visited: {...visited, nested.name},
            theme: theme,
          );
        }
      }
    }
  }
}

/// The icon and tint for a layer kind, mirroring the egui `layer_type_style`.
(LumitIcon, Color) _layerStyle(BridgeLayerKind kind, LumitTheme t) =>
    switch (kind) {
      BridgeLayerKind.footage => (LumitIcon.footage, t.layer.footage),
      BridgeLayerKind.sequence => (LumitIcon.sequence, t.layer.sequence),
      BridgeLayerKind.precomp => (LumitIcon.comp, t.layer.precomp),
      BridgeLayerKind.solid => (LumitIcon.solid, t.layer.solid),
      BridgeLayerKind.text => (LumitIcon.text, t.layer.text),
      BridgeLayerKind.camera => (LumitIcon.camera, t.layer.camera),
      // An adjustment layer reuses the solid glyph/colour, like the egui side.
      BridgeLayerKind.adjustment => (LumitIcon.solid, t.layer.solid),
      BridgeLayerKind.unknown => (LumitIcon.footage, t.textMuted),
    };

double _indentOf(int depth) => 6.0 + depth * 14.0;

/// The composition header row: the comp glyph in the accent, the comp name.
class _CompHeaderRow extends StatelessWidget {
  final String name;
  const _CompHeaderRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: EdgeInsets.only(left: _indentOf(0), right: 6, top: 2, bottom: 4),
      child: Row(
        children: [
          lumitIcon(LumitIcon.comp, size: 14, color: t.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name, style: t.bodyPrimary, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// A muted note row ("no layers", "… recursive nesting").
class _MutedRow extends StatelessWidget {
  final int depth;
  final String text;
  final bool warn;
  const _MutedRow({required this.depth, required this.text, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: EdgeInsets.only(left: _indentOf(depth) + 18, right: 6, top: 2, bottom: 2),
      child: Text(text, style: t.small.copyWith(color: warn ? t.warning : t.textMuted)),
    );
  }
}

/// One selectable layer row: an optional twirl (precomp only), the type glyph
/// in its layer colour, and the name. Hover fills with `surface4`; the selected
/// row fills faintly and draws its name in the primary text colour.
class _LayerRow extends StatefulWidget {
  final LumitIcon icon;
  final Color tint;
  final String name;
  final int depth;
  final bool selected;
  final bool? twirlOpen;
  final Key? twirlKey;
  final VoidCallback? onTwirl;
  final VoidCallback onTap;

  const _LayerRow({
    required this.icon,
    required this.tint,
    required this.name,
    required this.depth,
    required this.selected,
    required this.twirlOpen,
    required this.twirlKey,
    required this.onTwirl,
    required this.onTap,
  });

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final fill = widget.selected
        ? t.accent.withValues(alpha: 0.18)
        : _hover
            ? t.surface4
            : null;
    final twirl = widget.twirlOpen == null
        ? const SizedBox(width: 18)
        : GestureDetector(
            key: widget.twirlKey,
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTwirl,
            child: SizedBox(
              width: 18,
              child: lumitIcon(
                widget.twirlOpen! ? LumitIcon.twirlOpen : LumitIcon.twirlClosed,
                size: 10,
                color: t.textMuted,
              ),
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 22,
          color: fill,
          padding: EdgeInsets.only(left: _indentOf(widget.depth), right: 6),
          child: Row(
            children: [
              twirl,
              lumitIcon(widget.icon, size: 13, color: widget.tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.name,
                  style: widget.selected
                      ? t.bodyPrimary
                      : t.body.copyWith(color: t.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
