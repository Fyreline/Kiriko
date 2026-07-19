//! `shell::inspector::channel_picker` — the reusable three-colour channel
//! picker (P2/K-143).
//!
//! In plain terms: some effects split a picture into three tinted channels
//! (Chromatic aberration's three radial taps, K-144). This one small widget
//! shows those three colours as swatches — click a swatch to open the colour
//! picker — so every such effect presents its channel colours the same way.
//! Any effect whose schema declares three Colour parameters named
//! `channel_colour_1`, `channel_colour_2`, `channel_colour_3` gets this widget
//! automatically (see `effects_rows`), instead of three separate colour rows.

use super::*;

/// The stable parameter ids the picker groups, in order. An effect declares
/// these three Colour params (defaults red / green / blue by convention) to
/// adopt the widget.
pub(crate) const CHANNEL_COLOUR_IDS: [&str; 3] =
    ["channel_colour_1", "channel_colour_2", "channel_colour_3"];

/// Render the three-colour channel picker (P2/K-143): three scene-linear
/// colour swatches, each opening egui's colour picker (wheel + sliders — the
/// "expand" control of the owner's reference). `rgb` holds the three channels'
/// current scene-linear RGB, already clamped into the picker's gamut; the
/// function mutates it in place and returns `true` when any swatch changed, so
/// the caller commits all three together in one undoable step. The parameters
/// are scene-linear, exactly what egui's Rgb button edits, so values pass
/// straight through — the same conversion the single-colour effect rows use.
pub(crate) fn three_colour_swatches(
    c: &mut egui::Ui,
    theme: &Theme,
    rgb: &mut [[f32; 3]; 3],
) -> bool {
    c.label(
        egui::RichText::new("Channels")
            .small()
            .color(theme.text_muted),
    );
    let mut changed = false;
    for (i, chan) in rgb.iter_mut().enumerate() {
        // A small number before each swatch (Colour 1 / 2 / 3 in the owner's
        // reference), so the three read as an ordered set.
        c.label(
            egui::RichText::new(format!("{}", i + 1))
                .small()
                .color(theme.text_secondary),
        );
        if egui::color_picker::color_edit_button_rgb(c, chan).changed() {
            changed = true;
        }
    }
    changed
}
