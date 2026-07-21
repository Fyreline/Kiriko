// The Dart half of bridge v0 (docs/flutter-port/03-ARCHITECTURE.md "Bridge
// v0"): a thin dart:ffi wrapper over the `lumit_bridge` shared library. Dart
// calls the crate's C functions, each of which returns a Rust-owned UTF-8 JSON
// string; this side copies the string out, immediately frees it back to Rust,
// and decodes the JSON into typed Dart classes.
//
// The whole frontend must work WITHOUT the library present: `tryLoad` returns
// null when the `.dll` cannot be found or bound, and the app keeps its
// placeholder behaviour. Nothing here is imported into a code path that runs
// before a successful `tryLoad`, so the tests (which never load the library)
// stay green.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The kind of a project item, mirroring `lumit_core::model::ProjectItem`.
/// `unknown` covers a kind string a newer engine might add — drawn quietly
/// rather than crashing.
enum BridgeItemKind { footage, folder, composition, solid, unknown }

BridgeItemKind _kindOf(Object? raw) => switch (raw) {
      'footage' => BridgeItemKind.footage,
      'folder' => BridgeItemKind.folder,
      'composition' => BridgeItemKind.composition,
      'solid' => BridgeItemKind.solid,
      _ => BridgeItemKind.unknown,
    };

/// The kind of a composition layer, mirroring `lumit_core::model::LayerKind`.
/// `unknown` degrades a variant a newer engine might add.
enum BridgeLayerKind {
  footage,
  solid,
  precomp,
  text,
  camera,
  sequence,
  adjustment,
  unknown,
}

BridgeLayerKind _layerKindOf(Object? raw) => switch (raw) {
      'footage' => BridgeLayerKind.footage,
      'solid' => BridgeLayerKind.solid,
      'precomp' => BridgeLayerKind.precomp,
      'text' => BridgeLayerKind.text,
      'camera' => BridgeLayerKind.camera,
      'sequence' => BridgeLayerKind.sequence,
      'adjustment' => BridgeLayerKind.adjustment,
      _ => BridgeLayerKind.unknown,
    };

/// A footage item's probe status, mirroring the bridge's `status` field.
/// `unprobed` is the state before probing (or a `--no-default-features` build
/// that never probes); `unknown` degrades a status a newer engine might add.
enum BridgeMediaStatus { ok, missing, unprobed, failed, unknown }

BridgeMediaStatus _statusOf(Object? raw) => switch (raw) {
      'ok' => BridgeMediaStatus.ok,
      'missing' => BridgeMediaStatus.missing,
      'unprobed' => BridgeMediaStatus.unprobed,
      'failed' => BridgeMediaStatus.failed,
      _ => BridgeMediaStatus.unknown,
    };

int _asInt(Object? raw, [int fallback = 0]) =>
    raw is num ? raw.toInt() : fallback;

/// An exact rational frame rate, `{num, den}` as the engine stores it (e.g.
/// 60000/1001). [fps] is the convenience double for display only.
class BridgeFps {
  final int num;
  final int den;

  const BridgeFps(this.num, this.den);

  double get fps => den == 0 ? 0 : num / den;

  factory BridgeFps.fromJson(Map<String, dynamic> m) =>
      BridgeFps(_asInt(m['num']), _asInt(m['den'], 1));
}

/// A layer's switches, mirroring `lumit_core::model::Switches` field-for-field.
/// The on-by-default switches (visible/audible/fx) default to true when a field
/// is absent, matching the model's serde defaults.
class BridgeSwitches {
  final bool visible;
  final bool audible;
  final bool locked;
  final bool threeD;
  final bool collapse;
  final bool fx;
  final bool solo;
  final bool motionBlur;

  const BridgeSwitches({
    required this.visible,
    required this.audible,
    required this.locked,
    required this.threeD,
    required this.collapse,
    required this.fx,
    required this.solo,
    required this.motionBlur,
  });

