// The Viewer tool row (phase F-D): Select / Hand / Shape / Pen, mirroring the
// egui toolbar (crates/lumit-ui/src/shell/app_update.rs:971 area). Each tool is
// an icon toggle (accent when active); the Shape button wears the current mask
// shape and a right-click picks Rectangle / Ellipse / Star, exactly as the egui
// `shape_resp.context_menu` does. Tool state lives on the additive
// `AppStateStub.viewerTool` / `viewerShape` (the Dart mirror of the egui
// `ToolMode` / `ShapeKind`).

import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../state/app_state.dart';
import '../widgets/controls.dart';

class ViewerToolbar extends StatelessWidget {
  final AppStateStub app;
  const ViewerToolbar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final tool = app.viewerTool;
        return Container(
          height: 28,
          color: t.surface1,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              _ToolButton(
                icon: LumitIcon.pointer,
                active: tool == ToolMode.select,
                tooltip: 'Select / move the view (V)',
                onTap: () => app.setViewerTool(ToolMode.select),
              ),
              _ToolButton(
                icon: LumitIcon.move,
                active: tool == ToolMode.hand,
                tooltip: 'Drag to pan the view (H)',
                onTap: () => app.setViewerTool(ToolMode.hand),
              ),
              _ShapeToolButton(app: app, active: tool == ToolMode.shape),
              _ToolButton(
                icon: LumitIcon.pen,
                active: tool == ToolMode.pen,
                tooltip: 'Click points to draw a mask; click the first to close '
                    '(G)',
                onTap: () => app.setViewerTool(ToolMode.pen),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single tool toggle: the glyph in the accent when active, muted otherwise.
class _ToolButton extends StatelessWidget {
  final LumitIcon icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return LumitTooltip(
      message: tooltip,
      child: HouseButton(
        frameless: true,
        small: true,
        onPressed: onTap,
        child: lumitIcon(
          icon,
          size: 15,
          color: active ? t.accent : t.textMuted,
        ),
      ),
    );
  }
}

/// The Shape tool button: it wears the current [ShapeKind]'s glyph; a left-click
/// selects the Shape tool, a right-click raises the Rectangle / Ellipse / Star
/// picker (the egui `shape_resp.context_menu`).
class _ShapeToolButton extends StatelessWidget {
  final AppStateStub app;
  final bool active;
  const _ShapeToolButton({required this.app, required this.active});

  LumitIcon get _icon => switch (app.viewerShape) {
        ShapeKind.rectangle => LumitIcon.rectangle,
        ShapeKind.ellipse => LumitIcon.ellipse,
        ShapeKind.star => LumitIcon.star,
      };

  Future<void> _pickShape(BuildContext context, Offset position) async {
    final picked = await showLumitPopup<ShapeKind>(
      context: context,
      position: position,
      builder: (close) => FloatSurface(
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final kind in ShapeKind.values)
                MenuRow(
                  selected: app.viewerShape == kind,
                  onPressed: () => close(kind),
                  child: Text(kind.label),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) app.setViewerShape(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return LumitTooltip(
      message: 'Draw a ${app.viewerShape.label.toLowerCase()} mask — '
          'right-click to pick a shape (Q)',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => _pickShape(context, d.globalPosition),
        child: HouseButton(
          key: const ValueKey('shape-tool'),
          frameless: true,
          small: true,
          onPressed: () => app.setViewerTool(ToolMode.shape),
          child: lumitIcon(
            _icon,
            size: 15,
            color: active ? t.accent : t.textMuted,
          ),
        ),
      ),
    );
  }
}
