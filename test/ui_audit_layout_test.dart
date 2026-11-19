// PetLayout window math for petScale 0.6-1.6 with min/max panels.
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/pet_window.dart';

import 'ui_audit_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PetLayout: positive sizes, panel always fits, expanded >= collapsed', () {
    final panels = {
      'min': PetBrain.panelMin,
      'default': PetBrain.panelDefault,
      'max': PetBrain.panelMax,
    };
    for (var s = 0.6; s <= 1.6001; s += 0.1) {
      for (final e in panels.entries) {
        final l = PetLayout(s, e.value);
        final tag = 'scale ${s.toStringAsFixed(1)} panel ${e.key}';
        for (final z in [l.stage, l.collapsed, l.expanded]) {
          expect(z.width, greaterThan(0), reason: tag);
          expect(z.height, greaterThan(0), reason: tag);
          expect(z.width.isFinite && z.height.isFinite, isTrue, reason: tag);
        }
        // panel container is panel.width wide + 20 margin, and sits under bubble+stage with a 10px bottom margin
        expect(l.expanded.width, greaterThanOrEqualTo(e.value.width + 20), reason: '$tag width');
        expect(l.expanded.width, greaterThanOrEqualTo(l.stage.width), reason: '$tag stage width');
        expect(l.expanded.height, greaterThanOrEqualTo(PetLayout.bubbleH + l.stage.height + e.value.height + 10), reason: '$tag height');
        expect(l.expanded.height, greaterThan(l.collapsed.height), reason: tag);
        expect(l.collapsed.width, greaterThanOrEqualTo(220), reason: tag);
      }
    }
  });

  testWidgets('PetBrain.setPanelSize clamps', (t) async {
    await auditSetUp(t);
    final b = PetBrain();
    b.setPanelSize(-5, -5);
    expect(b.panelW, PetBrain.panelMin.width);
    expect(b.panelH, PetBrain.panelMin.height);
    b.setPanelSize(1e9, 1e9);
    expect(b.panelW, PetBrain.panelMax.width);
    expect(b.panelH, PetBrain.panelMax.height);
    b.setPanelSize(400, 400);
    expect(b.panelW, 400);
    b.dispose();
  });

  testWidgets('the expanded window at petScale 1.6 + max panel fits a 1440x900 screen? (info)', (t) async {
    const l = PetLayout(1.6, PetBrain.panelMax);
    // Not an assertion on product intent, just recorded for the report.
    // ignore: avoid_print
    print('scale1.6+max panel expanded=${l.expanded}  scale0.6+min=${const PetLayout(0.6, PetBrain.panelMin).expanded}');
  });
}
