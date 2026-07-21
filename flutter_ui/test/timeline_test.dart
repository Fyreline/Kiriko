// Phase-F3 Timeline tests: the pure geometry / degradation / snapping logic
// (no widget tree), and widget tests over the live panel driven by a fake
// DocumentBridge (comp tabs, layer rows, switch/scrub/select/trim wiring).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/panels/timeline/lane_scale.dart';
import 'package:lumit_flutter/panels/timeline/outline_layout.dart';
import 'package:lumit_flutter/panels/timeline_panel.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/theme/theme.dart';
import 'package:lumit_flutter/widgets/controls.dart';

/// Two comps ("Scene" with two layers + a marker, "Titles" empty) in the exact
/// shape the Rust bridge emits.
const _twoCompJson = '''
{
  "ok": true,
  "items": [
    {
      "id": "c0", "name": "Scene", "kind": "composition", "children": [],
      "comp": {
        "width": 1920, "height": 1080,
        "fps": {"num": 60, "den": 1}, "frame_count": 300,
        "layers": [
          {
            "id": "l0", "index": 0, "name": "hero", "kind": "footage",
            "in_frame": 60, "out_frame": 240, "label": 2,
            "switches": {"visible": true, "audible": true, "locked": false,
              "three_d": false, "collapse": false, "fx": true,
              "solo": false, "motion_blur": false}
          },
          {
            "id": "l1", "index": 1, "name": "backdrop", "kind": "solid",
            "in_frame": 0, "out_frame": 300, "label": 0,
            "switches": {"visible": false, "audible": true, "locked": false,
              "three_d": false, "collapse": false, "fx": true,
              "solo": false, "motion_blur": false}
          }
        ],
        "markers": [120]
      }
    },
    {
      "id": "c1", "name": "Titles", "kind": "composition", "children": [],
      "comp": {"width": 1920, "height": 1080, "fps": {"num": 60, "den": 1},
        "frame_count": 120, "layers": [], "markers": []}
    }
  ],
  "can_undo": true, "can_redo": false, "path": null
}''';

/// A fake bridge that always answers with the two-comp document and records the
/// ops it is asked to run.
class _TimelineFake implements DocumentBridge {
  final List<String> ops = [];

  BridgeReply _snap() => BridgeReply.parse(_twoCompJson);

  BridgeReply _op(String record) {
    ops.add(record);
    return _snap();
  }

  @override
  BridgeReply snapshot() => _snap();
  @override
  BridgeReply newProject() => _snap();
  @override
  BridgeReply undo() => _snap();
  @override
  BridgeReply redo() => _snap();
  @override
  BridgeReply openProject(String p) => _snap();
  @override
  BridgeReply saveProject(String p) => _snap();
  @override
  BridgeReply newComposition(String name) => _snap();
  @override
  BridgeReply importFootage(String p) => _snap();
  @override
  BridgeReply setLayerSwitch(
          String compId, String layerId, String switchName, bool value) =>
      _op('switch:$compId/$layerId/$switchName=$value');
  @override
  BridgeReply editLayerSpan(
          String compId, String layerId, String edit, int frame) =>
      _op('span:$compId/$layerId/$edit@$frame');
  @override
  BridgeReply setTransform(
          String compId, String layerId, String property, double value) =>
      _op('transform:$compId/$layerId/$property=$value');
  @override
  BridgeReply addMarker(String compId, int frame) => _op('marker:$compId@$frame');
  @override
  DecodedFrame? decodeFrame(String itemId, int frame) => null;
}

Widget _host(AppStateStub app) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: ThemeScope(
          theme: LumitTheme.dark(),
          animationLevel: AnimationLevel.none,
          showTooltips: false,
          child: TimelinePanel(app: app),
        ),
      ),
    );

