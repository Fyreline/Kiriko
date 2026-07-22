// Section D (editors, viewer and panels) widget + unit tests, over a fake that
// offers both DocumentBridge and the v0.5 EditOpsBridge capability. Covers: the
// Text / Solid / Camera property editors; the Viewer toolbar tool row and shape
// picker; the preview-scale picker; the Project panel rename, missing badge and
// context ops; the Hierarchy id-based nesting and comp-scoped selection; the
// Effects category grouping; and the effect eyedropper arm + editable param
// kinds.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/panels/effect_controls_panel.dart';
import 'package:lumit_flutter/panels/effects_presets_panel.dart';
import 'package:lumit_flutter/panels/hierarchy_panel.dart';
import 'package:lumit_flutter/panels/project_panel.dart';
import 'package:lumit_flutter/panels/viewer_toolbar.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/theme/theme.dart';
import 'package:lumit_flutter/widgets/controls.dart';

/// A fake offering DocumentBridge (via noSuchMethod → ok snapshot) and the v0.5
/// EditOpsBridge, whose snapshot carries a text, solid, camera and footage layer
/// (the footage carries an effect with colour / bool / enum params), a nested
/// precomp by `source_comp_id`, and a missing footage item. Ops are recorded.
class _Fake implements DocumentBridge, EditOpsBridge {
  final List<String> ops = [];

  static const _json = '''
  {
    "ok": true,
    "items": [
      {
        "id": "c1", "name": "Scene", "kind": "composition", "children": [],
        "comp": {
          "width": 1920, "height": 1080, "fps": {"num": 60, "den": 1},
          "frame_count": 300,
          "layers": [
            {"id":"lt","index":0,"name":"Title","kind":"text",
             "in_frame":0,"out_frame":300,"label":0,"switches":{}},
            {"id":"ls","index":1,"name":"BG","kind":"solid",
             "in_frame":0,"out_frame":300,"label":0,"switches":{},
             "colour":[0.2,0.4,0.6,1.0]},
            {"id":"lc","index":2,"name":"Cam","kind":"camera",
             "in_frame":0,"out_frame":300,"label":0,"switches":{}},
            {"id":"lf","index":3,"name":"clip","kind":"footage",
             "in_frame":0,"out_frame":300,"label":0,"switches":{},
             "effects":[
               {"id":"e1","name":"blur","enabled":true,"params":[
                 {"name":"tint","kind":"colour","value":[1.0,0.0,0.0,1.0]},
                 {"name":"invert","kind":"bool","value":true},
                 {"name":"mode","kind":"enum","value":1,
                  "range":{"options":["Soft","Hard","Wild"]}}
               ]}
             ]},
            {"id":"lp","index":4,"name":"ref","kind":"precomp",
             "in_frame":0,"out_frame":300,"label":0,"switches":{},
             "source_comp_id":"c2"}
          ],
          "markers": []
        }
      },
      {
        "id": "c2", "name": "Nested", "kind": "composition", "children": [],
        "comp": {
          "width": 1920, "height": 1080, "fps": {"num": 60, "den": 1},
          "frame_count": 300,
          "layers": [
            {"id":"la","index":0,"name":"inner","kind":"footage",
             "in_frame":0,"out_frame":300,"label":0,"switches":{}}
          ],
          "markers": []
        }
      },
      {"id":"fmiss","name":"gone.mp4","kind":"footage","children":[],
       "status":"missing"}
    ],
    "can_undo": false, "can_redo": false, "path": null
  }''';

  BridgeReply _snap() => BridgeReply.parse(_json);
  BridgeReply _op(String r) {
    ops.add(r);
    return _snap();
  }

  @override
  BridgeReply snapshot() => _snap();

  @override
  List<BridgeEffectInfo> listEffects() => const [
        BridgeEffectInfo(
            name: 'blur',
            label: 'Gaussian blur',
            category: 'blur_sharpen',
            categoryLabel: 'Blur & sharpen'),
        BridgeEffectInfo(
            name: 'glow',
            label: 'Glow',
            category: 'stylise',
            categoryLabel: 'Stylise'),
      ];

  @override
  List<BridgeBlendMode> listBlendModes() => const [];

  @override
  BridgeReply addEffect(String c, String l, String name) =>
      _op('addeffect:$c/$l/$name');
  @override
  BridgeReply setEffectParamColour(String c, String l, String e, String p,
          double r, double g, double b, double a) =>
      _op('fxcolour:$c/$l/$e/$p=$r,$g,$b,$a');

