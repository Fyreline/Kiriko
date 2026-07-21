// The layer/footage-placement interactive slice (05-PARITY-CHECKLIST "Layer &
// footage placement"): the Composition menu's add-layer items route to the real
// ops; a Project-panel footage double-click places it into the front comp; a
// composition double-click fronts it; and the project right-click menu renders
// the egui item set with Composition settings opening the dialogue.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/panels/project_panel.dart';
import 'package:lumit_flutter/shell/menu_bar.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/state/workspace.dart';
import 'package:lumit_flutter/theme/theme.dart';
import 'package:lumit_flutter/widgets/controls.dart';

/// A document with one footage item and two compositions (both carrying a comp
/// block so the front comp resolves).
const _projectJson = '''
{
  "ok": true,
  "items": [
    {"id": "f0", "name": "clip.mp4", "kind": "footage", "children": [],
      "status": "ok"},
    {"id": "c0", "name": "Scene", "kind": "composition", "children": [],
      "comp": {"width": 1920, "height": 1080, "fps": {"num": 60, "den": 1},
        "frame_count": 100, "layers": [], "markers": []}},
    {"id": "c1", "name": "Titles", "kind": "composition", "children": [],
      "comp": {"width": 1920, "height": 1080, "fps": {"num": 60, "den": 1},
        "frame_count": 100, "layers": [], "markers": []}}
  ],
  "can_undo": false, "can_redo": false, "path": null
}''';

/// A fake bridge that always answers with [_projectJson] and records the layer
/// ops the panels dispatch.
class _Fake implements DocumentBridge {
  final List<String> ops = [];
  BridgeReply _snap() => BridgeReply.parse(_projectJson);
  BridgeReply _op(String r) {
    ops.add(r);
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
      _snap();
  @override
  BridgeReply editLayerSpan(
          String compId, String layerId, String edit, int frame) =>
      _snap();
  @override
  BridgeReply setTransform(
          String compId, String layerId, String property, double value) =>
      _snap();
  @override
  BridgeReply addMarker(String compId, int frame) => _snap();
  @override
  BridgeReply addSolidLayer(String compId) => _op('add_solid:$compId');
  @override
  BridgeReply addTextLayer(String compId) => _op('add_text:$compId');
  @override
  BridgeReply addCameraLayer(String compId) => _op('add_camera:$compId');
  @override
  BridgeReply addAdjustmentLayer(String compId) => _op('add_adjustment:$compId');
  @override
  BridgeReply addSequenceLayer(String compId) => _op('add_sequence:$compId');
  @override
  BridgeReply addFootageLayer(String compId, String itemId) =>
      _op('add_footage:$compId/$itemId');
  @override
  BridgeReply reorderLayer(String compId, String layerId, int newIndex) =>
      _op('reorder:$compId/$layerId->$newIndex');
  @override
  BridgeReply deleteLayer(String compId, String layerId) => _snap();
  @override
  BridgeReply duplicateLayer(String compId, String layerId) => _snap();
  @override
  BridgeReply setCompSettings(String compId, String name, int width, int height,
          int fpsNum, int fpsDen, int durationFrames) =>
      _op('comp_settings:$compId');
  @override
  BridgeReply togglePropertyAnimated(
          String compId, String layerId, String property, int frame) =>
      _snap();
  @override
  BridgeReply addKeyframe(String compId, String layerId, String property,
          int frame, double value) =>
      _snap();
  @override
  BridgeReply removeKeyframe(
          String compId, String layerId, String property, int frame) =>
      _snap();
  @override
  BridgeReply shiftKeyframes(String compId, String layerId, String property,
          List<int> frames, int delta) =>
      _snap();
  @override
  BridgeReply setWorkAreaEdge(String compId, int frame, bool isOut) => _snap();
  @override
  List<BridgeEffectInfo> listEffects() => const [];
  @override
  BridgeReply addEffect(String compId, String layerId, String effectName) =>
      _snap();
  @override
  BridgeReply removeEffect(String compId, String layerId, String effectId) =>
      _snap();
  @override
  BridgeReply setEffectEnabled(
          String compId, String layerId, String effectId, bool enabled) =>
      _snap();
  @override
  BridgeReply setEffectParamScalar(String compId, String layerId,
          String effectId, String paramName, double value) =>
      _snap();
  @override
  BridgeReply setEffectParamColour(String compId, String layerId,
          String effectId, String paramName, double r, double g, double b,
          double a) =>
      _snap();
  @override
  BridgeReply setKeyframeInterp(String compId, String layerId, String property,
          int frame, String interpIn, String interpOut, double speedIn,
          double influenceIn, double speedOut, double influenceOut) =>
      _snap();
  @override
  BridgeReply setRetimeEnabled(String compId, String layerId, bool enabled) =>
      _snap();
  @override
  BridgeReply setRetimeSpeed(String compId, String layerId, double speed) =>
      _snap();
  @override
  BridgeReply setSegmentPreset(
          String compId, String layerId, int frame, String ease) =>
      _snap();
  @override
  BridgeReply segmentToRate(String compId, String layerId, int frame) => _snap();
  @override
  BridgeReply dragBoundary(
          String compId, String layerId, int index, int frame) =>
      _snap();
  @override
  List<BridgeBlendMode> listBlendModes() => const [];
  @override
  BridgeReply setBlendMode(String compId, String layerId, String mode) =>
      _snap();
  @override
  BridgeReply setMatte(String compId, String layerId, String source,
          String channel, bool inverted) =>
      _snap();
  @override
  BridgeReply setParent(String compId, String layerId, String parent) =>
      _snap();
  @override
  BridgeReply setMotionBlur(String compId, bool enabled, double shutterAngle,
          double shutterPhase, int samples) =>
      _snap();
  @override
  BridgeReply addMask(String compId, String layerId, String kind) => _snap();
  @override
  BridgeExportPreset exportPreset(
          String presetName, String compName, String template) =>
      BridgeExportPreset.idle;
  @override
  BridgeReply startExport(String compId, String specJson, String outPath) =>
      _snap();
  @override
  BridgeExportState exportPoll() => BridgeExportState.idle;
  @override
  BridgeReply exportCancel() => _snap();
  @override
  DecodedFrame? decodeFrame(String itemId, int frame) => null;
}

/// Mount [child] in a themed Overlay (so popups and modals have somewhere to go).
Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: ThemeScope(
          theme: LumitTheme.dark(),
          animationLevel: AnimationLevel.none,
          showTooltips: false,
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => child)],
          ),
        ),
      ),
    );

