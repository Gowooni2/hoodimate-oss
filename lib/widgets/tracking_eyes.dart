import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';

/// Kimi-style eyes: the eyeless idle sprite with two glossy eyes painted on
/// top that follow the cursor smoothly and blink on their own.
///
/// Eye geometry is measured from assets/sprites/idle.png (430x512):
/// left eye (165,116), right eye (264,116), ~20 px across.
class TrackingEyesSprite extends StatefulWidget {
  final double size;

  /// -1..1 in each axis: where the cursor is relative to the pet.
  final Offset gaze;

  /// Lip sync: Rhubarb mouth shape (A..H, X) while a voice line plays.
  final ValueListenable<String?>? mouth;

  /// Mood shown with the eyes (live-eye characters).
  final EyeLook look;

  /// Eyes shut (sleeping).
  final bool asleep;
  const TrackingEyesSprite(
      {super.key,
      required this.size,
      required this.gaze,
      this.mouth,
      this.look = EyeLook.normal,
      this.asleep = false});

  @override
  State<TrackingEyesSprite> createState() => _TrackingEyesSpriteState();
}

/// How open a lip shape is (0 closed .. 1 wide), for mouthless talking.
double openness(String? shape) => switch (shape) {
      'D' => 1.0,
      'C' || 'H' => 0.75,
      'E' => 0.65,
      'F' || 'B' || 'G' => 0.45,
      'A' => 0.1,
      _ => 0.0,
    };

final ValueNotifier<String?> _silent = ValueNotifier(null);

class _TrackingEyesSpriteState extends State<TrackingEyesSprite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));
  final _rand = Random();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _timer = Timer(
        Duration(
          milliseconds: 2500 + _rand.nextInt(3500),
        ), () {
      if (!mounted) return;
      _blink.forward(from: 0).then((_) {
        if (!mounted) return;
        _blink.reverse().then((_) {
          // sometimes a quick double blink
          if (mounted && _rand.nextDouble() < 0.2) {
            _blink.forward(from: 0).then((_) => _blink.reverse());
          }
          _scheduleBlink();
        });
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(Character.current.noEyes,
              fit: BoxFit.contain, gaplessPlayback: true),
          // No mouth (Hoodies): talking shows as the eyes squashing with
          // each sound and a small bounce.
          ValueListenableBuilder<String?>(
            valueListenable: widget.mouth ?? _silent,
            builder: (context, shape, _) {
              final talk = Character.current.hasMouth ? 0.0 : openness(shape);
              return Transform.translate(
                offset: Offset(0, -widget.size * 0.012 * talk),
                child: AnimatedBuilder(
                  animation: _blink,
                  builder: (context, _) => CustomPaint(
                    painter: _EyesPainter(
                        gaze: widget.gaze,
                        look: widget.look,
                        close: widget.asleep
                            ? 1.0
                            : max(Curves.easeIn.transform(_blink.value), 0.38 * talk)),
                  ),
                ),
              );
            },
          ),
          if (widget.mouth != null && Character.current.hasMouth)
            ValueListenableBuilder<String?>(
              valueListenable: widget.mouth!,
              builder: (context, shape, _) => shape == null
                  ? const SizedBox.shrink()
                  : CustomPaint(painter: _MouthPainter(shape)),
            ),
        ],
      ),
    );
  }
}

/// Eye expressions for live-eye characters (the Hoodies show their mood
/// only with the eyes).
enum EyeLook { normal, happy, sad, bored, surprised, angry }

class _EyesPainter extends CustomPainter {
  final Offset gaze;
  final double close; // 0 open .. 1 shut
  final EyeLook look;
  _EyesPainter({required this.gaze, required this.close, this.look = EyeLook.normal});

  static Character get _ch => Character.current;

