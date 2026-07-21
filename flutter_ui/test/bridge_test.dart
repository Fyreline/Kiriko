// Bridge v0 Dart-side tests: the JSON → typed-model parsing (fed literal
// strings, no library needed), and the guarantee that AppStateStub without a
// bridge behaves exactly as the F0 placeholder did.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/state/app_state.dart';

/// A minimal in-memory [DocumentBridge] for the AppStateStub tests: it mirrors
/// the engine's shapes (ok snapshots, a calm error for a bad import path) so the
/// dialogue-wiring logic can be exercised without the library or plugin
/// channels. It also records what it was asked to do.
class _FakeBridge implements DocumentBridge {
  final List<BridgeItem> items = [];
  String? path;

  // Call records the tests assert on.
  final List<String> imported = [];
  int saveCalls = 0;
  String? lastSavePath;

  // Snapshot-v2 op records.
  final List<String> ops = [];

  /// When set, the next op returns this error instead of a snapshot.
  String? nextOpError;

  /// What [decodeFrame] should return (null by default).
  DecodedFrame? decodeResult;
  final List<String> decoded = [];

  BridgeSnapshot _snap() => BridgeSnapshot(
        items: List.of(items),
        canUndo: items.isNotEmpty,
        canRedo: false,
        path: path,
      );

  @override
  BridgeReply snapshot() => BridgeReply.ok(_snap());

  @override
  BridgeReply newProject() {
    items.clear();
    path = null;
    return BridgeReply.ok(_snap());
  }

  @override
  BridgeReply undo() => BridgeReply.ok(_snap());

  @override
  BridgeReply redo() => BridgeReply.ok(_snap());

  @override
  BridgeReply openProject(String p) {
    path = p;
    return BridgeReply.ok(_snap());
  }

  @override
  BridgeReply saveProject(String p) {
    saveCalls++;
    lastSavePath = p;
    if (p.isNotEmpty) path = p;
    if (path == null) {
      return const BridgeReply.err('save project: no path yet');
    }
    return BridgeReply.ok(_snap());
  }

  @override
  BridgeReply newComposition(String name) {
    items.add(BridgeItem(
      id: 'c${items.length}',
      name: name.isEmpty ? 'Comp ${items.length + 1}' : name,
      kind: BridgeItemKind.composition,
      children: const [],
    ));
    return BridgeReply.ok(_snap());
  }

  @override
  BridgeReply importFootage(String p) {
    if (p.isEmpty) return const BridgeReply.err('import footage: no path given');
    imported.add(p);
    items.add(BridgeItem(
      id: 'f${items.length}',
      name: p,
      kind: BridgeItemKind.footage,
      children: const [],
    ));
    return BridgeReply.ok(_snap());
  }

  BridgeReply _op(String record) {
    ops.add(record);
    final err = nextOpError;
    if (err != null) {
      nextOpError = null;
      return BridgeReply.err(err);
    }
    return BridgeReply.ok(_snap());
  }

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
  BridgeReply addMarker(String compId, int frame) =>
      _op('marker:$compId@$frame');

  @override
  DecodedFrame? decodeFrame(String itemId, int frame) {
    decoded.add('$itemId@$frame');
    return decodeResult;
  }
}

