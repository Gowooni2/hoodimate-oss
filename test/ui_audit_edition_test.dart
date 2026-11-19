// Edition gating of Settings + the chat emoticon picker.
// Run: flutter test test/ui_audit_edition_test.dart [--dart-define=EDITION=store|lite]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/emoticons.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/widgets/chat_panel.dart';
import 'package:hoodimong/widgets/settings_panel.dart';
import 'package:hoodimong/widgets/sticker.dart';

import 'ui_audit_helpers.dart';

void main() {
  final ed = Ed.current;
  final store = ed == Edition.store || ed == Edition.direct;
  final lite = ed == Edition.lite;
  final personal = ed == Edition.personal;

  for (final lang in langs) {
    testWidgets('settings gating ($lang, ${ed.name})', (t) async {
      await auditSetUp(t);
      Lang.code = lang;
      setView(t, const Size(1000, 4000));
      final b = newBrain();
      await t.pumpWidget(host(SettingsPanel(brain: b), size: const Size(400, 4000)));
      await settle(t);
      bool any(List<String> s) => s.any((x) => find.textContaining(x).evaluate().isNotEmpty);
      bool hint(List<String> s) => find.byWidgetPredicate((w) =>
          w is TextField && s.any((x) => (w.decoration?.hintText ?? w.decoration?.labelText ?? '').contains(x))).evaluate().isNotEmpty;

      final stockHint = hint(['Stock symbol', '관심 종목', '股票代码']);
      final findBtn = any(['찾기', 'Find', '查找']) && find.widgetWithText(OutlinedButton, lang == 'ko' ? '찾기' : lang == 'zh' ? '查找' : 'Find').evaluate().isNotEmpty ||
          find.text(lang == 'ko' ? '찾기' : lang == 'zh' ? '查找' : 'Find').evaluate().isNotEmpty;
      final briefing = any(['Market briefing', '투자 브리핑', '市场简报']);
      final attribution = any(['Open-Meteo']) || any(['Yahoo']);
      final notice = any(['Good to know', '주의사항', '注意事项']);
      final privacy = any(['Privacy policy', '개인정보 처리방침', '隐私政策']);
      final support = any(['Support', '지원·문의', '支持与联系']);
      final sync = any(['Sync between Macs', '맥끼리 동기화', '多台 Mac 同步']);
      final tools = any(['Let the AI use tools', 'AI 도구 쓰기', '允许 AI 使用工具']);
      final eleven = any(['ElevenLabs']);

      if (store) {
        expect(stockHint, isFalse, reason: 'stock field in store');
        expect(findBtn, isFalse, reason: 'city Find button in store');
        expect(briefing, isFalse, reason: 'market briefing in store');
        expect(attribution, isFalse, reason: 'Open-Meteo/Yahoo line in store');
        expect(notice, isTrue, reason: 'Good to know box missing in store');
        expect(privacy, isTrue);
        expect(support, isTrue);
      }
      if (lite) {
        expect(sync, isFalse, reason: 'sync in lite');
        expect(tools, isFalse, reason: 'AI tools in lite');
        expect(eleven, isFalse, reason: 'ElevenLabs in lite');
        expect(stockHint, isFalse);
        expect(briefing, isFalse);
        expect(privacy, isTrue);
        expect(support, isTrue);
        // Lite has no stock/news tools: crediting Yahoo/Google News there is wrong (Open-Meteo geocoding is used, keep that).
        expect(any(['Yahoo']), isFalse, reason: 'Yahoo attribution shown in lite although lite has no market/tools');
      }
      if (personal) {
        expect(stockHint, isTrue);
        expect(briefing, isTrue);
        expect(sync && tools && eleven, isTrue);
        expect(notice, isFalse);
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      b.dispose();
      Lang.code = 'en';
    });
  }

  testWidgets('emoticon picker: 25 stickers, coming-soon hidden, sending adds sticker message (${ed.name})', (t) async {
    await auditSetUp(t);
    Lang.code = 'en';
    setView(t, const Size(900, 900));
    final b = newBrain();
    await t.pumpWidget(host(ChatPanel(brain: b), size: const Size(340, 320)));
    await t.pump();
    final before = b.memory.active.chat.length;
    await t.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await t.pumpAndSettle();
    expect(Emoticons.basic.items.length, 25);
    // The grid is lazy: scroll the picker to count every sticker.
    final seen = <String>{};
    final grid = find.byType(GridView);
    for (var i = 0; i < 8; i++) {
      for (final s in t.widgetList<StickerView>(find.descendant(of: grid, matching: find.byType(StickerView)))) {
        seen.add(s.emoticon.id);
      }
      await t.drag(grid, const Offset(0, -150));
      await t.pump();
    }
    expect(seen.length, 25, reason: 'picker shows ${seen.length}/25');
    expect(find.text('More feeling packs coming soon'), findsNothing, reason: 'v1 sells nothing: hide');
    // scroll back and send the first one
    await t.drag(grid, const Offset(0, 2000));
    await t.pumpAndSettle();
    final first = find.descendant(of: grid, matching: find.byType(StickerView)).first;
    await t.tap(first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final chat = b.memory.active.chat;
    expect(chat.length, greaterThan(before));
    expect(chat.any((m) => m.fromUser && m.sticker != null), isTrue);
    expect(find.byType(StickerView), findsWidgets, reason: 'sticker bubble in the chat list');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    b.dispose();
  });
}
