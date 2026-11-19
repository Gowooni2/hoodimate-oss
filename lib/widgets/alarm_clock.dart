import 'dart:math';

import 'package:flutter/material.dart';

/// The big ringing alarm clock the pet holds while a reminder rings:
/// shakes, bells clatter, the face panics. Drawn in code (no assets).
class AlarmClock extends StatefulWidget {
  final double size;
  const AlarmClock({super.key, required this.size});

  @override
  State<AlarmClock> createState() => _AlarmClockState();
}

class _AlarmClockState extends State<AlarmClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ring,
      builder: (context, _) {
        final t = _ring.value;
        final ringing = t < 0.8;
        final shake = ringing ? sin(t * 2 * pi * 14) : 0.0;
        return Transform.rotate(
          angle: shake * 0.18,
          child: SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter:
                  _ClockPainter(phase: t, ringing: ringing, shake: shake),
            ),
          ),
        );
      },
    );
  }
}

/// A round pastel alarm clock with a face. Drawn in a unit box.
class _ClockPainter extends CustomPainter {
  final double phase;
  final bool ringing;
  final double shake;
  _ClockPainter({required this.phase, required this.ringing, required this.shake});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s * 0.56);
    final r = s * 0.33;
    final ink = Paint()..color = const Color(0xFF6B3A2E);
    final stroke = Paint()
      ..color = const Color(0xFF6B3A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeCap = StrokeCap.round;

    // legs
    for (final dx in [-0.55, 0.55]) {
      canvas.drawLine(c + Offset(dx * r, r * 0.8),
          c + Offset(dx * r * 1.25, r * 1.18), stroke..strokeWidth = s * 0.04);
    }
    stroke.strokeWidth = s * 0.025;

    // bells (alternate hits) and hammer
    final hit = ringing ? sin(phase * 2 * pi * 14) : 0.0;
    final bell = Paint()..color = const Color(0xFFFFC94D);
    for (final side in [-1.0, 1.0]) {
      final lift = ringing && hit * side > 0 ? s * 0.02 : 0.0;
      final bc = c + Offset(side * r * 0.72, -r * 0.98 - lift);
      canvas.save();
      canvas.translate(bc.dx, bc.dy);
      canvas.rotate(side * 0.5);
      final dome = Rect.fromCenter(center: Offset.zero, width: r * 0.78, height: r * 0.62);
      canvas.drawArc(dome, pi, pi, true, bell);
      canvas.drawArc(dome, pi, pi, true, stroke);
      canvas.restore();
    }
    final hammerTop = c + Offset(hit * r * 0.32, -r * 1.22);
    canvas.drawLine(c + Offset(0, -r * 0.95), hammerTop, stroke);
    canvas.drawCircle(hammerTop, s * 0.028, ink);

    // body
    canvas.drawCircle(c, r * 1.06, Paint()..color = const Color(0xFFFF8A80));
    canvas.drawCircle(c, r * 1.06, stroke);
    canvas.drawCircle(c, r * 0.86, Paint()..color = Colors.white);

    // hour ticks
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final o = Offset(cos(a), sin(a));
      canvas.drawLine(c + o * r * 0.74, c + o * r * (i % 3 == 0 ? 0.62 : 0.68),
          Paint()
            ..color = const Color(0xFFE0B8A8)
            ..strokeWidth = s * 0.012
            ..strokeCap = StrokeCap.round);
    }

    // face: panicked-cute while ringing, squinty smile between bursts
    final eyeY = c.dy - r * 0.12;
    for (final dx in [-0.3, 0.3]) {
      final e = Offset(c.dx + dx * r, eyeY);
      if (ringing) {
        // > < squeezed eyes
        final k = r * 0.1;
        final dir = dx < 0 ? 1.0 : -1.0;
        canvas.drawLine(e + Offset(-k * dir, -k), e + Offset(k * dir, 0), stroke);
        canvas.drawLine(e + Offset(k * dir, 0), e + Offset(-k * dir, k), stroke);
      } else {
        canvas.drawCircle(e, r * 0.07, ink);
      }
    }
    final blush = Paint()..color = const Color(0x66FF6B8A);
    for (final dx in [-0.5, 0.5]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(c.dx + dx * r, c.dy + r * 0.12),
              width: r * 0.24,
              height: r * 0.13),
          blush);
    }
    if (ringing) {
      // wide shouting mouth that flaps
      final open = 0.14 + 0.08 * sin(phase * 2 * pi * 9).abs();
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(c.dx, c.dy + r * 0.3), width: r * 0.32, height: r * open * 2),
          Paint()..color = const Color(0xFFB0413E));
    } else {
      canvas.drawArc(
          Rect.fromCenter(center: Offset(c.dx, c.dy + r * 0.2), width: r * 0.3, height: r * 0.22),
          0.2,
          pi - 0.4,
          false,
          stroke);
    }

    // vibration marks
    if (ringing) {
      final v = Paint()
        ..color = const Color(0xFFFF6B6B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..strokeCap = StrokeCap.round;
      for (final side in [-1.0, 1.0]) {
        for (var k = 1; k <= 2; k++) {
          final rr = r * (1.2 + k * 0.16);
          canvas.drawArc(Rect.fromCircle(center: c, radius: rr),
              side < 0 ? pi - 0.35 : -0.35, 0.7, false, v);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.phase != phase || old.ringing != ringing || old.shake != shake;
}
