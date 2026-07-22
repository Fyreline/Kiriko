// The recovery modal (section E): the probe that decides whether to offer it,
// the three-option modal wired through the real calls, and the shell trigger
// with a fake bridge and injected file times (no real disk, no real window).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/bridge/bridge.dart';
import 'package:lumit_flutter/shell/recovery_dialog.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/theme/theme.dart';
import 'package:lumit_flutter/widgets/controls.dart';

/// A fake bridge that answers `listAutosaves`/`restoreJournal`/`openProject`
/// and records what it was asked to do; everything else is a benign ok snapshot.
class _RecoveryFake implements DocumentBridge, EditOpsBridge {
  _RecoveryFake({this.autosaves = const []});

  final List<BridgeAutosave> autosaves;
  final List<String> ops = [];

  BridgeSnapshot _snap() =>
      const BridgeSnapshot(items: [], canUndo: false, canRedo: false, path: null);

  @override
  BridgeReply snapshot() => BridgeReply.ok(_snap());

  @override
  BridgeReply openProject(String p) {
    ops.add('open:$p');
    return BridgeReply.ok(_snap());
  }

  @override
  List<BridgeAutosave> listAutosaves(String p) => autosaves;

  @override
  BridgeReply restoreJournal(String p) {
    ops.add('restore:$p');
    return BridgeReply.ok(_snap());
  }

  @override
  List<String> bootLog() => const ['lumit-bridge 0.7.0'];

  @override
  dynamic noSuchMethod(Invocation invocation) => BridgeReply.ok(_snap());
}

Widget _harness(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: LumitTheme.dark(),
        animationLevel: AnimationLevel.none,
        showTooltips: false,
        child: Overlay(
          initialEntries: [OverlayEntry(builder: (_) => child)],
        ),
      ),
    );

void main() {
  group('probeRecovery', () {
    const project = '/proj/scene.lum';
    const autosaves = [
      BridgeAutosave(slot: 1, path: '/proj/autosaves/scene.autosave-1.lum'),
      BridgeAutosave(slot: 2, path: '/proj/autosaves/scene.autosave-2.lum'),
    ];

    test('offers recovery when an autosave is newer than the save', () {
      final times = {
        project: DateTime(2026, 7, 22, 10, 0),
        autosaves[0].path: DateTime(2026, 7, 22, 10, 30),
        autosaves[1].path: DateTime(2026, 7, 22, 10, 5),
      };
      final r = probeRecovery(
        projectPath: project,
        autosaves: autosaves,
        mtimeOf: (p) => times[p],
      );
      expect(r.offer, isTrue);
    });

    test('declines when the save is newer than every autosave', () {
      final times = {
        project: DateTime(2026, 7, 22, 11, 0),
        autosaves[0].path: DateTime(2026, 7, 22, 10, 30),
        autosaves[1].path: DateTime(2026, 7, 22, 10, 5),
      };
      final r = probeRecovery(
        projectPath: project,
        autosaves: autosaves,
        mtimeOf: (p) => times[p],
      );
      expect(r.offer, isFalse);
    });

    test('declines when there are no autosaves', () {
      final r = probeRecovery(
        projectPath: project,
        autosaves: const [],
        mtimeOf: (_) => DateTime(2026),
      );
      expect(r.offer, isFalse);
    });
  });

  testWidgets('the modal wires each option through its callback', (tester) async {
    const autosaves = [
      BridgeAutosave(slot: 1, path: '/proj/autosaves/scene.autosave-1.lum'),
    ];
    var restored = false;
    var lastSave = false;
    BridgeAutosave? opened;

    await tester.pumpWidget(_harness(RecoveryDialog(
      autosaves: autosaves,
      onRestoreJournal: () => restored = true,
      onOpenLastSave: () => lastSave = true,
      onOpenAutosave: (a) => opened = a,
    )));

    expect(find.text('Recover changes'), findsOneWidget);

    await tester.tap(find.text('Restore journal'));
    await tester.pump();
    expect(restored, isTrue);

    await tester.tap(find.text('Open last save'));
    await tester.pump();
    expect(lastSave, isTrue);

    await tester.tap(find.textContaining('Slot 1'));
    await tester.pump();
    expect(opened, autosaves.first);
  });

  testWidgets('Escape resolves to Open last save (egui-neutral)',
      (tester) async {
    var lastSave = false;
    await tester.pumpWidget(_harness(RecoveryDialog(
      autosaves: const [],
      onRestoreJournal: () {},
      onOpenLastSave: () => lastSave = true,
      onOpenAutosave: (_) {},
    )));
    await tester.pump(); // let the modal's Focus autofocus
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(lastSave, isTrue);
  });

  testWidgets('maybeShowRecovery shows the modal and Restore hits the bridge',
      (tester) async {
    const project = '/proj/scene.lum';
    const autosaves = [
      BridgeAutosave(slot: 1, path: '/proj/autosaves/scene.autosave-1.lum'),
    ];
    final fake = _RecoveryFake(autosaves: autosaves);
    final app = AppStateStub(bridge: fake);

    late BuildContext ctx;
    await tester.pumpWidget(_harness(Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })));

    final shown = maybeShowRecovery(
      ctx,
      app,
      projectPath: project,
      mtimeOf: (p) => p == project
          ? DateTime(2026, 7, 22, 10, 0)
          : DateTime(2026, 7, 22, 10, 30),
    );
    expect(shown, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Recover changes'), findsOneWidget);

    await tester.tap(find.text('Restore journal'));
    await tester.pumpAndSettle();
    expect(fake.ops, contains('restore:$project'));
    // The modal is gone after a choice.
    expect(find.text('Recover changes'), findsNothing);
  });

  testWidgets('maybeShowRecovery is a no-op without a bridge', (tester) async {
    final app = AppStateStub(); // no bridge
    late BuildContext ctx;
    await tester.pumpWidget(_harness(Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })));
    final shown = maybeShowRecovery(ctx, app,
        projectPath: '/proj/scene.lum', mtimeOf: (_) => DateTime(2026));
    expect(shown, isFalse);
  });
}
