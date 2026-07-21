// The Scopes panel (phase F2, docs/07-UI-SPEC.md §8): waveform, vectorscope and
// histogram over the frame the Viewer is showing. Ported from
// crates/lumit-ui/src/shell/scopes.rs.
//
// In plain terms: a scope reads the picture's brightness and colour instead of
// showing the picture — a colourist's instrument. It reads the SAME decoded
// pixels the Viewer blits (through the shared preview source), so the trace
// always matches what's on screen. The trace is drawn on the fixed scope colours
// — never the theme (15-DESIGN §8) — because a scope is read on a near-black
// graticule whatever the chrome. When a frame is momentarily unavailable the
// last trace is held rather than blanked (K-130).
//
// The trace is built as a small 256×256 image off the build path (only when the
// shown frame or the chosen scope changes) and painted stretched, so build() and
// paint() never recompute over the frame's pixels.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/controls.dart';
import 'preview_source.dart';
import 'scope_maths.dart';

/// Which scope one panel instance shows (chosen in its header).
enum ScopeKind { waveformLuma, waveformRgb, vectorscope, histogram }

String _scopeLabel(ScopeKind k) => switch (k) {
      ScopeKind.waveformLuma => 'Waveform (luma)',
      ScopeKind.waveformRgb => 'Waveform (RGB)',
      ScopeKind.vectorscope => 'Vectorscope',
      ScopeKind.histogram => 'Histogram',
    };

class ScopesPanel extends StatefulWidget {
  final AppStateStub app;
  const ScopesPanel({super.key, required this.app});

  @override
  State<ScopesPanel> createState() => _ScopesPanelState();
}

class _ScopesPanelState extends State<ScopesPanel> {
  ScopeKind _kind = ScopeKind.waveformLuma;

  /// The last-built trace, held across a momentarily-unavailable frame (K-130).
  ui.Image? _trace;
  int _builtGeneration = -1;
  ScopeKind? _builtKind;
  bool _building = false;

