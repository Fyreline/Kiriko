//! Effect presets (docs/07-UI-SPEC.md §6/§7, K-065): save a layer's whole
//! effect stack to a file and load it onto another layer.
//!
//! In plain terms: an effect preset is just the list of effects on a layer,
//! with their settings, written to a small `.lumfx` JSON file so it can be
//! reused or shared. Loading one gives every effect a fresh id, so applying
//! the same preset to two layers never makes them share an instance.

use lumit_core::model::EffectInstance;

/// A saved effect stack. `format` is bumped if the on-disk shape changes;
/// the effects are exactly the model's `EffectInstance`s, so a preset always
/// round-trips whatever a project does.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EffectPreset {
    pub format: u32,
    pub name: String,
    pub effects: Vec<EffectInstance>,
}

/// The current on-disk format version.
pub const PRESET_FORMAT: u32 = 1;

/// The file extension presets use (a plain JSON document inside).
pub const PRESET_EXTENSION: &str = "lumfx";

/// Serialise a stack to the preset JSON text.
pub fn to_json(name: &str, effects: &[EffectInstance]) -> Result<String, String> {
    serde_json::to_string_pretty(&EffectPreset {
        format: PRESET_FORMAT,
        name: name.to_owned(),
        effects: effects.to_vec(),
    })
    .map_err(|e| e.to_string())
}

/// Parse preset JSON text back to a preset. A newer `format` still loads:
/// unknown fields ride along in each effect's `extra` map, matching how the
/// project file tolerates forward-compatible additions.
pub fn from_json(text: &str) -> Result<EffectPreset, String> {
    serde_json::from_str::<EffectPreset>(text).map_err(|e| e.to_string())
}

/// The preset's effects with fresh instance ids — what actually lands on a
/// layer, so applying one preset to several layers never shares an instance
/// id (ids are instance identity only; they never feed a cache key).
pub fn instantiated(preset: &EffectPreset) -> Vec<EffectInstance> {
    preset
        .effects
        .iter()
        .cloned()
        .map(|mut e| {
            e.id = uuid::Uuid::now_v7();
            e
        })
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn stack() -> Vec<EffectInstance> {
        vec![
            lumit_core::fx::instantiate("blur").unwrap(),
            lumit_core::fx::instantiate("glow").unwrap(),
        ]
    }

    #[test]
    fn a_preset_round_trips_through_json() {
        let effects = stack();
        let json = to_json("My look", &effects).unwrap();
        let back = from_json(&json).unwrap();
        assert_eq!(back.format, PRESET_FORMAT);
        assert_eq!(back.name, "My look");
        assert_eq!(back.effects, effects);
    }

    #[test]
    fn instantiating_gives_fresh_ids_but_keeps_the_effects() {
        let preset = from_json(&to_json("look", &stack()).unwrap()).unwrap();
        let a = instantiated(&preset);
        let b = instantiated(&preset);
        // Same effects and params, but every instance id is unique.
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].effect, preset.effects[0].effect);
        assert_ne!(a[0].id, preset.effects[0].id);
        assert_ne!(a[0].id, b[0].id);
    }

    #[test]
    fn a_newer_format_still_loads() {
        // A preset written by a hypothetical newer Lumit, with an unknown
        // top-level field, still parses — serde ignores what it doesn't know.
        let effects = stack();
        let mut v = serde_json::to_value(EffectPreset {
            format: 99,
            name: "future".into(),
            effects: effects.clone(),
        })
        .unwrap();
        v.as_object_mut()
            .unwrap()
            .insert("future_field".into(), serde_json::json!(true));
        let back = from_json(&v.to_string()).unwrap();
        assert_eq!(back.effects, effects);
    }
}
