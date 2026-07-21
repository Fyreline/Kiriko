// The Timeline panel (phase F3): a comp-tab strip, the two-row time ruler, the
// per-layer outline + lane rows with clip bars, and the bottom bar's zoom /
// magnet / graph-lens controls. When no composition is open it keeps the F0
// placeholder centre. Pure geometry, the degradation table and snapping live in
// panels/timeline/ and are unit-tested; this file is the widget composition.

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../icons/icons.dart';
import '../state/app_state.dart';
import '../widgets/controls.dart';
import 'timeline/comp_tabs.dart';
import 'timeline/lane_scale.dart';
import 'timeline/layer_row.dart';
import 'timeline/ruler.dart';

/// The fixed outline-column width (px). Resizable later; F3 pins it at 260 and
/// degrades the switch cluster when the panel is too narrow to hold it.
const double _kOutlineWidth = 260;
const double _kRulerHeight = 36;

class TimelinePanel extends StatelessWidget {
  final AppStateStub app;
  const TimelinePanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final comp = app.frontComp;
        final compId = app.frontCompIdResolved;
        return Column(
          children: [
            CompTabStrip(app: app),
            Expanded(
              child: (comp != null && compId != null)
                  ? _TimelineBody(app: app, comp: comp, compId: compId)
                  : Center(
                      child: Text(
                        'Layer rows, lanes and the graph lens arrive in phase F3.',
                        style: t.small,
                      ),
                    ),
            ),
            _BottomBar(app: app),
          ],
        );
      },
    );
  }
}

/// The live timeline body when a comp is fronted: ruler band on top, the layer
/// rows below (scrolling vertically), and the playhead line over both.
class _TimelineBody extends StatelessWidget {
  final AppStateStub app;
  final BridgeComp comp;
  final String compId;
  const _TimelineBody({
    required this.app,
    required this.comp,
    required this.compId,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        // The outline never swallows the lane; below ~340 px it shrinks so the
        // lane keeps at least 80 px, and the switch cluster degrades to suit.
        final outlineW =
            _kOutlineWidth.clamp(60.0, (totalW - 80).clamp(60.0, _kOutlineWidth));
        final trackLeft = outlineW.toDouble();
        final trackW = (totalW - outlineW - 8).clamp(40.0, double.infinity);
        final scale = LaneScale.fit(
          trackLeft: trackLeft,
          trackWidth: trackW.toDouble(),
          frameCount: comp.frameCount,
          zoom: app.timelineZoom,
        );
        final fps = comp.fps.fps;
        final markers = comp.markers;
        final layers = comp.layers;

        final playheadX = scale.xOfFrame(app.previewFrame);
        final showPlayhead =
            playheadX >= trackLeft - 0.5 && playheadX <= trackLeft + trackW + 0.5;

        return Stack(
          children: [
            Column(
              children: [
                // Ruler band: outline header on the left, the two-row ruler over
                // the lane.
                SizedBox(
                  height: _kRulerHeight,
                  child: Row(
                    children: [
                      Container(
                        width: outlineW.toDouble(),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          border: Border(
                            bottom: BorderSide(color: t.hairline, width: 1),
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('Layer', style: t.small),
                      ),
                      Expanded(
                        child: TimelineRuler(
                          app: app,
                          scale: scale,
                          fps: fps,
                          markers: markers,
                          height: _kRulerHeight,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < layers.length; i++)
                          LayerRow(
                            key: ValueKey(layers[i].id),
                            app: app,
                            compId: compId,
                            layer: layers[i],
                            displayIndex: i,
                            outlineWidth: outlineW.toDouble(),
                            scale: scale,
                            fps: fps,
                            markers: markers,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (showPlayhead)
              Positioned(
                left: playheadX,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 1, color: t.accent),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The bottom bar: zoom (− + and readout), the magnet snap toggle, and the graph
/// lens toggle — the same controls the F0 skeleton carried, kept correct.
class _BottomBar extends StatelessWidget {
  final AppStateStub app;
  const _BottomBar({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      height: 24,
      color: t.surface2,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          HouseButton(
            frameless: true,
            small: true,
            onPressed: () => app.zoomTimeline(1.4),
            child: Text('+', style: t.bodyPrimary),
          ),
          HouseButton(
            frameless: true,
            small: true,
            onPressed: () => app.zoomTimeline(1 / 1.4),
            child: Text('−', style: t.bodyPrimary),
          ),
          HouseButton(
            frameless: true,
            small: true,
            onPressed: app.zoomTimelineFit,
            child: Text('Fit', style: t.small),
          ),
          const SizedBox(width: 6),
          Text('${(app.timelineZoom * 100).round()}%', style: t.small),
          const SizedBox(width: 10),
          LumitTooltip(
            message: 'Snapping',
            child: HouseButton(
              frameless: true,
              small: true,
              onPressed: () {
                app.snapping = !app.snapping;
                app.setNotice(app.snapping ? 'snapping on' : 'snapping off');
              },
              child: lumitIcon(
                LumitIcon.magnet,
                size: 13,
                color: app.snapping ? t.accent : t.textMuted,
              ),
            ),
          ),
          const Spacer(),
          LumitTooltip(
            message: 'Graph editor (Shift+F3)',
            child: HouseButton(
              frameless: true,
              small: true,
              onPressed: app.toggleGraphMode,
              child: lumitIcon(
                LumitIcon.graphCurve,
                size: 13,
                color: app.timelineGraphMode ? t.accent : t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