  // Everything else on DocumentBridge → a benign ok snapshot.
  @override
  dynamic noSuchMethod(Invocation invocation) => _snap();

  // --- EditOpsBridge (the ones these tests drive) ------------------------
  @override
  BridgeReply setTextContent(String c, String l, String text, double size,
          double r, double g, double b, double a) =>
      _op('text:$c/$l/"$text"/$size');
  @override
  BridgeReply setSolid(String c, String l, double r, double g, double b,
          double a, int w, int h) =>
      _op('solid:$c/$l/$r,$g,$b,$a/${w}x$h');
  @override
  BridgeReply setCameraZoom(String c, String l, double zoom) =>
      _op('camera:$c/$l/$zoom');
  @override
  BridgeReply renameItem(String id, String name) => _op('rename:$id/"$name"');
  @override
  BridgeReply deleteItem(String id) => _op('delete:$id');
  @override
  BridgeReply moveToRoot(String id) => _op('moveroot:$id');
  @override
  BridgeReply relink(String id, String path) => _op('relink:$id/$path');
  @override
  BridgeReply setEffectParamBool(String c, String l, String e, String p, bool v) =>
      _op('fxbool:$c/$l/$e/$p=$v');
  @override
  BridgeReply setEffectParamChoice(
          String c, String l, String e, String p, int i) =>
      _op('fxchoice:$c/$l/$e/$p=$i');
}

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(480, 760)),
        child: ThemeScope(
          theme: LumitTheme.forScheme(LumitColorScheme.dark, ThemeShape.sharp),
          animationLevel: AnimationLevel.none,
          showTooltips: false,
          child: Overlay(
            initialEntries: [OverlayEntry(builder: (_) => child)],
          ),
        ),
      ),
    );

