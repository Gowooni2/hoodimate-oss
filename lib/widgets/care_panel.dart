import 'dart:math';

import 'package:flutter/material.dart';

import '../models/pet_state.dart';
import '../models/profile.dart';
import '../services/pet_brain.dart';
import '../services/sfx.dart';
import '../services/weather_service.dart';

/// Care tab, pastel "toy box" style: the pet says what it needs in a
/// speech bubble, four gauge cards, four puffy round care buttons.
/// Buttons that can't be used right now turn grey and show why.
class CarePanel extends StatelessWidget {
  final PetBrain brain;
  const CarePanel({super.key, required this.brain});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: brain,
      builder: (context, _) {
        // Scrolls instead of overflowing when the panel is dragged small.
        return LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: max(0, box.maxHeight - 20)),
          child: IntrinsicHeight(
          child: Column(
            children: [
              _NeedBubble(text: brain.needText(), mood: brain.baseMood()),
              if (brain.weather.current != null) ...[
                const SizedBox(height: 6),
                _WeatherChip(w: brain.weather.current!),
              ],
              const SizedBox(height: 8),
              Row(children: [
                _Gauge('🍪', Lang.t('배부름', 'Hunger', '饱腹'), brain.hunger, const Color(0xFFFFB86B),
                    const Color(0xFFFFF1DC)),
                const SizedBox(width: 8),
                _Gauge('💗', Lang.t('행복', 'Happy', '开心'), brain.happiness, const Color(0xFFFF8FB1),
                    const Color(0xFFFFE8EF)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _Gauge('🌿', Lang.t('건강', 'Health', '健康'), brain.health, const Color(0xFF7FD18B),
                    const Color(0xFFE6F7E8)),
                const SizedBox(width: 8),
                _Gauge('⚡', Lang.t('기운', 'Energy', '精力'), brain.energy, const Color(0xFF8AB6FF),
                    const Color(0xFFE6F0FF)),
              ]),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(child: _PuffyButton('🍪', Lang.t('밥', 'Feed', '喂食'), const Color(0xFFFFD59E),
                      brain.feedBlock, brain.feed, 'feed')),
                  Flexible(child: _PuffyButton('🧸', Lang.t('놀기', 'Play', '玩耍'), const Color(0xFFFFB8CF),
                      brain.playBlock, brain.play, 'play')),
                  Flexible(child: _PuffyButton('💊', Lang.t('약', 'Medicine', '吃药'), const Color(0xFFB5E8BE),
                      brain.medicineBlock, brain.medicine, 'medicine')),
                  Flexible(child: _PuffyButton(
                      '🌙',
                      brain.sleeping
                          ? Lang.t('자는 중', 'Sleeping', '睡觉中')
                          : Lang.t('재우기', 'Sleep', '睡觉'),
                      const Color(0xFFC5D8FF),
                      brain.sleepBlock,
                      brain.toggleSleep,
                      'sleep')),
                  Flexible(child: _PuffyButton('💢', Lang.t('혼내기', 'Scold', '责骂'), const Color(0xFFFFB3A1),
                      brain.scoldBlock, brain.scold, 'scold')),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
          ),
          ),
        ));
      },
    );
  }
}

/// Tiny round face of the pet + a speech bubble with the current need.
class _NeedBubble extends StatelessWidget {
  final String text;
  final PetMood mood;
  const _NeedBubble({required this.text, required this.mood});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFF4E2),
            border: Border.all(color: const Color(0xFFF3DDBA), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Transform.scale(
            scale: 1.9,
            alignment: const Alignment(0, -0.55),
            child: Image.asset(mood.sprite, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 6),
        // bubble tail
        CustomPaint(size: const Size(8, 12), painter: _TailPainter()),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1A8A5A2B),
                    blurRadius: 8,
                    offset: Offset(0, 3)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(text,
                  key: ValueKey(text),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B4A2B))),
            ),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pastel gauge card; gently pulses when the value is low.
class _Gauge extends StatefulWidget {
  final String emoji;
  final String label;
  final double value;
  final Color color;
  final Color bg;
  const _Gauge(this.emoji, this.label, this.value, this.color, this.bg);

  @override
  State<_Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<_Gauge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  bool get _low => widget.value < 25;

