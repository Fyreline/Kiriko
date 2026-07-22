// The recovery modal (egui `dialogs.rs::recovery_modal`, docs/10 §4). On launch
// with a live bridge, when the project's autosaves look newer than its last save
// — the signal that the last session ended without saving — the shell offers to
// recover: replay the interrupted crash journal, keep the last save, or open one
// of the rotating autosaves.
//
// egui's three options are Restore / Open last save / Open autosave (the single
// latest). The bridge exposes the WHOLE autosave list (`list_autosaves`), so the
// Flutter modal lists every slot rather than only the newest — the ledger E row
// asked for the list, and it is a faithful superset of the doc's third option.
//
// Two honesties, recorded on the ledger E row:
//  * The bridge's `restore_journal` REPLAYS the journal as it applies — there is
//    no non-destructive "does a journal exist?" probe — so the modal cannot be
//    triggered by journal existence and cannot show a change count up front. It
//    is triggered by the checkable signal (an autosave newer than the save), and
//    the Restore-journal reply's own count surfaces after the fact.
//  * "Open an autosave" loads the autosave content but remembers the real
//    project as the last project, mirroring egui; the engine's loaded path still
//    follows the autosave until the bridge grows a load-but-keep-path op (see
//    `AppStateStub.openPath`).
//
// egui's window has no Escape/close affordance — the user must pick one of the
// three. The Flutter modal mirrors that (the scrim does not dismiss) but treats
// Escape as "Open last save", the neutral, non-destructive choice, so a keyboard
// user is never trapped — a benign enhancement, not a behaviour change.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import '../state/app_state.dart';
import '../widgets/controls.dart';

/// The outcome of probing whether recovery should be offered.
class RecoveryProbe {
  /// Whether the modal should be shown.
  final bool offer;

  /// The autosaves found beside the project (newest first, as the bridge lists).
  final List<BridgeAutosave> autosaves;

  const RecoveryProbe({required this.offer, required this.autosaves});
}

/// Decide whether to offer recovery: true when a rotating autosave is newer than
/// the project's own file (the last save), the checkable stand-in for "the last
/// session ended without saving". Pure and injectable — [mtimeOf] returns a
/// file's last-modified time (or null when it cannot be read), so the whole
/// decision is unit-testable without touching the disk.
RecoveryProbe probeRecovery({
  required String projectPath,
  required List<BridgeAutosave> autosaves,
  required DateTime? Function(String path) mtimeOf,
}) {
  if (autosaves.isEmpty) {
    return RecoveryProbe(offer: false, autosaves: autosaves);
  }
  final projectMtime = mtimeOf(projectPath);
  DateTime? newestAuto;
  for (final a in autosaves) {
    final m = mtimeOf(a.path);
    if (m != null && (newestAuto == null || m.isAfter(newestAuto))) {
      newestAuto = m;
    }
  }
  final offer = newestAuto != null &&
      (projectMtime == null || newestAuto.isAfter(projectMtime));
  return RecoveryProbe(offer: offer, autosaves: autosaves);
}

/// A file's last-modified time, or null when it cannot be read.
DateTime? fileMtime(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) return f.lastModifiedSync();
  } catch (_) {}
  return null;
}

/// Probe and, when warranted, show the recovery modal over the app Overlay.
/// Returns true when the modal was shown. A no-op without a bridge, without a
/// project path, or when the probe declines. [mtimeOf] is injectable for tests.
bool maybeShowRecovery(
  BuildContext context,
  AppStateStub app, {
  required String? projectPath,
  DateTime? Function(String path)? mtimeOf,
}) {
  if (projectPath == null || app.bridge == null) return false;
  final autosaves = app.listAutosaves(projectPath);
  final probe = probeRecovery(
    projectPath: projectPath,
    autosaves: autosaves,
    mtimeOf: mtimeOf ?? fileMtime,
  );
  if (!probe.offer) return false;
  showRecoveryDialog(
    context,
    app,
    projectPath: projectPath,
    autosaves: probe.autosaves,
  );
  return true;
}

/// Insert the recovery modal into the app Overlay, wiring each option through
/// the real calls. Returns the entry (removed when a choice is made).
OverlayEntry showRecoveryDialog(
  BuildContext context,
  AppStateStub app, {
  required String projectPath,
  required List<BridgeAutosave> autosaves,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => RecoveryDialog(
      autosaves: autosaves,
      onRestoreJournal: () {
        close();
        app.restoreJournal(projectPath);
      },
      onOpenLastSave: () {
        // The last save is already the loaded document (reopened at launch), so
        // this simply dismisses and keeps it — egui's resolve_recovery(false).
        close();
      },
      onOpenAutosave: (a) {
        close();
        app.openPath(a.path, rememberAs: projectPath);
      },
    ),
  );
  overlay.insert(entry);
  return entry;
}

/// The modal card itself. Stateless over its callbacks so it can be pumped and
/// driven directly in a widget test.
class RecoveryDialog extends StatefulWidget {
  final List<BridgeAutosave> autosaves;
  final VoidCallback onRestoreJournal;
  final VoidCallback onOpenLastSave;
  final void Function(BridgeAutosave) onOpenAutosave;

  const RecoveryDialog({
    super.key,
    required this.autosaves,
    required this.onRestoreJournal,
    required this.onOpenLastSave,
    required this.onOpenAutosave,
  });

  @override
  State<RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<RecoveryDialog> {
  final FocusNode _focus = FocusNode(debugLabel: 'recovery-modal');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onOpenLastSave();
      return KeyEventResult.handled;
    }
    // A modal absorbs the rest so shell shortcuts do not fire underneath it.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // A dimming scrim that does NOT dismiss — a genuine modal, like the
          // egui window that stays until a button is pressed (the theme's own
          // backdrop colour, as the other dialogues use).
          Positioned.fill(
            child: ModalBarrier(color: t.modalBackdrop, dismissible: false),
          ),
          Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(t.tokens.floatRadius),
                border: Border.all(color: t.hairline),
                boxShadow: t.floatShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recover changes', style: t.heading),
                  const SizedBox(height: 8),
                  Text(
                    'The last session may have ended without saving. Restore the '
                    'interrupted changes, keep the last saved version, or open an '
                    'autosave.',
                    style: t.body.copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      HouseButton(
                        onPressed: widget.onRestoreJournal,
                        child: const Text('Restore journal'),
                      ),
                      HouseButton(
                        onPressed: widget.onOpenLastSave,
                        child: const Text('Open last save'),
                      ),
                    ],
                  ),
                  if (widget.autosaves.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Open an autosave',
                        style: t.small.copyWith(color: t.textMuted)),
                    const SizedBox(height: 4),
                    for (final a in widget.autosaves)
                      MenuRow(
                        onPressed: () => widget.onOpenAutosave(a),
                        child: Text(_autosaveLabel(a)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A friendly label for a slot: its number and the file name (slot 1 newest).
  static String _autosaveLabel(BridgeAutosave a) {
    final name = a.path.split(RegExp(r'[\\/]')).last;
    return a.slot == 1 ? 'Slot ${a.slot} (newest) — $name' : 'Slot ${a.slot} — $name';
  }
}
