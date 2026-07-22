// The keyframe interpolation right-click menu, ported from the egui graph key
// context menu (crates/lumit-ui/src/shell/graph.rs:1676): Easy ease / Linear /
// Hold / Unify handles / Delete. It is shared by the lane keyframe rows and
// (once it exists) the graph editor's value keys, so a right-clicked key eases
// the same way in both frontends.
//
// In plain terms: right-click a keyframe and pick how it should move through
// itself. "Easy ease" is the After Effects preset — flat handles, speed 0 and a
// third of the gap's reach (the `EASY_EASE` constant, anim.rs:40). "Unify" only
// appears when a key's two handles were pulled apart, and re-joins them at their
// average slope, each keeping its own reach (graph.rs:1712).
//
// Commit paths honour the bridge's op set: a single interp choice goes through
// `setKeyframeInterp` per (property, frame); a multi-key delete goes through
// `applyKeyframeBatch` (one undo step) since that op understands `remove`, while
// interp changes have no batch op so they apply per key.

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../state/app_state.dart';
import '../../widgets/controls.dart';
import 'lane_selection.dart';

/// The After Effects easy-ease reach — `lumit_core::anim::EASY_EASE`'s influence
/// (a third of the span); its speed is 0 (flat handles).
const double kEasyEaseInfluence = 1.0 / 3.0;

/// The interpolation a menu choice commits for one keyframe: the two side
/// variant names (`Hold`/`Linear`/`Bezier`) and, for a Bezier side, its
/// `(speed, influence)` handle. Pure, so the resolution is unit-tested.
@immutable
class KeyframeInterpSides {
  final String interpIn;
  final String interpOut;
  final double speedIn;
  final double influenceIn;
  final double speedOut;
  final double influenceOut;

  const KeyframeInterpSides({
    required this.interpIn,
    required this.interpOut,
    this.speedIn = 0,
    this.influenceIn = kEasyEaseInfluence,
    this.speedOut = 0,
    this.influenceOut = kEasyEaseInfluence,
  });

  /// Easy ease: both sides Bezier, speed 0, influence a third (the AE preset,
  /// graph.rs:1680 → `EASY_EASE`).
  static const easyEase = KeyframeInterpSides(
    interpIn: 'Bezier',
    interpOut: 'Bezier',
  );

  /// Linear both sides (graph.rs:1684).
  static const linear = KeyframeInterpSides(
    interpIn: 'Linear',
    interpOut: 'Linear',
  );

  /// Hold both sides (graph.rs:1688) — a hard step.
  static const hold = KeyframeInterpSides(
    interpIn: 'Hold',
    interpOut: 'Hold',
  );

  /// Unify a broken bezier key: both handles take the average slope, each
  /// keeping its own reach (graph.rs:1712) — the inverse of an Alt-drag break.
  factory KeyframeInterpSides.unify(BridgeKeyframe key) {
    final sIn = key.bezierIn?.speed ?? 0;
    final sOut = key.bezierOut?.speed ?? 0;
    final avg = 0.5 * (sIn + sOut);
    return KeyframeInterpSides(
      interpIn: 'Bezier',
      interpOut: 'Bezier',
      speedIn: avg,
      influenceIn: key.bezierIn?.influence ?? kEasyEaseInfluence,
      speedOut: avg,
      influenceOut: key.bezierOut?.influence ?? kEasyEaseInfluence,
    );
  }
}

/// Whether the "Unify handles" entry should show for [key]: both sides are
/// Bezier and their slopes differ (a broken key), matching graph.rs:1694.
bool unifyEligible(BridgeKeyframe key) {
  final a = key.bezierIn, b = key.bezierOut;
  if (a == null || b == null) return false;
  return a.speed != b.speed;
}

/// A JSON `remove` op array (the `applyKeyframeBatch` vocabulary: `add`/`remove`/
/// `toggle`) for every key in [targets] that shares [layerId] — one undo step
/// for a multi-key delete. Pure, so the payload is unit-tested.
String removeBatchJson(String layerId, Iterable<LaneKeyId> targets) {
  final buf = StringBuffer('[');
  var first = true;
  for (final k in targets) {
    if (k.layerId != layerId) continue;
    if (!first) buf.write(',');
    first = false;
    buf.write('{"property":"${k.property}","action":"remove","frame":${k.frame}}');
  }
  buf.write(']');
  return buf.toString();
}

