// The timeline cache bar: warm-frame bands over the ruler, the Flutter mirror of
// egui's `AppState::cache_bar` (crates/lumit-ui/src/app_state/previewing.rs:201).
//
// In plain terms: as you scrub or play, the engine keeps the frames it has
// already rendered in memory so it never re-renders them. This thin strip along
// the bottom of the ruler shows WHICH frames are held — a success-tinted band
// over every cached (warm) frame — so you can see at a glance how much of the
// comp is ready to play back instantly.
//
// The bridge `cache_stats` export reports only aggregate counters, not which
// frames are warm, so the warm set is tracked Dart-side as the PreviewSource
// drives frames into the engine cache (AppStateStub.warmFramesFor). egui draws
// three tiers (RAM / disk / none); the bridge has only the RAM tier today, so
// this draws the RAM band alone (theme.success, docs/15-DESIGN §6.3). The stats
// poll rides the app cadence via the `cacheBarRevision` notifier — never per
// paint.

import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../widgets/controls.dart';
import 'lane_scale.dart';

/// Collapse a set of warm comp frames into sorted, contiguous half-open ranges
/// `[start, end)` — one band is drawn per range rather than per frame. Pure, so
/// the banding is unit-tested without a widget.
List<(int, int)> warmFrameRanges(Set<int> frames) {
  if (frames.isEmpty) return const [];
  final sorted = frames.toList()..sort();
  final out = <(int, int)>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (final f in sorted.skip(1)) {
    if (f == prev + 1) {
      prev = f;
      continue;
    }
    out.add((start, prev + 1));
    start = f;
    prev = f;
  }
  out.add((start, prev + 1));
  return out;
}

/// The cache bar over the lane: a thin RAM-tier band at the ruler's bottom edge,
/// covering the warm comp frames. Its own local x=0 maps to the lane left
/// ([LaneScale.trackLeft]), like the ruler and work-area band it sits with. It
/// watches the app's [AppStateStub.cacheBarRevision] notifier so it repaints on
/// the app cadence when the warm set changes, not on every frame.
class TimelineCacheBar extends StatelessWidget {
  final AppStateStub app;
  final String compId;
  final LaneScale scale;
  final double height;

  /// The band thickness (px) at the ruler's bottom edge.
  static const double bandHeight = 3;

  const TimelineCacheBar({
    super.key,
    required this.app,
    required this.compId,
    required this.scale,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: app.cacheBarRevision,
        builder: (context, revision, child) {
          final ranges = warmFrameRanges(app.warmFramesFor(compId));
          if (ranges.isEmpty) return const SizedBox.shrink();
          return CustomPaint(
            size: Size(scale.trackWidth, height),
            painter: _CacheBarPainter(
              ranges: ranges,
              scale: scale,
              ram: t.success,
            ),
          );
        },
      ),
    );
  }
}

class _CacheBarPainter extends CustomPainter {
  final List<(int, int)> ranges;
  final LaneScale scale;
  final Color ram;

  _CacheBarPainter({
    required this.ranges,
    required this.scale,
    required this.ram,
  });

  double _lx(num frame) => scale.xOfFrame(frame) - scale.trackLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height - TimelineCacheBar.bandHeight;
    final paint = Paint()..color = ram;
    for (final (start, end) in ranges) {
      final l = _lx(start).clamp(0.0, size.width);
      final r = _lx(end).clamp(0.0, size.width);
      if (r <= l) continue;
      canvas.drawRect(Rect.fromLTRB(l, top, r, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_CacheBarPainter old) =>
      old.ranges != ranges ||
      old.ram != ram ||
      old.scale.pxPerFrame != scale.pxPerFrame ||
      old.scale.viewStartFrame != scale.viewStartFrame ||
      old.scale.trackWidth != scale.trackWidth;
}
