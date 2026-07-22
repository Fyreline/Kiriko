// The empty-lane right-click menu, ported from the egui timeline background
// context menu (crates/lumit-ui/src/shell/timeline/panel.rs:384): Composition
// settings · Reveal in project · Show time grid · Beat sensitivity slider +
// Detect beats · Clear beat markers. Right-click empty lane space (below or
// between the layer bars) to reach it.
//
// In plain terms: this is the menu for the timeline itself rather than a layer.
// It opens the comp's settings, highlights the comp in the Project panel,
// toggles the vertical time guide lines, and — where the comp has audio — finds
// the beats and drops markers on them (a stronger slider setting finds more).
//
// The beat sensitivity (0–100, higher = more beats) is stored on the app state
// like egui's `beat_sensitivity`; the bridge's `detectBeats` turns the
// percentage into the detector's δ itself (beats.rs:85), so the slider value
// passes straight through. The time-grid toggle is session-only lane state the
// Timeline body owns, reached here through a callback.

import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../widgets/controls.dart';

/// Show the empty-lane context menu at [position] (global). [showTimeGrid] is
/// the body's current grid state (drawn with a tick), toggled through
/// [onToggleGrid]. Beat detection reads/writes [AppStateStub.beatSensitivity].
Future<void> showLaneContextMenu({
  required BuildContext context,
  required AppStateStub app,
  required String compId,
  required bool showTimeGrid,
  required VoidCallback onToggleGrid,
  required Offset position,
  required Future<void> Function() onCompositionSettings,
}) async {
  await showLumitPopup<void>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 210,
      child: _LaneMenuBody(
        app: app,
        compId: compId,
        showTimeGrid: showTimeGrid,
        onToggleGrid: onToggleGrid,
        onCompositionSettings: onCompositionSettings,
        close: () => close(null),
      ),
    ),
  );
}

class _LaneMenuBody extends StatefulWidget {
  final AppStateStub app;
  final String compId;
  final bool showTimeGrid;
  final VoidCallback onToggleGrid;
  final Future<void> Function() onCompositionSettings;
  final VoidCallback close;

  const _LaneMenuBody({
    required this.app,
    required this.compId,
    required this.showTimeGrid,
    required this.onToggleGrid,
    required this.onCompositionSettings,
    required this.close,
  });

  @override
  State<_LaneMenuBody> createState() => _LaneMenuBodyState();
}

class _LaneMenuBodyState extends State<_LaneMenuBody> {
  AppStateStub get app => widget.app;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuRow(
          onPressed: () {
            widget.close();
            widget.onCompositionSettings();
          },
          child: const Text('Composition settings…'),
        ),
        MenuRow(
          onPressed: () {
            // Reveal in project: front the comp's own item in the Project panel
            // (panel.rs:369 — a click on empty space selects the comp item).
            app.selectProjectItem(widget.compId);
            widget.close();
          },
          child: const Text('Reveal in project'),
        ),
        const _MenuDivider(),
        LumitTooltip(
          message: 'Vertical guide lines through the lanes',
          child: MenuRow(
            selected: widget.showTimeGrid,
            onPressed: () {
              widget.onToggleGrid();
              widget.close();
            },
            child: const Text('Show time grid'),
          ),
        ),
        const _MenuDivider(),
        // Beat detection lives where the markers land (docs/09 §5): a 0–100
        // sensitivity slider and the detect/clear actions.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: _SensitivitySlider(
            value: app.beatSensitivity,
            onChanged: (v) => setState(() => app.beatSensitivity = v),
          ),
        ),
        MenuRow(
          onPressed: () {
            app.detectBeats(app.beatSensitivity);
            widget.close();
          },
          child: const Text('Detect beats'),
        ),
        MenuRow(
          onPressed: () {
            app.clearBeatMarkers();
            widget.close();
          },
          child: const Text('Clear beat markers'),
        ),
      ],
    );
  }
}

/// A compact 0–100 sensitivity slider with a label and live readout — the
/// house-styled stand-in for egui's `Slider::new(&mut beat_sens, 0..=100)`.
class _SensitivitySlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _SensitivitySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Beat sensitivity',
                  style: t.small.copyWith(color: t.textMuted)),
            ),
            Text('$value',
                style: t.small.copyWith(color: t.textSecondary)),
          ],
        ),
        const SizedBox(height: 3),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            void emit(double localX) {
              final frac = (localX / w).clamp(0.0, 1.0);
              onChanged((frac * 100).round());
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => emit(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
              child: SizedBox(
                height: 14,
                child: CustomPaint(
                  size: Size(w, 14),
                  painter: _SliderPainter(
                    frac: (value / 100).clamp(0.0, 1.0),
                    track: t.surface1,
                    fill: t.accent,
                    knob: t.textPrimary,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double frac;
  final Color track, fill, knob;
  _SliderPainter({
    required this.frac,
    required this.track,
    required this.fill,
    required this.knob,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(0, cy - 2, size.width, cy + 2), r),
      Paint()..color = track,
    );
    final fx = frac * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(0, cy - 2, fx, cy + 2), r),
      Paint()..color = fill,
    );
    canvas.drawCircle(Offset(fx.clamp(0, size.width), cy), 5, Paint()..color = knob);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.frac != frac;
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
