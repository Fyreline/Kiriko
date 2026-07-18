//! The composition hierarchy panel (K-102, the AE-style composition
//! flowchart in its simplest tree form): a read-only tree of the active
//! composition — its layers, with precomp layers expandable to reveal the
//! layers of the composition they nest.
//!
//! In plain terms: complex projects nest compositions inside one another (a
//! layer can *be* another composition). This panel shows that nesting as an
//! indented, foldable outline, so you can see at a glance what a composition
//! is built from and jump to any layer inside it — the "view composition
//! hierarchy" tool. It is a viewer, not an editor: clicking a row selects
//! that layer (and switches to its composition); it changes nothing.
//!
//! This is the simple tree form of the future node-graph flowchart. All
//! colours come from the theme; it constructs no `Color32` of its own.

use super::*;
use lumit_core::model::{Document, LayerKind};
use uuid::Uuid;

/// Render the hierarchy of the active composition (the one whose Timeline is
/// shown, else the previewed one).
pub(crate) fn hierarchy_panel(ui: &mut egui::Ui, theme: &Theme, app: &mut AppState) {
    let doc = app.store.snapshot();
    let Some(root) = app.selected_comp.or(app.preview_comp) else {
        empty_hint(
            ui,
            theme,
            "Composition hierarchy",
            "Open a composition to see its layers and the compositions nested inside it.",
        );
        return;
    };
    let Some(root_comp) = doc.comp(root) else {
        empty_hint(
            ui,
            theme,
            "Composition hierarchy",
            "Open a composition to see its layers and the compositions nested inside it.",
        );
        return;
    };

    let sel_comp = app.selected_comp;
    let sel_layer = app.selected_layer;
    // A click yields (composition, layer) to select once the tree is drawn,
    // so the walk can borrow the document snapshot without also borrowing app.
    let mut click: Option<(Uuid, Uuid)> = None;

    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                ui.add_space(6.0);
                ui.label(crate::icons::text(Icon::Comp, 13.0).color(theme.accent));
                ui.label(egui::RichText::new(&root_comp.name).color(theme.text_primary));
            });
            ui.add_space(2.0);
            let mut visited = vec![root];
            layer_rows(
                ui,
                theme,
                &doc,
                root,
                1,
                sel_comp,
                sel_layer,
                &mut visited,
                &mut click,
            );
        });

    if let Some((comp, layer)) = click {
        app.selected_comp = Some(comp);
        app.selected_layer = Some(layer);
    }
}

/// One composition's layers, indented by `depth`. Precomp layers fold open to
/// their nested composition's own layers; `visited` breaks any cycle (a comp
/// that, invalidly, nests itself) so the walk always terminates.
#[allow(clippy::too_many_arguments)]
fn layer_rows(
    ui: &mut egui::Ui,
    theme: &Theme,
    doc: &Document,
    comp_id: Uuid,
    depth: usize,
    sel_comp: Option<Uuid>,
    sel_layer: Option<Uuid>,
    visited: &mut Vec<Uuid>,
    click: &mut Option<(Uuid, Uuid)>,
) {
    let Some(comp) = doc.comp(comp_id) else {
        return;
    };
    if comp.layers.is_empty() {
        indented(ui, depth, |ui| {
            ui.label(
                egui::RichText::new("no layers")
                    .small()
                    .color(theme.text_muted),
            );
        });
        return;
    }
    for layer in &comp.layers {
        let (icon, col) = layer_type_style(&layer.kind, theme);
        let selected = sel_comp == Some(comp_id) && sel_layer == Some(layer.id);
        if let LayerKind::Precomp { comp: nested } = layer.kind {
            let id = ui.make_persistent_id(("hierarchy", comp_id, layer.id));
            let mut state = egui::collapsing_header::CollapsingState::load_with_default_open(
                ui.ctx(),
                id,
                depth < 2,
            );
            ui.horizontal(|ui| {
                ui.add_space(indent_of(depth));
                state.show_toggle_button(ui, egui::collapsing_header::paint_default_icon);
                if layer_label(ui, theme, icon, col, &layer.name, selected).clicked() {
                    *click = Some((comp_id, layer.id));
                }
            });
            state.show_body_unindented(ui, |ui| {
                if visited.contains(&nested) {
                    indented(ui, depth + 1, |ui| {
                        ui.label(
                            egui::RichText::new("… recursive nesting")
                                .small()
                                .color(theme.warning),
                        );
                    });
                } else {
                    visited.push(nested);
                    layer_rows(
                        ui,
                        theme,
                        doc,
                        nested,
                        depth + 1,
                        sel_comp,
                        sel_layer,
                        visited,
                        click,
                    );
                    visited.pop();
                }
            });
        } else {
            ui.horizontal(|ui| {
                ui.add_space(indent_of(depth) + 18.0);
                if layer_label(ui, theme, icon, col, &layer.name, selected).clicked() {
                    *click = Some((comp_id, layer.id));
                }
            });
        }
    }
}

/// An icon-plus-name selectable row for one layer.
fn layer_label(
    ui: &mut egui::Ui,
    theme: &Theme,
    icon: Icon,
    col: egui::Color32,
    name: &str,
    selected: bool,
) -> egui::Response {
    ui.horizontal(|ui| {
        ui.label(crate::icons::text(icon, 13.0).color(col));
        let text = egui::RichText::new(name).color(if selected {
            theme.text_primary
        } else {
            theme.text_secondary
        });
        ui.selectable_label(selected, text)
    })
    .inner
}

/// Left pad for a nesting depth.
fn indent_of(depth: usize) -> f32 {
    6.0 + depth as f32 * 14.0
}

/// Run `add` inside a row indented to `depth`.
fn indented(ui: &mut egui::Ui, depth: usize, add: impl FnOnce(&mut egui::Ui)) {
    ui.horizontal(|ui| {
        ui.add_space(indent_of(depth) + 18.0);
        add(ui);
    });
}