void main() {
  group('LaneScale (time↔pixel under zoom)', () {
    test('zoom 1 fits the whole comp from frame 0', () {
      final s = LaneScale.fit(
          trackLeft: 100, trackWidth: 600, frameCount: 300, zoom: 1);
      expect(s.viewStartFrame, 0);
      expect(s.pxPerFrame, closeTo(2.0, 1e-9));
      expect(s.xOfFrame(0), closeTo(100, 1e-9));
      expect(s.xOfFrame(300), closeTo(700, 1e-9));
      expect(s.frameOfX(400), closeTo(150, 1e-9));
    });

    test('zoom doubles pixels-per-frame and never scrolls past the ends', () {
      final s = LaneScale.fit(
        trackLeft: 0,
        trackWidth: 600,
        frameCount: 300,
        zoom: 2,
        desiredStartFrame: 999, // clamped to (300 - 150)
      );
      expect(s.pxPerFrame, closeTo(4.0, 1e-9));
      expect(s.viewStartFrame, closeTo(150, 1e-9));
    });

    test('a degenerate comp still yields a usable scale', () {
      final s =
          LaneScale.fit(trackLeft: 0, trackWidth: 100, frameCount: 0, zoom: 1);
      expect(s.frameCount, 1);
      expect(s.pxPerFrame.isFinite, isTrue);
    });
  });

  group('chooseTicks (zoom-adaptive density)', () {
    test('coarse scale keeps labels from crowding', () {
      // 2 px/sec: a 1 s label step would be 2 px — far too dense.
      final spec = chooseTicks(2);
      expect(spec.secondsPerLabel, greaterThanOrEqualTo(30));
    });

    test('fine scale allows tight, frequent labels', () {
      final spec = chooseTicks(200); // 200 px/sec
      expect(spec.secondsPerLabel, lessThanOrEqualTo(1));
      expect(spec.secondsPerMinor, lessThanOrEqualTo(spec.secondsPerLabel));
    });
  });

  group('chooseColumns (degradation order)', () {
    test('a wide outline shows the whole footage cluster', () {
      final c = chooseColumns(260, canAudio: true, isPrecomp: false);
      expect(c.eye, isTrue);
      expect(c.speaker, isTrue);
      expect(c.solo, isTrue);
      expect(c.lock, isTrue);
      expect(c.fx, isTrue);
      expect(c.motionBlur, isTrue);
      expect(c.threeD, isTrue);
      expect(c.index, isTrue);
    });

    test('columns drop in order: collapse/3D, then fx/MB, then solo…', () {
      // Narrow enough to drop the low-priority switches but keep eye+lock.
      final c = chooseColumns(120, canAudio: true, isPrecomp: true);
      expect(c.eye, isTrue, reason: 'eye survives longest');
      // 3D/collapse and fx/MB go before solo/speaker/index.
      expect(c.collapse, isFalse);
      expect(c.threeD, isFalse);
      expect(c.motionBlur, isFalse);
    });

    test('a tiny width shows glyph + name only', () {
      final c = chooseColumns(36, canAudio: true, isPrecomp: false);
      expect(c.eye, isFalse);
      expect(c.lock, isFalse);
      expect(c.index, isFalse);
      expect(c, isA<OutlineColumns>());
    });

    test('non-audio layers never reserve a speaker', () {
      final c = chooseColumns(260, canAudio: false, isPrecomp: false);
      expect(c.speaker, isFalse);
    });
  });

  group('snapFrame', () {
    test('snapping off is the identity', () {
      expect(
        snapFrame(77, fps: 60, markers: const [120], snapping: false, pxPerFrame: 2),
        77,
      );
    });

    test('a near whole-second lands on the second', () {
      // 2 px/frame → 6 px threshold = 3 frames. 61 is 1 frame from 60.
      expect(
        snapFrame(61, fps: 60, markers: const [], snapping: true, pxPerFrame: 2),
        60,
      );
    });

    test('a marker wins when it is the closest candidate', () {
      expect(
        snapFrame(119, fps: 60, markers: const [120], snapping: true, pxPerFrame: 4),
        120,
      );
    });

    test('nothing within the threshold is left alone', () {
      expect(
        snapFrame(77, fps: 60, markers: const [120], snapping: true, pxPerFrame: 4),
        77,
      );
    });
  });

  group('Timeline panel (fake bridge)', () {
    testWidgets('comp tabs render every composition', (tester) async {
      final app = AppStateStub(bridge: _TimelineFake());
      await tester.pumpWidget(_host(app));
      expect(find.text('Scene'), findsOneWidget);
      expect(find.text('Titles'), findsOneWidget);
    });

    testWidgets('clicking a comp pill fronts that comp', (tester) async {
      final app = AppStateStub(bridge: _TimelineFake());
      await tester.pumpWidget(_host(app));
      expect(app.frontCompIdResolved, 'c0');
      await tester.tap(find.text('Titles'));
      await tester.pump();
      expect(app.frontCompIdResolved, 'c1');
    });

    testWidgets('layer rows render their names', (tester) async {
      final app = AppStateStub(bridge: _TimelineFake());
      await tester.pumpWidget(_host(app));
      expect(find.text('hero'), findsOneWidget);
      expect(find.text('backdrop'), findsOneWidget);
    });

    testWidgets('tapping the eye toggles visible off through the op',
        (tester) async {
      final fake = _TimelineFake();
      final app = AppStateStub(bridge: fake);
      await tester.pumpWidget(_host(app));
      await tester.tap(find.byKey(const ValueKey('sw:l0:visible')));
      await tester.pump();
      expect(fake.ops, contains('switch:c0/l0/visible=false'));
    });

    testWidgets('tapping a bar selects the layer', (tester) async {
      final app = AppStateStub(bridge: _TimelineFake());
      await tester.pumpWidget(_host(app));
      // l1 (backdrop) spans the whole lane; a tap over the lane centre selects it.
      await tester.tapAt(const Offset(500, 97));
      await tester.pump();
      expect(app.selectedLayer, 'l1');
    });

    testWidgets('dragging the left edge issues a trim_in at the dragged frame',
        (tester) async {
      final fake = _TimelineFake();
      final app = AppStateStub(bridge: fake)..snapping = false;
      await tester.pumpWidget(_host(app));
      // Geometry: width 800 → outline 260, trackW 532, pxPerFrame = 532/300.
      const ppf = 532 / 300;
      final startX = 260 + 60 * ppf; // l0 in-point (frame 60) left edge
      const dx = 30.0;
      final expected = ((startX + dx - 260) / ppf).round();
      await tester.dragFrom(Offset(startX, 75), const Offset(dx, 0));
      await tester.pump();
      expect(fake.ops, contains('span:c0/l0/trim_in@$expected'));
    });

    testWidgets('a scrub click on the ruler moves the playhead', (tester) async {
      final app = AppStateStub(bridge: _TimelineFake())..snapping = false;
      await tester.pumpWidget(_host(app));
      const ppf = 532 / 300;
      final x = 260 + 150 * ppf; // frame 150
      await tester.tapAt(Offset(x, 46)); // ruler band y
      await tester.pump();
      expect(app.previewFrame, 150);
    });
  });
}