  @override
  void paint(Canvas canvas, Size size) {
    // Same placement as BoxFit.contain of the sprite.
    final ch = _ch;
    final imgW = ch.spriteSize.width, imgH = ch.spriteSize.height;
    final k = min(size.width / imgW, size.height / imgH);
    final ox = (size.width - imgW * k) / 2;
    final oy = (size.height - imgH * k) / 2;
    final g = Offset(gaze.dx.clamp(-1.0, 1.0), gaze.dy.clamp(-1.0, 1.0));
    final shift = Offset(g.dx * ch.lookRange.dx, g.dy * ch.lookRange.dy); // sprite px

    var side = -1.0; // left eye first
    for (final e in [ch.leftEye, ch.rightEye]) {
      final c = Offset(ox + (e.dx + shift.dx) * k, oy + (e.dy + shift.dy) * k);
      final big = look == EyeLook.surprised ? 1.15 : 1.0;
      final rx = ch.eyeRadius * k * big, ry = ch.eyeRadius * 1.06 * k * big * (1 - 0.92 * close);
      if (look == EyeLook.happy && close < 0.5) {
        // happy: upturned arcs (^ ^)
        canvas.drawArc(
            Rect.fromCenter(center: c + Offset(0, rx * 0.25), width: rx * 1.9, height: rx * 1.6),
            pi * 1.12, pi * 0.76, false,
            Paint()
              ..color = ch.eyeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = rx * 0.42
              ..strokeCap = StrokeCap.round);
        side = -side;
        continue;
      }
      final eye = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
      canvas.drawOval(eye, Paint()..color = ch.eyeColor);
      if (close < 0.5) {
        // glossy highlights, slightly opposite the gaze like real eyes
        final h1 = c + Offset(rx * 0.35 - g.dx * rx * 0.1, -ry * 0.4);
        canvas.drawOval(
            Rect.fromCenter(center: h1, width: rx * 0.55, height: ry * 0.5),
            Paint()..color = Colors.white.withValues(alpha: 0.95));
        canvas.drawCircle(c + Offset(-rx * 0.3, ry * 0.35), rx * 0.12,
            Paint()..color = Colors.white.withValues(alpha: 0.6));
      }
      if ((look == EyeLook.sad || look == EyeLook.bored || look == EyeLook.angry) && close < 0.5) {
        // eyelid in the face colour: flat and low for bored, sloping down
        // to the outer corner for sad, down to the inner corner for angry
        // (a frown, owner 2026-10-28)
        final top = c.dy - ry * 1.2;
        final inner = switch (look) {
          EyeLook.sad => c.dy - ry * 0.55,
          EyeLook.angry => c.dy + ry * 0.05,
          _ => c.dy - ry * 0.05,
        };
        final outer = look == EyeLook.angry ? c.dy - ry * 0.75 : c.dy - ry * 0.05;
        final innerX = c.dx - side * rx * 1.25, outerX = c.dx + side * rx * 1.25;
        final lid = Path()
          ..moveTo(innerX, top)
          ..lineTo(outerX, top)
          ..lineTo(outerX, outer)
          ..lineTo(innerX, inner)
          ..close();
        canvas.save();
        // only over the eye itself, never onto the hood around it
        canvas.clipPath(Path()..addOval(Rect.fromCenter(center: c, width: rx * 2.16, height: ry * 2.16)));
        canvas.drawPath(lid, Paint()..color = ch.face);
        canvas.drawLine(Offset(innerX, inner), Offset(outerX, outer),
            Paint()
              ..color = ch.eyeColor
              ..strokeWidth = rx * 0.16
              ..strokeCap = StrokeCap.round);
        canvas.restore();
      }
      side = -side;
    }
  }

  @override
  bool shouldRepaint(_EyesPainter old) =>
      old.gaze != gaze || old.close != close || old.look != look;
}

/// Talking mouth over the sprite's painted smile, one of Rhubarb's shapes:
/// A closed (M/B/P), B slightly open, C open, D wide, E rounded, F pucker,
/// G teeth on lip (F/V), H tongue up (L), X rest.
class _MouthPainter extends CustomPainter {
  final String shape;
  _MouthPainter(this.shape);

  static const _inside = Color(0xFF5B2B26);

