// Renders the panels to test/tmp/ui_audit/*.png for eyeballing (not assertions).
// Run: flutter test test/ui_audit_png_test.dart --dart-define=EDITION=store
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/panel_theme.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/care_panel.dart';
import 'package:hoodimong/widgets/chat_panel.dart';
import 'package:hoodimong/widgets/settings_panel.dart';

import 'ui_audit_helpers.dart';

Future<void> shot(WidgetTester t, PetBrain b, String name, Widget Function() panel,
    {Size panelSize = PetBrain.panelDefault, String tab = 'Chat', bool scrollBottom = false, double? tall}) async {
  final theme = PanelTheme.byId(b.panelTheme);
  final key = GlobalKey();
  final inner = tabBody(panelSize);
  final h = tall ?? inner.height;
  setView(t, Size(panelSize.width + 40, h + 90));
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: auditTheme(),
    home: Material(
      color: const Color(0xFFCCCCCC),
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: panelSize.width,
              height: h + 51,
              decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.border, width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  height: 36,
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  decoration: BoxDecoration(color: theme.tabBg, borderRadius: BorderRadius.circular(18)),
                  alignment: Alignment.center,
                  child: Text('$tab   (tab bar stand-in)', style: TextStyle(color: theme.label, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
                Expanded(child: panel()),
              ]),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump(const Duration(milliseconds: 300));
  if (scrollBottom) {
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    s.position.jumpTo(s.position.maxScrollExtent);
    await t.pump(const Duration(milliseconds: 200));
  }
  await t.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('test/tmp/ui_audit/${Ed.current.name}_$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

void seed(PetBrain b, String lang) {
  final p = b.memory.active;
  p.chat.clear();
  final now = DateTime.now();
  final long = lang == 'zh'
      ? '今天的天气真不错呀，我们一起去公园散步吧，然后顺便买一杯热乎乎的奶茶回来慢慢喝，好不好？我还想在回家的路上给你拍很多很多照片，把今天的好心情都留下来，以后翻出来看的时候一定会笑出声。'
      : lang == 'ko'
          ? '오늘 날씨가 너무 좋아서 같이 공원에 산책 가고 싶어요! 돌아오는 길에 따뜻한 차도 한 잔 사 와서 천천히 마시면 좋겠어요. 사진도 많이 찍어서 나중에 보면서 웃자요.'
          : 'The weather is so lovely today, shall we walk to the park together and grab a warm drink on the way home? Supercalifragilisticexpialidocious_unbroken_long_word_test.';
  p.chat.addAll([
    ChatMessage(text: long, fromUser: true, at: now),
    ChatMessage(text: lang == 'zh' ? '好呀好呀！' : lang == 'ko' ? '좋아요!' : 'Yay, let\'s go!', fromUser: false, at: now),
    ChatMessage(text: long, fromUser: false, at: now),
    ChatMessage(text: 'Hi', fromUser: true, at: now, sticker: 'hello'),
  ]);
}

void main() {
  testWidgets('png: tabs, languages, sizes, themes (${Ed.current.name})', (t) async {
    await auditSetUp(t);
    ignoreMissingPlugins();
    final b = newBrain();
    Lang.code = 'en';
    seed(b, 'en');
    await shot(t, b, 'en_default_chat', () => ChatPanel(brain: b), tab: 'Chat');
    await shot(t, b, 'en_default_care', () => CarePanel(brain: b), tab: 'Care');
    await shot(t, b, 'en_default_settings_top', () => SettingsPanel(brain: b), tab: 'Settings');
    await shot(t, b, 'en_default_settings_bottom', () => SettingsPanel(brain: b), tab: 'Settings', scrollBottom: true);
    await shot(t, b, 'en_min_care', () => CarePanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Care');

    Lang.code = 'zh';
    seed(b, 'zh');
    await shot(t, b, 'zh_default_chat_long', () => ChatPanel(brain: b), tab: 'Chat');
    CuteFont.scale = 1.5;
    await shot(t, b, 'zh_min_chat_x1.5', () => ChatPanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Chat');
    CuteFont.scale = 1.0;

    Lang.code = 'ko';
    seed(b, 'ko');
    await shot(t, b, 'ko_min_settings_top', () => SettingsPanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Settings');
    await shot(t, b, 'ko_min_settings_bottom', () => SettingsPanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Settings', scrollBottom: true);
    await shot(t, b, 'ko_min_care', () => CarePanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Care');
    await shot(t, b, 'ko_min_chat', () => ChatPanel(brain: b), panelSize: PetBrain.panelMin, tab: 'Chat');

    Lang.code = 'en';
    seed(b, 'en');
    for (final th in PanelTheme.all) {
      b.panelTheme = th.id;
      await shot(t, b, 'theme_${th.id}', () => ChatPanel(brain: b), tab: th.en);
    }
    b.panelTheme = 'cream';
    resetGlobals();
    b.dispose();
  });
}
