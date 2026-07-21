// Modal dialogues driven from the menu bar (phase F4): the composition
// settings / new-composition dialogue and the shared modal scaffold.
//
// The dialogues are real chrome in the Settings-window visual style; some of
// what they collect is not yet wired to the engine, and that is stated
// honestly (K-007). Composition settings has no bridge op at all: on OK it
// records the intent through `app.engine(…)` and closes — the UI is real, the
// commit is a stub. New composition commits the name through the real
// `app.newComposition` op; size, frame rate and duration await a comp-settings
// bridge op and are noted as pending in the dialogue.
//
// The dialogue is shown through the app's Overlay (like the menus and
// dropdowns) rather than shell state, so it needs no shell wiring. A dimmed
// backdrop eats clicks and closes on tap; Cancel/OK close from the buttons.

import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import '../widgets/controls.dart';

/// The frame-rate presets the egui composition dialogue offers (dialogs.rs).
/// The egui dialogue also accepts free-typed rates (e.g. 29.9997); this slice
/// offers the preset dropdown only.
const List<double> kFpsPresets = [
  23.976,
  24.0,
  25.0,
  29.97,
  30.0,
  50.0,
  59.94,
  60.0,
  120.0,
];

/// Open the composition-settings dialogue (edit an existing comp). The commit
/// is honestly stubbed — there is no comp-settings bridge op yet.
Future<void> showCompositionSettingsDialog(
  BuildContext context,
  AppStateStub app,
) =>
    _showModal(
      context,
      (close) => _CompDialog(app: app, creating: false, close: close),
    );

/// Open the new-composition dialogue. On OK the name commits through the real
/// `app.newComposition` op.
Future<void> showNewCompositionDialog(
  BuildContext context,
  AppStateStub app,
) =>
    _showModal(
      context,
      (close) => _CompDialog(app: app, creating: true, close: close),
    );

/// Insert a centred modal into the app Overlay with a dimmed, click-to-dismiss
/// backdrop. Completes when the dialogue closes.
Future<void> _showModal(
  BuildContext context,
  Widget Function(VoidCallback close) builder,
) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  var done = false;
  void close() {
    if (done) return;
    done = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      final t = ThemeScope.of(context).theme;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: Container(color: t.modalBackdrop),
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: () {}, // swallow clicks inside the dialogue
              child: builder(close),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return Future<void>.value();
}

class _CompDialog extends StatefulWidget {
  final AppStateStub app;

  /// Creating a new comp (title "New composition", button "Create") versus
  /// editing settings ("Composition settings", "Apply").
  final bool creating;
  final VoidCallback close;

  const _CompDialog({
    required this.app,
    required this.creating,
    required this.close,
  });

  @override
  State<_CompDialog> createState() => _CompDialogState();
}

class _CompDialogState extends State<_CompDialog> {
  // Defaults mirror the egui new-comp dialogue (compositions.rs
  // open_new_comp_dialog): 1920×1080, 60 fps, 30 s.
  late final TextEditingController _name = TextEditingController(text: 'Comp');
  final FocusNode _nameFocus = FocusNode();
  int _width = 1920;
  int _height = 1080;
  double _fps = 60.0;
  int _durationS = 30;

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.creating) {
      // Commit the name through the real op; size/fps/duration await a
      // comp-settings bridge op (noted in the dialogue and the checklist).
      widget.app.newComposition(_name.text.trim());
    } else {
      // No comp-settings bridge op yet — record the intent honestly and close.
      widget.app.engine('Set composition settings (bridge op pending)');
    }
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(t.tokens.floatRadius),
        border: Border.all(color: t.hairline),
        boxShadow: t.floatShadow,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.creating ? 'New composition' : 'Composition settings',
            style: t.heading,
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: t.hairline),
          const SizedBox(height: 8),
          _DialogRow(
            label: 'Name',
            control: _NameField(controller: _name, focus: _nameFocus),
          ),
          _DialogRow(
            label: 'Size',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragValueField(
                  value: _width,
                  min: 16,
                  max: 16384,
                  speed: 8,
                  onChanged: (v) => setState(() => _width = v.round()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('×', style: t.small),
                ),
                DragValueField(
                  value: _height,
                  min: 16,
                  max: 16384,
                  speed: 8,
                  onChanged: (v) => setState(() => _height = v.round()),
                ),
              ],
            ),
          ),
          _DialogRow(
            label: 'Frame rate',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BareDropdown<double>(
                  value: _fps,
                  options: kFpsPresets,
                  label: _fpsLabel,
                  onChanged: (v) => setState(() => _fps = v),
                ),
                const SizedBox(width: 6),
                Text('fps', style: t.small),
              ],
            ),
          ),
          _DialogRow(
            label: 'Duration',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragValueField(
                  value: _durationS,
                  min: 1,
                  max: 86400,
                  onChanged: (v) => setState(() => _durationS = v.round()),
                ),
                const SizedBox(width: 6),
                Text('sec', style: t.small),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.creating
                ? 'Size, frame rate and duration apply once the '
                    'composition-settings bridge op lands; the name commits now.'
                : 'Applying is stubbed until the composition-settings bridge op '
                    'lands.',
            style: t.small.copyWith(color: t.textDisabled),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              HouseButton(
                onPressed: widget.close,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              HouseButton(
                onPressed: _confirm,
                child: Text(widget.creating ? 'Create' : 'Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Frame-rate label: a whole rate reads as an integer, a fractional one keeps
/// its decimals (23.976, 29.97).
String _fpsLabel(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// One label-left / control-right dialogue row (the Settings-window row style).
class _DialogRow extends StatelessWidget {
  final String label;
  final Widget control;
  const _DialogRow({required this.label, required this.control});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyPrimary)),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
  }
}

/// The name text field, in the Settings-window text-box style.
class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  const _NameField({required this.controller, required this.focus});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface0,
        borderRadius: BorderRadius.circular(t.tokens.controlRadius),
        border: Border.all(color: t.hairline),
      ),
      child: EditableText(
        controller: controller,
        focusNode: focus,
        style: t.bodyPrimary,
        cursorColor: t.accent,
        backgroundCursorColor: t.surface2,
        selectionColor: t.accent.withValues(alpha: 0.5),
      ),
    );
  }
}