Future<void> _secondTap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('Property editors beyond Transform', () {
    testWidgets('a text layer shows the Text group and commits size',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)..selectLayer('lt');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      // Edit the size box → setTextContent commits (content, size, fill).
      await tester.tap(find.byKey(const ValueKey('text-size')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, '120');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fake.ops.any((o) => o.startsWith('text:c1/lt/')), isTrue);
      expect(fake.ops.any((o) => o.contains('/120')), isTrue);
    });

    testWidgets('a solid layer shows the Solid group and commits size',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)..selectLayer('ls');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      expect(find.text('Solid'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('solid-width')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, '640');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // The colour seeds from the snapshot; the size carries the edit.
      expect(fake.ops.any((o) => o.startsWith('solid:c1/ls/') && o.contains('640x')),
          isTrue);
    });

    testWidgets('a camera layer shows the Camera group and commits zoom',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)..selectLayer('lc');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      expect(find.text('Camera'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('camera-zoom')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, '2000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fake.ops.any((o) => o.startsWith('camera:c1/lc/')), isTrue);
    });
  });

  group('Viewer toolbar', () {
    testWidgets('selecting a tool and picking a shape updates the state',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 120));
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ViewerToolbar(app: app)));
      await tester.pump();

      expect(app.viewerTool, ToolMode.select);
      // Right-click the Shape tool → the shape picker, choose Ellipse.
      await tester.tap(find.byKey(const ValueKey('shape-tool')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Ellipse'), findsOneWidget);
      await tester.tap(find.text('Ellipse'));
      await tester.pumpAndSettle();
      expect(app.viewerShape, ShapeKind.ellipse);
      expect(app.viewerTool, ToolMode.shape); // picking a shape arms the tool
    });
  });

  group('Preview scale', () {
    test('the picker sets the render scale factor', () {
      final app = AppStateStub(bridge: _Fake());
      expect(app.previewScale, PreviewScale.full);
      app.setPreviewScale(PreviewScale.third);
      expect(app.previewScale, PreviewScale.third);
      expect(app.previewScale.factor, closeTo(1 / 3, 1e-9));
    });
  });

  group('Project panel', () {
    testWidgets('a missing footage row shows the badge and a Relink button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.pump();

      expect(find.text('missing'), findsOneWidget);
      expect(find.byKey(const ValueKey('relink-fmiss')), findsOneWidget);
    });

    test('relink routes the chosen path through the relink op', () {
      final fake = _Fake();
      final app = AppStateStub(bridge: fake);
      app.relink('fmiss', '/new/gone.mp4');
      expect(fake.ops, contains('relink:fmiss//new/gone.mp4'));
    });

    testWidgets('the missing-only toggle filters to missing rows',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.pump();

      expect(find.text('Scene'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('missing-toggle')));
      await tester.pump();
      // Only the missing footage row remains; the comps are hidden.
      expect(find.text('Scene'), findsNothing);
      expect(find.text('gone.mp4'), findsOneWidget);
    });

    testWidgets('a second click renames a row in place → renameItem',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake);
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.pump();

      await _secondTap(tester, find.text('Scene'));
      await tester.pump();
      expect(find.byKey(const ValueKey('rename-field')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('rename-field')), 'Intro');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fake.ops, contains('rename:c1/"Intro"'));
    });

    testWidgets('the context menu Delete and Move to root call their ops',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake);
      await tester.pumpWidget(_host(ProjectPanel(app: app)));
      await tester.pump();

      await tester.tap(find.text('gone.mp4'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to root'));
      await tester.pumpAndSettle();
      expect(fake.ops, contains('moveroot:fmiss'));

      await tester.tap(find.text('gone.mp4'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(fake.ops, contains('delete:fmiss'));
    });
  });

  group('Hierarchy', () {
    testWidgets('a precomp nests by source_comp_id and fronts its comp on select',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final app = AppStateStub(bridge: _Fake());
      await tester.pumpWidget(_host(HierarchyPanel(app: app)));
      await tester.pump();

      // The precomp (named "ref") folds open to the nested comp's "inner" layer,
      // resolved by id not by name.
      expect(find.text('inner'), findsOneWidget);
      // Selecting the nested layer fronts its owning comp (c2) then selects it.
      await tester.tap(find.text('inner'));
      await tester.pump();
      expect(app.frontCompId, 'c2');
      expect(app.selectedLayer, 'la');
    });
  });

  group('Effects & presets', () {
    testWidgets('effects group under collapsing category headers',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final app = AppStateStub(bridge: _Fake())..selectLayer('lf');
      await tester.pumpWidget(_host(EffectsPresetsPanel(app: app)));
      await tester.pump();

      expect(find.text('Blur & sharpen'), findsOneWidget);
      expect(find.text('Stylise'), findsOneWidget);
      expect(find.text('Gaussian blur'), findsOneWidget);
      // Collapsing the Blur & sharpen header hides its effect.
      await tester.tap(find.text('Blur & sharpen'));
      await tester.pump();
      expect(find.text('Gaussian blur'), findsNothing);
      expect(find.text('Glow'), findsOneWidget);
    });
  });

  group('Effect controls — editable kinds + eyedropper', () {
    testWidgets('the bool param is an editable checkbox → setEffectParamBool',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)..selectLayer('lf');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('fxbool-e1-invert')));
      await tester.pump();
      expect(fake.ops, contains('fxbool:c1/lf/e1/invert=false'));
    });

    testWidgets('the enum param with options is an editable dropdown → choice',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)..selectLayer('lf');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      // The dropdown shows the current option label ("Hard" = index 1).
      expect(find.byKey(const ValueKey('fxenum-e1-mode')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fxenum-e1-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wild'));
      await tester.pumpAndSettle();
      expect(fake.ops, contains('fxchoice:c1/lf/e1/mode=2'));
    });

    testWidgets('the colour dropper arms the eyedropper', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final app = AppStateStub(bridge: _Fake())..selectLayer('lf');
      await tester.pumpWidget(_host(EffectControlsPanel(app: app)));
      await tester.pump();

      expect(app.eyedropperArmed, isFalse);
      await tester.tap(find.byKey(const ValueKey('fxdropper-e1-tint')));
      await tester.pump();
      expect(app.eyedropperArmed, isTrue);
      expect(app.eyedropperArm?.paramName, 'tint');
    });

    test('commitEyedropper writes the sampled colour and disarms', () {
      final fake = _Fake();
      final app = AppStateStub(bridge: fake)
        ..armEyedropper(const EyedropperArm(
          compId: 'c1',
          layerId: 'lf',
          effectId: 'e1',
          paramName: 'tint',
        ));
      app.commitEyedropper(0.5, 0.25, 0.75);
      expect(app.eyedropperArmed, isFalse);
      expect(fake.ops.any((o) => o.startsWith('fxcolour:c1/lf/e1/tint=0.5,0.25,0.75')),
          isTrue);
    });
  });
}