  factory BridgeSwitches.fromJson(Map<String, dynamic> m) => BridgeSwitches(
        visible: m['visible'] is bool ? m['visible'] as bool : true,
        audible: m['audible'] is bool ? m['audible'] as bool : true,
        locked: m['locked'] == true,
        threeD: m['three_d'] == true,
        collapse: m['collapse'] == true,
        fx: m['fx'] is bool ? m['fx'] as bool : true,
        solo: m['solo'] == true,
        motionBlur: m['motion_blur'] == true,
      );
}

/// One composition layer as the Timeline reads it. `inFrame`/`outFrame` are comp
/// frames derived from the comp's own rate; `index` is the stack position
/// (0 = top).
class BridgeLayer {
  final String id;
  final int index;
  final String name;
  final BridgeLayerKind kind;
  final int inFrame;
  final int outFrame;
  final int label;
  final BridgeSwitches switches;

  const BridgeLayer({
    required this.id,
    required this.index,
    required this.name,
    required this.kind,
    required this.inFrame,
    required this.outFrame,
    required this.label,
    required this.switches,
  });

  factory BridgeLayer.fromJson(Map<String, dynamic> m) => BridgeLayer(
        id: m['id'] is String ? m['id'] as String : '',
        index: _asInt(m['index']),
        name: m['name'] is String ? m['name'] as String : '',
        kind: _layerKindOf(m['kind']),
        inFrame: _asInt(m['in_frame']),
        outFrame: _asInt(m['out_frame']),
        label: _asInt(m['label']),
        switches: m['switches'] is Map
            ? BridgeSwitches.fromJson(
                (m['switches'] as Map).cast<String, dynamic>())
            : const BridgeSwitches(
                visible: true,
                audible: true,
                locked: false,
                threeD: false,
                collapse: false,
                fx: true,
                solo: false,
                motionBlur: false,
              ),
      );
}

/// A composition's detail: size, frame rate, derived frame count, layers (top
/// first) and marker frames.
class BridgeComp {
  final int width;
  final int height;
  final BridgeFps fps;
  final int frameCount;
  final List<BridgeLayer> layers;
  final List<int> markers;

  const BridgeComp({
    required this.width,
    required this.height,
    required this.fps,
    required this.frameCount,
    required this.layers,
    required this.markers,
  });

  factory BridgeComp.fromJson(Map<String, dynamic> m) {
    final layers = <BridgeLayer>[];
    final rawLayers = m['layers'];
    if (rawLayers is List) {
      for (final l in rawLayers) {
        if (l is Map) {
          layers.add(BridgeLayer.fromJson(l.cast<String, dynamic>()));
        }
      }
    }
    final markers = <int>[];
    final rawMarkers = m['markers'];
    if (rawMarkers is List) {
      for (final frame in rawMarkers) {
        if (frame is num) markers.add(frame.toInt());
      }
    }
    return BridgeComp(
      width: _asInt(m['width']),
      height: _asInt(m['height']),
      fps: m['fps'] is Map
          ? BridgeFps.fromJson((m['fps'] as Map).cast<String, dynamic>())
          : const BridgeFps(0, 1),
      frameCount: _asInt(m['frame_count']),
      layers: layers,
      markers: markers,
    );
  }
}

/// A footage item's probed media metadata, present once its status is `ok`.
class BridgeMedia {
  final int durationFrames;
  final BridgeFps fps;
  final int width;
  final int height;
  final bool audio;

  const BridgeMedia({
    required this.durationFrames,
    required this.fps,
    required this.width,
    required this.height,
    required this.audio,
  });

  factory BridgeMedia.fromJson(Map<String, dynamic> m) => BridgeMedia(
        durationFrames: _asInt(m['duration_frames']),
        fps: m['fps'] is Map
            ? BridgeFps.fromJson((m['fps'] as Map).cast<String, dynamic>())
            : const BridgeFps(0, 1),
        width: _asInt(m['width']),
        height: _asInt(m['height']),
        audio: m['audio'] == true,
      );
}

