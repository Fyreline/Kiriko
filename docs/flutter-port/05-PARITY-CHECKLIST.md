# 05 — Parity checklist (living)

The tick-list for the one-for-one port. Updated in the same commit as the work,
newest state wins. ☐ to do · ◐ partial (remainder named) · ☑ done (with tests
where the row is logic).

## Phase F0 — scaffold and chrome

- ☑ Flutter project scaffolded (`flutter_ui/`, package `lumit_flutter`), analyzer clean
- ☑ Theme port: all 7 colour schemes digit-for-digit, ShapeTokens SHARP/ROUND,
  `with_accent` hover shift by mode, `label_colour`, `document_colour`,
  AnimationLevel durations — unit-tested against the Rust values
- ☑ Inter Medium bundled; type scale 16/12/12/11/12
- ☑ Icon set: 44 variants mapped to Iconoir, motion-blur mark as a CustomPainter
- ☑ Settings model: Performance / Autosave / Interface / Export defaults matching
  the engine constants — unit-tested
- ☑ Workspace persistence to JSON (schemes, shape, accent, animation, settings,
  dock layout)
- ☑ Dock: tree model (splits/tabs/panes) + default workspace byte-matching
  `default_layout()` shares — unit-tested; resizable dividers; tab pills with
  the three-state styling; solo panes bare
- ☑ Dock: drag a tab / bare-pane grip to re-dock — model + interaction, unit-
  and widget-tested (movePanel/simplify with the every-panel-once invariant; a
  ghost pill, drop-zone previews and commit-on-release over both shapes)
- ☑ Bare-pane affordances: right-click "Pop out into its own window" (surfaces
  the multi-window notice for now); the corner drag grip built (2×3 dot grid,
  drags the pane exactly like a tab)
- ☐ Pop out a panel into its own OS window (multi-window; deferred, see 04)
- ☑ Menu bar: File / Edit / Composition / Window with the full shipped item set
  (engine-backed items dispatch to the stub state and surface a notice)
- ☑ Status line: notices, error tint rule, export-progress slot
- ☑ Settings window: all five pages, every control, fixed geometry, opens on
  Appearance; scheme/shape/accent/motion apply live
- ☑ Accent colour picker (HSV square + hue strip + hex), reusable for the
  future editor-colour submenu
- ☑ Command palette: modal, fuzzy filter, keyboard selection, the shipped
  command list (incl. the hidden export alias)
- ☑ Shortcut routing: the §5 inventory table wired to the stub state, with the
  text-field focus gate
- ☑ Panel stubs: all seven panels with real chrome (Viewer surround, scope
  graticule placeholder, timeline strip skeleton) so the workspace reads right