  PreviewSource get _source => widget.app.previewSource;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onSourceChanged);
    _maybeRebuild();
  }

  @override
  void dispose() {
    _source.removeListener(_onSourceChanged);
    _trace?.dispose();
    super.dispose();
  }

  void _onSourceChanged() => _maybeRebuild();

  /// Rebuild the trace when the shown frame or the chosen scope changed. Runs
  /// off the build path; the async image decode notifies via setState.
  void _maybeRebuild() {
    final frame = _source.displayedFrame;
    if (frame == null) return;
    final gen = _source.generation;
    if (gen == _builtGeneration && _kind == _builtKind) return;
    if (_building) return;

    final rgba = buildTraceRgba(frame, _kind);
    _building = true;
    ui.decodeImageFromPixels(
      rgba,
      scopeGrid,
      scopeGrid,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted) {
          img.dispose();
          return;
        }
        _building = false;
        _trace?.dispose();
        setState(() {
          _trace = img;
          _builtGeneration = gen;
          _builtKind = _kind;
        });
      },
    );
  }

  void _pickKind(ScopeKind k) {
    setState(() => _kind = k);
    _maybeRebuild();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      color: ScopeColours.standard.bg,
      child: Column(
        children: [
          Container(
            height: 22,
            color: t.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.centerLeft,
            child: BareDropdown<ScopeKind>(
              value: _kind,
              options: ScopeKind.values,
              label: _scopeLabel,
              onChanged: _pickKind,
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _ScopePainter(kind: _kind, trace: _trace),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Counts → RGBA trace texture (fixed scope colours, never the theme).
// ---------------------------------------------------------------------------

int _r8(Color c) => (c.r * 255).round();
int _g8(Color c) => (c.g * 255).round();
int _b8(Color c) => (c.b * 255).round();

/// A soft, saturating map from a count to a 0..1 trace intensity — the square
/// root lifts faint traces without blowing out dense ones (a phosphor falloff).
double _intensity(int count, int peak) {
  if (peak == 0) return 0;
  final v = count / peak;
  if (v <= 0) return 0;
  return math.min(1.0, math.sqrt(v));
}

/// Fill an opaque RGBA buffer with the scope backdrop.
Uint8List _backdrop() {
  final bg = ScopeColours.standard.bg;
  final buf = Uint8List(scopeGrid * scopeGrid * 4);
  final r = _r8(bg), g = _g8(bg), b = _b8(bg);
  for (var i = 0; i < buf.length; i += 4) {
    buf[i] = r;
    buf[i + 1] = g;
    buf[i + 2] = b;
    buf[i + 3] = 0xff;
  }
  return buf;
}

/// Add `frac` of a trace colour onto one pixel, clamped — additive over the
/// backdrop so overlapping channels brighten toward white, like a real scope.
void _addTrace(Uint8List buf, int cell, Color colour, double frac) {
  final f = frac.clamp(0.0, 1.0);
  final base = cell * 4;
  final chans = [_r8(colour), _g8(colour), _b8(colour)];
  for (var c = 0; c < 3; c++) {
    final add = (chans[c] * f).toInt();
    final v = buf[base + c] + add;
    buf[base + c] = v > 255 ? 255 : v;
  }
}

int _peakOf(List<Int32List> grids) {
  var peak = 0;
  for (final g in grids) {
    for (final v in g) {
      if (v > peak) peak = v;
    }
  }
  return peak;
}

/// Build the 256×256 RGBA trace for [frame] under [kind], on the fixed scope
/// colours. Pure over the pixels — no theme, no canvas.
Uint8List buildTraceRgba(DecodedFrame frame, ScopeKind kind) {
  final sc = ScopeColours.standard;
  final buf = _backdrop();
  switch (kind) {
    case ScopeKind.waveformLuma:
      final grids =
          waveformCounts(frame.rgba, frame.width, frame.height, WaveMode.luma);
      final peak = _peakOf(grids);
      for (var cell = 0; cell < scopeGrid * scopeGrid; cell++) {
        final f = _intensity(grids[0][cell], peak);
        if (f > 0) _addTrace(buf, cell, sc.trace, f);
      }
    case ScopeKind.waveformRgb:
      final grids =
          waveformCounts(frame.rgba, frame.width, frame.height, WaveMode.rgb);
      final peak = _peakOf(grids);
      final colours = [sc.red, sc.green, sc.blue];
      for (var cell = 0; cell < scopeGrid * scopeGrid; cell++) {
        for (var c = 0; c < 3; c++) {
          final f = _intensity(grids[c][cell], peak);
          if (f > 0) _addTrace(buf, cell, colours[c], f);
        }
      }
    case ScopeKind.vectorscope:
      final grid = vectorscopeCounts(frame.rgba, frame.width, frame.height);
      var peak = 0;
      for (final v in grid) {
        if (v > peak) peak = v;
      }
      for (var cell = 0; cell < scopeGrid * scopeGrid; cell++) {
        final f = _intensity(grid[cell], peak);
        if (f > 0) _addTrace(buf, cell, sc.trace, f);
      }
    case ScopeKind.histogram:
      final bins = histogramCounts(frame.rgba, frame.width, frame.height);
      final peak = _peakOf(bins);
      final colours = [sc.red, sc.green, sc.blue];
      for (var chan = 0; chan < 3; chan++) {
        for (var bin = 0; bin < scopeGrid; bin++) {
          final h = (_intensity(bins[chan][bin], peak) * (scopeGrid - 1)).round();
          for (var row = scopeGrid - 1 - h; row < scopeGrid; row++) {
            if (row < 0) continue;
            _addTrace(buf, row * scopeGrid + bin, colours[chan], 0.7);
          }
        }
      }
  }
  return buf;
}

// ---------------------------------------------------------------------------
// Painting: trace stretched to the panel + the graticule on top.
// ---------------------------------------------------------------------------

class _ScopePainter extends CustomPainter {
  final ScopeKind kind;
  final ui.Image? trace;
  const _ScopePainter({required this.kind, required this.trace});

  @override
  void paint(Canvas canvas, Size size) {
    final grat = Paint()
      ..color = ScopeColours.standard.graticule
      ..strokeWidth = 1;

    if (kind == ScopeKind.vectorscope) {
      // A vectorscope reads square: fit the biggest centred square.
      final side = size.width < size.height ? size.width : size.height;
      final left = (size.width - side) / 2;
      final top = (size.height - side) / 2;
      final square = Rect.fromLTWH(left, top, side, side);
      if (trace != null) {
        canvas.drawImageRect(
          trace!,
          Rect.fromLTWH(0, 0, scopeGrid.toDouble(), scopeGrid.toDouble()),
          square,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      _paintVectorGraticule(canvas, square, grat);
      return;
    }

    if (trace != null) {
      canvas.drawImageRect(
        trace!,
        Rect.fromLTWH(0, 0, scopeGrid.toDouble(), scopeGrid.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    // Quarter-mark reference lines (0/25/50/75/100 %).
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grat);
    }
  }

  void _paintVectorGraticule(Canvas canvas, Rect square, Paint grat) {
    final centre = square.center;
    final radius = square.width * 0.45;
    canvas.drawCircle(centre, radius, grat..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(centre.dx - radius, centre.dy),
        Offset(centre.dx + radius, centre.dy), grat);
    canvas.drawLine(Offset(centre.dx, centre.dy - radius),
        Offset(centre.dx, centre.dy + radius), grat);
    // The six primary/secondary hue targets on the graticule.
    final dot = Paint()..color = ScopeColours.standard.graticule;
    for (final target in vectorTargets()) {
      // The trace grid uses a 0.9 scale margin; place the marks on that grid so
      // they line up with where full-saturation colour lands.
      final px = square.left + target.x * square.width;
      final py = square.top + target.y * square.height;
      canvas.drawCircle(Offset(px, py), 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ScopePainter old) =>
      old.kind != kind || !identical(old.trace, trace);
}