/// A decoded footage frame: tightly-packed straight (non-premultiplied) RGBA8,
/// `width * height * 4` bytes. The bytes are copied out of the engine's buffer,
/// which is freed immediately, so this owns its pixels.
class DecodedFrame {
  final int width;
  final int height;
  final Uint8List rgba;

  const DecodedFrame({
    required this.width,
    required this.height,
    required this.rgba,
  });
}

/// One node in the Project panel tree. Folders carry nested [children]; every
/// other kind carries an empty list. A composition additionally carries [comp]
/// (its size/layers/markers); a footage item carries its probe [status] and,
/// once probed, its [media] metadata.
class BridgeItem {
  final String id;
  final String name;
  final BridgeItemKind kind;
  final List<BridgeItem> children;

  /// Present for compositions (snapshot v2), else null.
  final BridgeComp? comp;

  /// Present for footage items once probed cleanly, else null.
  final BridgeMedia? media;

  /// Present for footage items (the probe status), else null.
  final BridgeMediaStatus? status;

  const BridgeItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.children,
    this.comp,
    this.media,
    this.status,
  });

  factory BridgeItem.fromJson(Map<String, dynamic> m) {
    final rawChildren = m['children'];
    final children = <BridgeItem>[];
    if (rawChildren is List) {
      for (final child in rawChildren) {
        if (child is Map) {
          children.add(BridgeItem.fromJson(child.cast<String, dynamic>()));
        }
      }
    }
    return BridgeItem(
      id: m['id'] is String ? m['id'] as String : '',
      name: m['name'] is String ? m['name'] as String : '',
      kind: _kindOf(m['kind']),
      children: children,
      comp: m['comp'] is Map
          ? BridgeComp.fromJson((m['comp'] as Map).cast<String, dynamic>())
          : null,
      media: m['media'] is Map
          ? BridgeMedia.fromJson((m['media'] as Map).cast<String, dynamic>())
          : null,
      status: m.containsKey('status') ? _statusOf(m['status']) : null,
    );
  }
}

/// A decoded document snapshot — the `{"ok":true, …}` reply shape.
class BridgeSnapshot {
  final List<BridgeItem> items;
  final bool canUndo;
  final bool canRedo;

  /// The loaded/last-saved project path, or null for an unsaved document.
  final String? path;

  const BridgeSnapshot({
    required this.items,
    required this.canUndo,
    required this.canRedo,
    required this.path,
  });

  factory BridgeSnapshot.fromJson(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <BridgeItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          items.add(BridgeItem.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return BridgeSnapshot(
      items: items,
      canUndo: m['can_undo'] == true,
      canRedo: m['can_redo'] == true,
      path: m['path'] is String ? m['path'] as String : null,
    );
  }
}

/// The result of one bridge call: a snapshot on success, or a calm error string
/// for the status line on failure. Parsing a malformed reply is itself an
/// error, never a throw.
class BridgeReply {
  final BridgeSnapshot? snapshot;
  final String? error;

  const BridgeReply.ok(this.snapshot) : error = null;
  const BridgeReply.err(this.error) : snapshot = null;

  bool get ok => error == null;

  /// Decode a reply string. `{"ok":true,…}` yields a snapshot; `{"ok":false,
  /// "error":"…"}` yields the error; anything else is reported as malformed.
  factory BridgeReply.parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const BridgeReply.err('bridge returned malformed JSON');
    }
    if (decoded is! Map) {
      return const BridgeReply.err('bridge returned malformed JSON');
    }
    final map = decoded.cast<String, dynamic>();
    if (map['ok'] == true) {
      return BridgeReply.ok(BridgeSnapshot.fromJson(map));
    }
    final err = map['error'];
    return BridgeReply.err(err is String ? err : 'bridge error');
  }
}

// The C signatures. Strings cross as `Pointer<Char>`; the engine allocates the
// replies and frees them through `lumit_bridge_free_string`.
typedef _NoArgC = Pointer<Char> Function();
typedef _NoArgDart = Pointer<Char> Function();
typedef _StrArgC = Pointer<Char> Function(Pointer<Char>);
typedef _StrArgDart = Pointer<Char> Function(Pointer<Char>);
typedef _FreeC = Void Function(Pointer<Char>);
typedef _FreeDart = void Function(Pointer<Char>);

