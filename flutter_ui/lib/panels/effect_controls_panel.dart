// The Effect controls panel (phase F4, first slice): the Transform property
// rows for the selected layer of the front composition, in the settings-card
// style. Effects stacks, keyframes and stopwatches are later waves — this slice
// is transform only.
//
// Honesty note (K-007): snapshot v2 carries no current transform *values* (only
// the setter op exists), so a value box shows the value the user set this
// session — an em-dash before any edit — and the group opens with a one-line
// hint saying so. Real current values arrive with snapshot v3. Each commit
// routes through `app.setTransform` and is one undo step (the op's nature).

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../icons/icons.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';

/// Fixed width of a value cell so the axis boxes line up down the group.
const double _cellWidth = 60.0;

class EffectControlsPanel extends StatelessWidget {
  final AppStateStub app;
  const EffectControlsPanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final comp = app.frontComp;
        final compId = app.frontCompIdResolved;
        final selectedId = app.selectedLayer;
        BridgeLayer? layer;
        if (comp != null && selectedId != null) {
          for (final l in comp.layers) {
            if (l.id == selectedId) {
              layer = l;
              break;
            }
          }
        }
        if (layer == null || compId == null) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                'Select a layer to edit its transform and effects here.',
                style: t.small,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          children: [
            _LayerTitle(layer: layer),
            const SizedBox(height: 6),
            _TransformGroup(app: app, compId: compId, layer: layer),
          ],
        );
      },
    );
  }
}

/// The selected layer's title line: type glyph + name.
class _LayerTitle extends StatelessWidget {
  final BridgeLayer layer;
  const _LayerTitle({required this.layer});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final (icon, tint) = _layerStyle(layer.kind, t);
    return Row(
      children: [
        lumitIcon(icon, size: 15, color: tint),
        const SizedBox(width: 6),
        Expanded(
          child: Text(layer.name, style: t.bodyPrimary, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The Transform group card: a titled surface holding the property rows.
class _TransformGroup extends StatelessWidget {
  final AppStateStub app;
  final String compId;
  final BridgeLayer layer;
  const _TransformGroup({
    required this.app,
    required this.compId,
    required this.layer,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final round = t.shape == ThemeShape.round;
    final threeD = layer.switches.threeD || layer.kind == BridgeLayerKind.camera;

    final rows = <Widget>[
      _HintRow(
        text: 'Values shown after first edit — current values arrive with '
            'snapshot v3.',
      ),
      _PairRow(
        app: app,
        compId: compId,
        layerId: layer.id,
        label: 'Anchor point',
        propX: 'anchor_x',
        propY: 'anchor_y',
        seed: 0,
      ),
      _PositionRow(
        app: app,
        compId: compId,
        layerId: layer.id,
        threeD: threeD,
      ),
      _ScaleRow(app: app, compId: compId, layerId: layer.id),
      _SingleRow(
        app: app,
        compId: compId,
        layerId: layer.id,
        label: 'Rotation',
        prop: 'rotation',
        seed: 0,
        suffix: '°',
        speed: 0.5,
      ),
      _SingleRow(
        app: app,
        compId: compId,
        layerId: layer.id,
        label: 'Opacity',
        prop: 'opacity',
        seed: 100,
        suffix: '%',
        min: 0,
        max: 100,
        decimals: 0,
        speed: 0.5,
      ),
      if (threeD) ...[
        _SingleRow(
          app: app,
          compId: compId,
          layerId: layer.id,
          label: 'Rotation x',
          prop: 'rotation_x',
          seed: 0,
          suffix: '°',
          speed: 0.5,
        ),
        _SingleRow(
          app: app,
          compId: compId,
          layerId: layer.id,
          label: 'Rotation y',
          prop: 'rotation_y',
          seed: 0,
          suffix: '°',
          speed: 0.5,
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Transform', style: t.small),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius:
                round ? BorderRadius.circular(t.tokens.cardRadius) : null,
            border: round ? null : Border.all(color: t.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Container(height: 1, color: t.hairline),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HintRow extends StatelessWidget {
  final String text;
  const _HintRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: t.small.copyWith(color: t.textDisabled)),
    );
  }
}

/// A property row: a left label and one or more value cells on the right.
class _RowShell extends StatelessWidget {
  final String label;
  final List<Widget> cells;
  const _RowShell({required this.label, required this.cells});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyPrimary)),
          const SizedBox(width: 12),
          ...cells,
        ],
      ),
    );
  }
}

/// A linked-by-nothing x/y pair (Anchor point): two independent value cells.
class _PairRow extends StatelessWidget {
  final AppStateStub app;
  final String compId;
  final String layerId;
  final String label;
  final String propX;
  final String propY;
  final num seed;
  const _PairRow({
    required this.app,
    required this.compId,
    required this.layerId,
    required this.label,
    required this.propX,
    required this.propY,
    required this.seed,
  });

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      cells: [
        _AxisField(
          app: app,
          compId: compId,
          layerId: layerId,
          prop: propX,
          seed: seed,
        ),
        const SizedBox(width: 4),
        _AxisField(
          app: app,
          compId: compId,
          layerId: layerId,
          prop: propY,
          seed: seed,
        ),
      ],
    );
  }
}

/// Position: x and y always, plus z when the layer is 3D.
class _PositionRow extends StatelessWidget {
  final AppStateStub app;
  final String compId;
  final String layerId;
  final bool threeD;
  const _PositionRow({
    required this.app,
    required this.compId,
    required this.layerId,
    required this.threeD,
  });

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: 'Position',
      cells: [
        _AxisField(
          app: app,
          compId: compId,
          layerId: layerId,
          prop: 'position_x',
          seed: 0,
        ),
        const SizedBox(width: 4),
        _AxisField(
          app: app,
          compId: compId,
          layerId: layerId,
          prop: 'position_y',
          seed: 0,
        ),
        if (threeD) ...[
          const SizedBox(width: 4),
          _AxisField(
            app: app,
            compId: compId,
            layerId: layerId,
            prop: 'position_z',
            seed: 0,
          ),
        ],
      ],
    );
  }
}

