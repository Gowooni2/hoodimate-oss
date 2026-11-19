import 'dart:math';

import 'package:flutter/material.dart';

import '../edition.dart';

import '../models/manual.dart';
import '../models/profile.dart';
import '../services/pet_brain.dart';
import '../services/sfx.dart';
import '../models/emoticons.dart';
import '../models/emotion_fx.dart';
import '../models/panel_theme.dart';
import 'sticker.dart';
import '../services/project_memory.dart';

/// Chat tab: project context picker, message history, voice + text input.
/// Replies appear as text only.
class ChatPanel extends StatefulWidget {
  final PetBrain brain;
  const ChatPanel({super.key, required this.brain});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  /// Keeps the cursor in the input box after sending, so the owner can
  /// keep typing without clicking it again.
  final _focus = FocusNode();
  String _chatSig = '';

  @override
  void initState() {
    super.initState();
    _chatSig = _signature();
    widget.brain.addListener(_onBrain);
    widget.brain.askAiConsent = _askAiConsent;
    _toBottom(animate: false);
  }

  /// One-time permission before chats go to a cloud AI provider.
  Future<bool> _askAiConsent(String provider) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lang.t('AI로 대화를 보낼까요?', 'Send chats to an AI?', '要把聊天发送给 AI 吗？'),
            style: const TextStyle(fontSize: 15)),
        content: Text(
            Lang.t(
                '대답을 만들기 위해 입력한 글, 최근 대화, 펫 이름·생일과 사는 곳(도시·우편번호·주·나라) 같은 프로필 정보가 $provider 서버로 보내져요. 처리 방식은 $provider의 개인정보 정책을 따라요. 후디메이트 개발자는 이 내용을 받거나 저장하지 않아요.',
                'To answer, what you type, recent chat and profile details (pet name, birthday and your area: city, ZIP code, state, country) are sent to $provider. $provider handles them under its own privacy policy. Hoodimate\'s developer never receives or stores them.',
                '为了回答，你输入的内容、最近的聊天以及资料（宠物名字、生日以及所在地：城市、邮政编码、州/省、国家）会发送到 $provider，并按 $provider 的隐私政策处理。Hoodimate 的开发者不会接收或保存这些内容。'),
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: Text(Lang.t('보내지 않기', 'Don\'t send', '不发送'))),
          FilledButton(onPressed: () => Navigator.pop(c, true),
              child: Text(Lang.t('동의하고 보내기', 'Agree and send', '同意并发送'))),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void didUpdateWidget(ChatPanel old) {
    super.didUpdateWidget(old);
    if (old.brain != widget.brain) {
      old.brain.removeListener(_onBrain);
      widget.brain.addListener(_onBrain);
    }
  }

  @override
  void dispose() {
    widget.brain.removeListener(_onBrain);
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Message count + last message length: changes on new messages
  // (typed, spoken, AI replies) and on an edited last message.
  String _signature() {
    final msgs = widget.brain.chat;
    return msgs.isEmpty ? '0' : '${msgs.length}:${msgs.last.text.length}';
  }

  void _onBrain() {
    final sig = _signature();
    if (sig == _chatSig) return;
    _chatSig = sig;
    _toBottom();
  }

  /// KakaoTalk-style emoticon picker (owned packs; more sold later).
  Future<void> _pickSticker() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 320,
          height: 380,
          child: DefaultTabController(
            length: Emoticons.owned.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [for (final p in Emoticons.owned) Tab(text: p.name)],
                ),
                Expanded(
                  child: TabBarView(children: [
                    for (final p in Emoticons.owned)
                      GridView.count(
                        crossAxisCount: 4,
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final e in p.items)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.pop(ctx, e.id),
                              child: Tooltip(message: e.caption, child: StickerView(e, size: 64)),
                            ),
                        ],
                      ),
                  ]),
                ),
                // No packs are sold in v1: don't advertise what isn't there yet.
                if (Ed.packSales != PackSales.none) Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Text(
                      Lang.t('더 많은 감정팩은 곧 판매해요', 'More feeling packs coming soon', '更多表情包即将推出'),
                      style: const TextStyle(fontSize: 11, color: Colors.black45)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _focus.requestFocus();
    if (id == null) return;
    widget.brain.sendSticker(id);
    _toBottom();
  }

  void _send() {
    widget.brain.sendChat(_ctrl.text);
    _ctrl.clear();
    _toBottom();
    _focus.requestFocus();
  }

  // Scroll after the new message is laid out; once more shortly after
  // in case a long bubble grows the list past the first frame.
  void _toBottom({bool animate = true}) {
    void go() {
      if (!mounted || !_scroll.hasClients) return;
      // A freshly opened manual is read from the top.
      final mem = widget.brain.memory;
      final freshManual =
          mem.active.id == Manual.roomId && mem.active.chat.length <= 2;
      final end = freshManual ? 0.0 : _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      Future.delayed(const Duration(milliseconds: 120), go);
    });
  }

  Future<void> _newProject() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lang.t('새 대화방', 'New chat room', '新聊天室'),
            style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: name,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
              hintText: Lang.t('예: 이사 준비, 포트폴리오', 'e.g. Moving, Portfolio', '例如：搬家、作品集')),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Lang.t('취소', 'Cancel', '取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(Lang.t('만들기', 'Create', '创建'))),
        ],
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok == true && n.isNotEmpty) {
      widget.brain.createProject(n);
      _toBottom(animate: false);
    }
  }

  void _toggleMic() {
    final b = widget.brain;
    if (b.listening) {
      b.stopListening();
    } else {
      b.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.brain,
      builder: (context, _) {
        final brain = widget.brain;
        final mem = brain.memory;
        final msgs = brain.chat;
        return Column(
          children: [
            // project context picker
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                children: [
                  for (final p in mem.visible)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Jiggle(
                        child: InputChip(
                        label:
                            Text(p.label, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        selected: p.id == mem.active.id,
                        showCheckmark: false,
                        selectedColor: const Color(0xFFFFE3B3),
                        onSelected: (_) {
                          brain.switchProject(p.id);
                          _toBottom(animate: false);
                        },
                        // 일상 stays; others close into the archive.
                        onDeleted: p.id == ProjectMemory.generalId
                            ? null
                            : () => brain.archiveProject(p.id),
                        deleteIcon: const Icon(Icons.close, size: 13),
                        deleteButtonTooltipMessage:
                            Lang.t('닫기 (보관함으로)', 'Close (to archive)', '关闭（放入归档）'),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: Lang.t('새 대화방', 'New chat room', '新聊天室'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _newProject,
                  ),
                ],
              ),
            ),
            Expanded(
              child: msgs.isEmpty
                  ? Center(
                      child: Text(
                          Lang.t('펫을 꾹 누르거나 🎤를 눌러 말해 보세요',
                              'Press and hold the pet, or tap 🎤, to talk', '长按宠物或点击 🎤 开始说话'),
                          style: const TextStyle(
                              color: Colors.black45, fontSize: 12)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final theme = PanelTheme.byId(widget.brain.panelTheme);
                        final m = msgs[i];
                        return Align(
                          alignment: m.fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Emoticons.byId(m.sticker) != null
                              // KakaoTalk-style emoticon: big animated
                              // sticker, caption underneath, no bubble
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: m.fromUser
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      StickerView(Emoticons.byId(m.sticker)!, size: 104),
                                      if (m.text != Emoticons.byId(m.sticker)!.caption)
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                          constraints: const BoxConstraints(maxWidth: 250),
                                          decoration: BoxDecoration(
                                            color: m.fromUser ? theme.userBubble : theme.petBubble,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: SelectableText(CuteFont.fit(m.text), style: CuteFont.style(size: 13.5)),
                                        )
                                      // the lettering on the sticker says it already
                                      else if (EmotionFx.byEmoticon[m.sticker] == null)
                                        Text(m.text,
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6E6258))),
                                    ],
                                  ),
                                )
                              : Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            constraints: const BoxConstraints(maxWidth: 250),
                            decoration: BoxDecoration(
                              color: m.fromUser
                                  ? theme.userBubble
                                  : theme.petBubble,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(CuteFont.fit(m.text),
                                style: CuteFont.style(size: 13.5)),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: brain.listening
                        ? Lang.t('그만 듣기', 'Stop listening', '停止聆听')
                        : Lang.t('말하기', 'Talk', '说话'),
                    icon: Icon(brain.listening ? Icons.stop_circle : Icons.mic,
                        size: 22,
                        color: brain.listening ? Colors.redAccent : null),
                    onPressed: brain.thinking ? null : _toggleMic,
                  ),
                  IconButton(
                    tooltip: Lang.t('이모티콘', 'Emoticons', '表情'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
                    onPressed: _pickSticker,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      // The pet listens / wonders while the owner types (1.1).
                      onChanged: brain.ownerTyping,
                      // Enter sends but keeps the box focused for the next line.
                      onEditingComplete: () {},
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: brain.thinking
                            ? Lang.t('생각 중...', 'Thinking...', '思考中...')
                            : Lang.t('글로 물어보기...', 'Type to ask...', '打字提问...'),
                        hintStyle: const TextStyle(fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, size: 20),
                    onPressed: brain.thinking ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Haptic-style feedback for the desktop: a quick little shake and squish
/// whenever the child is pressed. Listens to raw pointer-downs, so the
/// child's own tap/close handling is untouched.
/// Buzzes like a phone on a desk when pressed: shake + [sound]
/// (assets/sfx) + a trackpad haptic.
class Jiggle extends StatefulWidget {
  final Widget child;
  final String sound;
  const Jiggle({super.key, required this.child, this.sound = 'buzz'});

  @override
  State<Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<Jiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _c.forward(from: 0);
        Sfx.play(widget.sound);
      },
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final fade = 1 - t; // shake dies out
          final dx = sin(t * pi * 10) * 2.4 * fade; // fast buzz
          final squish = 1 - 0.06 * sin(t * pi) ;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(scale: squish, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
