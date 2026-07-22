// The per-layer right-click context menu, ported from the egui
// `layer_context_menu` (crates/lumit-ui/src/shell/timeline/menu.rs): the things
// you can do to a layer in one place (the house pattern — right-click, never
// scattered buttons). Every entry now routes to a real op: Rename opens an
// in-place outline editor (committing `renameLayer`), Add effect opens the
// categorised effect picker (committing `addEffect`), Convert to sequenced and
// Trim to source end call the v0.5 ops (Trim is offered only for a retimed
// footage clip, as egui does, menu.rs:174-184).

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../widgets/controls.dart';
import 'columns.dart';

/// The actions the layer menu can raise.
enum _LayerMenuAction {
  rename,
  addEffect,
  addMask,
  blendMode,
  matte,
  parent,
  duplicate,
  delete,
  solo,
  enabled,
  motionBlur,
  convert,
  trim,
}

/// The starter mask shapes the "Add mask" submenu offers (egui menu.rs) — the
/// [kind] string is what `addMask` takes.
const List<(String label, String kind)> _maskShapes = [
  ('Rectangle', 'rectangle'),
  ('Ellipse', 'ellipse'),
  ('Star', 'star'),
];

/// Show the layer context menu at [position] (global) and run the chosen action
/// against [app]. Mirrors the egui item set. [onRename] is called for the
/// Rename entry so the row can open its in-place outline editor (the row owns
/// the edit state); every other entry is handled here.
Future<void> showLayerContextMenu({
  required BuildContext context,
  required AppStateStub app,
  required String compId,
  required BridgeLayer layer,
  required Offset position,
  VoidCallback? onRename,
}) async {
  // Trim to source end is offered only for a retimed footage clip — the egui
  // condition (menu.rs:174-184: `Footage { retime: Some(_) }`).
  final retimed =
      layer.kind == BridgeLayerKind.footage && layer.retime != null;
  final action = await showLumitPopup<_LayerMenuAction>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuRow(
            onPressed: () => close(_LayerMenuAction.rename),
            child: const Text('Rename'),
          ),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.addEffect),
            child: const _MenuSubmenuLabel('Add effect'),
          ),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.addMask),
            child: const _MenuSubmenuLabel('Add mask'),
          ),
          const _MenuDivider(),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.blendMode),
            child: const _MenuSubmenuLabel('Blend mode'),
          ),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.matte),
            child: const _MenuSubmenuLabel('Matte'),
          ),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.parent),
            child: const _MenuSubmenuLabel('Parent'),
          ),
          const _MenuDivider(),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.duplicate),
            child: const _MenuLabelWithShortcut('Duplicate', 'Ctrl+D'),
          ),
          MenuRow(
            onPressed: () => close(_LayerMenuAction.delete),
            child: const Text('Delete'),
          ),
          const _MenuDivider(),
          MenuRow(
            selected: layer.switches.solo,
            onPressed: () => close(_LayerMenuAction.solo),
            child: const Text('Solo'),
          ),
          MenuRow(
            selected: layer.switches.visible,
            onPressed: () => close(_LayerMenuAction.enabled),
            child: const Text('Enabled'),
          ),
          MenuRow(
            selected: layer.switches.motionBlur,
            onPressed: () => close(_LayerMenuAction.motionBlur),
            child: const Text('Motion blur'),
          ),
          if (layer.kind == BridgeLayerKind.footage) ...[
            const _MenuDivider(),
            MenuRow(
              onPressed: () => close(_LayerMenuAction.convert),
              child: const Text('Convert to sequenced layer'),
            ),
            if (retimed)
              MenuRow(
                onPressed: () => close(_LayerMenuAction.trim),
                child: const Text('Trim to source end'),
              ),
          ],
        ],
      ),
    ),
  );
  if (action == null) return;
  // The context menu has closed; the picker submenus open at the same anchor.
  if (!context.mounted) return;
  switch (action) {
    case _LayerMenuAction.duplicate:
      app.duplicateLayer(compId, layer.id);
    case _LayerMenuAction.delete:
      app.deleteLayer(compId, layer.id);
    case _LayerMenuAction.solo:
      app.setLayerSwitch(compId, layer.id, 'solo', !layer.switches.solo);
    case _LayerMenuAction.enabled:
      app.setLayerSwitch(compId, layer.id, 'visible', !layer.switches.visible);
    case _LayerMenuAction.motionBlur:
      app.setLayerSwitch(
          compId, layer.id, 'motion_blur', !layer.switches.motionBlur);
    case _LayerMenuAction.addMask:
      await _showMaskShapeMenu(
          context: context, app: app, compId: compId, layer: layer,
          position: position);
    case _LayerMenuAction.blendMode:
      await showBlendModePicker(
          context: context, app: app, compId: compId, layer: layer,
          position: position);
    case _LayerMenuAction.matte:
      await showMattePicker(
          context: context, app: app, compId: compId, layer: layer,
          position: position);
    case _LayerMenuAction.parent:
      await showParentPicker(
          context: context, app: app, compId: compId, layer: layer,
          position: position);
    case _LayerMenuAction.rename:
      // The row owns the in-place editor; it commits `renameLayer`.
      onRename?.call();
    case _LayerMenuAction.addEffect:
      await _showAddEffectMenu(
          context: context, app: app, compId: compId, layer: layer,
          position: position);
    case _LayerMenuAction.convert:
      app.convertToSequenced(compId, layer.id);
    case _LayerMenuAction.trim:
      app.trimToSourceEnd(compId, layer.id);
  }
}