void main() {
  group('BridgeSnapshot parsing', () {
    test('an empty document parses to no items and no undo', () {
      final reply = BridgeReply.parse(
        '{"ok":true,"items":[],"can_undo":false,"can_redo":false,"path":null}',
      );
      expect(reply.ok, isTrue);
      final snap = reply.snapshot!;
      expect(snap.items, isEmpty);
      expect(snap.canUndo, isFalse);
      expect(snap.canRedo, isFalse);
      expect(snap.path, isNull);
    });

    test('a nested folder tree parses with kinds and children', () {
      const json = '''
      {
        "ok": true,
        "items": [
          {
            "id": "f1", "name": "Compositions", "kind": "folder",
            "children": [
              {"id": "c1", "name": "Intro", "kind": "composition", "children": []}
            ]
          },
          {"id": "a1", "name": "clip.mp4", "kind": "footage", "children": []},
          {"id": "s1", "name": "White solid", "kind": "solid", "children": []}
        ],
        "can_undo": true, "can_redo": false, "path": "C:/edit.lum"
      }''';
      final reply = BridgeReply.parse(json);
      expect(reply.ok, isTrue);
      final snap = reply.snapshot!;
      expect(snap.canUndo, isTrue);
      expect(snap.path, 'C:/edit.lum');
      expect(snap.items.length, 3);

      final folder = snap.items[0];
      expect(folder.kind, BridgeItemKind.folder);
      expect(folder.name, 'Compositions');
      expect(folder.children.length, 1);
      expect(folder.children[0].kind, BridgeItemKind.composition);
      expect(folder.children[0].name, 'Intro');

      expect(snap.items[1].kind, BridgeItemKind.footage);
      expect(snap.items[2].kind, BridgeItemKind.solid);
    });

    test('an unknown kind degrades rather than throwing', () {
      final reply = BridgeReply.parse(
        '{"ok":true,"items":[{"id":"x","name":"?","kind":"nebula","children":[]}],'
        '"can_undo":false,"can_redo":false,"path":null}',
      );
      expect(reply.ok, isTrue);
      expect(reply.snapshot!.items.single.kind, BridgeItemKind.unknown);
    });

    test('an error reply carries the message, not a snapshot', () {
      final reply = BridgeReply.parse(
        '{"ok":false,"error":"open project: not a Lumit project"}',
      );
      expect(reply.ok, isFalse);
      expect(reply.snapshot, isNull);
      expect(reply.error, 'open project: not a Lumit project');
    });

    test('malformed JSON is reported, never thrown', () {
      final reply = BridgeReply.parse('not json at all');
      expect(reply.ok, isFalse);
      expect(reply.error, contains('malformed'));
    });
  });

  group('AppStateStub without a bridge', () {
    test('bridge is null and no snapshot is held', () {
      final app = AppStateStub();
      expect(app.bridge, isNull);
      expect(app.snapshot, isNull);
    });

    test('document actions keep the exact F0 notice text', () {
      // Each action must produce the same notice as the original
      // `engine('…')` call did, so the placeholder build is unchanged. A fresh
      // instance per action keeps the notices from bleeding together.
      var app = AppStateStub()..newProject();
      expect(app.notice, 'New project — engine bridge arrives in phase F1');

      app = AppStateStub()..newComposition();
      expect(app.notice, 'New composition — engine bridge arrives in phase F1');

      app = AppStateStub()..undo();
      expect(app.notice, 'Undo — engine bridge arrives in phase F1');

      app = AppStateStub()..redo();
      expect(app.notice, 'Redo — engine bridge arrives in phase F1');

      app = AppStateStub()..save();
      expect(app.notice, 'Save — engine bridge arrives in phase F1');

      app = AppStateStub()..openProject();
      expect(app.notice, 'Open project — engine bridge arrives in phase F1');

      app = AppStateStub()..importFootage();
      expect(app.notice, 'Import footage — engine bridge arrives in phase F1');
    });
  });

  group('AppStateStub file dialogues (fake bridge)', () {
    test('save with no path routes to the save-location seam', () async {
      final fake = _FakeBridge();
      var pickerCalled = false;
      final app = AppStateStub(
        bridge: fake,
        saveLocationPicker: () async {
          pickerCalled = true;
          return '/tmp/new.lum';
        },
      );
      await app.save();
      expect(pickerCalled, isTrue, reason: 'no path yet, so Save asks where');
      expect(fake.lastSavePath, '/tmp/new.lum');
      expect(app.snapshot!.path, '/tmp/new.lum');
      expect(app.notice, 'Project saved');
    });

    test('save with a known path saves in place, no dialogue', () async {
      final fake = _FakeBridge()..path = '/tmp/existing.lum';
      var pickerCalled = false;
      final app = AppStateStub(
        bridge: fake,
        saveLocationPicker: () async {
          pickerCalled = true;
          return null;
        },
      );
      await app.save();
      expect(pickerCalled, isFalse);
      expect(fake.saveCalls, 1);
      expect(fake.lastSavePath, '', reason: 'empty path = save in place');
    });

    test('cancelling the save dialogue changes nothing', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(bridge: fake, saveLocationPicker: () async => null);
      await app.save();
      expect(fake.saveCalls, 0);
      expect(app.snapshot!.path, isNull);
    });

    test('importing N footage files posts a calm count', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(
        bridge: fake,
        footagePicker: () async => ['/a/one.mp4', '/a/two.mov'],
      );
      await app.importFootage();
      expect(fake.imported, ['/a/one.mp4', '/a/two.mov']);
      expect(app.notice, '2 items imported');
      expect(app.errorNotice, isNull);
      expect(app.snapshot!.items.length, 2);
    });

    test('a single import reads as one item', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(
        bridge: fake,
        footagePicker: () async => ['/a/clip.mp4'],
      );
      await app.importFootage();
      expect(app.notice, '1 item imported');
    });

    test('a partial import failure surfaces via the error tint', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(
        bridge: fake,
        footagePicker: () async => ['', '/a/ok.mp4'],
      );
      await app.importFootage();
      expect(app.notice, '1 item imported');
      expect(app.errorNotice, 'import footage: no path given');
    });

    test('cancelling the footage dialogue changes nothing', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(bridge: fake, footagePicker: () async => []);
      await app.importFootage();
      expect(fake.imported, isEmpty);
      expect(app.snapshot!.items, isEmpty);
    });

    test('opening a project remembers its path', () async {
      final fake = _FakeBridge();
      String? remembered;
      final app = AppStateStub(
        bridge: fake,
        openProjectPicker: () async => '/edit/project.lum',
        rememberProject: (p) => remembered = p,
      );
      await app.openProject();
      expect(app.snapshot!.path, '/edit/project.lum');
      expect(remembered, '/edit/project.lum');
      expect(app.notice, 'Project opened');
    });

    test('cancelling the open dialogue changes nothing', () async {
      final fake = _FakeBridge();
      final app = AppStateStub(bridge: fake, openProjectPicker: () async => null);
      await app.openProject();
      expect(app.snapshot!.path, isNull);
    });
  });

  group('AppStateStub last-project restore', () {
    test('a live bridge reopens the last project when its file exists', () {
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}restore-me.lum')
        ..writeAsStringSync('placeholder');
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final fake = _FakeBridge();
      final app = AppStateStub(bridge: fake, lastProjectPath: file.path);
      expect(app.snapshot!.path, file.path);
      expect(app.notice, 'Project reopened');
    });

    test('a missing last project degrades quietly, never a crash', () {
      final fake = _FakeBridge();
      final app = AppStateStub(
          bridge: fake, lastProjectPath: '/no/such/place/gone.lum');
      expect(app.snapshot!.path, isNull, reason: 'nothing was reopened');
    });
  });

  group('Snapshot v2 parsing', () {
    // A comp (two layers, switches, markers) plus a probed footage item, in the
    // exact shape the Rust bridge emits.
    const json = '''
    {
      "ok": true,
      "items": [
        {
          "id": "c1", "name": "Scene", "kind": "composition", "children": [],
          "comp": {
            "width": 1920, "height": 1080,
            "fps": {"num": 60, "den": 1}, "frame_count": 300,
            "layers": [
              {
                "id": "l0", "index": 0, "name": "top", "kind": "footage",
                "in_frame": 60, "out_frame": 240, "label": 2,
                "switches": {
                  "visible": true, "audible": true, "locked": false,
                  "three_d": false, "collapse": false, "fx": true,
                  "solo": true, "motion_blur": false
                }
              },
              {
                "id": "l1", "index": 1, "name": "bg", "kind": "solid",
                "in_frame": 0, "out_frame": 300, "label": 0,
                "switches": {
                  "visible": false, "audible": true, "locked": true,
                  "three_d": true, "collapse": false, "fx": true,
                  "solo": false, "motion_blur": true
                }
              }
            ],
            "markers": [120, 240]
          }
        },
        {
          "id": "f1", "name": "clip.mp4", "kind": "footage", "children": [],
          "status": "ok",
          "media": {
            "duration_frames": 150, "fps": {"num": 30000, "den": 1001},
            "width": 1280, "height": 720, "audio": true
          }
        }
      ],
      "can_undo": true, "can_redo": false, "path": null
    }''';

    test('a composition parses its size, rate, layers and markers', () {
      final snap = BridgeReply.parse(json).snapshot!;
      final comp = snap.items[0].comp!;
      expect(comp.width, 1920);
      expect(comp.height, 1080);
      expect(comp.fps.num, 60);
      expect(comp.fps.den, 1);
      expect(comp.fps.fps, 60.0);
      expect(comp.frameCount, 300);
      expect(comp.markers, [120, 240]);
      expect(comp.layers.length, 2);

      final top = comp.layers[0];
      expect(top.index, 0);
      expect(top.name, 'top');
      expect(top.kind, BridgeLayerKind.footage);
      expect(top.inFrame, 60);
      expect(top.outFrame, 240);
      expect(top.label, 2);
      expect(top.switches.solo, isTrue);
      expect(top.switches.visible, isTrue);

      final bg = comp.layers[1];
      expect(bg.kind, BridgeLayerKind.solid);
      expect(bg.switches.visible, isFalse);
      expect(bg.switches.locked, isTrue);
      expect(bg.switches.threeD, isTrue);
      expect(bg.switches.motionBlur, isTrue);
    });

    test('a footage item parses its status and media metadata', () {
      final snap = BridgeReply.parse(json).snapshot!;
      final footage = snap.items[1];
      expect(footage.kind, BridgeItemKind.footage);
      expect(footage.status, BridgeMediaStatus.ok);
      final media = footage.media!;
      expect(media.durationFrames, 150);
      expect(media.fps.num, 30000);
      expect(media.fps.den, 1001);
      expect(media.width, 1280);
      expect(media.height, 720);
      expect(media.audio, isTrue);
    });

    test('an unprobed footage item has a status but no media block', () {
      final snap = BridgeReply.parse(
        '{"ok":true,"items":[{"id":"f","name":"x.mp4","kind":"footage",'
        '"children":[],"status":"unprobed"}],'
        '"can_undo":false,"can_redo":false,"path":null}',
      ).snapshot!;
      expect(snap.items[0].status, BridgeMediaStatus.unprobed);
      expect(snap.items[0].media, isNull);
    });

    test('unknown layer kinds and statuses degrade rather than throwing', () {
      final snap = BridgeReply.parse(
        '{"ok":true,"items":[{"id":"c","name":"C","kind":"composition",'
        '"children":[],"comp":{"width":1,"height":1,"fps":{"num":1,"den":1},'
        '"frame_count":1,"layers":[{"id":"l","index":0,"name":"n",'
        '"kind":"nebula","in_frame":0,"out_frame":1,"label":0,"switches":{}}],'
        '"markers":[]}}],"can_undo":false,"can_redo":false,"path":null}',
      ).snapshot!;
      expect(snap.items[0].comp!.layers[0].kind, BridgeLayerKind.unknown);
      // Absent switch fields fall back to their model defaults.
      expect(snap.items[0].comp!.layers[0].switches.visible, isTrue);
      expect(snap.items[0].comp!.layers[0].switches.solo, isFalse);
    });
  });

  group('AppStateStub snapshot-v2 op pass-throughs (fake bridge)', () {
    test('frontComp resolves the first composition in the snapshot', () {
      final fake = _FakeBridge();
      final app = AppStateStub(bridge: fake);
      expect(app.frontComp, isNull, reason: 'no comp yet');
      // A snapshot carrying a comp makes frontComp resolve it.
      app.snapshot = BridgeReply.parse(
        '{"ok":true,"items":[{"id":"c1","name":"Scene","kind":"composition",'
        '"children":[],"comp":{"width":640,"height":480,"fps":{"num":24,'
        '"den":1},"frame_count":48,"layers":[],"markers":[]}}],'
        '"can_undo":false,"can_redo":false,"path":null}',
      ).snapshot;
      expect(app.frontComp, isNotNull);
      expect(app.frontComp!.width, 640);
      expect(app.frontComp!.fps.num, 24);
    });

    test('the ops route to the bridge and refresh the snapshot', () {
      final fake = _FakeBridge()..newComposition('Scene');
      final app = AppStateStub(bridge: fake);
      app.setLayerSwitch('c1', 'l0', 'solo', true);
      app.editLayerSpan('c1', 'l0', 'move_in', 120);
      app.setTransform('c1', 'l0', 'opacity', 42.0);
      app.addMarker('c1', 90);
      expect(fake.ops, [
        'switch:c1/l0/solo=true',
        'span:c1/l0/move_in@120',
        'transform:c1/l0/opacity=42.0',
        'marker:c1@90',
      ]);
      expect(app.snapshot, isNotNull);
      expect(app.errorNotice, isNull);
    });

    test('an op failure surfaces on the error tint, no snapshot change', () {
      final fake = _FakeBridge()..newComposition('Scene');
      final app = AppStateStub(bridge: fake);
      fake.nextOpError = 'set transform: unknown property';
      app.setTransform('c1', 'l0', 'wobble', 1.0);
      expect(app.errorNotice, 'set transform: unknown property');
    });

    test('the ops are quiet no-ops without a bridge', () {
      final app = AppStateStub();
      // None of these throw or touch a null bridge.
      app.setLayerSwitch('c', 'l', 'solo', true);
      app.editLayerSpan('c', 'l', 'trim_in', 0);
      app.setTransform('c', 'l', 'opacity', 1.0);
      app.addMarker('c', 0);
      expect(app.decodeFrame('f', 0), isNull);
      expect(app.errorNotice, isNull);
    });

    test('decodeFrame passes through to the bridge and returns its frame', () {
      final fake = _FakeBridge()
        ..decodeResult = DecodedFrame(
          width: 2,
          height: 1,
          rgba: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        );
      final app = AppStateStub(bridge: fake);
      final frame = app.decodeFrame('f1', 7);
      expect(fake.decoded, ['f1@7']);
      expect(frame, isNotNull);
      expect(frame!.width, 2);
      expect(frame.rgba.length, 8);
    });
  });
}