// Snapshot-v2 op signatures (mixed argument types).
typedef _SwitchC = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, Bool);
typedef _SwitchDart = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, bool);
typedef _SpanC = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, Int64);
typedef _SpanDart = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, int);
typedef _TransformC = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, Double);
typedef _TransformDart = Pointer<Char> Function(
    Pointer<Char>, Pointer<Char>, Pointer<Char>, double);
typedef _MarkerC = Pointer<Char> Function(Pointer<Char>, Int64);
typedef _MarkerDart = Pointer<Char> Function(Pointer<Char>, int);

// Frame decode: a raw RGBA8 buffer with its size written into out-pointers.
typedef _DecodeC = Pointer<Uint8> Function(
    Pointer<Char>, Uint64, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _DecodeDart = Pointer<Uint8> Function(
    Pointer<Char>, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _FreeBufferC = Void Function(Pointer<Uint8>, Size);
typedef _FreeBufferDart = void Function(Pointer<Uint8>, int);

/// The set of document operations the frontend drives the engine through. The
/// real implementation is [LumitBridge] (dart:ffi over the shared library); the
/// interface exists so tests can supply a fake without loading the library or
/// touching plugin channels — every method is a pure `String → BridgeReply`
/// call, so a fake is a handful of lines.
abstract class DocumentBridge {
  BridgeReply snapshot();
  BridgeReply newProject();
  BridgeReply undo();
  BridgeReply redo();
  BridgeReply openProject(String path);

  /// Save to [path]; an empty string saves to the loaded path (an error reply
  /// if the document has never been saved).
  BridgeReply saveProject(String path);
  BridgeReply newComposition(String name);

  /// Add a footage item referencing the media file at [path]. With the engine's
  /// `media` feature the item is probed and its metadata/status ride the
  /// returned snapshot.
  BridgeReply importFootage(String path);

  /// Flip a layer's switch through the real op (undoable). [switchName] is the
  /// model's own field name (`visible`, `audible`, `locked`, `solo`,
  /// `motion_blur`, `fx`, `three_d`, `collapse`).
  BridgeReply setLayerSwitch(
      String compId, String layerId, String switchName, bool value);

  /// Edit a layer's span relative to the playhead [frame]. [edit] is one of
  /// `move_in`, `move_out`, `trim_in`, `trim_out`.
  BridgeReply editLayerSpan(
      String compId, String layerId, String edit, int frame);

  /// Set one transform property to a static [value]. [property] is a snake_case
  /// `TransformProp` name (e.g. `position_x`, `rotation`, `opacity`).
  BridgeReply setTransform(
      String compId, String layerId, String property, double value);

  /// Drop a user marker on the composition timeline at [frame].
  BridgeReply addMarker(String compId, int frame);

  /// Decode one footage frame to RGBA8 (the F2 CPU path), or null on failure
  /// (missing/unreadable file, no engine library). The pixels are copied out of
  /// the engine buffer, which is freed immediately.
  DecodedFrame? decodeFrame(String itemId, int frame);
}

/// The loaded `lumit_bridge` library, bound to typed calls. Construct with
/// [tryLoad]; a null result means the app runs on its placeholders.
class LumitBridge implements DocumentBridge {
  final _NoArgDart _version;
  final _NoArgDart _newProject;
  final _StrArgDart _openProject;
  final _StrArgDart _saveProject;
  final _NoArgDart _snapshot;
  final _StrArgDart _newComposition;
  final _StrArgDart _importFootage;
  final _NoArgDart _undo;
  final _NoArgDart _redo;
  final _SwitchDart _setLayerSwitch;
  final _SpanDart _editLayerSpan;
  final _TransformDart _setTransform;
  final _MarkerDart _addMarker;
  final _DecodeDart _decodeFrame;
  final _FreeDart _freeString;
  final _FreeBufferDart _freeBuffer;

  LumitBridge._(DynamicLibrary lib)
      : _version = lib.lookupFunction<_NoArgC, _NoArgDart>(
          'lumit_bridge_version',
        ),
        _newProject = lib.lookupFunction<_NoArgC, _NoArgDart>(
          'lumit_bridge_new_project',
        ),
        _openProject = lib.lookupFunction<_StrArgC, _StrArgDart>(
          'lumit_bridge_open_project',
        ),
        _saveProject = lib.lookupFunction<_StrArgC, _StrArgDart>(
          'lumit_bridge_save_project',
        ),
        _snapshot = lib.lookupFunction<_NoArgC, _NoArgDart>(
          'lumit_bridge_snapshot',
        ),
        _newComposition = lib.lookupFunction<_StrArgC, _StrArgDart>(
          'lumit_bridge_new_composition',
        ),
        _importFootage = lib.lookupFunction<_StrArgC, _StrArgDart>(
          'lumit_bridge_import_footage',
        ),
        _undo = lib.lookupFunction<_NoArgC, _NoArgDart>(
          'lumit_bridge_undo',
        ),
        _redo = lib.lookupFunction<_NoArgC, _NoArgDart>(
          'lumit_bridge_redo',
        ),
        _setLayerSwitch = lib.lookupFunction<_SwitchC, _SwitchDart>(
          'lumit_bridge_set_layer_switch',
        ),
        _editLayerSpan = lib.lookupFunction<_SpanC, _SpanDart>(
          'lumit_bridge_edit_layer_span',
        ),
        _setTransform = lib.lookupFunction<_TransformC, _TransformDart>(
          'lumit_bridge_set_transform',
        ),
        _addMarker = lib.lookupFunction<_MarkerC, _MarkerDart>(
          'lumit_bridge_add_marker',
        ),
        _decodeFrame = lib.lookupFunction<_DecodeC, _DecodeDart>(
          'lumit_bridge_decode_frame',
        ),
        _freeString = lib.lookupFunction<_FreeC, _FreeDart>(
          'lumit_bridge_free_string',
        ),
        _freeBuffer = lib.lookupFunction<_FreeBufferC, _FreeBufferDart>(
          'lumit_bridge_free_buffer',
        );

  /// Load the library and bind it, or return null if it cannot be found or a
  /// symbol is missing. Never throws — a failure is just "run on placeholders".
  static LumitBridge? tryLoad() {
    for (final candidate in _candidatePaths()) {
      try {
        final lib = DynamicLibrary.open(candidate);
        return LumitBridge._(lib);
      } catch (_) {
        // Try the next candidate.
      }
    }
    return null;
  }

  /// Where the library might live, in the order the runner should try:
  /// beside the executable first (the shipped layout), then the Cargo debug
  /// output relative to the working directory (the developer layout), then the
  /// bare name so the OS loader's own search path gets a turn.
  static List<String> _candidatePaths() {
    const name = 'lumit_bridge.dll';
    final paths = <String>[];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      paths.add('$exeDir${Platform.pathSeparator}$name');
    } catch (_) {
      // resolvedExecutable can be unavailable in some hosts; skip it.
    }
    final cwd = Directory.current.path;
    final sep = Platform.pathSeparator;
    paths.add('$cwd$sep..$sep..$sep..${sep}target${sep}debug$sep$name');
    paths.add('$cwd$sep..${sep}target${sep}debug$sep$name');
    paths.add(name);
    return paths;
  }

  /// `{"version":"…","abi":1,"ok":true}` as the raw decoded map, or null if the
  /// reply is malformed. Used for a boot-time handshake / log line.
  Map<String, dynamic>? version() {
    final raw = _callNoArg(_version);
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  BridgeReply snapshot() => BridgeReply.parse(_callNoArg(_snapshot));
  @override
  BridgeReply newProject() => BridgeReply.parse(_callNoArg(_newProject));
  @override
  BridgeReply undo() => BridgeReply.parse(_callNoArg(_undo));
  @override
  BridgeReply redo() => BridgeReply.parse(_callNoArg(_redo));

  @override
  BridgeReply openProject(String path) =>
      BridgeReply.parse(_callStrArg(_openProject, path));

  /// Save to [path]; an empty string saves to the loaded path (an error reply
  /// if the document has never been saved).
  @override
  BridgeReply saveProject(String path) =>
      BridgeReply.parse(_callStrArg(_saveProject, path));

  @override
  BridgeReply newComposition(String name) =>
      BridgeReply.parse(_callStrArg(_newComposition, name));

  @override
  BridgeReply importFootage(String path) =>
      BridgeReply.parse(_callStrArg(_importFootage, path));

  @override
  BridgeReply setLayerSwitch(
    String compId,
    String layerId,
    String switchName,
    bool value,
  ) {
    final c = compId.toNativeUtf8();
    final l = layerId.toNativeUtf8();
    final s = switchName.toNativeUtf8();
    try {
      return BridgeReply.parse(_readReply(
        _setLayerSwitch(c.cast(), l.cast(), s.cast(), value),
      ));
    } finally {
      malloc.free(c);
      malloc.free(l);
      malloc.free(s);
    }
  }

  @override
  BridgeReply editLayerSpan(
    String compId,
    String layerId,
    String edit,
    int frame,
  ) {
    final c = compId.toNativeUtf8();
    final l = layerId.toNativeUtf8();
    final e = edit.toNativeUtf8();
    try {
      return BridgeReply.parse(_readReply(
        _editLayerSpan(c.cast(), l.cast(), e.cast(), frame),
      ));
    } finally {
      malloc.free(c);
      malloc.free(l);
      malloc.free(e);
    }
  }

  @override
  BridgeReply setTransform(
    String compId,
    String layerId,
    String property,
    double value,
  ) {
    final c = compId.toNativeUtf8();
    final l = layerId.toNativeUtf8();
    final p = property.toNativeUtf8();
    try {
      return BridgeReply.parse(_readReply(
        _setTransform(c.cast(), l.cast(), p.cast(), value),
      ));
    } finally {
      malloc.free(c);
      malloc.free(l);
      malloc.free(p);
    }
  }

  @override
  BridgeReply addMarker(String compId, int frame) {
    final c = compId.toNativeUtf8();
    try {
      return BridgeReply.parse(_readReply(_addMarker(c.cast(), frame)));
    } finally {
      malloc.free(c);
    }
  }

  @override
  DecodedFrame? decodeFrame(String itemId, int frame) {
    final id = itemId.toNativeUtf8();
    final outW = malloc<Uint32>();
    final outH = malloc<Uint32>();
    final outLen = malloc<Size>();
    try {
      final ptr = _decodeFrame(id.cast(), frame, outW, outH, outLen);
      if (ptr == nullptr) return null;
      final len = outLen.value;
      try {
        // Copy the pixels out before the buffer is freed back to Rust.
        final rgba = Uint8List.fromList(ptr.asTypedList(len));
        return DecodedFrame(
          width: outW.value,
          height: outH.value,
          rgba: rgba,
        );
      } finally {
        _freeBuffer(ptr, len);
      }
    } finally {
      malloc.free(id);
      malloc.free(outW);
      malloc.free(outH);
      malloc.free(outLen);
    }
  }

  // Copy a reply string out of the engine-owned pointer, then free it back to
  // Rust. The copy must happen before the free, so `toDartString` runs inside
  // the try and the free in the finally.
  String _readReply(Pointer<Char> ptr) {
    if (ptr == nullptr) {
      return '{"ok":false,"error":"bridge returned a null reply"}';
    }
    try {
      return ptr.cast<Utf8>().toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  String _callNoArg(_NoArgDart fn) => _readReply(fn());

  String _callStrArg(_StrArgDart fn, String arg) {
    final argPtr = arg.toNativeUtf8();
    try {
      return _readReply(fn(argPtr.cast<Char>()));
    } finally {
      malloc.free(argPtr);
    }
  }
}
