// The per-layer-type glyph and identity colour, ported from the egui
// `layer_type_style` (crates/lumit-ui/src/shell/panels.rs). Kept apart so both
// the outline row and the lane bar read the same mapping.

import 'package:flutter/widgets.dart';

import '../../bridge/bridge.dart';
import '../../icons/icons.dart';
import '../../theme/theme.dart';

/// The glyph + identity colour a layer of [kind] draws with, from the theme's
/// per-type [LayerColours].
({LumitIcon icon, Color colour}) layerTypeStyle(
  BridgeLayerKind kind,
  LumitTheme theme,
) {
  final l = theme.layer;
  return switch (kind) {
    BridgeLayerKind.footage => (icon: LumitIcon.footage, colour: l.footage),
    BridgeLayerKind.sequence => (icon: LumitIcon.sequence, colour: l.sequence),
    BridgeLayerKind.precomp => (icon: LumitIcon.comp, colour: l.precomp),
    BridgeLayerKind.solid => (icon: LumitIcon.solid, colour: l.solid),
    BridgeLayerKind.text => (icon: LumitIcon.text, colour: l.text),
    BridgeLayerKind.camera => (icon: LumitIcon.camera, colour: l.camera),
    // Adjustment reuses the solid glyph/colour (a comp-sized effect container),
    // exactly as the egui frontend does; unknown degrades to the same.
    BridgeLayerKind.adjustment => (icon: LumitIcon.solid, colour: l.solid),
    BridgeLayerKind.unknown => (icon: LumitIcon.solid, colour: l.solid),
  };
}

/// Whether a layer of this kind can carry audio — so its row shows a speaker
/// (footage/sequence/precomp only), per the F3 brief.
bool layerCanCarryAudio(BridgeLayerKind kind) =>
    kind == BridgeLayerKind.footage ||
    kind == BridgeLayerKind.sequence ||
    kind == BridgeLayerKind.precomp;