  @override
  void initState() {
    super.initState();
    if (_low) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Gauge old) {
    super.didUpdateWidget(old);
    if (_low && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!_low && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Transform.scale(
            scale: 1 + 0.025 * sin(_pulse.value * pi), child: child),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 9),
          decoration: BoxDecoration(
            color: widget.bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _low
                    ? const Color(0xFFFF8A8A)
                    : widget.color.withValues(alpha: 0.35),
                width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Text(widget.emoji, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(widget.label,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B4A2B))),
                        const Spacer(),
                        Text(_low ? '!' : '${widget.value.round()}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _low
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFFA08060))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ChunkyBar(value: widget.value / 100, color: widget.color),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thick rounded bar with a soft top highlight.
class _ChunkyBar extends StatelessWidget {
  final double value;
  final Color color;
  const _ChunkyBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        builder: (context, v, _) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: v.clamp(0.04, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(color, Colors.white, 0.35)!, color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round puffy button that squishes when pressed.
class _PuffyButton extends StatefulWidget {
  final String emoji;
  final String label;
  final Color color;

  /// Why the action is unavailable right now (null = available).
  final String? blocked;
  final VoidCallback onTap;

  /// Sound + haptic pattern in Sfx (feed, play, medicine, sleep, scold).
  final String sound;
  const _PuffyButton(this.emoji, this.label, this.color, this.blocked,
      this.onTap, this.sound);

  @override
  State<_PuffyButton> createState() => _PuffyButtonState();
}

class _PuffyButtonState extends State<_PuffyButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;

  // Each action wobbles its own way after the press.
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  Matrix4 _wobble(double t) {
    final f = 1 - t;
    switch (widget.sound) {
      case 'feed': // three chomps
        final s = 1 - 0.10 * (sin(t * pi * 6).abs()) * f;
        return Matrix4.diagonal3Values(1 + (1 - s) * 0.5, s, 1);
      case 'play': // bounce up
        return Matrix4.translationValues(0, -10 * sin(t * pi) * f, 0);
      case 'medicine': // gentle tilt
        return Matrix4.rotationZ(0.18 * sin(t * pi * 2) * f);
      case 'sleep': // slow sink
        return Matrix4.translationValues(0, 4 * sin(t * pi), 0);
      case 'scold': // hard rattle
        return Matrix4.translationValues(5 * sin(t * pi * 12) * f, 0, 0);
      default:
        return Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.blocked == null;
    final c = enabled ? widget.color : const Color(0xFFE6E2DD);
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          GestureDetector(
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapCancel: () => setState(() => _down = false),
            onTapUp: enabled
                ? (_) {
                    setState(() => _down = false);
                    _fx.forward(from: 0);
                    Sfx.play(widget.sound);
                    widget.onTap();
                  }
                : null,
            child: MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.forbidden,
              child: AnimatedBuilder(
                animation: _fx,
                builder: (context, child) => Transform(
                    alignment: Alignment.center,
                    transform: _wobble(_fx.value),
                    child: child),
                child: AnimatedScale(
                scale: _down ? 0.88 : 1,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.4),
                      radius: 0.9,
                      colors: [Color.lerp(c, Colors.white, 0.55)!, c],
                    ),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                                color: c.withValues(alpha: 0.55),
                                blurRadius: _down ? 4 : 10,
                                offset: Offset(0, _down ? 2 : 5)),
                          ]
                        : null,
                  ),
                  child: Opacity(
                    opacity: enabled ? 1 : 0.45,
                    child: Text(widget.emoji,
                        style: const TextStyle(fontSize: 23)),
                  ),
                ),
              ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(widget.label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: enabled
                      ? const Color(0xFF6B4A2B)
                      : const Color(0xFFB5ABA0))),
          SizedBox(
            height: 16,
            child: enabled
                ? null
                : Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EEE8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.blocked!,
                        style: const TextStyle(
                            fontSize: 9.5, color: Color(0xFF9A8B7C))),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Small live-weather line: "☀️ 서울 21° · 오늘 15~24° · 비 10%".
class _WeatherChip extends StatelessWidget {
  final WeatherInfo w;
  const _WeatherChip({required this.w});

  @override
  Widget build(BuildContext context) {
    final effect = w.isHot
        ? Lang.t(' · 더워서 금방 지쳐요', ' · gets tired fast in the heat', ' · 天热容易累')
        : w.isCold
            ? Lang.t(' · 추워서 시무룩', ' · gloomy in the cold', ' · 天冷闷闷不乐')
            : w.sky == Sky.thunder
                ? Lang.t(' · 천둥이 무서워요', ' · scared of thunder', ' · 怕打雷')
                : w.isLovely
                    ? Lang.t(' · 날씨 좋아서 신나요', ' · happy about the nice weather', ' · 天气好心情好')
                    : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${w.emoji} ${w.city} ${w.tempF}°F · '
        '${Lang.t('오늘', 'Today', '今天')} ${w.minF}~${w.maxF}°F · '
        '${Lang.t('비', 'Rain', '下雨')} ${w.rainChance}%$effect',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4F6B8A)),
      ),
    );
  }
}
