// The Viewer's CPU frame source (phase F2, docs/flutter-port/05 §F2).
//
// In plain terms: the Viewer needs actual pictures to show. This object works
// out WHICH footage the playhead is over, asks the engine bridge to decode that
// one frame to raw pixels, turns those pixels into a `ui.Image` Flutter can
// blit, and keeps a small cache so scrubbing back and forth is cheap. The
// Scopes panel reads the very same decoded pixels from here, so the trace always
// matches the picture on screen.
//
// HONEST LIMITATION (single-layer preview): the real compositor still lives in
// the egui crate (crates/lumit-ui) — the layered, transformed, effected comp
// frame is NOT available to Flutter yet. So this previews only the *topmost
// visible footage layer* whose span covers the playhead, decoded straight, with
// no transform, no blending, no effects. The composited-comp preview arrives
// when the compositor is extracted from egui into a shared crate (a later wave);
// until then this is labelled as single-layer everywhere it shows.
//
// A further limitation until the snapshot carries it: a footage layer in the
// snapshot does NOT carry its source item's id (only its own name), so the layer
// is matched to a footage item by name. Retime is also not in the snapshot, so
// the comp-frame → source-frame mapping is a straight offset (subtract in_frame),
// not the real Retime curve. Both are noted where they bite.

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../bridge/bridge.dart';
import '../state/app_state.dart';

/// What the Viewer previews this frame: a resolved footage [item] and the
/// [sourceFrame] within it (the comp frame minus the layer's in-point).
@immutable
class PreviewTarget {
  final BridgeItem item;
  final int sourceFrame;
  const PreviewTarget(this.item, this.sourceFrame);

  @override
  bool operator ==(Object other) =>
      other is PreviewTarget &&
      other.item.id == item.id &&
      other.sourceFrame == sourceFrame;

  @override
  int get hashCode => Object.hash(item.id, sourceFrame);
}

/// Find the footage item a footage [layer] references. The snapshot's layer
/// carries no item id (bridge v0.2), so it is matched to a footage item by name
/// — the honest F2 approximation. Searches nested folders. Null when no footage
/// item shares the layer's name.
BridgeItem? footageItemForLayer(BridgeLayer layer, List<BridgeItem> items) {
  BridgeItem? found;
  void walk(List<BridgeItem> xs) {
    for (final it in xs) {
      if (found != null) return;
      if (it.kind == BridgeItemKind.footage && it.name == layer.name) {
        found = it;
        return;
      }
      walk(it.children);
    }
  }

  walk(items);
  return found;
}

/// Resolve what the Viewer previews at [previewFrame]: the topmost VISIBLE
/// footage layer whose span covers the frame, mapped to its source item and
/// source frame. Pure, so the resolution rules are unit-tested without a bridge.
///
/// `layers` is top-first (index 0 = top), so the first covering match wins.
/// The span test mirrors the engine: in_frame ≤ frame < out_frame.
PreviewTarget? resolvePreview(
  BridgeComp? comp,
  int previewFrame,
  List<BridgeItem> items,
) {
  if (comp == null) return null;
  for (final layer in comp.layers) {
    if (layer.kind != BridgeLayerKind.footage) continue;
    if (!layer.switches.visible) continue;
    if (previewFrame < layer.inFrame || previewFrame >= layer.outFrame) continue;
    final item = footageItemForLayer(layer, items);
    if (item == null) continue;
    // Straight offset — Retime is not in the snapshot yet, so a retimed layer
    // previews as if played straight (noted in the checklist).
    return PreviewTarget(item, previewFrame - layer.inFrame);
  }
  return null;
}

/// One cache slot: the blit-ready image and the raw pixels behind it (so the
/// Scopes can read exactly the frame the Viewer is showing, even on a cache
/// hit where no fresh decode happens).
class _CacheEntry {
  final ui.Image image;
  final DecodedFrame frame;
  const _CacheEntry(this.image, this.frame);
}