/// The "Add effect" submenu: the built-in registry grouped under its category
/// headings (bridge v0.5 `category`/`categoryLabel`, mirroring the Effects &
/// presets browser), each row committing the effect through `addEffect`. An
/// older registry with no categories lists flat under one "Effects" heading. An
/// empty registry (no bridge) shows a quiet hint.
Future<void> _showAddEffectMenu({
  required BuildContext context,
  required AppStateStub app,
  required String compId,
  required BridgeLayer layer,
  required Offset position,
}) async {
  // Group by category, preserving the registry's order (first-seen wins) — the
  // same grouping the Effects & presets panel uses.
  final groups = <String, (String, List<BridgeEffectInfo>)>{};
  for (final e in app.listEffects()) {
    final key = e.category.isEmpty ? '' : e.category;
    final label = e.categoryLabel.isEmpty ? 'Effects' : e.categoryLabel;
    (groups[key] ??= (label, <BridgeEffectInfo>[])).$2.add(e);
  }
  final name = await showLumitPopup<String>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 220,
      child: groups.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text('No effects available'),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in groups.entries) ...[
                      if (entry.key.isNotEmpty)
                        _MenuCategoryHeading(entry.value.$1),
                      for (final e in entry.value.$2)
                        MenuRow(
                          onPressed: () => close(e.name),
                          child: Text(e.label),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    ),
  );
  if (name != null) app.addEffect(compId, layer.id, name);
}

/// A muted category heading inside the Add-effect submenu.
class _MenuCategoryHeading extends StatelessWidget {
  final String label;
  const _MenuCategoryHeading(this.label);
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Text(label,
          style: t.small.copyWith(
              color: t.textMuted, fontWeight: FontWeight.w600)),
    );
  }
}

/// The "Add mask" submenu: Rectangle / Ellipse / Star, each committing a
/// starter mask through `addMask` (the egui menu.rs shape set).
Future<void> _showMaskShapeMenu({
  required BuildContext context,
  required AppStateStub app,
  required String compId,
  required BridgeLayer layer,
  required Offset position,
}) async {
  final kind = await showLumitPopup<String>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 160,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final shape in _maskShapes)
            MenuRow(
              onPressed: () => close(shape.$2),
              child: Text(shape.$1),
            ),
        ],
      ),
    ),
  );
  if (kind != null) app.addMask(compId, layer.id, kind);
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Container(height: 1, color: t.hairline),
    );
  }
}

/// A menu label with a trailing chevron marking a submenu (the picker opens on
/// click at the same anchor — the house pattern keeps the family of choices in
/// one place rather than scattered).
class _MenuSubmenuLabel extends StatelessWidget {
  final String label;
  const _MenuSubmenuLabel(this.label);
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text('›', style: t.small.copyWith(color: t.textMuted)),
      ],
    );
  }
}

class _MenuLabelWithShortcut extends StatelessWidget {
  final String label;
  final String shortcut;
  const _MenuLabelWithShortcut(this.label, this.shortcut);
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(shortcut, style: t.small.copyWith(color: t.textMuted)),
      ],
    );
  }
}
