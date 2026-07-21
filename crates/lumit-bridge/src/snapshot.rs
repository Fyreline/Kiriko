//! Turning a [`Document`] into the snapshot JSON the panels read.
//!
//! # In plain terms
//!
//! A *snapshot* is the whole document written out as JSON for the Flutter side
//! to draw. "Snapshot v2" keeps every field v1 had (the item tree, undo flags,
//! path) and *adds* detail the Viewer, Timeline and editors need: for a
//! composition the `comp` block (its size, frame rate, frame count, layers and
//! markers); for a footage item its `media` metadata and probe `status`. The
//! rule is strictly additive — an older reader still finds everything it knew.
//!
//! Frames are integers derived from the composition's *own* frame rate the way
//! the egui frontend derives them (rational time, never threaded f64): a layer's
//! in/out frame is the frame containing its in/out point, and the frame count is
//! the comp's duration divided by one frame, rounded to the nearest whole frame.

use crate::media::MediaCache;
use crate::state::Bridge;
use lumit_core::model::{Composition, Document, Layer, LayerKind, ProjectItem};
use lumit_core::time::Rational;
use serde_json::{json, Value};
use std::collections::HashSet;
use uuid::Uuid;

/// The document tree as the Project panel reads it, plus the v2 detail. Walks
/// [`Document::root_items`] and nests each folder's children, so the JSON mirrors
/// the panel's real nesting rather than the flat storage. A malformed folder
/// cycle is broken by the `seen` set, never looped.
pub(crate) fn snapshot_value(bridge: &Bridge) -> Value {
    let doc = bridge.store.snapshot();
    let mut seen = HashSet::new();
    let items: Vec<Value> = doc
        .root_items()
        .into_iter()
        .filter_map(|id| item_value(&doc, &bridge.media, id, &mut seen))
        .collect();
    json!({
        "ok": true,
        "items": items,
        "can_undo": bridge.store.can_undo(),
        "can_redo": bridge.store.can_redo(),
        "path": bridge.path.as_ref().map(|p| p.to_string_lossy().into_owned()),
    })
}

/// One item as `{id, name, kind, children, …}`. `children` is populated only for
/// folders (recursively). A composition additionally carries a `comp` block; a
/// footage item carries `status` and, once probed, a `media` block. Returns
/// `None` for an id already visited (cycle guard) or absent from the document.
fn item_value(
    doc: &Document,
    media: &MediaCache,
    id: Uuid,
    seen: &mut HashSet<Uuid>,
) -> Option<Value> {
    if !seen.insert(id) {
        return None;
    }
    let item = doc.item(id)?;
    let children: Vec<Value> = match item {
        ProjectItem::Folder(f) => f
            .children
            .iter()
            .filter_map(|child| item_value(doc, media, *child, seen))
            .collect(),
        _ => Vec::new(),
    };
    let mut obj = json!({
        "id": id.to_string(),
        "name": item.name(),
        "kind": item_kind(item),
        "children": children,
    });
    match item {
        ProjectItem::Composition(c) => {
            obj["comp"] = comp_value(c);
        }
        ProjectItem::Footage(f) => {
            let (status, detail) = media.snapshot_for(f.id);
            obj["status"] = json!(status);
            if let Some(detail) = detail {
                obj["media"] = detail;
            }
        }
        _ => {}
    }
    Some(obj)
}

fn item_kind(item: &ProjectItem) -> &'static str {
    match item {
        ProjectItem::Footage(_) => "footage",
        ProjectItem::Folder(_) => "folder",
        ProjectItem::Composition(_) => "composition",
        ProjectItem::Solid(_) => "solid",
    }
}

/// A composition's v2 detail: size, frame rate (as the model stores it,
/// `{num, den}`), the derived frame count, every layer, and the marker frames.
fn comp_value(c: &Composition) -> Value {
    // FrameRate serialises to `{"num":…,"den":…}` — exactly what Dart expects,
    // and exact (no f64 rounding of the rate itself).
    let fps = serde_json::to_value(c.frame_rate).unwrap_or(json!({ "num": 0, "den": 1 }));
    let layers: Vec<Value> = c
        .layers
        .iter()
        .enumerate()
        .map(|(index, l)| layer_value(c, index, l))
        .collect();
    // Markers as comp-frame indices (the frame containing each marker's time).
    let markers: Vec<i64> = c
        .markers
        .iter()
        .map(|m| c.frame_rate.frame_at(m.time))
        .collect();
    json!({
        "width": c.width,
        "height": c.height,
        "fps": fps,
        "frame_count": comp_frame_count(c),
        "layers": layers,
        "markers": markers,
    })
}