/// The choices the menu can raise.
enum KeyframeInterpChoice { easyEase, linear, hold, unify, delete }

/// Show the keyframe interpolation menu at [position] (global) for [targets]
/// (the keys the choice applies to — the selection when the right-clicked key is
/// part of a multi-selection, else just it). [hit] is the right-clicked key's
/// data, used to shape the Unify entry and its average-slope commit.
///
/// Interp choices (Easy ease / Linear / Hold) apply to every target through
/// `setKeyframeInterp` (there is no batch-interp bridge op, so this is one undo
/// step per key). Unify applies only to [hit] (a per-key handle join, exactly as
/// graph.rs applies it to the single `idx`). Delete removes every target — via
/// `applyKeyframeBatch` when several share a layer (one undo step), else the
/// single-key `removeKeyframe`.
Future<void> showKeyframeInterpMenu({
  required BuildContext context,
  required AppStateStub app,
  required String compId,
  required BridgeKeyframe hit,
  required LaneKeyId hitId,
  required Set<LaneKeyId> targets,
  required Offset position,
}) async {
  final showUnify = unifyEligible(hit);
  final choice = await showLumitPopup<KeyframeInterpChoice>(
    context: context,
    position: position,
    builder: (close) => FloatSurface(
      width: 170,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuRow(
            onPressed: () => close(KeyframeInterpChoice.easyEase),
            child: const Text('Easy ease'),
          ),
          MenuRow(
            onPressed: () => close(KeyframeInterpChoice.linear),
            child: const Text('Linear'),
          ),
          MenuRow(
            onPressed: () => close(KeyframeInterpChoice.hold),
            child: const Text('Hold'),
          ),
          if (showUnify)
            MenuRow(
              onPressed: () => close(KeyframeInterpChoice.unify),
              child: const Text('Unify handles'),
            ),
          const _MenuDivider(),
          MenuRow(
            onPressed: () => close(KeyframeInterpChoice.delete),
            child: const Text('Delete key'),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return;
  applyKeyframeInterpChoice(
    app: app,
    compId: compId,
    choice: choice,
    hit: hit,
    hitId: hitId,
    targets: targets,
  );
}

/// Commit a resolved menu [choice] against [app] — factored out of the widget so
/// the commit routing is unit-testable without an overlay.
void applyKeyframeInterpChoice({
  required AppStateStub app,
  required String compId,
  required KeyframeInterpChoice choice,
  required BridgeKeyframe hit,
  required LaneKeyId hitId,
  required Set<LaneKeyId> targets,
}) {
  switch (choice) {
    case KeyframeInterpChoice.easyEase:
      _applySides(app, compId, targets, (_) => KeyframeInterpSides.easyEase);
    case KeyframeInterpChoice.linear:
      _applySides(app, compId, targets, (_) => KeyframeInterpSides.linear);
    case KeyframeInterpChoice.hold:
      _applySides(app, compId, targets, (_) => KeyframeInterpSides.hold);
    case KeyframeInterpChoice.unify:
      // Unify is inherently per-key (it averages one key's two handles), so it
      // applies to the right-clicked key alone (graph.rs:1712 uses `idx`).
      _applySides(app, compId, {hitId}, (_) => KeyframeInterpSides.unify(hit));
    case KeyframeInterpChoice.delete:
      _deleteTargets(app, compId, targets);
  }
}

void _applySides(
  AppStateStub app,
  String compId,
  Set<LaneKeyId> targets,
  KeyframeInterpSides Function(LaneKeyId) sidesFor,
) {
  for (final k in targets) {
    final s = sidesFor(k);
    app.setKeyframeInterp(
      compId,
      k.layerId,
      k.property,
      k.frame,
      s.interpIn,
      s.interpOut,
      speedIn: s.speedIn,
      influenceIn: s.influenceIn,
      speedOut: s.speedOut,
      influenceOut: s.influenceOut,
    );
  }
}

void _deleteTargets(AppStateStub app, String compId, Set<LaneKeyId> targets) {
  if (targets.length <= 1) {
    final k = targets.first;
    app.removeKeyframe(compId, k.layerId, k.property, k.frame);
    return;
  }
  // Several keys: one undo step per layer via the batch remove op.
  final layers = {for (final k in targets) k.layerId};
  for (final layerId in layers) {
    app.applyKeyframeBatch(compId, layerId, removeBatchJson(layerId, targets));
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Container(height: 1, color: t.hairline),
    );
  }
}
