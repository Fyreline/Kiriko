# 06 — Remaining work (delete-on-done ledger)

Every partially finished (◐/◑) or not-started (☐) item extracted from
05-PARITY-CHECKLIST.md on 2026-07-22 (owner request). **Rows are deleted as they
land** — an empty section gets deleted too; an empty file means the transfer is
complete. 05 stays the permanent record; this file is the burn-down.

Excluded on purpose (not parity work): flutter_rust_bridge codegen (deferred by
design until the API stabilises), the macOS pass, the post-parity design changes
in 05 §post-parity, and the two recorded behavioural deviations (export
queue-snapshot timing; share-export VBR cap).

## A — bridge ops (Rust + Dart plumbing) — LANDED (bridge v0.7, ABI 6→7)

All section-A bridge ops shipped. Rust ops (in-crate tested, three feature
configs green) + FFI exports + typed Dart plumbing on the additive
`EditOpsBridge` capability interface (kept off `DocumentBridge` so the existing
fakes need no change) + `AppStateStub` pass-throughs (errors → `errorNotice`) +
`edit_ops_test.dart`. One caveat recorded, not a stub:

- **Beat detection** runs **synchronously** in the bridge (`detect_beats` mixes
  the comp audio through the headless input builder and analyses in one blocking
  call the Dart side awaits off its UI isolate), where egui runs it off-thread
  (`detect_beats`/`poll_beats`). If long-audio latency bites, a start/poll pair
  like the export ops is the follow-up — the maths is identical, only the
  threading differs. `clear_beat_markers` is always available (a plain marker
  edit). Detection needs the `media` + `render` features; a feature-less build
  reports that calmly.