/// Perform a double-tap on [finder].
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  group('Menu bar add-layer', () {
    testWidgets('Composition ▸ Add solid layer calls addSolidLayer on the front '
        'comp', (tester) async {
      final fake = _Fake();
      final app = AppStateStub(bridge: fake);
      await tester.pumpWidget(_host(LumitMenuBar(
        app: app,
        workspace: Workspace(),
        onOpenSettings: () {},
        onOpenPalette: () {},
      )));
      await tester.tap(find.text('Composition'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add solid layer'));
      await tester.pumpAndSettle();
      // The front comp resolves to the first composition (c0).
      expect(fake.ops, contains('add_solid:c0'));
    });
  });

  group('Project panel interaction', () {
    testWidgets('double-clicking a footage item places it into the front comp',
        (tester) async {
      final fake = _Fake();
      final app = AppStateStub(bridge: fake);
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await _doubleTap(tester, find.text('clip.mp4'));
      await tester.pumpAndSettle();
      expect(fake.ops, contains('add_footage:c0/f0'));
    });

    testWidgets('double-clicking a composition fronts it', (tester) async {
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await _doubleTap(tester, find.text('Titles'));
      await tester.pumpAndSettle();
      expect(app.frontCompId, 'c1');
    });

    testWidgets('clicking a row selects it (highlight)', (tester) async {
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.tap(find.text('clip.mp4'));
      // onTap is deferred while the row disambiguates from a double-tap; pump
      // past the double-tap timeout so the single tap resolves.
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.selectedProjectItem, 'f0');
    });

    testWidgets('right-click renders the egui item set and Composition settings '
        'opens the dialogue', (tester) async {
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.tap(find.text('Scene'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      // The full egui project menu.
      expect(find.text('Composition settings…'), findsOneWidget);
      expect(find.text('Relink…'), findsOneWidget);
      expect(find.text('Find missing footage'), findsOneWidget);
      expect(find.text('Move to root'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // Composition settings opens the settings dialogue (title + Apply button).
      await tester.tap(find.text('Composition settings…'));
      await tester.pumpAndSettle();
      expect(find.text('Composition settings'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('a stub menu entry surfaces a calm notice', (tester) async {
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.tap(find.text('clip.mp4'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relink…'));
      await tester.pumpAndSettle();
      expect(app.notice, contains('Relink'));
    });
  });
}