/// One layer's v2 detail. `in_frame`/`out_frame` are the comp frames containing
/// the layer's in/out points (derived from the comp's own rate); `switches`
/// mirrors the model's [`lumit_core::model::Switches`] field names verbatim.
fn layer_value(c: &Composition, index: usize, l: &Layer) -> Value {
    let switches = serde_json::to_value(l.switches).unwrap_or(json!({}));
    json!({
        "id": l.id.to_string(),
        "index": index,
        "name": l.name,
        "kind": layer_kind(&l.kind),
        "in_frame": c.frame_rate.frame_at(l.in_point),
        "out_frame": c.frame_rate.frame_at(l.out_point),
        "label": l.label,
        "switches": switches,
    })
}

/// The layer-kind tag, mirroring the [`LayerKind`] variant names.
fn layer_kind(kind: &LayerKind) -> &'static str {
    match kind {
        LayerKind::Footage { .. } => "footage",
        LayerKind::Solid { .. } => "solid",
        LayerKind::Precomp { .. } => "precomp",
        LayerKind::Text { .. } => "text",
        LayerKind::Camera { .. } => "camera",
        LayerKind::Sequence { .. } => "sequence",
        LayerKind::Adjustment => "adjustment",
    }
}

/// The comp's frame count: duration ÷ one-frame, rounded to the nearest whole
/// frame — the same quantity `lumit-ui`'s `comp_frame_count` computes, but kept
/// on rational time (no f64 threading) and at least one frame.
fn comp_frame_count(c: &Composition) -> i64 {
    let Ok(frame_dur) = c.frame_rate.frame_duration() else {
        return 1;
    };
    let Ok(frames) = c.duration.0.checked_div(frame_dur.0) else {
        return 1;
    };
    round_rational(frames).max(1)
}