- **Recovery `restore_journal`** replays whatever on-disk crash journal exists
  for the opened project's document id (the engine's `JournalFile` read+replay,
  the egui recovery path). The bridge does **not yet write** the journal on every
  commit, so today it recovers a journal a prior session (e.g. the egui app) left
  rather than one this bridge wrote — a named follow-up (wire journal-append into
  the bridge commit path, matching egui's `AppState::commit`). `list_autosaves`
  is a pure folder scan and is complete.

## B — performance follow-ups (K-176/K-177 remainders)

Landed rows below are removed (bridge v0.8, ABI 7→8). Remaining:

- **Fence/keyed-mutex handshake for the shared texture** — only if the owner's
  live run shows tearing. **Verify on the owner's machine first**; not built
  speculatively. (Unchanged; the shared texture presents without a
  producer/consumer fence today.)
- **Footage probing off-thread** — *deferred, annotated honestly, not faked.*
  The Project-panel **thumbnail** half of this row **landed** (see below); the
  off-thread probe move did **not**. Reason: the bridge's synchronous probe
  cache is read *synchronously* by several ops — `convert_to_sequenced` and
  `trim_to_source_end` (source duration, `items.rs`), `add_footage_layer`
  sizing, and relink's sibling-missing check — so moving probing onto a worker
  needs those consumers to probe-on-demand or the ops silently degrade to their
  unprobed fallback. That is a real, low-leverage change (probes fire only on
  import/open/relink, "small files imported one at a time" per `media.rs`), and
  landing it half-built would drift those ops. Named follow-up: a probe worker
  drained on `lumit_bridge_snapshot` polls (mirroring egui's
  `MediaRegistry::poll`) **plus** a synchronous `ensure_probed` fallback for the
  consumers above.

**Landed (bridge v0.8, removed from the burn-down):**

- ~~Bridge-side rendered-frame cache~~ — **done.** `crates/lumit-bridge/src/
  framecache.rs`: an LRU of RGBA frames keyed `(comp, frame, scale, document
  epoch)`, the epoch being the identity of the current `Arc<Document>` snapshot
  (pinned so a pointer is never reused mid-cache — the ABA-safe mirror of egui's
  `Arc::as_ptr` doc-identity keying). A re-scrubbed frame skips the GPU entirely
  (proven by a render-counter test). Budget/`clear_cache`/`cache_stats` FFI
  exports; wired to the render path via `render_comp_frame`.
- ~~Engine-side render cancellation~~ — **done.** `crates/lumit-bridge/src/
  cancel.rs` + `render_comp_frame_gen(generation)` and `render_cancel_stale`.
  The worker threads its latest-wins generation through the render; a cache
  **miss** whose generation is below the published high-water mark aborts before
  the GPU render (the granularity the monolithic headless render allows —
  checked once the renderer lock is held, reported honestly). `PreviewSource`
  publishes each primary render's generation from the UI isolate so a stale
  render queued behind the lock is skipped.
- ~~Settings cache controls~~ — **done for what is real.** "Clear cache" calls
  `clear_cache` **and** empties the Dart decoded-frame LRU
  (`PreviewSource.clearDecodedCache`); the Memory-budget field drives
  `set_cache_budget`. "Choose cache root folder" controls the **disk** cache
  root, which the bridge does not have yet — the picker stays and its hint now
  says the folder is remembered for the engine disk tier when it lands (annotated
  in 05, not faked).
- ~~Project-panel thumbnails~~ — **done.** `lumit_bridge_thumbnail(item_id,
  max_edge)` decodes a representative frame once, box-downscales it (never
  upscales), and caches it on the `MediaCache`. Exported as the `ThumbnailBridge`
  Dart capability + `AppStateStub.thumbnail(...)` seam for the Project-panel
  agent; no panel UI built here.

## C — timeline and graph UI

**Landed (2026-07-22, removed from the burn-down):**

- ~~Keyframe right-click interpolation menu~~ — **done** for lane keys.
  `panels/timeline/keyframe_interp_menu.dart` (Easy ease / Linear / Hold / Unify
  handles / Delete), ported from `graph.rs:1676`: Easy ease is `EASY_EASE`
  (speed 0, influence 1/3, `anim.rs:40`); Unify averages the two slopes keeping
  each reach (`graph.rs:1712`) and shows only for a broken bezier key
  (`graph.rs:1694`). Wired into the lane's right-click (`property_row.dart`); a
  multi-selection all take the choice via per-key `setKeyframeInterp`, and a
  multi-delete batches through `applyKeyframeBatch` `remove` (there is no
  batch-interp bridge op — honestly noted). **Graph-editor keys** ride the
  unbuilt transform value graph (below): the Flutter graph editor has no value
  keys yet, so there is nothing there to right-click.
- ~~Empty-lane context menu~~ — **done.** `panels/timeline/lane_context_menu.dart`
  (Composition settings → the shared dialogue · Reveal in project →
  `selectProjectItem(compId)`, `panel.rs:369` · Show time grid → a session-only
  lane grid the Timeline body draws, `panel.rs:398` · Beat sensitivity 0–100
  slider + Detect → `detectBeats` · Clear beat markers → `clearBeatMarkers`),
  ported from `panel.rs:384`. Opens on a right-click on empty lane space, drawn
  behind the rows so a bar/key wins the hit-test.
- ~~Comp-tab-strip right-click → Pop out timeline~~ — **done.** `comp_tabs.dart`
  posts the same multi-window notice the dock's own pop-out seam uses
  (`shell.dart:288`), ready to route to a real seam when E lands.
- ~~Timeline remainder: resizable outline column · keyframe copy/paste ·
  MB master into the top row~~ — **done.** The outline/lane divider drags
  `_outlineWidth` (session state); Ctrl+C/V go through the additive app-state
  seam `copySelectedKeyframes`/`pasteKeyframes` (the shell owns the keys) with
  the clipboard logic + pure round-trip in `keyframe_clipboard.dart` (copy the
  selection, paste value-batched at the playhead then restore each eased key's
  shape); the composition motion-blur master now sits in the timeline top row
  beside the search box.
- ~~Transport: loop the work area~~ — **done.** `viewer_panel.dart`
  `workAreaLoopFrame` loops `[in, out)` when a work area is set (else the whole
  comp), snaps a playhead scrubbed outside back to the start, and wraps modularly
  — mirroring `playback.rs comp_cached_tick`.

**Remaining:**

- Graph editor — the genuine parity remainder is the **transform value/speed
  graph** for the selected animated property and the Retime **Time**
  (source-position) lens (`graph.rs:86-94`, K-078): egui draws both; the Flutter
  graph editor still ports only the Retime *speed* lens. Its dependents ride that
  same build — the **Vegas default-lens preference** (`graph.rs:164`: egui does
  persist it, but it only chooses between the speed lens and the Time lens, so it
  is inert until the Time lens exists), **boundary beat/frame snapping** on graph
  drags (`graph.rs:1616-1628`), and **value-key bezier/speed handles**.
  *egui-gap verdicts (04-RETIMING spec-only — egui never built them, verified in
  graph.rs and excluded from parity):* RATE/MAP **type chips** + ease-name labels
  (§9.4 — no `RATE`/`MAP`/`chip` in graph.rs); **kink badges** (§6.1 — no `kink`
  in graph.rs); **numeric % and t·s entry fields** (§9.3 — no `TextEdit`/
  `DragValue`/type-to-edit in graph.rs; the sole `double_clicked` is the
  background add-key at `graph.rs:1095`); the graph's **own overrun hatching**
  (§7.2 — no `overrun`/`hatch` in graph.rs; egui hatches overrun only on the clip
  bar, `panel.rs:992`).
- Timeline remainder — **blocked on the snapshot / a missing binding (verified):**
  - **Beat markers drawn distinctly** — blocked. The snapshot serialises markers
    as bare comp-frame indices (`snapshot.rs:137`, `Vec<i64>`) with no
    beat/user/chapter kind, so beat markers render as ruler flags (they *do*
    render) but cannot be styled apart. Needs a marker-kind field on the snapshot.
  - **Cache bar** — awaits the `cache_stats` Dart binding. The bridge frame cache
    (with a `cache_stats` FFI export) landed this wave in `framecache.rs`, but
    `bridge.dart` has no Dart `cache_stats` accessor yet, so `cache_bar()` has no
    stats to draw. Parked until that binding lands.
  - **Sequence sub-bars** (clip boundaries inside a sequence layer's bar) —
    blocked on the snapshot: `BridgeLayer` carries no `clips`, so clip boundaries
    are not reachable from Dart.
  - **Overrun HOLD hatch on clip bars** (`panel.rs:992-1085`) — blocked on the
    snapshot: `overrun_span_secs` (`speed_rows.rs:68`) needs the layer's
    `start_offset`, its local in/out points and the source duration; the snapshot
    carries the retime store and (via the source item) the media duration, but
    **not** `start_offset` nor the layer's local in/out, so the held span cannot
    be located.
- Layer context menu: wire Rename (in-place editor), Add effect (categorised
  picker), Convert to sequenced, Trim to source end (ops from A) — untouched this
  pass (outside the numbered timeline/graph work order; Rename-in-place needs
  outline-cell edit plumbing and Add-effect overlaps the effects picker).

## D — editors, viewer and panels

Most of section D landed (2026-07-22): the Text/Solid/Camera property editors,
the Viewer toolbar + shape picker, the transform/eyedropper overlays, the
resolution picker, the Project-panel rename/missing/context ops, id-based
hierarchy nesting, and effect category grouping + editable param kinds. The
remainders below carry an honest reason.

- **Property editors — read-back:** the Text, Solid and Camera groups are wired
  (`setTextContent`/`setSolid`/`setCameraZoom`) and land in the Effect controls
  panel below Transform. A solid's colour reads back from the snapshot; text
  content, solid size and camera zoom are held in a session-edit map because the
  snapshot does not carry them — true read-back awaits those snapshot fields.
- **Viewer mask draw — geometry:** the Shape tool draws a rubber-band and, on
  release, commits a mask via `addMask` (a kind only). The egui path commits real
  rectangle/ellipse/star **geometry** (`SetLayerMasks`); the bridge `addMask` op
  takes no geometry, so the drawn size/position is not honoured — awaits a
  geometry-carrying mask op.
- **Viewer transform gizmo — full manipulator:** the selected 2D layer draws an
  anchor crosshair, draggable to move its Position (`setTransform`). The full
  pan-behind anchor maths, the bounding box and the scale handles await the
  `LayerMap` (layer↔screen transform) port from `overlays.rs`.
- **Resolution picker — scale plumbing + realtime tier:** the Full/Half/Third/
  Quarter picker sits in the transport and drives `AppStateStub.previewScale`.
  The `PreviewSource` render path (perf-pass file) still renders at scale 1.0, so
  it must adopt `previewScale` to actually downsample. The realtime-tier readout
  is engine `RealtimeController` machinery the bridge does not run — it awaits the
  engine playback machinery.
- **Project panel — thumbnails:** the `thumbnail` bridge binding has now landed
  (`ThumbnailBridge`). Rendering it in the rows (async `DecodedFrame` → image,
  with a cache) is the remaining integration step.
- **Effects presets — `.lumfx`:** save/load cannot round-trip byte-compatibly
  from the snapshot, which flattens each effect's `EffectKey` (its namespace and
  version are dropped, only the match name survives) and each parameter's
  animation. A faithful preset awaits a preset bridge op (serialising the engine
  `EffectInstance`) or an `EffectInstance` read-back in the snapshot.
- **Effects drag-onto-layer — timeline seam:** an effect row is Draggable and the
  Effect controls panel is a `DragTarget` that applies it to the shown layer. The
  Timeline-row drop target awaits the timeline agent's `DragTarget` seam on the
  layer rows.
- **Effect controls — per-parameter stopwatch/navigator:** blocked on the bridge.
  There are only effect-param value setters (`setEffectParamScalar/Colour/Choice/
  Bool/Seed/Point`), no effect-param **keyframe** ops — so no stopwatch/navigator
  on effect params until those land. (The extra param kinds and the eyedropper
  did land this wave.)

## E — chrome and shell

_Value-field context menu, UI scale, splash boot log and the recovery modal
landed 2026-07-22 (section-E burn-down) — rows deleted. Two rows remain:_

- Tooltip breadth pass — **shell + widgets done** (2026-07-22): `LumitTooltip`
  now covers the status-line export-cancel button and the dock bare-pane drag
  grip (`shell/shell.dart`, `shell/dock_widget.dart`); the dock tab pop-out
  button already had one. Deliberately none (egui parity) on menu-bar items,
  the splash, command-palette rows and dock tab pills. **Split**: the remaining
  egui `on_hover_text` surfaces live in the timeline/editors agents' files —
  layer switches, transport step/loop, the ruler, the scopes header — and are
  those agents' rows, not this one.
- Pop out a panel into its own OS window (multi-window) — **BLOCKED, with
  evidence (2026-07-22)**. Verdict recorded on 05's F0 row and below. Kept as
  the graceful-degradation notice (`shell/shell.dart` `onPopOut`); no real
  window is opened, tests never spawn one.
  - The pinned SDK is **stable 3.44.7** (`flutter --version`). Its multi-window
    support exists only as `packages/flutter/lib/src/widgets/_window.dart` —
    every symbol is `@internal` (importing it fails `flutter analyze`) and each
    API throws `UnsupportedError` unless `isWindowingEnabled`, which reads
    `debugEnabledFeatureFlags.contains('windowing')` — a build-time flag OFF by
    default (`packages/flutter/lib/src/foundation/_features.dart`). The file's
    own header says "Do not import this file in production applications… switch
    to Flutter's main release channel." Enabling it would need a channel change
    + a feature flag + `@internal` use — all barred by the analyze gate and the
    pinned-SDK constraint.
  - The community route (`desktop_multi_window` and kin) gives each window its
    own Flutter engine/isolate, i.e. a **separate Dart heap** — so a popped-out
    panel could not host the body over the SAME `AppStateStub` (the F0 spec's
    requirement); it would need a serialising channel between engines, which is
    a different feature, not this one. Not added.
  - Re-attempt when the official windowing API ships on stable un-gated (track
    flutter/flutter#30701 / #142845).

## Stale rows to reconcile in 05 while burning down

- RECONCILED (2026-07-22, with the section-A burn-down): the graph-lens "→Rate
  drift figure dropped by BridgeReply" remainder was stale — `driftSeconds` is
  threaded and the notice reads "fitted, N ms drift"; 05's F3 graph-lens
  named-remainder has been updated to drop the drift-figure caveat.
