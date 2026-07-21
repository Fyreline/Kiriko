// The render isolate (the perf pass, K-176 — the big one).
//
// In plain terms: rendering a whole composited comp and reading its pixels back
// is heavy work. Doing it on the UI isolate freezes the interface every frame
// of a scrub or playback (the "laggy af" report; docs/14 and K-017 say the UI
// thread must never render a frame). This file moves that work onto a long-lived
// background worker isolate.
//
// HOW THE ENGINE STATE STAYS SHARED. The worker opens its OWN
// `DynamicLibrary.open` of the SAME `lumit_bridge.dll` file. A DLL opened twice
// in one process shares one copy of its data, so both handles see the one engine
// state behind the bridge's process-wide `Mutex` (crates/lumit-bridge/src/
// state.rs: `static BRIDGE: OnceLock<Mutex<Bridge>>`, taken only for the
// duration of one call and never across a re-entrant call, so it cannot
// deadlock). That mutex is exactly what makes a render on the worker isolate
// safe while the UI isolate keeps driving document ops — the two serialise
// through the lock rather than racing. Only the read-only render/decode calls
// ride the worker; document mutations stay on the UI isolate's bridge handle.
//
// LATEST-WINS. Requests carry a monotonic `generation`. The worker answers each
// in order; a reply the [PreviewSource] no longer wants is simply dropped there
// (it only ever keeps one request outstanding). If the worker cannot be spawned
// or the library cannot be opened in it, the renderer degrades to the inline
// [SynchronousFrameRenderer] so the Viewer never goes dark — the required
// fallback when isolates are unavailable.

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bridge/bridge.dart';
import '../state/app_state.dart';
import 'preview_source.dart';