/// Round a rational to the nearest integer (ties toward +∞), in i128 so the
/// doubling cannot overflow a well-formed rate. Frame counts are non-negative,
/// where this agrees with f64 rounding.
fn round_rational(r: Rational) -> i64 {
    let num = i128::from(r.num());
    let den = i128::from(r.den()); // invariant: > 0
    let doubled = num * 2 + den; // round-half-up numerator over 2·den
    i64::try_from(doubled.div_euclid(den * 2)).unwrap_or(i64::MAX)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod tests {
    use super::*;
    use lumit_core::markers::Marker;
    use lumit_core::model::{
        FootageItem, Layer, LayerKind, LinearColour, MediaRef, MotionBlur, Switches, TransformGroup,
    };
    use lumit_core::ops::Op;
    use lumit_core::store::DocumentStore;
    use lumit_core::time::{CompTime, Duration, FrameRate};

    fn ct(n: i64) -> CompTime {
        CompTime(Rational::new(n, 1).unwrap())
    }

    #[test]
    fn round_rational_rounds_to_nearest() {
        assert_eq!(round_rational(Rational::new(7, 2).unwrap()), 4); // 3.5 → 4
        assert_eq!(round_rational(Rational::new(5, 2).unwrap()), 3); // 2.5 → 3
        assert_eq!(round_rational(Rational::new(10, 3).unwrap()), 3); // 3.33 → 3
        assert_eq!(round_rational(Rational::new(300, 1).unwrap()), 300);
    }

    /// Snapshot v2: a comp with two layers, switches, markers and a footage
    /// item's probe status all serialise into the expected shape. Built through
    /// the real store so the JSON is exactly what the bridge would emit.
    #[test]
    fn comp_with_layers_serialises_v2_shape() {
        let comp = Composition {
            id: Uuid::now_v7(),
            name: "Scene".into(),
            width: 1920,
            height: 1080,
            frame_rate: FrameRate::new(60, 1).unwrap(),
            duration: Duration(Rational::new(5, 1).unwrap()),
            background: LinearColour::BLACK,
            work_area: None,
            layers: vec![
                sample_layer("top", ct(1), ct(4)),
                sample_layer("bottom", ct(0), ct(5)),
            ],
            markers: vec![Marker::user(Uuid::now_v7(), Rational::new(2, 1).unwrap())],
            motion_blur: MotionBlur::default(),
            extra: serde_json::Map::new(),
        };
        let store = DocumentStore::new(Document::new());
        store
            .commit(Op::AddItem {
                index: 0,
                item: Box::new(ProjectItem::Composition(comp)),
            })
            .unwrap();
        let bridge = Bridge {
            store,
            path: None,
            media: MediaCache::default(),
        };
        let snap = snapshot_value(&bridge);

        let comp_json = &snap["items"][0];
        assert_eq!(comp_json["kind"], json!("composition"));
        let comp_block = &comp_json["comp"];
        assert_eq!(comp_block["width"], json!(1920));
        assert_eq!(comp_block["height"], json!(1080));
        assert_eq!(comp_block["fps"], json!({ "num": 60, "den": 1 }));
        // 5 s at 60 fps = 300 frames.
        assert_eq!(comp_block["frame_count"], json!(300));

        let layers = comp_block["layers"].as_array().unwrap();
        assert_eq!(layers.len(), 2);
        // Index 0 is the top layer; in/out frames derive from 60 fps.
        assert_eq!(layers[0]["index"], json!(0));
        assert_eq!(layers[0]["name"], json!("top"));
        assert_eq!(layers[0]["kind"], json!("footage"));
        assert_eq!(layers[0]["in_frame"], json!(60)); // 1 s
        assert_eq!(layers[0]["out_frame"], json!(240)); // 4 s
        let sw = &layers[0]["switches"]; // switches mirror the model's field names
        assert_eq!(sw["visible"], json!(true));
        assert_eq!(sw["audible"], json!(true));
        assert_eq!(sw["locked"], json!(false));
        assert_eq!(sw["solo"], json!(false));
        assert_eq!(sw["motion_blur"], json!(false));
        assert_eq!(sw["fx"], json!(true));
        assert_eq!(sw["three_d"], json!(false));
        assert_eq!(sw["collapse"], json!(false));

        // Markers are comp-frame indices: 2 s → frame 120.
        assert_eq!(comp_block["markers"], json!([120]));
        assert!(bridge.store.can_undo());
    }

    /// A footage item without a cache entry reports status "unprobed" and no
    /// media block — the shape a `--no-default-features` build always produces.
    #[test]
    fn footage_without_a_probe_is_unprobed() {
        let footage = FootageItem {
            id: Uuid::now_v7(),
            name: "clip.mp4".into(),
            media: MediaRef {
                relative_path: "clip.mp4".into(),
                absolute_path: String::new(),
                fingerprint: None,
                extra: serde_json::Map::new(),
            },
            extra: serde_json::Map::new(),
        };
        let store = DocumentStore::new(Document::new());
        store
            .commit(Op::AddItem {
                index: 0,
                item: Box::new(ProjectItem::Footage(footage)),
            })
            .unwrap();
        let bridge = Bridge {
            store,
            path: None,
            media: MediaCache::default(),
        };
        let snap = snapshot_value(&bridge);
        assert_eq!(snap["items"][0]["status"], json!("unprobed"));
        assert!(snap["items"][0].get("media").is_none());
    }

    fn sample_layer(name: &str, in_point: CompTime, out_point: CompTime) -> Layer {
        Layer {
            id: Uuid::now_v7(),
            name: name.into(),
            kind: LayerKind::Footage {
                item: Uuid::now_v7(),
                retime: None,
            },
            in_point,
            out_point,
            start_offset: ct(0),
            transform: TransformGroup::default(),
            matte: None,
            parent: None,
            label: 0,
            volume_db: lumit_core::anim::Property::zero(),
            blend: Default::default(),
            masks: Vec::new(),
            effects: Vec::new(),
            switches: Switches::default(),
            extra: serde_json::Map::new(),
        }
    }
}
