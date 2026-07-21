// The Scopes' pixel maths (phase F2), ported one-for-one from
// crates/lumit-ui/src/shell/scopes.rs. Pure counting over the decoded frame's
// RGBA bytes, so every rule is a plain unit test like the Rust side — no canvas,
// no theme, no image.
//
// In plain terms: a scope reads brightness and colour instead of the picture.
// These functions turn a frame's pixels into the little grids the painters draw:
// a waveform (brightness per column), a histogram (how many pixels at each
// brightness) and a vectorscope (colour as position on a circle). The subsample
// stride keeps a big frame cheap — a 256-wide plot never needs every 4K pixel.

import 'dart:math' as math;
import 'dart:typed_data';

/// Trace grid resolution (columns × levels), matching the Rust `GRID`.
const int scopeGrid = 256;

/// Cap on pixels sampled per trace, matching the Rust `MAX_SAMPLES`: scopes
/// degrade gracefully and a 256-wide plot resolves far less than a 1080p frame.
const int scopeMaxSamples = 240000;

/// Which channels a waveform plots.
enum WaveMode { luma, rgb }

/// Rec.709 luma of an sRGB (gamma) pixel, 0..255 → 0.0..1.0. Scopes read the
/// displayed (gamma-encoded) signal, as video scopes do — no linearisation.
double luma8(int r, int g, int b) =>
    (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

/// Pixel strides (x, y) that keep the sampled count near [scopeMaxSamples].
/// Both axes scale by the same factor so coverage stays even.
List<int> scopeStrides(int width, int height) {
  final total = math.max(1, width * height);
  if (total <= scopeMaxSamples) return const [1, 1];
  final factor = math.max(1.0, math.sqrt(total / scopeMaxSamples));
  final s = math.max(1, factor.ceil());
  return [s, s];
}

/// Map a 0..1 value to a grid row: 1.0 (bright) at the top (row 0), 0.0 at the
/// bottom.
int valueRow(double v) {
  final clamped = v.clamp(0.0, 1.0);
  final row = ((1.0 - clamped) * (scopeGrid - 1)).round();
  return math.min(row, scopeGrid - 1);
}

/// Column-vs-value counts for a waveform. `GRID` rows of `GRID` columns each,
/// row 0 = brightest (top). One grid for luma, three (`r`, `g`, `b`) for RGB.
List<Int32List> waveformCounts(
  Uint8List rgba,
  int width,
  int height,
  WaveMode mode,
) {
  final channels = mode == WaveMode.rgb ? 3 : 1;
  final grids =
      List.generate(channels, (_) => Int32List(scopeGrid * scopeGrid));
  if (width == 0 || height == 0 || rgba.length < width * height * 4) {
    return grids;
  }
  final strides = scopeStrides(width, height);
  final sx = strides[0], sy = strides[1];
  for (var y = 0; y < height; y += sy) {
    for (var x = 0; x < width; x += sx) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final bx = math.min(x * scopeGrid ~/ width, scopeGrid - 1);
      if (mode == WaveMode.luma) {
        final by = valueRow(luma8(r, g, b));
        grids[0][by * scopeGrid + bx]++;
      } else {
        final chans = [r, g, b];
        for (var c = 0; c < 3; c++) {
          final by = valueRow(chans[c] / 255.0);
          grids[c][by * scopeGrid + bx]++;
        }
      }
    }
  }
  return grids;
}

/// Per-channel brightness counts: `[r, g, b]`, each `GRID` bins.
List<Int32List> histogramCounts(Uint8List rgba, int width, int height) {
  final bins = List.generate(3, (_) => Int32List(scopeGrid));
  if (width == 0 || height == 0 || rgba.length < width * height * 4) {
    return bins;
  }
  final strides = scopeStrides(width, height);
  final sx = strides[0], sy = strides[1];
  for (var y = 0; y < height; y += sy) {
    for (var x = 0; x < width; x += sx) {
      final i = (y * width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final bin = rgba[i + c] * (scopeGrid - 1) ~/ 255;
        bins[c][bin]++;
      }
    }
  }
  return bins;
}

/// Rec.601 Cb/Cr of an sRGB pixel (0..1 each), the broadcast vectorscope's
/// axes. Cb/Cr each span roughly -0.5..0.5; a neutral colour has both at 0.
/// Matches the Rust `vectorscope_counts` transform exactly.
List<double> cbcr(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final cb = -0.168736 * rf - 0.331264 * gf + 0.5 * bf;
  final cr = 0.5 * rf - 0.418688 * gf - 0.081312 * bf;
  return [cb, cr];
}

/// Chroma counts on the vectorscope's square grid (row 0 = top), centred, with
/// a margin so full-saturation points land inside rather than on the edge.
Int32List vectorscopeCounts(Uint8List rgba, int width, int height) {
  final grid = Int32List(scopeGrid * scopeGrid);
  if (width == 0 || height == 0 || rgba.length < width * height * 4) {
    return grid;
  }
  final strides = scopeStrides(width, height);
  final sx = strides[0], sy = strides[1];
  final centre = (scopeGrid - 1) / 2.0;
  final scale = scopeGrid * 0.9;
  for (var y = 0; y < height; y += sy) {
    for (var x = 0; x < width; x += sx) {
      final i = (y * width + x) * 4;
      final c = cbcr(rgba[i], rgba[i + 1], rgba[i + 2]);
      final px = centre + c[0] * scale;
      // Screen y grows downward; Cr up, so negate it.
      final py = centre - c[1] * scale;
      if (px >= 0 && px < scopeGrid && py >= 0 && py < scopeGrid) {
        grid[py.toInt() * scopeGrid + px.toInt()]++;
      }
    }
  }
  return grid;
}

/// The six primary/secondary vectorscope targets, in signal terms (full-range
/// 75% would sit on the graticule boxes; 100% primaries used here for the hue
/// marks). Returned as fractional grid positions (0..1 in x and y) so the
/// painter places dots and a test can assert their angle.
class VectorTarget {
  final String label;
  final double x; // fraction across the grid, 0..1
  final double y; // fraction down the grid, 0..1
  const VectorTarget(this.label, this.x, this.y);
}

/// Grid-fraction position of a pure colour on the vectorscope, using the same
/// transform as [vectorscopeCounts].
VectorTarget vectorTarget(String label, int r, int g, int b) {
  final centre = (scopeGrid - 1) / 2.0;
  final scale = scopeGrid * 0.9;
  final c = cbcr(r, g, b);
  final px = centre + c[0] * scale;
  final py = centre - c[1] * scale;
  return VectorTarget(label, px / scopeGrid, py / scopeGrid);
}

/// The six hue targets marked on the vectorscope graticule — the primary and
/// secondary colours at full saturation, in the broadcast R-Yl-G-Cy-B-Mg order.
List<VectorTarget> vectorTargets() => [
      vectorTarget('R', 255, 0, 0),
      vectorTarget('Yl', 255, 255, 0),
      vectorTarget('G', 0, 255, 0),
      vectorTarget('Cy', 0, 255, 255),
      vectorTarget('B', 0, 0, 255),
      vectorTarget('Mg', 255, 0, 255),
    ];