// The two engine symbols the worker needs, plus the buffer free. Mirrors the
// private typedefs in bridge.dart (kept local so the worker is self-contained).
typedef _RenderC = Pointer<Uint8> Function(
    Pointer<Char>, Uint64, Float, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _RenderDart = Pointer<Uint8> Function(
    Pointer<Char>, int, double, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _DecodeC = Pointer<Uint8> Function(
    Pointer<Char>, Uint64, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _DecodeDart = Pointer<Uint8> Function(
    Pointer<Char>, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Size>);
typedef _FreeBufferC = Void Function(Pointer<Uint8>, Size);
typedef _FreeBufferDart = void Function(Pointer<Uint8>, int);
// Zero-copy shared-texture render (K-177): no buffer returned — the frame stays
// on the GPU; the reply carries only the NT handle and dimensions.
typedef _RenderSharedC = Bool Function(
    Pointer<Char>, Uint64, Pointer<Uint64>, Pointer<Uint32>, Pointer<Uint32>);
typedef _RenderSharedDart = bool Function(
    Pointer<Char>, int, Pointer<Uint64>, Pointer<Uint32>, Pointer<Uint32>);

/// What the isolate needs to boot: the port to hand its own receive port back
/// on, and the candidate library paths to open (the UI isolate resolved these).
class _WorkerInit {
  final SendPort mainPort;
  final List<String> libPaths;
  const _WorkerInit(this.mainPort, this.libPaths);
}

/// A [FrameRenderer] that runs the heavy render/decode on a worker isolate, with
/// an inline [SynchronousFrameRenderer] fallback for the spawn window and for a
/// machine where the worker cannot open the library.
class IsolateFrameRenderer implements FrameRenderer {
  final AppStateStub app;

  @override
  final bool supportsCompRender;

  @override
  final bool supportsSharedTexture;

  final SynchronousFrameRenderer _fallback;
  final List<String> _libPaths;

  final ReceivePort _fromWorker = ReceivePort();
  SendPort? _toWorker;
  Isolate? _isolate;
  bool _ready = false;
  bool _failed = false;
  bool _disposed = false;

  /// Callbacks awaiting a worker RGBA reply (comp/decode), keyed by generation.
  final Map<int, void Function(DecodedFrame?)> _awaiting = {};

  /// Callbacks awaiting a worker shared-texture reply, keyed by generation.
  final Map<int, void Function(SharedFrame?)> _awaitingShared = {};

  /// Requests raised before the worker's send port arrived (the spawn window).
  final List<void Function()> _startupQueue = [];

  IsolateFrameRenderer._(this.app, this.supportsCompRender,
      this.supportsSharedTexture, this._libPaths)
      : _fallback = SynchronousFrameRenderer(app) {
    _fromWorker.listen(_onWorkerMessage);
    _spawn();
  }

  /// Build a renderer for [app]'s loaded [LumitBridge], or null when the app has
  /// no real library to open in a worker (then the caller keeps the inline
  /// renderer). [supportsCompRender] is read from the UI-isolate bridge — a
  /// cheap symbol-presence check, safe to do on the UI thread.
  static IsolateFrameRenderer? tryCreate(AppStateStub app) {
    final bridge = app.bridge;
    if (bridge is! LumitBridge) return null;
    final paths = <String>[
      if (bridge.loadedPath != null) bridge.loadedPath!,
      ...LumitBridge.candidateLibraryPaths(),
    ];
    return IsolateFrameRenderer._(app, bridge.supportsCompRender,
        bridge.supportsSharedTexture, paths);
  }

  Future<void> _spawn() async {
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        _WorkerInit(_fromWorker.sendPort, _libPaths),
        debugName: 'lumit-render',
      );
    } catch (_) {
      // No worker: everything falls back to the inline renderer.
      _failed = true;
      final queued = List<void Function()>.from(_startupQueue);
      _startupQueue.clear();
      for (final run in queued) {
        run();
      }
    }
  }

  void _onWorkerMessage(Object? message) {
    if (message is SendPort) {
      _toWorker = message;
      _ready = true;
      final queued = List<void Function()>.from(_startupQueue);
      _startupQueue.clear();
      for (final run in queued) {
        run();
      }
      return;
    }
    if (message is! List) return;
    // A shared-texture reply is tagged; an RGBA (comp/decode) reply is a bare
    // 4-tuple `[generation, width, height, ttd]`.
    if (message.length == 5 && message[0] == 'shared') {
      final generation = message[1] as int;
      final handle = message[2] as int;
      final width = message[3] as int;
      final height = message[4] as int;
      final onFrame = _awaitingShared.remove(generation);
      if (onFrame == null) return; // superseded/unknown — drop it
      if (handle != 0 && width > 0 && height > 0) {
        onFrame(SharedFrame(handle: handle, width: width, height: height));
      } else {
        onFrame(null);
      }
      return;
    }
    if (message.length == 4) {
      final generation = message[0] as int;
      final width = message[1] as int;
      final height = message[2] as int;
      final ttd = message[3];
      final onFrame = _awaiting.remove(generation);
      if (onFrame == null) return; // superseded/unknown — drop it
      if (ttd is TransferableTypedData && width > 0 && height > 0) {
        onFrame(DecodedFrame(
            width: width, height: height, rgba: ttd.materialize().asUint8List()));
      } else {
        onFrame(null);
      }
    }
  }

  void _dispatch(int generation, List<Object?> wire,
      void Function(DecodedFrame?) onFrame) {
    if (_disposed) {
      onFrame(null);
      return;
    }
    if (_failed) {
      // Route through the inline fallback (comp vs decode by the leading tag).
      _runFallback(wire, onFrame);
      return;
    }
    if (!_ready) {
      _startupQueue.add(() => _dispatch(generation, wire, onFrame));
      return;
    }
    _awaiting[generation] = onFrame;
    _toWorker!.send(wire);
  }

  void _runFallback(List<Object?> wire, void Function(DecodedFrame?) onFrame) {
    if (wire[0] == 'comp') {
      _fallback.requestComp(wire[1] as String, wire[2] as int, wire[3] as double,
          wire[4] as int, onFrame);
    } else {
      _fallback.requestDecode(
          wire[1] as String, wire[2] as int, wire[4] as int, onFrame);
    }
  }

  /// The shared-texture sibling of [_dispatch] — its reply is a
  /// [SharedFrame], not pixels, so it uses its own awaiting map.
  void _dispatchShared(int generation, List<Object?> wire,
      void Function(SharedFrame?) onFrame) {
    if (_disposed) {
      onFrame(null);
      return;
    }
    if (_failed) {
      _fallback.requestShared(
          wire[1] as String, wire[2] as int, wire[4] as int, onFrame);
      return;
    }
    if (!_ready) {
      _startupQueue.add(() => _dispatchShared(generation, wire, onFrame));
      return;
    }
    _awaitingShared[generation] = onFrame;
    _toWorker!.send(wire);
  }

  @override
  void requestComp(String compId, int frame, double scale, int generation,
      void Function(DecodedFrame?) onFrame) {
    _dispatch(generation, ['comp', compId, frame, scale, generation], onFrame);
  }

  @override
  void requestShared(String compId, int frame, int generation,
      void Function(SharedFrame?) onFrame) {
    _dispatchShared(
        generation, ['shared', compId, frame, 0.0, generation], onFrame);
  }

  @override
  void requestDecode(String itemId, int frame, int generation,
      void Function(DecodedFrame?) onFrame) {
    _dispatch(generation, ['decode', itemId, frame, 1.0, generation], onFrame);
  }

  @override
  void dispose() {
    _disposed = true;
    _awaiting.clear();
    _awaitingShared.clear();
    _startupQueue.clear();
    _fromWorker.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

// ---------------------------------------------------------------------------
// The worker isolate.
// ---------------------------------------------------------------------------

/// The worker entrypoint: open the library, then service render/decode requests
/// off the UI isolate, replying with the pixels wrapped in a
/// [TransferableTypedData] (a zero-copy hand-off back to the UI isolate).
void _workerMain(_WorkerInit init) {
  final recv = ReceivePort();
  init.mainPort.send(recv.sendPort);

  DynamicLibrary? lib;
  for (final path in init.libPaths) {
    try {
      lib = DynamicLibrary.open(path);
      break;
    } catch (_) {
      // Try the next candidate.
    }
  }

  if (lib == null) {
    // No library in the worker: answer null to everything so the UI isolate's
    // renderer keeps its last picture rather than hanging on a lost request.
    recv.listen((message) {
      if (message is! List || message.length != 5) return;
      final generation = message[4] as int;
      if (message[0] == 'shared') {
        init.mainPort.send(['shared', generation, 0, 0, 0]);
      } else {
        init.mainPort.send([generation, 0, 0, null]);
      }
    });
    return;
  }

  _RenderDart? render;
  _DecodeDart? decode;
  _RenderSharedDart? renderShared;
  _FreeBufferDart? freeBuffer;
  try {
    render = lib.lookupFunction<_RenderC, _RenderDart>(
        'lumit_bridge_render_comp_frame');
  } catch (_) {
    render = null;
  }
  try {
    decode =
        lib.lookupFunction<_DecodeC, _DecodeDart>('lumit_bridge_decode_frame');
  } catch (_) {
    decode = null;
  }
  try {
    renderShared = lib.lookupFunction<_RenderSharedC, _RenderSharedDart>(
        'lumit_bridge_render_to_shared');
  } catch (_) {
    renderShared = null;
  }
  try {
    freeBuffer = lib.lookupFunction<_FreeBufferC, _FreeBufferDart>(
        'lumit_bridge_free_buffer');
  } catch (_) {
    freeBuffer = null;
  }

  recv.listen((message) {
    if (message is! List || message.length != 5) return;
    final kind = message[0] as String;
    final id = message[1] as String;
    final frame = message[2] as int;
    final scale = message[3] as double;
    final generation = message[4] as int;

    if (kind == 'shared') {
      final shared = _renderShared(renderShared, id, frame);
      init.mainPort.send(['shared', generation, shared.$1, shared.$2, shared.$3]);
      return;
    }
    final reply = (kind == 'comp')
        ? _renderOne(render, freeBuffer, id, frame, scale)
        : _decodeOne(decode, freeBuffer, id, frame);
    init.mainPort.send([generation, reply.$1, reply.$2, reply.$3]);
  });
}

/// Render one comp into the shared GPU texture on the worker; returns
/// `(handle, width, height)` — zeros on failure. No buffer to free: the frame
/// stays on the GPU (K-177).
(int, int, int) _renderShared(
    _RenderSharedDart? renderShared, String compId, int frame) {
  if (renderShared == null) return (0, 0, 0);
  final id = compId.toNativeUtf8();
  final outHandle = malloc<Uint64>();
  final outW = malloc<Uint32>();
  final outH = malloc<Uint32>();
  try {
    final ok = renderShared(id.cast(), frame, outHandle, outW, outH);
    if (!ok) return (0, 0, 0);
    return (outHandle.value, outW.value, outH.value);
  } finally {
    malloc.free(id);
    malloc.free(outHandle);
    malloc.free(outW);
    malloc.free(outH);
  }
}

/// Run one comp render on the worker; returns `(width, height, ttd?)`.
(int, int, TransferableTypedData?) _renderOne(_RenderDart? render,
    _FreeBufferDart? freeBuffer, String compId, int frame, double scale) {
  if (render == null || freeBuffer == null) return (0, 0, null);
  final id = compId.toNativeUtf8();
  final outW = malloc<Uint32>();
  final outH = malloc<Uint32>();
  final outLen = malloc<Size>();
  try {
    final ptr = render(id.cast(), frame, scale, outW, outH, outLen);
    if (ptr == nullptr) return (0, 0, null);
    final len = outLen.value;
    try {
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      return (outW.value, outH.value, TransferableTypedData.fromList([bytes]));
    } finally {
      freeBuffer(ptr, len);
    }
  } finally {
    malloc.free(id);
    malloc.free(outW);
    malloc.free(outH);
    malloc.free(outLen);
  }
}

/// Decode one footage frame on the worker; returns `(width, height, ttd?)`.
(int, int, TransferableTypedData?) _decodeOne(_DecodeDart? decode,
    _FreeBufferDart? freeBuffer, String itemId, int frame) {
  if (decode == null || freeBuffer == null) return (0, 0, null);
  final id = itemId.toNativeUtf8();
  final outW = malloc<Uint32>();
  final outH = malloc<Uint32>();
  final outLen = malloc<Size>();
  try {
    final ptr = decode(id.cast(), frame, outW, outH, outLen);
    if (ptr == nullptr) return (0, 0, null);
    final len = outLen.value;
    try {
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      return (outW.value, outH.value, TransferableTypedData.fromList([bytes]));
    } finally {
      freeBuffer(ptr, len);
    }
  } finally {
    malloc.free(id);
    malloc.free(outW);
    malloc.free(outH);
    malloc.free(outLen);
  }
}