- ☑ Splash boot card (K-008: centred card, boot lines, click to skip; the
  engine's real boot log streams in at F1) — widget-tested
- ☑ Active-panel accent edge (last click wins, one pane at a time) —
  widget-tested
- ☐ Sharp/Round: Round cards ☑ (fill, radius, padding, gap, shadow); window
  inset ☑; resize-gap hover/drag tinting ☑

## Phase F1 — bridge (in progress)

- ◐ `lumit-bridge` crate ☑ (bridge v0: hand-rolled JSON over a C ABI, loaded
  over `dart:ffi`; catch_unwind on every export, Rust-owned strings freed via
  `lumit_bridge_free_string`, single-client `Mutex` state; in-crate tests).
  flutter_rust_bridge codegen ☐ — deferred until the API surface stabilises
  (bridge v0 is hand-rolled JSON over C ABI, see 03-ARCHITECTURE §Bridge v0)
- ☑ Project open/save/snapshot/ops. Live: new project, open (`.lum`), save (to
  the loaded path, or a save dialogue when the project has no path yet — the
  egui Save behaviour, no separate Save As), document snapshot (item tree +
  can_undo/can_redo + path), new composition through the real op/undo path,
  undo/redo
- ☑ File dialogues (the `file_selector` plugin): Open project (`.lum` filter),
  Save (falls through to a save dialogue with `untitled.lum` when unsaved),
  Import footage (multi-select, filter mirrors the egui import list). Dialogue
  calls route through injectable seams so widget tests stub paths without
  plugin channels
- ☑ Import footage → `lumit_bridge_import_footage`: one footage item per file
  through the real AddItem/undo path (no auto-folder, mirroring the egui
  frontend); one calm notice for N imported, failures in the error tint. No
  media probing yet (probing/thumbnails are F2)
- ☑ Reopen the last project on launch: the workspace persists `lastProjectPath`
  (set on open/save-with-path), and a live bridge reopens it when the file is
  still on disk — a missing or unreadable file degrades to a calm status-line
  notice, never a crash
- ◐ Project panel live: item tree + type icons (footage/folder/composition/
  solid) with layer-colour tints and nesting, empty-document hint, hover fill.
  Not yet: thumbnails, relink, missing badge, selection/drag
- ☐ Session restore *within* a project (open comps, playhead, selection) — the
  per-project session the egui shell restores on open; F1 restores only which
  project file reopens, not its saved session

## Phase F2 — Viewer (in progress)

- ☐ Shared-texture path (D3D11 interop) + `Texture` widget. BLOCKED on the same
  compositor extraction as the composited-comp preview below — the frame to
  share does not exist outside the egui crate yet
- ☐ Composited-comp preview (all layers, transforms, effects). BLOCKED: the
  compositor still lives in `crates/lumit-ui`; until it is extracted into a
  shared crate, Flutter can only decode single footage frames, not composite
  them. The Viewer's preview is honestly labelled single-layer everywhere
- ☑ CPU RGBA fallback — **single-layer footage preview** (honest wording). The
  Viewer resolves the front comp's topmost visible footage layer whose span
  covers the playhead, maps comp-frame → source-frame by straight offset
  (Retime is not in the snapshot yet — noted in code), decodes one frame via
  `decodeFrame` through a shared `PreviewSource` (throttled to one decode per
  painted frame, an 8-entry `ui.Image` LRU), and blits it fit-to-panel on the
  neutral surround. NB the snapshot layer carries no source-item id, so the
  layer is matched to its footage item by name (documented limitation). Unit-
  and widget-tested. `preview_source.dart`, `viewer_panel.dart`
- ◐ Transport: play/pause on a Ticker at the comp's rational fps, looping the
  composition (mirrors the egui transport, which loops the work area); frame +
  SMPTE timecode readout; `Full` resolution label as-is. Remaining: the
  resolution ladder is engine-side (a later phase), so the label is static

## Bridge v0.2 data + ops (done, feeds F2/F3/F4)

- ☑ Snapshot v2 (additive): comps carry `{width,height,fps,frame_count,layers,
  markers}`; footage carries `status` (ok/missing/unprobed/failed) and, once
  probed, `media` `{duration_frames,fps,width,height,audio}`. Frames are integers
  from the comp's own rate (rational time). Layer `kind`/`switches` mirror the
  model names. Typed Dart classes (`BridgeComp`/`BridgeLayer`/`BridgeSwitches`/
  `BridgeMedia`/`BridgeFps`) parse it; `AppStateStub.frontComp` resolves the
  active comp
- ☑ Layer/transform/marker ops through the real undo path: `set_layer_switch`,
  `edit_layer_span`, `set_transform`, `add_marker` (each one `lumit-core` op, one
  undo step, full snapshot back). Dart pass-throughs refresh the snapshot and
  surface failures on the error tint
- ◑ Footage probing on import/open (`media` feature): resolution, rate, frame
  count and status carried in the snapshot; missing files probe to `missing`,
  never an error. Synchronous at this phase; not yet off-thread, no thumbnails
- ◐ Transport ☑ (play/pause, frame + timecode, `Full` label); resolution picker
  + realtime tier readout ☐ (the ladder is engine-side, a later phase)
- ☑ Missing-footage slate: generated colour bars (band-for-band from
  `lumit-media/src/slate.rs`, drawn from `documentColour`, never a bundled
  asset) with the item path overlaid; a present-but-unreadable file shows a
  dark "unreadable" slate (docs/07 §3.3). `slate.dart`
- ☑ Scopes over the shown frame: Waveform (luma), Waveform (RGB), Vectorscope,
  Histogram — chosen in a `BareDropdown`, drawn on the fixed `ScopeColours`
  (never the theme), reading the same decoded pixels as the Viewer through the
  shared `PreviewSource`; the trace is built off the build path (256×256 image,
  rebuilt only when the shown frame or the scope changes) and the last trace is
  held when a frame is momentarily unavailable (K-130). Scope maths ported
  one-for-one from `scopes.rs` and unit-tested. `scopes_panel.dart`,
  `scope_maths.dart`
- ☐ Eyedropper magnifier; transform overlays

## Phase F3 — Timeline (in progress)

- ☑ Comp-tab strip: one pill per composition in the snapshot (three-state fill,
  a local copy of the dock tab styling), clicking fronts that comp
  (`AppStateStub.frontCompId` + `frontCompSelect`); the current-time readout
  (frame + seconds at comp fps) sits at the strip's right
- ☑ Two-row time ruler over the lane: the full-height band (owner design change,
  see post-parity item 2), zoom-adaptive frame/second ticks + labels, markers as
  small flags, click/drag anywhere scrubs the playhead (`goToFrame`); the
  playhead is an accent line over ruler and lanes — unit-tested (tick density,
  scrub) + widget-tested
- ☑ Layer rows (22 px): outline column (fixed 260 px) with layer index, type
  glyph + 3 px colour tab, ellipsised name, and the switch cluster (eye, speaker
  — footage/sequence/precomp only, solo, lock, fx, motion blur, 3D, collapse),
  each toggling through `setLayerSwitch`; muted/hidden rows dim their name
- ☑ Outline degradation order (owner design change, see post-parity item 3):
  switches drop collapse/3D → fx/MB → solo → speaker → index as the column
  narrows, never overlapping; glyph + name + eye survive longest — unit-tested
- ☑ Clip bars on the lane: type-colour wash + 3 px tab + hairline edge (accent
  when selected); click a bar or outline row selects (`selectedLayer`, now a
  layer-id String); drag the body to move (one `move_in` op — see the SpanEdit
  note below), drag the 6 px edge handles to trim (`trim_in`/`trim_out`);
  snapping rounds drags to whole seconds and marker frames — widget-tested
- ☑ Bottom bar: zoom − / + / Fit + percentage readout, magnet snap toggle, graph
  lens toggle (kept from the F0 skeleton, zoom readout corrected to `zoom×100`)
- ☐ Remainder (still open): keyframe lanes (glyphs, drag, copy/paste), outline
  twirls + Transform/Effects property rows, the graph lens, matte/blend/parent
  columns, layer context menu + rename/duplicate/delete, layer search + hide
  toggle, the top-row MB-master toggle, beat markers/cache bar, sequence sub-bars
  and the overrun HOLD hatch, work area (the snapshot carries none yet),
  horizontal scroll/pan + scrollbar when zoomed, resizable outline column

## Phase F4 — editors (in progress)

Effect controls rows · keyframe navigators · channel picker · Effects & presets
(.lumfx) · Scopes (waveform/vectorscope/histogram) · Hierarchy · Export
dialogue + queue · Comp settings · Add mask · Recovery modal

First slice (2026-07-21):

- ☑ Hierarchy: the front comp's layer tree — comp header (accent glyph + name),
  layers indented with the layer-type glyph/colour, precomp rows twirl open to
  reveal the nested comp's layers, click selects a layer by its stable id.
  `hierarchy_panel.dart`, widget-tested. Nesting is resolved by matching the
  precomp layer's *name* against the project's compositions, because snapshot v2
  tags a precomp only as `kind:"precomp"` and carries no source-comp id (cycle-
  guarded by name); snapshot v3 should carry the id (then match by id, and
  comp-scoped selection becomes possible). The full project flowchart / node
  graph is later.
- ◐ Effect controls: the selected layer's **Transform** rows in the settings-card
  style — Anchor point (x,y), Position (x,y[,z when 3D]), Scale (x,y with a link
  toggle), Rotation, Opacity (and Rotation x/y when 3D), each committing through
  `app.setTransform` (one undo step). `effect_controls_panel.dart`, widget-
  tested. **Values-on-read pending snapshot v3**: the snapshot carries no current
  transform values yet, so a box shows the value set this session and an em-dash
  before any edit, with a one-line hint saying so. Open: effects stacks,
  keyframes/stopwatches, the linked-scale ratio (the link sets both axes to the
  same value until value read-back), and commit-on-release for the drag (today's
  `DragValueField` commits each drag step; typing commits once).
- ◐ Comp settings: the composition-settings / new-composition dialogue in the
  Settings-window visual style (name, size, frame-rate preset dropdown,
  duration), shown through the app Overlay. `dialogs.dart`, wired from the
  Composition menu, widget-tested. **UI real, bridge op pending**: New
  composition commits the *name* through the real `app.newComposition` op; size /
  frame rate / duration and the whole Composition-settings apply are honestly
  stubbed (`app.engine('Set composition settings (bridge op pending)')`) until a
  comp-settings bridge op lands.
- ☐ Add mask ▸ Rectangle/Ellipse/Star: still routes to `app.engine` (mask ops
  are not in the bridge); the submenu reads correctly.

## Post-parity fixes (owner's known rough edges — do NOT fix during the port)

Collected here as they come up so parity stays honest. Behavioural changes wait
until parity; the pure *defects* in this list (marked "defect") are different —
the port should simply not have them, and their absence must not be read as a
deviation when the two frontends are compared side by side.

Recorded 2026-07-21, from the owner:

1. **Settings dialogue z-order (defect).** In the egui Settings window (and
   similar surfaces), text can get stuck rendering behind input boxes. The
   Flutter port must keep labels and controls in one layout flow so nothing
   can overlap; do not reproduce.
2. **Timeline ruler height (design change, post-parity or at F3 build time).**
   The time ruler above the lane area should span the full two-row band —
   the egui frontend draws it one row tall even though the mouse-interaction
   region already covers both rows. Decide at F3: build the Flutter ruler
   two rows tall from the start (the owner's stated intent) and note the
   deliberate deviation here when done.
   → Built into the F3 timeline from the start (recorded deviation): the ruler
   band spans the full two-row height, labels up top, ticks below.
3. **Layer-area overcrowding (design change, F3).** The timeline's layer
   outline handles small panel sizes badly — switches, buttons and labels
   start overlapping as the column shrinks. The Flutter layer area needs a
   real degradation order (truncate/hide columns before anything overlaps).
   Design it during F3 rather than copying the egui behaviour.
   → Built into the F3 timeline from the start (recorded deviation): the outline
   measures its width and drops switches collapse/3D → fx/MB → solo → speaker →
   index, never overlapping; glyph + name + eye survive longest.
4. **Value boxes clip their row (defect).** DragValue-style value boxes
   across most of the egui UI clip at the bottom of the row they sit on.
   The Flutter `DragValueField` must size rows to fit their controls; do
   not reproduce. Owner notes there are probably more of this kind — add
   them here as they surface.

5. **Full editor-colour customisation (design change, post-parity).** The
   accent picker should eventually live in a more advanced appearance
   submenu where every editor colour can be edited, not just the accent
   (owner, 2026-07-21; matches the long-standing theme-customisation wish).
   The single accent picker stays until then.

## Known deliberate deviations

- No migration of the eframe-persisted workspace; the Flutter frontend starts
  from defaults (03-ARCHITECTURE §Persistence).
- The Settings window opens on General, not Appearance (owner request,
  2026-07-21).
- The splash is not skippable by click (matches egui, where the boot card is
  the window; an early click-to-skip experiment was removed on owner
  feedback, 2026-07-21).
- Menus animate per AnimationLevel (egui's could not animate at all).
- macOS native menu bar deferred with the rest of the macOS pass.
