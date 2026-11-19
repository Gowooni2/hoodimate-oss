part of 'pet_brain.dart';

/// The pet reads what the owner says and reacts at once, without any AI
/// (1.1, owner 2026-10-28; rules ported from AvatarTalk, see
/// lib/models/owner_feelings.dart). Korean only for now: other text reads
/// as neutral and nothing changes.
///   - typing: a listening / wondering look
///   - sending: a short expression sequence (surprised -> love, angry -> sulky)
///   - insult: the pet sulks until an apology (or two loving messages);
///     while sulking it answers with a sulk line instead of asking the AI
///   - no AI key: a short line that fits the feeling instead of an error
extension PetBrainFeelings on PetBrain {
  /// How each expression looks on a Hoodie: mood (eyes), clip, emoticon.
  static const _look = <OwnerFeeling, (PetMood, String?, String?)>{
    OwnerFeeling.happy: (PetMood.happy, 'jump', 'yay'),
    OwnerFeeling.curious: (PetMood.thinking, 'listen', 'hmm'),
    OwnerFeeling.laugh: (PetMood.happy, 'tickle', 'tickle'),
    OwnerFeeling.angry: (PetMood.bored, 'scolded', 'sulky'),
    OwnerFeeling.sulky: (PetMood.sad, 'scolded', 'sulky'),
    OwnerFeeling.sad: (PetMood.sad, 'gloomy', 'sad'),
    OwnerFeeling.surprised: (PetMood.talking, 'scared', null),
    OwnerFeeling.love: (PetMood.happy, 'pet', 'love'),
    OwnerFeeling.thinking: (PetMood.thinking, 'think', 'hmm'),
  };

  static const _step = Duration(milliseconds: 1200);

  /// Frowning eyes: while an angry/sulky step shows, and for as long as the
  /// pet sulks (until the owner apologises).
  bool get angryEyes =>
      sulk.sulking || (_angryUntil != null && DateTime.now().isBefore(_angryUntil!));

  /// While the owner types (chat box onChanged).
  void ownerTyping(String partial) {
    if (thinking || sleeping || alarmText != null || partial.trim().isEmpty) return;
    final f = OwnerFeelings.listeningPreview(partial, sulking: sulk.sulking);
    if (f.isEmpty || f.first == OwnerFeeling.neutral) return;
    final look = _look[f.first];
    if (look == null) return;
    _overrideMood = look.$1;
    _overrideUntil = DateTime.now().add(const Duration(seconds: 2));
    _notify();
  }

  /// Reads [text], plays the expression sequence and updates the sulk
  /// state. Returns the sequence (empty when the text reads as neutral).
  List<OwnerFeeling> _feelOwner(String text) {
    final r = OwnerFeelings.read(text);
    if (r.feeling == OwnerFeeling.neutral && !sulk.sulking) return const [];
    final seq = sulk.react(r).where((f) => f != OwnerFeeling.neutral).toList();
    _save();
    _playFeelings(seq);
    return seq;
  }

  Future<void> _playFeelings(List<OwnerFeeling> seq) async {
    for (var i = 0; i < seq.length; i++) {
      final look = _look[seq[i]];
      if (look == null) continue;
      _overrideMood = look.$1;
      _overrideUntil = DateTime.now().add(_step * (i == seq.length - 1 ? 3 : 1));
      _angryUntil = (seq[i] == OwnerFeeling.angry || seq[i] == OwnerFeeling.sulky) ? _overrideUntil : null;
      if (look.$2 != null) _act(look.$2!);
      _notify();
      if (i < seq.length - 1) await Future.delayed(_step);
    }
  }

  /// A line the pet says by itself (sulking, or no AI to ask).
  (String, PetMood, String?)? _ownLine(List<OwnerFeeling> seq) {
    final last = seq.isEmpty ? OwnerFeeling.neutral : seq.last;
    final rnd = Random();
    String pick(List<String> ko, List<String> en, List<String> zh) {
      final i = rnd.nextInt(ko.length);
      return Lang.t(ko[i], en[i], zh[i]);
    }

    final look = _look[last];
    final text = switch (last) {
      OwnerFeeling.sulky => pick(
          ['흥… 사과하면 생각해 볼게.', '칫, 말 안 할 거야.', '…흥. 미안하다고 하면 풀어 줄지도?'],
          ['Hmph… say sorry and I\'ll think about it.', 'Tsk. Not talking.', '…Hmph. Maybe if you apologize?'],
          ['哼……道歉的话我考虑一下。', '切，不理你了。', '……哼。说对不起的话也许会原谅你？']),
      OwnerFeeling.angry => pick(['그런 말 하면 속상해!'], ['That hurts my feelings!'], ['你这样说我会难过的！']),
      OwnerFeeling.love => pick(['헤헤, 나도 좋아해!', '히히, 기분 최고야 ♡'], ['Hehe, I like you too!', 'Teehee, best feeling ever ♡'],
          ['嘿嘿，我也喜欢你！', '嘻嘻，心情超好 ♡']),
      OwnerFeeling.happy => pick(['좋아좋아!', '신난다!', '헤헤, 고마워!'], ['Yay!', 'Woohoo!', 'Hehe, thanks!'], ['好呀好呀！', '太开心了！', '嘿嘿，谢谢！']),
      OwnerFeeling.laugh => pick(['꺄르르! 웃겨!', 'ㅋㅋㅋ 배꼽 빠지겠다!'], ['Hahaha! So funny!', 'LOL, my tummy hurts!'], ['哈哈哈！好好笑！', '笑死我了！']),
      OwnerFeeling.sad => pick(['괜찮아? 내가 옆에 있을게.', '토닥토닥… 힘내.'], ["Are you okay? I'm right here.", 'Pat pat… you got this.'],
          ['还好吗？我在你身边。', '拍拍……加油。']),
      OwnerFeeling.surprised => pick(['헉, 정말?', '우와, 진짜야?'], ['Whoa, really?', 'No way!'], ['哇，真的吗？', '不会吧！']),
      OwnerFeeling.thinking || OwnerFeeling.curious => pick(['음… 궁금하다! AI 키를 넣어 주면 더 잘 대답할 수 있어.', '흠, 뭘까? 같이 생각해 보자!'],
          ["Hmm… good question! Add an AI key and I can answer better.", "Hmm, what could it be? Let's think together!"],
          ['嗯……好问题！填上 AI 密钥我就能答得更好。', '嗯，会是什么呢？一起想想吧！']),
      OwnerFeeling.neutral => null,
    };
    if (text == null) return null;
    return (text, look?.$1 ?? PetMood.happy, look?.$3);
  }
}
