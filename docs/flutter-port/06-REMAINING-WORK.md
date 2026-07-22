# 06 — Remaining work (delete-on-done ledger)

Every partially finished (◐/◑) or not-started (☐) item extracted from
05-PARITY-CHECKLIST.md on 2026-07-22 (owner request). **Rows are deleted as they
land** — the burn-down is complete: sections A–E landed together and the final
integration sweep (2026-07-22) closed the last cross-agent seams and thin
remainders. **What survives below is only genuinely blocked work, each row
carrying the evidence for why it cannot land yet.** 05 stays the permanent
record.

Excluded on purpose (not parity work): flutter_rust_bridge codegen (deferred by
design until the API stabilises), the macOS pass, the post-parity design changes
in 05 §post-parity, and the two recorded behavioural deviations (export
queue-snapshot timing; share-export VBR cap).

Closed in the final sweep (2026-07-22), removed from the burn-down:

- **Shell Ctrl+C/V → keyframe clipboard** — the shell key handler now routes
  Ctrl+C/Ctrl+V to `AppStateStub.copySelectedKeyframes`/`pasteKeyframes`
  (`shell/shell.dart`), behind the same text-field focus gate as the other
  shortcuts (egui note 2.2 / UI-7).
- **Resolution picker downsample** — `PreviewSource` threads
  `app.previewScale.factor` through the primary comp render (and the Dart LRU
  key carries the scale, mirroring the engine cache's per-scale keying), so
  Half/Third/Quarter actually render fewer pixels (`preview_source.dart`).
- **Timeline cache bar** — the `cache_stats` Dart binding was already on
  `CacheControlBridge`; `AppStateStub.cacheStats()` exposes it, warm frames are
  tracked as the `PreviewSource` drives them into the engine cache
  (`noteFrameWarmed`, scoped per comp+scale, reset on edit/clear), and
  `panels/timeline/cache_bar.dart` draws the RAM-tier band over the ruler
  (theme.success, 15-DESIGN §6.3), polling on the `cacheBarRevision` cadence,
  never per-paint.
- **Layer context menu final wiring** — Rename opens an in-place outline editor
  (`renameLayer`), Add effect opens the categorised submenu from `listEffects()`
  (`addEffect`), Convert to sequenced calls `convertToSequenced`, and Trim to
  source end calls `trimToSourceEnd`, offered only for a retimed footage clip
  (the egui condition, menu.rs:174-184) — `panels/timeline/layer_menu.dart`,
  `layer_row.dart`.
- **EffectDragData onto timeline rows** — each layer row is now a
  `DragTarget<EffectDragData>`; a dropped effect applies to that row's layer
  through `addEffect` (`layer_row.dart`), the sibling of the Effect controls
  drop target.
- **Project-panel thumbnails** — footage rows render a small decoded thumbnail
  through `app.thumbnail`, decoded asynchronously off the build and cached until
  the document epoch advances (a relink re-decodes), with the type glyph as the
  placeholder (`project_panel.dart`).
- **DragValueField Reset targets** — sensible `resetTo` defaults now flow to the
  transform axes (the property seed), the text size (72 pt), the New-composition
  width/height/duration (1920×1080 / 30 s), the autosave interval/copies (5 / 3)
  and the three cache budgets (`effect_controls_panel.dart`, `dialogs.dart`,
  `settings_window.dart`).

## Blocked — awaiting engine/bridge capability, with evidence

Each row states the specific missing capability. None can land Dart-side without
it; landing a half-built version would drift the engine's behaviour, so they are
annotated honestly rather than faked.

**Section A — bridge caveats (landed with a named follow-up):**

- **Beat detection runs synchronously** in the bridge (`detect_beats` mixes the
  comp audio through the headless input builder and analyses in one blocking
  call the Dart side awaits off its UI isolate), where egui runs it off-thread
  (`detect_beats`/`poll_beats`). If long-audio latency bites, a start/poll pair
  like the export ops is the follow-up — the maths is identical, only the
  threading differs.
- **Recovery `restore_journal` — bridge journal-append not wired.**
  `restore_journal` replays whatever on-disk crash journal a prior session left,
  but the bridge does **not yet write** the journal on every commit, so it
  recovers a journal the egui app (say) wrote rather than one this bridge wrote.
  Named follow-up: wire journal-append into the bridge commit path, matching
  egui's `AppState::commit`.

**Section B — performance follow-ups:**

- **Fence/keyed-mutex handshake for the shared texture** — only if the owner's
  live run shows tearing. **Verify on the owner's machine first**; not built
  speculatively. The shared texture presents without a producer/consumer fence
  today.
- **Footage probing off-thread** — the thumbnail half of this landed; the
  off-thread probe move did not. The bridge's synchronous probe cache is read
  *synchronously* by several ops — `convert_to_sequenced` and
  `trim_to_source_end` (source duration, `items.rs`), `add_footage_layer`
  sizing, and relink's sibling-missing check — so moving probing onto a worker
  needs those consumers to probe-on-demand or the ops silently degrade to their
  unprobed fallback. Named follow-up: a probe worker drained on
  `lumit_bridge_snapshot` polls (mirroring egui's `MediaRegistry::poll`) **plus**
  a synchronous `ensure_probed` fallback for the consumers above.

**Section C — timeline and graph:**

- **Graph editor — the transform value/speed graph and the Retime Time
  (source-position) lens** (`graph.rs:86-94`, K-078). The Flutter graph editor
  ports the Retime *speed* lens; the value/speed graph for an animated property
  and the Time lens are a substantial unbuilt graph-editor build beyond this
  seam-level sweep. Its dependents ride that same build — the **Vegas
  default-lens preference** (`graph.rs:164`, inert until the Time lens exists),
  **boundary beat/frame snapping** on graph drags (`graph.rs:1616-1628`), and
  **value-key bezier/speed handles**.
  *egui-gap verdicts (04-RETIMING spec-only — egui never built them, verified in
  graph.rs and excluded from parity):* RATE/MAP **type chips** + ease-name labels
  (§9.4); **kink badges** (§6.1); **numeric % and t·s entry fields** (§9.3); the
  graph's **own overrun hatching** (§7.2 — egui hatches overrun only on the clip
  bar, `panel.rs:992`).
- **Beat markers drawn distinctly** — the snapshot serialises markers as bare
  comp-frame indices (`snapshot.rs:137`, `Vec<i64>`) with no beat/user/chapter
  kind, so beat markers render as ruler flags but cannot be styled apart. Needs
  a marker-kind field on the snapshot.
- **Sequence sub-bars** (clip boundaries inside a sequence layer's bar) —
  `BridgeLayer` carries no `clips`, so clip boundaries are not reachable from
  Dart.
- **Overrun HOLD hatch on clip bars** (`panel.rs:992-1085`) —
  `overrun_span_secs` (`speed_rows.rs:68`) needs the layer's `start_offset`, its
  local in/out points and the source duration; the snapshot carries the retime
  store and the media duration but **not** `start_offset` nor the layer's local
  in/out, so the held span cannot be located.

**Section D — editors, viewer and panels:**

- **Property editors — read-back** for text content, solid size and camera zoom.
  The setters exist and a solid's colour reads back from the snapshot; text
  content, solid size and camera zoom are held in a session-edit map because the
  snapshot does not carry those fields. True read-back awaits them.
- **Viewer mask draw — geometry.** The Shape tool draws a rubber-band and
  commits a mask via `addMask` (a kind only). The egui path commits real
  rectangle/ellipse/star **geometry** (`SetLayerMasks`); the bridge `addMask` op
  takes no geometry, so the drawn size/position is not honoured — awaits a
  geometry-carrying mask op.
- **Viewer transform gizmo — full manipulator.** The selected 2D layer draws an
  anchor crosshair, draggable to move its Position. The pan-behind anchor maths,
  the bounding box and the scale handles await the `LayerMap` (layer↔screen
  transform) port from `overlays.rs`.
- **Resolution picker — realtime-tier readout.** The scale plumbing landed
  (above); the realtime-tier readout is engine `RealtimeController` machinery the
  bridge does not run — it awaits the engine playback machinery.
- **Effects presets — `.lumfx`.** Save/load cannot round-trip byte-compatibly
  from the snapshot, which flattens each effect's `EffectKey` (namespace and
  version dropped, only the match name survives) and each parameter's animation.
  A faithful preset awaits a preset bridge op (serialising the engine
  `EffectInstance`) or an `EffectInstance` read-back in the snapshot.
- **Effect controls — per-parameter stopwatch/navigator.** There are only
  effect-param value setters (`setEffectParamScalar/Colour/Choice/Bool/Seed/
  Point`), no effect-param **keyframe** ops — so no stopwatch/navigator on effect
  params until those land.

**Section E — chrome and shell:**

- **Pop out a panel into its own OS window (multi-window)** — BLOCKED, with
  evidence. The pinned SDK is **stable 3.44.7**. Its multi-window support exists
  only as `packages/flutter/lib/src/widgets/_window.dart` — every symbol is
  `@internal` (importing it fails `flutter analyze`) and each API throws
  `UnsupportedError` unless `isWindowingEnabled`, a build-time flag OFF by
  default. Enabling it would need a channel change + a feature flag + `@internal`
  use — all barred by the analyze gate and the pinned-SDK constraint. The
  community route (`desktop_multi_window` and kin) gives each window its own
  Flutter engine/isolate — a **separate Dart heap** — so a popped-out panel could
  not host the body over the SAME `AppStateStub` (the F0 spec's requirement).
  Kept as the graceful-degradation notice (`shell/shell.dart` `onPopOut`); no
  real window is opened, tests never spawn one. Re-attempt when the official
  windowing API ships on stable un-gated (flutter/flutter#30701 / #142845).

## Deferred, not blocked

- **Tooltip breadth pass — the remaining `on_hover_text` surfaces.** The shell +
  widgets tooltips landed; the remaining egui hover surfaces (layer switches,
  transport step/loop, the ruler, the scopes header) are optional cosmetic
  polish, not parity-blocking, and are unbuilt only by choice — deliberately none
  on menu-bar items, the splash, command-palette rows and dock tab pills (egui
  parity).

## Reconciled in 05

- (2026-07-22, section-A burn-down): the graph-lens "→Rate drift figure dropped
  by BridgeReply" remainder was stale — `driftSeconds` is threaded and the notice
  reads "fitted, N ms drift"; 05's F3 graph-lens named-remainder dropped the
  drift-figure caveat.
