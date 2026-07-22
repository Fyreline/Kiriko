// Regression for desk-test round 3: the Viewer placeholder must name the
// live state, never show the stale "the composited comp arrives when the
// compositor leaves the egui crate" promise (comp rendering has been live
// since K-175/K-177).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumit_flutter/panels/viewer_panel.dart';
import 'package:lumit_flutter/state/app_state.dart';
import 'package:lumit_flutter/theme/theme.dart';
import 'package:lumit_flutter/widgets/controls.dart';

Widget _host(AppStateStub app) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: LumitTheme.dark(),
        animationLevel: AnimationLevel.none,
        showTooltips: false,
        child: Overlay(
          initialEntries: [
            OverlayEntry(builder: (_) => ViewerPanel(app: app)),
          ],
        ),
      ),
    );

void main() {
  testWidgets('without an engine library the placeholder says so',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    final app = AppStateStub();
    await tester.pumpWidget(_host(app));
    await tester.pump();

    expect(
      find.textContaining('No engine library loaded'),
      findsOneWidget,
      reason: 'the placeholder names the real reason',
    );
  });

  testWidgets('the stale future-work promise never renders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    final app = AppStateStub();
    await tester.pumpWidget(_host(app));
    await tester.pump();

    expect(
      find.textContaining('compositor leaves the egui crate'),
      findsNothing,
      reason: 'desk-test round 3: comps render; the old promise is a defect',
    );
    expect(find.textContaining('Single-layer preview —'), findsNothing);
  });
}
