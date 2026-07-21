// The live Project panel (phase F1 + the interactive slice): one row per
// document item, folders nesting their children. A click selects (highlight); a
// double-click opens a composition (fronts it) or places a footage item into the
// front comp as a new layer; a right-click raises the egui project menu
// (Composition settings / Relink / Find missing footage / Move to root / Delete);
// and a footage row is Draggable onto the Timeline lane. An empty document shows
// a quiet hint.

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../icons/icons.dart';
import '../shell/dialogs.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';

class ProjectPanel extends StatelessWidget {
  final AppStateStub app;
  const ProjectPanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final snapshot = app.snapshot;
        final items = snapshot?.items ?? const <BridgeItem>[];
        if (items.isEmpty) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                'No items yet — import footage or create a composition',
                style: t.small,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final rows = <Widget>[];
        void walk(BridgeItem item, int depth) {
          rows.add(_ProjectRow(app: app, item: item, depth: depth));
          for (final child in item.children) {
            walk(child, depth + 1);
          }
        }

        for (final item in items) {
          walk(item, 0);
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: rows,
        );
      },
    );
  }
}

/// One Project panel row: a type icon (tinted with the layer colours where it
/// reads well), the item name, indented 14 px per level. Selected rows carry the
/// `surface2` highlight, hovered rows the `surface4` fill. A composition
/// double-click fronts it; a footage double-click (or a drag onto the Timeline)
/// places it as a layer; a right-click raises the project context menu.
class _ProjectRow extends StatefulWidget {
  final AppStateStub app;
  final BridgeItem item;
  final int depth;
  const _ProjectRow({
    required this.app,
    required this.item,
    required this.depth,
  });

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hover = false;

  AppStateStub get app => widget.app;
  BridgeItem get item => widget.item;

  void _handleDoubleTap() {
    switch (item.kind) {
      case BridgeItemKind.composition:
        app.frontCompSelect(item.id);
      case BridgeItemKind.footage:
        app.addFootageToFrontComp(item.id);
      case BridgeItemKind.folder:
      case BridgeItemKind.solid:
      case BridgeItemKind.unknown:
        // Folders and solids have no double-click action (matching egui).
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final (icon, tint) = _iconFor(item.kind, t);
    final selected = app.selectedProjectItem == item.id;
    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => app.selectProjectItem(item.id),
        onDoubleTap: _handleDoubleTap,
        onSecondaryTapDown: (d) {
          app.selectProjectItem(item.id);
          showProjectContextMenu(
            context: context,
            app: app,
            item: item,
            position: d.globalPosition,
          );
        },
        child: Container(
          height: 22,
          color: selected
              ? t.surface2
              : _hover
                  ? t.surface4
                  : null,
          padding:
              EdgeInsets.only(left: 6.0 + widget.depth * 14.0, right: 6),
          child: Row(
            children: [
              lumitIcon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.name,
                  style: t.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // A footage row is draggable onto the Timeline lane (the drop places it as a
    // new layer). Non-footage rows are plain.
    if (item.kind == BridgeItemKind.footage) {
      return Draggable<FootageDragData>(
        data: FootageDragData(item.id, item.name),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(name: item.name),
        child: row,
      );
    }
    return row;
  }

  /// The icon and its tint for a kind. Footage/composition/solid take their
  /// layer colours; folders take the muted text colour (they are structure, not
  /// content); an unknown kind falls back to a plain muted dot-style icon.
  (LumitIcon, Color) _iconFor(BridgeItemKind kind, LumitTheme t) =>
      switch (kind) {
        BridgeItemKind.footage => (LumitIcon.footage, t.layer.footage),
        BridgeItemKind.folder => (LumitIcon.folder, t.textMuted),
        BridgeItemKind.composition => (LumitIcon.comp, t.layer.precomp),
        BridgeItemKind.solid => (LumitIcon.solid, t.layer.solid),
        BridgeItemKind.unknown => (LumitIcon.footage, t.textMuted),
      };
}

/// The floating label shown under the pointer while a footage row is dragged.
class _DragFeedback extends StatelessWidget {
  final String name;
  const _DragFeedback({required this.name});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return FloatSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lumitIcon(LumitIcon.footage, size: 13, color: t.layer.footage),
            const SizedBox(width: 6),
            Text(name, style: t.small),
          ],
        ),
      ),
    );
  }
}

/// The actions the project context menu can raise (the egui project row menu,
/// panels.rs:909). Only [compSettings] is wired to a real op; the rest are
/// honest notice stubs pending their bridge ops (see 05-PARITY-CHECKLIST).
enum _ProjectMenuAction {
  compSettings,
  relink,
  findMissing,
  moveToRoot,
  delete,
}

/// Show the project context menu at [position] and run the chosen action.
/// Mirrors the egui item set; the entries without a bridge op speak through the
/// status line rather than doing nothing.
Future<void> showProjectContextMenu({
  required BuildContext context,
  required AppStateStub app,
  required BridgeItem item,
  required Offset position,
}) async {
  final isComp = item.kind == BridgeItemKind.composition;
  final action = await showLumitPopup<_ProjectMenuAction>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 210,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuRow(
            onPressed: () => close(_ProjectMenuAction.compSettings),
            child: const Text('Composition settings…'),
          ),
          MenuRow(
            onPressed: () => close(_ProjectMenuAction.relink),
            child: const Text('Relink…'),
          ),
          MenuRow(
            onPressed: () => close(_ProjectMenuAction.findMissing),
            child: const Text('Find missing footage'),
          ),
          MenuRow(
            onPressed: () => close(_ProjectMenuAction.moveToRoot),
            child: const Text('Move to root'),
          ),
          MenuRow(
            onPressed: () => close(_ProjectMenuAction.delete),
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  if (!context.mounted) return;
  switch (action) {
    case _ProjectMenuAction.compSettings:
      if (isComp) {
        // Front the comp so the settings dialogue seeds and commits to it.
        app.frontCompSelect(item.id);
        await showCompositionSettingsDialog(context, app);
      } else {
        app.setNotice('Composition settings apply to a composition');
      }
    case _ProjectMenuAction.relink:
      // Awaits a relink bridge op (05-PARITY-CHECKLIST).
      app.setNotice('Relink — engine op arrives with the media relink pass');
    case _ProjectMenuAction.findMissing:
      app.setNotice('Find missing footage — engine op still to arrive');
    case _ProjectMenuAction.moveToRoot:
      app.setNotice('Move to root — engine op still to arrive');
    case _ProjectMenuAction.delete:
      // No delete-item bridge op exists yet (state.rs/edits.rs have only
      // delete_layer); honest notice until one lands.
      app.setNotice('Delete item — engine op still to arrive');
  }
}