/// Scale: x and y with a link toggle. When linked (default) editing either axis
/// sets both to that value; unlinked, each edits independently.
///
/// Note: with no current values to read back (snapshot v3), the link sets both
/// axes to the same value rather than preserving an x:y ratio — the honest
/// degenerate until value read-back lands.
class _ScaleRow extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final String layerId;
  const _ScaleRow({
    required this.app,
    required this.compId,
    required this.layerId,
  });

  @override
  State<_ScaleRow> createState() => _ScaleRowState();
}

class _ScaleRowState extends State<_ScaleRow> {
  bool _linked = true;

  void _commitBoth(double v) {
    widget.app.setTransform(widget.compId, widget.layerId, 'scale_x', v);
    widget.app.setTransform(widget.compId, widget.layerId, 'scale_y', v);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return _RowShell(
      label: 'Scale',
      cells: [
        _AxisField(
          app: widget.app,
          compId: widget.compId,
          layerId: widget.layerId,
          prop: 'scale_x',
          seed: 100,
          suffix: '%',
          decimals: 1,
          speed: 0.5,
          onCommit: _linked ? _commitBoth : null,
        ),
        const SizedBox(width: 4),
        LumitTooltip(
          message: _linked
              ? 'Unlink scale (edit x and y separately)'
              : 'Link scale (edit both axes together)',
          child: HouseButton(
            frameless: true,
            small: true,
            onPressed: () => setState(() => _linked = !_linked),
            child: lumitIcon(
              _linked ? LumitIcon.link : LumitIcon.unlink,
              size: 13,
              color: _linked ? t.accent : t.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _AxisField(
          app: widget.app,
          compId: widget.compId,
          layerId: widget.layerId,
          prop: 'scale_y',
          seed: 100,
          suffix: '%',
          decimals: 1,
          speed: 0.5,
          onCommit: _linked ? _commitBoth : null,
        ),
      ],
    );
  }
}

/// A single-axis property row (Rotation, Opacity, Rotation x/y).
class _SingleRow extends StatelessWidget {
  final AppStateStub app;
  final String compId;
  final String layerId;
  final String label;
  final String prop;
  final num seed;
  final String? suffix;
  final num min;
  final num max;
  final int decimals;
  final double speed;
  const _SingleRow({
    required this.app,
    required this.compId,
    required this.layerId,
    required this.label,
    required this.prop,
    required this.seed,
    this.suffix,
    this.min = -100000,
    this.max = 100000,
    this.decimals = 1,
    this.speed = 1,
  });

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      cells: [
        _AxisField(
          app: app,
          compId: compId,
          layerId: layerId,
          prop: prop,
          seed: seed,
          suffix: suffix,
          min: min,
          max: max,
          decimals: decimals,
          speed: speed,
        ),
      ],
    );
  }
}

/// One transform value cell. Before the property is edited this session it
/// shows an em-dash placeholder; tapping it reveals a [DragValueField] seeded
/// with [seed] (no premature commit). Once a session value exists — or the user
/// has begun — it is a [DragValueField] that commits through `app.setTransform`.
class _AxisField extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final String layerId;
  final String prop;
  final num seed;
  final String? suffix;
  final num min;
  final num max;
  final int decimals;
  final double speed;

  /// When set, commit routes here instead of the plain per-property setter
  /// (the linked Scale row commits both axes together).
  final void Function(double value)? onCommit;

  const _AxisField({
    required this.app,
    required this.compId,
    required this.layerId,
    required this.prop,
    required this.seed,
    this.suffix,
    this.min = -100000,
    this.max = 100000,
    this.decimals = 1,
    this.speed = 1,
    this.onCommit,
  });

  @override
  State<_AxisField> createState() => _AxisFieldState();
}

class _AxisFieldState extends State<_AxisField> {
  bool _started = false;

  void _commit(num v) {
    final value = v.toDouble();
    final on = widget.onCommit;
    if (on != null) {
      on(value);
    } else {
      widget.app.setTransform(widget.compId, widget.layerId, widget.prop, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final session = widget.app.transformEditAt(widget.layerId, widget.prop);
    final key = ValueKey<String>('axis-${widget.prop}');
    if (session == null && !_started) {
      // The un-edited placeholder: a dash that begins editing on tap.
      return LumitTooltip(
        key: key,
        message: 'Not set this session — click to edit (snapshot v3 reads the '
            'current value)',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _started = true),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: _cellWidth,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: t.surface3,
                borderRadius: BorderRadius.circular(t.tokens.controlRadius),
              ),
              child: Text('—', style: t.body.copyWith(color: t.textDisabled)),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      key: key,
      width: _cellWidth,
      child: DragValueField(
        value: session ?? widget.seed,
        min: widget.min,
        max: widget.max,
        speed: widget.speed,
        decimals: widget.decimals,
        suffix: widget.suffix,
        onChanged: _commit,
      ),
    );
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
      BridgeLayerKind.adjustment => (LumitIcon.solid, t.layer.solid),
      BridgeLayerKind.unknown => (LumitIcon.footage, t.textMuted),
    };
