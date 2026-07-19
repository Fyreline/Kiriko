use super::*;

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod section_bar_tests {
    use super::*;

    /// Regression for the invisible effect-title bars: the bar was painted in
    /// `surface_1`, which is the very colour the Round shape fills each pane
    /// card with and sits within a few RGB steps of the Sharp background
    /// (`surface_0`) — so in the Effect Controls panel the bar could not be
    /// seen at all. The fill must stand apart from BOTH pane backgrounds in
    /// every colour scheme, or effect boundaries vanish again.
    #[test]
    fn the_effect_title_bar_stands_apart_from_both_pane_backgrounds() {
        use crate::theme::{ColorScheme, ThemeShape};
        for scheme in ColorScheme::ALL {
            let theme = Theme::for_scheme(scheme, ThemeShape::Sharp);
            let fill = section_bar_fill(&theme);
            assert_ne!(
                fill, theme.surface_0,
                "{scheme:?}: the bar must not match the Sharp panel background"
            );
            assert_ne!(
                fill, theme.surface_1,
                "{scheme:?}: the bar must not match the Round pane card fill"
            );
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod lane_key_tests {
    use super::*;
    use crate::app_state::{LaneKeySel, PropRow};
    use lumit_core::anim::{Keyframe, SideInterp};
    use lumit_core::model::TransformProp;

    fn key(t: f64, interp: SideInterp) -> Keyframe {
        Keyframe {
            time: rational_at(t),
            value: 0.0,
            interp_in: interp,
            interp_out: interp,
        }
    }

    // A lane drag shifts only the keys at the named times, and by the whole
    // delta — the group slides rigidly (note 2.1).
    #[test]
    fn shift_moves_only_the_named_times() {
        let keys = [
            key(0.0, SideInterp::Linear),
            key(1.0, SideInterp::Linear),
            key(2.0, SideInterp::Linear),
        ];
        let out = shift_keys_time(&keys, &[rational_at(1.0)], 0.5, 30.0);
        let times: Vec<f64> = out.iter().map(|k| k.time.to_f64()).collect();
        assert_eq!(times, vec![0.0, 1.5, 2.0]);
    }

    // A key dragged onto another key's time collapses to one (the collision rule
    // the graph editor uses), never a duplicate-time pair.
    #[test]
    fn shift_dedups_on_collision() {
        let keys = [
            key(0.0, SideInterp::Linear),
            key(1.0, SideInterp::Linear),
            key(2.0, SideInterp::Linear),
        ];
        let out = shift_keys_time(&keys, &[rational_at(1.0)], 1.0, 30.0);
        assert_eq!(out.len(), 2);
        assert!(out
            .iter()
            .all(|k| k.time.to_f64() == 0.0 || k.time.to_f64() == 2.0));
    }

    // Time never goes negative, and bezier handles ride along with the key.
    #[test]
    fn shift_clamps_and_keeps_handles() {
        let bez = SideInterp::Bezier {
            speed: 3.5,
            influence: 0.4,
        };
        let keys = [key(0.5, bez)];
        let out = shift_keys_time(&keys, &[rational_at(0.5)], -2.0, 30.0);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].time.to_f64(), 0.0);
        assert_eq!(out[0].interp_in, bez);
        assert_eq!(out[0].interp_out, bez);
    }

    fn sel(t: f64) -> LaneKeySel {
        LaneKeySel {
            layer: uuid::Uuid::nil(),
            row: PropRow::Transform(TransformProp::Rotation),
            time: rational_at(t),
        }
    }

    #[test]
    fn plain_click_replaces_the_selection() {
        let mut s = vec![sel(1.0), sel(2.0)];
        lane_select_click(&mut s, sel(3.0), egui::Modifiers::default());
        assert_eq!(s, vec![sel(3.0)]);
    }

    #[test]
    fn ctrl_click_toggles_membership() {
        let mut s = vec![sel(1.0)];
        let ctrl = egui::Modifiers {
            ctrl: true,
            ..Default::default()
        };
        lane_select_click(&mut s, sel(2.0), ctrl); // add
        assert_eq!(s, vec![sel(1.0), sel(2.0)]);
        lane_select_click(&mut s, sel(1.0), ctrl); // remove
        assert_eq!(s, vec![sel(2.0)]);
    }

    #[test]
    fn shift_click_toggles_membership_like_ctrl() {
        // UI-5: Shift now toggles too, so it can deselect (it used to only add).
        let mut s = vec![sel(1.0)];
        let shift = egui::Modifiers {
            shift: true,
            ..Default::default()
        };
        lane_select_click(&mut s, sel(2.0), shift); // add
        assert_eq!(s, vec![sel(1.0), sel(2.0)]);
        lane_select_click(&mut s, sel(2.0), shift); // already in — removes it
        assert_eq!(s, vec![sel(1.0)]);
    }

    fn psel(prop: TransformProp) -> crate::app_state::PropSel {
        crate::app_state::PropSel {
            layer: uuid::Uuid::nil(),
            row: PropRow::Transform(prop),
        }
    }

    // Shift-click ranges over the drawn order between anchor and target,
    // inclusive, whichever way round they sit (note 2.6b).
    #[test]
    fn prop_range_covers_the_rows_between() {
        let order = vec![
            psel(TransformProp::AnchorX),
            psel(TransformProp::PositionX),
            psel(TransformProp::ScaleX),
            psel(TransformProp::Rotation),
            psel(TransformProp::Opacity),
        ];
        let (range, to_anchor) = prop_range(
            &order,
            Some(psel(TransformProp::PositionX)),
            psel(TransformProp::Rotation),
        );
        assert!(!to_anchor);
        assert_eq!(
            range,
            vec![
                psel(TransformProp::PositionX),
                psel(TransformProp::ScaleX),
                psel(TransformProp::Rotation),
            ]
        );
        // Reversed (target above the anchor) gives the same inclusive span.
        let (range_rev, _) = prop_range(
            &order,
            Some(psel(TransformProp::Rotation)),
            psel(TransformProp::PositionX),
        );
        assert_eq!(range_rev.len(), 3);
        assert_eq!(range_rev.first(), Some(&psel(TransformProp::PositionX)));
    }

    // No usable anchor: Shift-click falls back to selecting just the target.
    #[test]
    fn prop_range_without_anchor_selects_target() {
        let order = vec![psel(TransformProp::Rotation)];
        let (range, to_anchor) = prop_range(&order, None, psel(TransformProp::Rotation));
        assert!(to_anchor);
        assert_eq!(range, vec![psel(TransformProp::Rotation)]);
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod motion_blur_switch_tests {
    use super::*;
    use crate::theme::{ColorScheme, ThemeShape};
    use lumit_core::model::Layer;
    use uuid::Uuid;

    /// Click the motion-blur switch (drawn into a known slot) and return the op it
    /// commits, if any.
    fn click_motion_blur(comp_id: Uuid, layer: &Layer) -> Option<lumit_core::Op> {
        let ctx = egui::Context::default();
        let theme = Theme::for_scheme(ColorScheme::ALL[0], ThemeShape::Sharp);
        let pending: std::cell::RefCell<Option<lumit_core::Op>> = std::cell::RefCell::new(None);
        let slot = egui::Rect::from_min_size(egui::pos2(50.0, 50.0), egui::vec2(40.0, 16.0));
        let run = |events: Vec<egui::Event>| {
            let ri = egui::RawInput {
                screen_rect: Some(egui::Rect::from_min_size(
                    egui::pos2(0.0, 0.0),
                    egui::vec2(200.0, 200.0),
                )),
                events,
                ..Default::default()
            };
            let _ = ctx.run(ri, |ctx| {
                egui::CentralPanel::default().show(ctx, |ui| {
                    let mut child = ui.new_child(
                        egui::UiBuilder::new()
                            .max_rect(slot)
                            .layout(egui::Layout::left_to_right(egui::Align::Center)),
                    );
                    motion_blur_control(
                        &mut child,
                        &theme,
                        comp_id,
                        layer,
                        &mut pending.borrow_mut(),
                    );
                });
            });
        };
        let c = slot.center();
        run(vec![]); // lay out
        run(vec![egui::Event::PointerMoved(c)]);
        run(vec![egui::Event::PointerButton {
            pos: c,
            button: egui::PointerButton::Primary,
            pressed: true,
            modifiers: egui::Modifiers::default(),
        }]);
        run(vec![egui::Event::PointerButton {
            pos: c,
            button: egui::PointerButton::Primary,
            pressed: false,
            modifiers: egui::Modifiers::default(),
        }]);
        pending.into_inner()
    }

    /// UI-12 regression: the per-layer motion-blur switch must draw and, when
    /// clicked, flip the layer's `motion_blur` flag (committing through
    /// `SetLayerMotionBlur`, so it persists). Driving it end-to-end through
    /// `AppState` also proves the op reaches the document.
    #[test]
    fn clicking_the_switch_toggles_the_layers_motion_blur_flag() {
        let mut app = AppState::default();
        app.new_composition();
        app.confirm_comp_dialog();
        app.add_solid_layer();
        let comp_id = app.selected_comp.unwrap();
        let layer = app.store.snapshot().comp(comp_id).unwrap().layers[0].clone();
        assert!(
            !layer.switches.motion_blur,
            "a fresh layer starts with motion blur off"
        );

        // Off -> the click commits an op turning it on.
        let op = click_motion_blur(comp_id, &layer).expect("the switch must emit an op");
        assert!(matches!(
            op,
            lumit_core::Op::SetLayerMotionBlur {
                motion_blur: true,
                ..
            }
        ));
        app.commit(op);
        let after = app.store.snapshot().comp(comp_id).unwrap().layers[0].clone();
        assert!(
            after.switches.motion_blur,
            "committing the switch op must set the flag"
        );

        // On -> clicking again turns it back off.
        let op = click_motion_blur(comp_id, &after).expect("the switch must emit an op");
        assert!(matches!(
            op,
            lumit_core::Op::SetLayerMotionBlur {
                motion_blur: false,
                ..
            }
        ));
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod channel_picker_tests {
    use super::*;
    use lumit_core::fx::ParamKind;

    // The three-colour channel picker (P2/K-143) finds its group by the stable
    // `channel_colour_1/2/3` ids. Chromatic aberration (K-144) is the first
    // adopter: its schema must declare exactly those three ids as Colour params
    // with red / green / blue defaults, or the picker silently stops finding
    // them (and the classic split defaults break).
    #[test]
    fn chromatic_aberration_declares_the_channel_picker_group() {
        let schema = lumit_core::fx::schema("chromatic_aberration").unwrap();
        let defaults = [
            [1.0, 0.0, 0.0, 1.0],
            [0.0, 1.0, 0.0, 1.0],
            [0.0, 0.0, 1.0, 1.0],
        ];
        for (id, want) in CHANNEL_COLOUR_IDS.iter().zip(defaults.iter()) {
            let ps = schema
                .params
                .iter()
                .find(|p| &p.id == id)
                .unwrap_or_else(|| panic!("missing channel colour param {id}"));
            match ps.kind {
                ParamKind::Colour { default, .. } => assert_eq!(&default, want, "{id} default"),
                _ => panic!("{id} must be a Colour parameter"),
            }
        }
    }
}
