import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'edition.dart';
import 'services/pet_brain.dart';
import 'widgets/clip_player.dart';
import 'widgets/pet_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final windowOptions = WindowOptions(
    size: Size(300, 348),
    minimumSize: Size(150, 150),
    backgroundColor: Colors.transparent,
    // Sold editions are a normal app (Dock icon + menu bar with the app name);
    // only the owner's own build hides from the Dock (App Review 4.0).
    skipTaskbar: Ed.current == Edition.personal,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true, // App Review 4.0: a window needs its title bar buttons
    alwaysOnTop: true,
  );
  await windowManager.setResizable(false); // sized from PetLayout only
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });

  final brain = PetBrain();
  await brain.init(); // also picks the character pack
  await PetClips.load();
  if (brain.demo) {
    // Promo recording stage: fixed 1080x1920 window (see DemoStage).
    await windowManager.setSize(const Size(1080, 1920));
    await windowManager.setPosition(Offset(brain.demoX, 100));
  } else {
    await PetLayout.apply(brain); // window size follows the saved pet size
    if (brain.startAt != null) await windowManager.setPosition(brain.startAt!);
  }
  runApp(HoodimateApp(brain: brain));
}

class HoodimateApp extends StatelessWidget {
  final PetBrain brain;
  const HoodimateApp({super.key, required this.brain});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hoodimate',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5E6C8)),
        fontFamily: '.AppleSystemUIFont',
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: PetWindow(brain: brain),
      ),
    );
  }
}