  @override
  void paint(Canvas canvas, Size size) {
    final ch = Character.current;
    final imgW = ch.spriteSize.width, imgH = ch.spriteSize.height;
    // shapes below are drawn for a ~31 px mouth; scale to this character
    final k = min(size.width / imgW, size.height / imgH) * ch.mouthWidth / 31;
    final kk = min(size.width / imgW, size.height / imgH);
    final ox = (size.width - imgW * kk) / 2;
    final oy = (size.height - imgH * kk) / 2;
    final c = Offset(ox + ch.mouthCenter.dx * kk, oy + ch.mouthCenter.dy * kk);
    final skinC = ch.skin, lineC = ch.mouthLine;
    // Hide the painted smile under a soft skin patch.
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 46 * k, height: 22 * k),
        Paint()
          ..shader = RadialGradient(colors: [
            skinC,
            skinC,
            skinC.withValues(alpha: 0)
          ], stops: const [0, 0.62, 1])
              .createShader(Rect.fromCenter(
                  center: c, width: 46 * k, height: 22 * k)));
    final stroke = Paint()
      ..color = lineC
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * k
      ..strokeCap = StrokeCap.round;
    void open(double w, double h, {bool tongue = true, bool teeth = false}) {
      final r = Rect.fromCenter(
          center: c + Offset(0, h * 0.15 * k), width: w * k, height: h * k);
      canvas.drawOval(r, Paint()..color = _inside);
      if (tongue && h > 7) {
        canvas.save();
        canvas.clipPath(Path()..addOval(r));
        canvas.drawOval(
            Rect.fromCenter(
                center: r.bottomCenter - Offset(0, r.height * 0.15),
                width: r.width * 0.7,
                height: r.height * 0.55),
            Paint()..color = const Color(0xFFE58A8A));
        canvas.restore();
      }
      if (teeth) {
        canvas.drawRect(
            Rect.fromLTWH(r.left + r.width * 0.2, r.top, r.width * 0.6,
                r.height * 0.3),
            Paint()..color = Colors.white);
      }
      canvas.drawOval(r, stroke..strokeWidth = 1.6 * k);
    }

    switch (shape) {
      case 'A': // lips pressed
        canvas.drawLine(c - Offset(10 * k, 0), c + Offset(10 * k, 0), stroke);
      case 'B':
        open(18, 7, tongue: false, teeth: true);
      case 'C':
        open(22, 12);
      case 'D':
        open(26, 17);
      case 'E':
        open(16, 13);
      case 'F':
        open(9, 9, tongue: false);
      case 'G':
        open(18, 7, tongue: false, teeth: true);
      case 'H':
        open(20, 12);
      default: // X: rest, the usual smile
        canvas.drawArc(
            Rect.fromCenter(
                center: c - Offset(0, 4 * k), width: 28 * k, height: 14 * k),
            0.35,
            pi - 0.7,
            false,
            stroke);
    }
  }

  @override
  bool shouldRepaint(_MouthPainter old) => old.shape != shape;
}

/// Close-up face for conversations (chat tab open): the character sheet's
/// face close-up with its eyes removed, and live eyes that follow the
/// cursor, blink, and look up-and-away while thinking.
///
/// Geometry measured on assets/face/*.png (420x350): eyes at (136,186)
/// and (285,186), about 36 px across.
class FaceView extends StatefulWidget {
  final double width;
  final Offset gaze;
  final bool talking;
  final ValueListenable<String?>? mouth;
  final bool asleep;
  const FaceView(
      {super.key,
      required this.width,
      required this.gaze,
      this.talking = false,
      this.mouth,
      this.asleep = false});

  @override
  State<FaceView> createState() => _FaceViewState();
}

class _FaceViewState extends State<FaceView> with SingleTickerProviderStateMixin {
  // Gentle idle sway inside the circle so the pet feels alive while
  // listening (eyes and blinking come from TrackingEyesSprite).
  late final AnimationController _sway = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat();

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Round avatar frame (like a profile picture): the face fills a
    // circle with a soft ring and shadow.
    final d = widget.width;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF6F3EE),
        border: Border.all(color: const Color(0xFFE6DED3), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x228A5A2B), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: ClipOval(
        // Head and shoulders of the eyeless sprite, eyes following the
        // cursor (TrackingEyesSprite). Thinking = looking up and away.
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: (d - d * 1.42) / 2,
              top: d * 0.045,
              width: d * 1.42,
              height: d * 1.42,
              child: AnimatedBuilder(
                animation: _sway,
                builder: (context, child) {
                  final t = _sway.value * 2 * pi;
                  // talking: livelier bob; listening: slow breathing sway
                  final amp = widget.talking ? 1.8 : 1.0;
                  return Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..translateByDouble(
                          0, (sin(t * (widget.talking ? 3 : 1)) * 0.012 * d) * amp, 0, 1)
                      ..rotateZ(sin(t) * 0.035 * amp)
                      ..scaleByDouble(1 + sin(t * 2) * 0.008, 1 - sin(t * 2) * 0.008, 1, 1),
                    child: child,
                  );
                },
                child: TrackingEyesSprite(
                    size: d * 1.42,
                    gaze: widget.asleep ? Offset.zero : widget.gaze,
                    mouth: widget.mouth,
                    asleep: widget.asleep),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