/// The shared CPU frame source. Lives on [AppStateStub] so the Viewer and the
/// Scopes panel read the same decoded pixels through one notifier.
///
/// It listens to the app: whenever the playhead (or document) changes it
/// re-resolves the preview and, if the wanted frame is not already cached,
/// decodes exactly one frame — the per-tick throttle. Decoding is synchronous
/// (the bridge FFI call), but turning bytes into a `ui.Image` is async, so a
/// listener is notified when the image lands.
class PreviewSource extends ChangeNotifier {
  final AppStateStub app;

  /// Small most-recently-used cache of decoded frames (keyed `itemId@frame`).
  static const int _cacheLimit = 8;
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();

  PreviewTarget? _target;
  ui.Image? _image;
  DecodedFrame? _displayedFrame;
  int _generation = 0;
  String? _pendingKey;
  bool _disposed = false;

  PreviewSource(this.app) {
    app.addListener(_onAppChanged);
    _resolveAndDecode();
  }

  /// What the Viewer resolved this frame (null = no footage under the playhead).
  PreviewTarget? get target => _target;

  /// The blit-ready image for the current frame, or null when there is nothing
  /// decoded to show (slate, placeholder, or an in-flight decode).
  ui.Image? get image => _image;

  /// The raw pixels the Viewer is currently showing — the Scopes panel reads
  /// this. Held across a momentarily-unavailable frame (K-130) rather than
  /// nulled, so a scrub or a not-yet-decoded frame keeps the last real trace.
  DecodedFrame? get displayedFrame => _displayedFrame;

  /// Bumped each time a new frame is shown, so the Scopes panel knows when to
  /// rebuild its trace without diffing pixel buffers.
  int get generation => _generation;

  void _onAppChanged() {
    if (_disposed) return;
    _resolveAndDecode();
  }

  void _resolveAndDecode() {
    final comp = app.frontComp;
    final target =
        resolvePreview(comp, app.previewFrame, app.snapshot?.items ?? const []);
    _target = target;

    // No footage, or footage that shows a slate rather than a picture: leave the
    // last decoded frame in place for the Scopes to hold, and let the Viewer
    // draw the slate/placeholder. Clear the live image so the Viewer stops
    // blitting a stale picture over a slate.
    if (target == null ||
        target.item.status == BridgeMediaStatus.missing ||
        target.item.status == BridgeMediaStatus.failed) {
      if (_image != null) {
        _image = null;
        notifyListeners();
      }
      return;
    }

    final key = '${target.item.id}@${target.sourceFrame}';
    final cached = _cache[key];
    if (cached != null) {
      _touch(key, cached);
      final changed = !identical(_image, cached.image);
      _image = cached.image;
      _displayedFrame = cached.frame;
      if (changed) {
        _generation++;
        notifyListeners();
      }
      return;
    }

    // At most one decode is in flight for a given key.
    if (_pendingKey == key) return;

    final decoded = app.decodeFrame(target.item.id, target.sourceFrame);
    if (decoded == null) {
      // Decode failed for this frame: hold the last picture/trace rather than
      // blanking (the file is fine — this frame just isn't ready).
      return;
    }
    if (decoded.width == 0 || decoded.height == 0) return;

    _pendingKey = key;
    ui.decodeImageFromPixels(
      decoded.rgba,
      decoded.width,
      decoded.height,
      ui.PixelFormat.rgba8888,
      (img) {
        if (_disposed) {
          img.dispose();
          return;
        }
        _pendingKey = null;
        _put(key, _CacheEntry(img, decoded));
        _image = img;
        _displayedFrame = decoded;
        _generation++;
        notifyListeners();
      },
    );
  }

  void _touch(String key, _CacheEntry entry) {
    _cache.remove(key);
    _cache[key] = entry;
  }

  void _put(String key, _CacheEntry entry) {
    _cache.remove(key);
    _cache[key] = entry;
    while (_cache.length > _cacheLimit) {
      final oldest = _cache.keys.first;
      final evicted = _cache.remove(oldest);
      // Free the GPU/CPU image behind the evicted entry; its bytes go with it.
      evicted?.image.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_onAppChanged);
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    super.dispose();
  }
}
