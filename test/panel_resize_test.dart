import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/pet_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('panel size is clamped and drives the window size', () {
    final b = PetBrain();
    b.setPanelSize(5000, 50);
    expect(b.panelW, PetBrain.panelMax.width);
    expect(b.panelH, PetBrain.panelMin.height);

    b.setPanelSize(600, 700);
    final small = PetLayout(b.petScale).expanded;
    final big = PetLayout.of(b).expanded;
    expect(big.width, 620); // panel + 20 margin
    expect(big.height - small.height, 700 - PetBrain.panelDefault.height);
    // closing the panel doesn't depend on its size
    expect(PetLayout.of(b).collapsed, PetLayout(b.petScale).collapsed);
  });
}
