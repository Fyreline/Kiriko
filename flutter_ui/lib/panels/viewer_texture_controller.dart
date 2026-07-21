// The Viewer's zero-copy texture lifecycle (K-177).
//
// In plain terms: on Windows the engine can draw the Viewer's picture straight
// into a piece of GPU memory that Flutter shows without any copy. The engine
// hands us an OS "handle" naming that memory; this object registers that handle
// with the Windows runner (over a small platform channel the runner implements),
// gets back a `textureId` the `Texture` widget shows, and tells the runner each
// time a new frame has been drawn. It re-registers when the handle or size
// changes (a comp resize), and — crucially — degrades quietly: if the runner
// does not implement the channel (an old build, or the C++ was not wired), it
// marks itself unavailable so the Viewer falls back to the read-back path. No
// pixels ever pass through this object.
//
// The platform-channel shape (method names, the shared-handle surface type, the
// register/frame-available dance) follows the MIT-licensed `flutter_wgpu_texture`
// package as a reference for the embedder plumbing — we borrow the pattern, not
// the code.

import 'package:flutter/services.dart';

/// Owns the `lumit/viewer_texture` platform-channel registration for one Viewer.
/// A fake [MethodChannel] can be injected so tests drive it without the runner.
class ViewerTextureController {
  /// The channel the Windows runner listens on (see
  /// `windows/runner/viewer_texture_bridge.cpp`).
  static const String channelName = 'lumit/viewer_texture';

  final MethodChannel _channel;

  int? _textureId;
  int? _handle;
  int? _width;
  int? _height;

  /// False once a channel call reports the runner has no handler (an unwired or
  /// old build). Sticky for the session: the Viewer then stays on the read-back
  /// path rather than retrying a channel that will never answer.
  bool _available = true;

  ViewerTextureController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// The current external-texture id, or null before the first registration.
  int? get textureId => _textureId;

  /// True until the platform channel is found to be missing.
  bool get available => _available;

  /// Register (or re-register) the shared texture named by [handle] with the
  /// given [width]/[height], returning its `textureId`. A no-op returning the
  /// existing id when the handle and size are unchanged. Returns null — and
  /// latches [available] to false — when the runner has no handler for the
  /// channel (so the Viewer falls back to the read-back path for the session).
  Future<int?> ensureRegistered(int handle, int width, int height) async {
    if (!_available) return null;
    if (_textureId != null &&
        _handle == handle &&
        _width == width &&
        _height == height) {
      return _textureId;
    }
    try {
      // A changed handle/size means a new shared texture: drop the old id first.
      if (_textureId != null) {
        await _channel
            .invokeMethod<void>('unregister', {'textureId': _textureId});
        _textureId = null;
      }
      final id = await _channel.invokeMethod<int>('register', {
        'handle': handle,
        'width': width,
        'height': height,
      });
      _textureId = id;
      _handle = handle;
      _width = width;
      _height = height;
      return id;
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      // Any other registration failure also drops us to the read-back path.
      _available = false;
      return null;
    }
  }

  /// Tell the runner a fresh frame has been drawn into the registered texture,
  /// so Flutter re-samples it. A no-op when nothing is registered. A transient
  /// failure is swallowed (one skipped frame), but a missing handler latches
  /// [available] off.
  Future<void> frameReady() async {
    final id = _textureId;
    if (!_available || id == null) return;
    try {
      await _channel.invokeMethod<void>('frameReady', {'textureId': id});
    } on MissingPluginException {
      _available = false;
    } catch (_) {
      // Keep the texture; a failed mark just skips this frame's repaint.
    }
  }

  /// Unregister the texture and forget it. Safe to call more than once.
  Future<void> dispose() async {
    final id = _textureId;
    _textureId = null;
    _handle = null;
    _width = null;
    _height = null;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('unregister', {'textureId': id});
    } catch (_) {
      // Nothing to do on shutdown.
    }
  }
}
