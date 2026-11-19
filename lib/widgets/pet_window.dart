import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../edition.dart';
import '../models/character.dart';
import '../models/emoticons.dart';
import '../models/emotion_fx.dart';
import '../models/panel_theme.dart';
import 'sticker.dart';
import '../models/pet_state.dart';
import '../models/profile.dart';
import '../services/links.dart';
import '../services/pet_brain.dart';
import 'alarm_clock.dart';
import 'care_panel.dart';
import 'chat_panel.dart';
import 'clip_player.dart';
import 'onboarding.dart';
import 'settings_panel.dart';
import 'tracking_eyes.dart';

/// Window geometry derived from the character size. The pet "stage" keeps
/// generous room around the character so hops, tilts and clip frames with
/// swinging arms are never cut by the window edge.
class PetLayout {
  /// Room for the speech bubble above the pet; grows with the chat text
  /// size so a lettering line plus two text lines still fit inside the box.
  static double get bubbleH => 72.0 * max(1.0, CuteFont.scale);
  static const base = 200.0;

  /// Opaque title strip at the top of sold editions (App Review 4.0); the
  /// traffic-light buttons sit inside it. The personal build has none.
  static double get stripH => Ed.current != Edition.personal ? 28.0 : 0.0;

  /// Everything above the stage: title strip plus speech bubble.
  static double get topH => stripH + bubbleH;

  /// Text lines that fit in the bubble box (margin 8 + padding 16, and the
  /// lettering line when there is one); the rest ends in "…" inside the box.
  static int bubbleLines(TextStyle style, {required bool lettering}) {
    final lineH = (style.fontSize ?? 13.5) * (style.height ?? 1.25);
    final room = bubbleH - 24 - (lettering ? 16 : 0);
    return (room / lineH).floor().clamp(1, 3);
  }

  final double scale;

  /// The open panel's size (the owner can drag its corner).
  final Size panel;
  const PetLayout(this.scale, [this.panel = PetBrain.panelDefault]);

  double get pet => base * scale;
  Size get stage => Size(pet * 1.5, pet * 1.38);
  Size get collapsed => Size(max(stage.width, 220), topH + stage.height);
  Size get expanded =>
      Size(max(stage.width, panel.width + 20), topH + stage.height + panel.height + 10);

  static PetLayout of(PetBrain b) => PetLayout(b.petScale, Size(b.panelW, b.panelH));

  /// Resizes the window; an open panel is first shrunk to fit the screen
  /// (a big pet plus a tall panel can be taller than a laptop display).
  static Future<void> apply(PetBrain b) async {
    if (b.panelOpen) {
      try {
        final d = await screenRetriever.getPrimaryDisplay();
        final vis = d.visibleSize ?? d.size;
        final roomH = vis.height - topH - of(b).stage.height - 30;
        final roomW = vis.width - 60;
        if (b.panelH > roomH || b.panelW > roomW) {
          b.setPanelSize(min(b.panelW, roomW), min(b.panelH, roomH));
        }
      } catch (_) {}
    }
    await windowManager.setSize(b.panelOpen ? of(b).expanded : of(b).collapsed);
  }
}

/// Moves the pet window smoothly in small steps. NSWindow's own animated
/// move paints a grey box behind a transparent window, so it isn't used.
int _glideId = 0;
Future<void> glideWindow(Offset to, {int ms = 500}) async {
  final id = ++_glideId;
  final from = (await windowManager.getBounds()).topLeft;
  const step = 16;
  final n = max(1, ms ~/ step);
  for (var i = 1; i <= n; i++) {
    if (id != _glideId) return; // a newer move took over
    final t = Curves.easeInOutCubic.transform(i / n);
    await windowManager.setPosition(Offset.lerp(from, to, t)!);
    await Future.delayed(const Duration(milliseconds: step));
  }
}

/// The always-on-top desktop window: speech bubble, the animated pet
/// (draggable), and the expandable panel with 대화/돌봄/설정 tabs.
class PetWindow extends StatefulWidget {
  final PetBrain brain;
  const PetWindow({super.key, required this.brain});

  @override
  State<PetWindow> createState() => _PetWindowState();
}

class _PetWindowState extends State<PetWindow>
    with SingleTickerProviderStateMixin {
  PetBrain get brain => widget.brain;
  bool _alarmShown = false;

  /// Sold editions open on Care and call the chat tab "Talk" (App Review
  /// 4.3(a): the pet-care identity comes first). The owner's own build
  /// keeps Chat · Care · Settings.
  static final bool _careFirst = Ed.isSold;
  static final int _iChat = _careFirst ? 1 : 0;
  static final int _iCare = _careFirst ? 0 : 1;
  static const int _iSettings = 2;

  /// 대화/돌봄/설정 tabs. On 대화 the pet switches to its close-up face.
  late final TabController _tabs =
      TabController(length: 3, initialIndex: _iCare, vsync: this)
        ..addListener(() {
          if (!_tabs.indexIsChanging) setState(() {});
        });

  @override
  void initState() {
    super.initState();
    brain.addListener(_syncAlarm);
    _wander = brain.wanderSignal;
    brain.petFeet = _petFeet;
    brain.filmUi = _filmUi;
    brain.showPet = _showPet;
    brain.openTalk = _openTalk;
    if (brain.needsOnboarding) {
      // First run: the walkthrough fills the panel.
      brain.panelOpen = true;
      PetLayout.apply(brain);
    }
    _menu.setMethodCallHandler((call) async {
      if (call.method == 'settings') await _openSettings();
      if (call.method == 'help') await Links.open(Ed.supportUrl);
    });
  }

  /// Panel moves for the filmed tour (PetBrain.runFilm).
  void _filmUi(String action) {
    switch (action) {
      case 'open':
        if (!brain.panelOpen) _togglePanel();
      case 'close':
        if (brain.panelOpen) _togglePanel();
      case 'care':
        _tabs.animateTo(_iCare);
      case 'chat':
        _tabs.animateTo(_iChat);
    }
  }

  static const _menu = MethodChannel('hoodimong/menu');

  double? _screenH;

  /// Our pet's feet for Hoodibot: the window is laid out top-down (bubble,
  /// then the stage with the pet centred in it); the protocol wants points
  /// from the main screen's bottom-left.
  Future<({double x, double y, double h})?> _petFeet() async {
    try {
      _screenH ??= (await screenRetriever.getPrimaryDisplay()).size.height;
      final b = await windowManager.getBounds();
      final l = PetLayout.of(brain);
      final feetTop = b.top + PetLayout.topH + l.stage.height / 2 + l.pet / 2;
      return (x: b.left + b.width / 2, y: _screenH! - feetTop, h: l.pet);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _menu.setMethodCallHandler(null);
    _tabs.dispose();
    _run?.cancel();
    brain.removeListener(_syncAlarm);
    super.dispose();
  }

  Timer? _run;
  Rect? _home;

  int _wander = 0;

  /// Random idle walk: glide the window sideways, staying on its display.
  Future<void> _maybeWander() async {
    if (brain.wanderSignal == _wander) return;
    _wander = brain.wanderSignal;
    if (_alarmShown) return;
    final b = await windowManager.getBounds();
    var x = b.left + brain.wanderDx;
    try {
      for (final d in await screenRetriever.getAllDisplays()) {
        final p = d.visiblePosition ?? Offset.zero;
        final r = p & (d.visibleSize ?? d.size);
        if (r.contains(b.center)) {
          x = x.clamp(r.left, max(r.left, r.right - b.width)).toDouble();
          break;
        }
      }
    } catch (_) {}
    await glideWindow(Offset(x, b.top));
  }

  void _syncAlarm() {
    if (brain.demo) return; // the demo stage animates inside its window
    _maybeWander();
    final on = brain.alarmText != null;
    if (on == _alarmShown) return;
    _alarmShown = on;
    on ? _startRunning() : _stopRunning();
  }

  /// While the alarm rings the pet window runs around the screen (random
  /// spots near home, on the same display) until it's caught with a click,
  /// then walks back home.
  Future<void> _startRunning() async {
    final home = _home = await windowManager.getBounds();
    var area = Rect.fromLTWH(home.left - 400, home.top - 250,
        home.width + 800, home.height + 500);
    try {
      for (final d in await screenRetriever.getAllDisplays()) {
        final p = d.visiblePosition ?? Offset.zero;
        final s = d.visibleSize ?? d.size;
        final r = p & s;
        if (r.contains(home.center)) {
          area = area.intersect(r);
          break;
        }
      }
    } catch (_) {}
    final rnd = Random();
    _run?.cancel();
    _run = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!_alarmShown) return;
      final x = area.left + rnd.nextDouble() * max(0.0, area.width - home.width);
      final y = area.top + rnd.nextDouble() * max(0.0, area.height - home.height);
      glideWindow(Offset(x, y), ms: 420);
    });
  }

  void _togglePanel() {
    brain.togglePanel();
    PetLayout.apply(brain);
  }

  Future<void> _showPet() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Menu bar > New alarm…: the Talk tab, where an alarm is just a sentence.
  void _openTalk() {
    if (!brain.panelOpen) _togglePanel();
    _tabs.animateTo(_iChat);
    _showPet();
  }

  /// Opens the panel on the Settings tab (menu: Hoodimate > Settings…).
  Future<void> _openSettings() async {
    if (!brain.panelOpen) _togglePanel();
    _tabs.animateTo(_iSettings);
    await windowManager.show();
    await windowManager.focus();
  }

  Tab get _chatTab => _careFirst
      ? Tab(text: Lang.t('💬 말하기', '💬 Talk', '💬 聊天'))
      : Tab(text: Lang.t('💬 대화', '💬 Chat', '💬 聊天'));

  Future<void> _stopRunning() async {
    _run?.cancel();
    _run = null;
    final home = _home;
    _home = null;
    if (home != null) {
      await glideWindow(home.topLeft);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (brain.demo) return DemoStage(brain: brain);
    return AnimatedBuilder(
      animation: brain,
      builder: (context, _) {
        final layout = PetLayout.of(brain);
        final theme = PanelTheme.byId(brain.panelTheme);
        return DragToMoveArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (PetLayout.stripH > 0) _TitleStrip(theme: theme),
              // speech bubble
              SizedBox(
                height: PetLayout.bubbleH,
                child: brain.bubbleText == null
                    ? const SizedBox.shrink()
                    : Container(
                        clipBehavior: Clip.hardEdge,
                        constraints: const BoxConstraints(maxWidth: 300),
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (Emoticons.byId(brain.bubbleSticker) != null) ...[
                              StickerView(Emoticons.byId(brain.bubbleSticker)!, size: 40),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (brain.bubbleFx != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: FxText(brain.bubbleFx!, size: 13),
                                    ),
                                  Text(
                                    CuteFont.fit(brain.bubbleText!),
                                    style: CuteFont.style(size: 13.5),
                                    maxLines: PetLayout.bubbleLines(CuteFont.style(size: 13.5),
                                        lettering: brain.bubbleFx != null),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox.fromSize(
                size: layout.stage,
                child: Center(
                  child: _AnimatedPet(
                      brain: brain,
                      layout: layout,
                      onTap: _togglePanel,
                      face: brain.panelOpen &&
                          _tabs.index == _iChat &&
                          !brain.needsOnboarding &&
                          brain.alarmText == null),
                ),
              ),
              if (brain.panelOpen)
                _PanelResizer(
                  brain: brain,
                  // right-click or Control-click: colors and chat font
                  child: GestureDetector(
                  onSecondaryTapUp: (d) => _appearanceMenu(d.globalPosition),
                  onTapUp: (d) {
                    if (HardwareKeyboard.instance.isControlPressed) _appearanceMenu(d.globalPosition);
                  },
                  child: Container(
                  width: brain.panelW,
                  height: brain.panelH,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: theme.bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: theme.shadow,
                          blurRadius: 14,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: brain.needsOnboarding
                      ? OnboardingFlow(
                          brain: brain,
                          theme: theme,
                          onDone: () {
                            _tabs.index = _iCare;
                            brain.completeOnboarding();
                          })
                      : Builder(
                    builder: (context) => Column(
                      children: [
                        Container(
                          height: 36,
                          margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                          decoration: BoxDecoration(
                            color: theme.tabBg,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TabBar(
                            controller: _tabs,
                            // English "Settings" needs the room.
                            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicatorPadding: const EdgeInsets.all(3),
                            indicator: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x1F8A5A2B),
                                    blurRadius: 4,
                                    offset: Offset(0, 1)),
                              ],
                            ),
                            labelColor: theme.label,
                            unselectedLabelColor: theme.tabDim,
                            labelStyle: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800),
                            unselectedLabelStyle: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                            tabs: [
                              if (!_careFirst) _chatTab,
                              Tab(text: Lang.t('🧸 돌봄', '🧸 Care', '🧸 照顾')),
                              if (_careFirst) _chatTab,
                              Tab(text: Lang.t('⚙️ 설정', '⚙️ Settings', '⚙️ 设置')),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabs,
                            children: [
                              if (!_careFirst) ChatPanel(brain: brain),
                              CarePanel(brain: brain),
                              if (_careFirst) ChatPanel(brain: brain),
                              SettingsPanel(
                                  brain: brain,
                                  onShowChat: () => _tabs.animateTo(_iChat)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Right-click / Control-click menu on the panel: color theme, chat font
  /// and text size. All kept per Mac.
  Future<void> _appearanceMenu(Offset at) async {
    final now = PanelTheme.byId(brain.panelTheme);
    PopupMenuItem<String> header(String text) => PopupMenuItem<String>(
        enabled: false,
        height: 26,
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.black54)));
    PopupMenuItem<String> pick(String value, bool on, Widget label) => PopupMenuItem<String>(
        value: value,
        height: 30,
        child: Row(children: [
          Expanded(child: label),
          if (on) const Icon(Icons.check_rounded, size: 16, color: Colors.black54),
        ]));
    const sizes = [(0.9, '작게', 'Small', '小'), (1.0, '보통', 'Normal', '标准'), (1.15, '크게', 'Large', '大'), (1.3, '아주 크게', 'Extra large', '特大')];
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      constraints: const BoxConstraints(minWidth: 190),
      items: [
        header(Lang.t('🎨 색', '🎨 Color', '🎨 颜色')),
        for (final t in PanelTheme.all)
          pick('theme:${t.id}', t.id == now.id, Row(children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: t.userBubble,
                shape: BoxShape.circle,
                border: Border.all(color: t.label.withValues(alpha: 0.5), width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(t.name, style: const TextStyle(fontSize: 13)),
          ])),
        const PopupMenuDivider(height: 8),
        header(Lang.t('🔤 대화 글꼴', '🔤 Chat font', '🔤 聊天字体')),
        pick('font:cute', CuteFont.cute,
            Text(Lang.t('귀여운 글꼴', 'Cute font', '可爱字体'),
                style: TextStyle(fontFamily: CuteFont.family, fontFamilyFallback: CuteFont.fallback, fontSize: 14))),
        pick('font:system', !CuteFont.cute,
            Text(Lang.t('기본 글꼴', 'System font', '系统字体'), style: const TextStyle(fontSize: 13))),
        const PopupMenuDivider(height: 8),
        header(Lang.t('🔠 글자 크기', '🔠 Text size', '🔠 字号')),
        for (final (v, ko, en, zh) in sizes)
          pick('size:$v', (CuteFont.scale - v).abs() < 0.01,
              Text(Lang.t(ko, en, zh), style: TextStyle(fontSize: 12.5 * v))),
      ],
    );
    if (r == null) return;
    final [kind, value] = r.split(':');
    switch (kind) {
      case 'theme':
        brain.setPanelTheme(value);
      case 'font':
        brain.setChatFont(cute: value == 'cute');
      case 'size':
        brain.setChatFont(scale: double.parse(value));
    }
    // The bubble row grows with the text size.
    if (kind != 'theme') await PetLayout.apply(brain);
  }
}

/// Wraps the open panel with a corner grip: drag it to make the panel
/// (and the window) bigger or smaller, double-click it for the default size.
class _PanelResizer extends StatefulWidget {
  final PetBrain brain;
  final Widget child;
  const _PanelResizer({required this.brain, required this.child});

  @override
  State<_PanelResizer> createState() => _PanelResizerState();
}

class _PanelResizerState extends State<_PanelResizer> {
  Size? _start;
  Offset? _from;
  bool _busy = false, _again = false;

  /// Window resizes are async; keep only the latest one in flight.
  Future<void> _applyWindow() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    do {
      _again = false;
      await PetLayout.apply(widget.brain);
    } while (_again);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brain;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          right: 2,
          bottom: 12,
          child: Tooltip(
            message: Lang.t('끌어서 크기 조절 · 두 번 누르면 원래 크기',
                'Drag to resize · double-click to reset', '拖动调整大小 · 双击恢复'),
            waitDuration: const Duration(milliseconds: 600),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _start = Size(b.panelW, b.panelH);
                  _from = d.globalPosition;
                },
                onPanUpdate: (d) {
                  final s = _start, f = _from;
                  if (s == null || f == null) return;
                  final delta = d.globalPosition - f;
                  // the panel is centered, so width grows on both sides
                  b.setPanelSize(s.width + delta.dx * 2, s.height + delta.dy);
                  _applyWindow();
                },
                onPanEnd: (_) {
                  b.setPanelSize(b.panelW, b.panelH, save: true);
                  _applyWindow();
                },
                onDoubleTap: () {
                  b.setPanelSize(PetBrain.panelDefault.width, PetBrain.panelDefault.height, save: true);
                  _applyWindow();
                },
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CustomPaint(painter: _GripPainter()),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three short diagonal lines, like a window's size grip.
class _GripPainter extends CustomPainter {
  const _GripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFC9AE8E)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final k in [0.35, 0.6, 0.85]) {
      canvas.drawLine(Offset(size.width * k, size.height - 4), Offset(size.width - 4, size.height * k), p);
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => false;
}

/// The pet with life:
/// - ComfyUI frame clips when available (static sprite + breathing otherwise)
/// - turns toward the mouse cursor anywhere on screen
/// - reacts to touch: hover = boop, rub the head = petting,
///   wiggle over the belly = tickle, touch while sick = thanks
/// - squash on tap, happy hop.
/// Tap = open/close panel. Long-press = talk (voice input while held).
class _AnimatedPet extends StatefulWidget {
  final PetBrain brain;
  final PetLayout layout;
  final VoidCallback onTap;

  /// Close-up face mode (chatting): big face, eyes on the cursor.
  final bool face;
  const _AnimatedPet(
      {required this.brain,
      required this.layout,
      required this.onTap,
      this.face = false});

  @override
  State<_AnimatedPet> createState() => _AnimatedPetState();
}

/// Cursor x positions over the last ~1.2 s: at least 4 left/right
/// reversals and 280 px of travel count as a shake.
bool isMouseShake(List<double> xs) {
  var flips = 0, travel = 0.0, last = 0.0;
  for (var i = 1; i < xs.length; i++) {
    final d = xs[i] - xs[i - 1];
    if (d.abs() < 6) continue;
    travel += d.abs();
    if (last != 0 && d.sign != last.sign) flips++;
    last = d;
  }
  return flips >= 4 && travel > 280;
}


class _AnimatedPetState extends State<_AnimatedPet>
    with TickerProviderStateMixin, WindowListener {
  late final AnimationController _breath;
  late final AnimationController _squash;
  late final AnimationController _hop;
  late final AnimationController _react;
  final _gaze = ValueNotifier(Offset.zero);
  int _lastHop = 0;
  int _lastReaction = 0;
  PetReaction _reaction = PetReaction.none;
  int _lastAction = 0;
  String? _playing; // one-shot action clip currently playing

  // cursor tracking
  Timer? _poll;
  bool _polling = false;
  int _tick = 0;
  Rect _win = Rect.zero;
  Offset? _lastCursor;
  DateTime _lastMove = DateTime.now();
  bool _inside = false;
  bool _watching = false; // cursor is moving: show tracking eyes

  // hover cursor: open hand on the head, pointing finger on the belly
  MouseCursor _cursor = SystemMouseCursors.basic;
  bool _dragging = false;

  void _hover(Offset local) {
    final size = widget.layout.pet;
    final head = local.dy < size * 0.42;
    final c = _dragging
        ? SystemMouseCursors.grabbing
        : (head ? SystemMouseCursors.grab : SystemMouseCursors.click);
    if (c != _cursor) setState(() => _cursor = c);
  }

  // rub detection
  double _lastX = 0;
  int _dir = 0;
  double _turnX = 0;
  final List<DateTime> _headTurns = [];
  final List<DateTime> _bellyTurns = [];

  PetBrain get brain => widget.brain;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    _squash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _hop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _react = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _lastHop = brain.hopSignal;
    _lastReaction = brain.reactionSignal;
    _lastAction = brain.actionSignal;
    _poll = Timer.periodic(const Duration(milliseconds: 40), (_) => _sample());
    windowManager.addListener(this);
    brain.cues.mouth.addListener(_onMouth);
  }

  // Switch to the live face when a voice line starts or ends (the mouth
  // shapes themselves repaint inside TrackingEyesSprite).
  bool _speaking = false;
  void _onMouth() {
    final s = brain.cues.mouth.value != null;
    if (s != _speaking && mounted) setState(() => _speaking = s);
  }

  @override
  void didUpdateWidget(_AnimatedPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (brain.hopSignal != _lastHop) {
      _lastHop = brain.hopSignal;
      _hop.forward(from: 0);
    }
    if (brain.actionSignal != _lastAction) {
      _lastAction = brain.actionSignal;
      final a = brain.action;
      _playing = a == null ? null : PetClips.resolveAction(a);
    }
    if (brain.reactionSignal != _lastReaction) {
      _lastReaction = brain.reactionSignal;
      _reaction = brain.reaction;
      _react.duration =
          Duration(milliseconds: _reaction == PetReaction.tickle ? 900 : 800);
      _react.forward(from: 0);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    brain.cues.mouth.removeListener(_onMouth);
    _poll?.cancel();
    _breath.dispose();
    _squash.dispose();
    _hop.dispose();
    _react.dispose();
    _gaze.dispose();
    super.dispose();
  }

  DateTime? _caughtAt;

  void _onTap() {
    final c = _caughtAt;
    if (c != null && DateTime.now().difference(c).inMilliseconds < 800) {
      return; // the release of the catching click: don't open the panel
    }
    _squash.forward().then((_) {
      if (mounted) _squash.reverse();
    });
    if (brain.alarmText != null) {
      brain.catchAlarm(); // caught it!
      return;
    }
    widget.onTap();
  }

  /// Reads the global cursor (works even when the pet window isn't focused).
  Future<void> _sample() async {
    if (_polling || !mounted) return;
    if (brain.demo) {
      // Scripted gaze for the recording: eyes sweep around smoothly.
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final target = brain.demoGaze
          ? Offset(sin(t * 1.7) * 0.95, cos(t * 1.15) * 0.55)
          : Offset.zero;
      final g = _gaze.value;
      _gaze.value = g + (target - g) * 0.2;
      if (brain.demoGaze != _watching) setState(() => _watching = brain.demoGaze);
      return;
    }
    _polling = true;
    try {
      // Refresh the window rect often near it (or when unknown), rarely far away.
      final near = _win.isEmpty ||
          (_lastCursor != null && _win.inflate(60).contains(_lastCursor!));
      if (near || _tick % 3 == 0 || _tick % 12 == 0) {
        _win = await windowManager.getBounds();
      }
      _tick++;
      final c = await screenRetriever.getCursorScreenPoint();
      _track(c);
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  /// Clicks on the empty, transparent parts of the pet window go through
  /// to the app behind it. Only the pet, its speech bubble and the open
  /// panel catch the mouse.
  bool _ignoring = false;

  void _clickThrough(Offset cursor, Rect petBox) {
    if (brain.demo) return;
    final win = _win;
    if (win.isEmpty || !win.contains(cursor)) {
      // Left the window (or unknown): never stay stuck ignoring the next hover.
      _setIgnoring(false);
      return;
    }
    final l = widget.layout;
    final strip = PetLayout.stripH > 0 &&
        Rect.fromLTWH(win.left, win.top, win.width, PetLayout.stripH).contains(cursor);
    final bubble = brain.bubbleText != null &&
        Rect.fromLTWH(win.left, win.top + PetLayout.stripH, win.width, PetLayout.bubbleH)
            .deflate(8)
            .contains(cursor);
    final panelTop = win.top + PetLayout.topH + l.stage.height;
    final panel = brain.panelOpen && cursor.dy >= panelTop - 4;
    // The standard close / minimize buttons sit in the window's top-left corner.
    final buttons = Rect.fromLTWH(win.left, win.top, 84, 30).contains(cursor);
    final hit = petBox.inflate(12).contains(cursor) ||
        strip ||
        bubble ||
        buttons ||
        panel ||
        _dragging ||
        brain.alarmText != null; // window is running around: always catchable
    _setIgnoring(!hit);
  }

  void _setIgnoring(bool v) {
    if (v == _ignoring) return;
    _ignoring = v;
    windowManager.setIgnoreMouseEvents(v, forward: true);
  }

  // Window restored / focused: make sure it takes mouse events again.
  @override
  void onWindowFocus() => _resetWin();
  @override
  void onWindowRestore() => _resetWin();
  @override
  void onWindowMoved() => _resetWin();
  @override
  void onWindowResized() => _resetWin();

  void _resetWin() {
    _tick = 0; // refresh the window rect on the next sample
    if (!brain.demo) _setIgnoring(false);
  }

  // Shaking the mouse near a sleeping pet wakes it: several quick
  // left-right reversals within ~1.2 s, close to the pet.
  final List<(DateTime, double)> _shakeX = [];
  void _shake(DateTime now, Offset cursor, Offset center) {
    if ((cursor - center).distance > 360) {
      _shakeX.clear();
      return;
    }
    _shakeX.add((now, cursor.dx));
    _shakeX.removeWhere((e) => now.difference(e.$1) > const Duration(milliseconds: 1200));
    if (isMouseShake(_shakeX.map((e) => e.$2).toList())) {
      _shakeX.clear();
      brain.wakeByShake();
    }
  }

  void _track(Offset cursor) {
    final l = widget.layout;
    // Pet box in screen coordinates (centered in the stage under the bubble).
    final cx = _win.left + _win.width / 2;
    final cy = _win.top + PetLayout.topH + l.stage.height / 2;
    final box = Rect.fromCenter(
        center: Offset(cx, cy), width: l.pet * 0.8, height: l.pet * 0.95);

    final now = DateTime.now();
    if (_lastCursor == null || (cursor - _lastCursor!).distance > 0.5) {
      _lastMove = now;
    }
    _lastCursor = cursor;

    // Gaze: lean toward the cursor; drift back to center when it rests.
    final idle = now.difference(_lastMove) > const Duration(seconds: 20);
    final watching = !idle && !brain.sleeping;
    if (watching != _watching && mounted) setState(() => _watching = watching);
    final target = (idle || brain.sleeping)
        ? Offset.zero
        : Offset(((cursor.dx - cx) / 350).clamp(-1.0, 1.0),
            ((cursor.dy - cy) / 350).clamp(-1.0, 1.0));
    final g = _gaze.value;
    final next = g + (target - g) * 0.18;
    if ((next - g).distance > 0.002) _gaze.value = next;

    _clickThrough(cursor, box);
    if (brain.sleeping) _shake(now, cursor, Offset(cx, cy));

    // Touch.
    final inside = box.contains(cursor);
    if (inside && !_inside) brain.onTouched();
    _inside = inside;
    if (!inside) {
      _dir = 0;
      return;
    }
    final dx = cursor.dx - _lastX;
    _lastX = cursor.dx;
    if (dx.abs() < 1.5) return;
    final d = dx.sign.toInt();
    if (_dir != 0 && d != _dir && (cursor.dx - _turnX).abs() > 8 * l.scale) {
      final head = cursor.dy < box.top + box.height * 0.42;
      (head ? _headTurns : _bellyTurns).add(now);
      _turnX = cursor.dx;
    }
    _dir = d;
    _headTurns.removeWhere(
        (t) => now.difference(t) > const Duration(milliseconds: 2000));
    _bellyTurns.removeWhere(
        (t) => now.difference(t) > const Duration(milliseconds: 1200));
    if (_headTurns.length >= 3) {
      _headTurns.clear();
      brain.onPetted();
    } else if (_bellyTurns.length >= 4) {
      _bellyTurns.clear();
      brain.onTickled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mood = brain.currentMood();
    final size = widget.layout.pet;
    // A clip carries its own motion, so the breathing bob is only for
    // static sprites.
    // Cursor moving + idle: eyeless sprite with eyes that follow the cursor
    // (the idle clip has its eyes baked in, so it plays only at rest).
    final alarm = brain.alarmText != null;
    final busy = brain.busyClip;
    final busyClip = busy != null && PetClips.resolveAction(busy) != null;
    final speaking = brain.cues.mouth.value != null;
    // Live-eye characters (the Hoodies) keep their eyes on the cursor in
    // every awake mood and show the mood in the eye shape; others only at
    // rest, as before.
    final liveEyes = !Character.current.hasMouth;
    final eyeMode = !alarm &&
        _playing == null &&
        !busyClip &&
        (liveEyes
            ? (mood != PetMood.sleepy && !brain.sleeping)
            : ((mood == PetMood.idle && _watching) || speaking));
    final look = brain.angryEyes && !brain.sleeping ? EyeLook.angry : switch (mood) {
      PetMood.happy || PetMood.celebrating || PetMood.waving => EyeLook.happy,
      PetMood.sad || PetMood.sick || PetMood.rain => EyeLook.sad,
      PetMood.bored || PetMood.hot => EyeLook.bored,
      _ => EyeLook.normal,
    };
    final hasClip =
        _playing != null || busyClip || (PetClips.has(mood) && !eyeMode);
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) => _hover(e.localPosition),
      onExit: (_) => setState(() => _cursor = SystemMouseCursors.basic),
      child: Listener(
        onPointerDown: (_) {
          // While the window runs around, a press is a catch: a tap would
          // often be read as a window drag because the window moves.
          if (brain.alarmText != null) {
            _squash.forward().then((_) {
              if (mounted) _squash.reverse();
            });
            brain.catchAlarm();
            _caughtAt = DateTime.now();
            return;
          }
          setState(() {
            _dragging = true;
            _cursor = SystemMouseCursors.grabbing;
          });
        },
        onPointerUp: (e) {
          _dragging = false;
          _hover(e.localPosition);
        },
        child: GestureDetector(
          onTap: _onTap,
          onLongPressStart: (_) => brain.startListening(),
          onLongPressEnd: (_) => brain.stopListening(),
          child: AnimatedBuilder(
            animation:
                Listenable.merge([_breath, _squash, _hop, _react, _gaze]),
            builder: (context, _) {
              final t = _breath.value * 2 * pi;
              final breatheDy =
                  hasClip ? 0.0 : sin(t) * 5.0 * widget.layout.scale;
              final breatheScale = hasClip ? 1.0 : 1 + sin(t) * 0.015;
              final sq = _squash.value;
              final hopDy = -sin(_hop.value * pi) * 24.0 * widget.layout.scale;

              // reaction motion (skipped while a pre-rendered action plays:
              // the clip already carries the motion)
              final r = _react.value;
              final fade =
                  (_react.isAnimating && _playing == null) ? 1 - r : 0.0;
              var rotZ = 0.0, dy = 0.0, nod = 0.0, sx = 1.0, sy = 1.0;
              switch (_reaction) {
                case PetReaction.boop:
                  rotZ = sin(r * 4 * pi) * 0.05 * fade;
                case PetReaction.pet:
                  final w = sin(r * 4 * pi) * fade;
                  sx = 1 + 0.05 * w;
                  sy = 1 - 0.07 * w;
                  rotZ = sin(r * 2 * pi) * 0.05 * fade;
                case PetReaction.tickle:
                  // giggly wiggle with little bounces
                  rotZ = sin(r * 10 * pi) * 0.10 * fade;
                  dy = -sin(r * 5 * pi).abs() * 7 * fade;
                case PetReaction.thanks:
                  nod = sin(r * pi) * 0.25;
                  dy = sin(r * pi) * 6;
                case PetReaction.none:
                  break;
              }

              // Alarm: frantic jitter and little panicked hops.
              if (alarm) {
                rotZ += sin(t * 18) * 0.09;
                dy -= sin(t * 9).abs() * 10 * widget.layout.scale;
              }

              final gz = _gaze.value;
              final m = Matrix4.identity()
                ..translateByDouble(gz.dx * 6, breatheDy + hopDy + dy, 0, 1)
                ..setEntry(3, 2, 0.0012)
                ..rotateY(gz.dx * (eyeMode ? 0.12 : 0.30))
                ..rotateX(-gz.dy * 0.10 + nod)
                ..rotateZ(rotZ)
                ..scaleByDouble(breatheScale * (1 + 0.10 * sq) * sx,
                    breatheScale * (1 - 0.16 * sq) * sy, 1, 1);
              return Transform(
                alignment: Alignment.center,
                transform: m,
                child: SizedBox(
                  width: size * 1.05,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: widget.face
                        ? FaceView(
                            key: const ValueKey('face'),
                            width: size * 1.05,
                            gaze: brain.thinking
                                ? const Offset(0.7, -0.8) // looking up, pondering
                                : gz,
                            talking: brain.thinking || brain.bubbleText != null,
                            mouth: brain.cues.mouth,
                            asleep: brain.sleeping,
                          )
                        : eyeMode
                        ? TrackingEyesSprite(
                            key: const ValueKey('eyes'),
                            size: size,
                            gaze: gz,
                            mouth: brain.cues.mouth,
                            look: liveEyes ? look : EyeLook.normal)
                        : ClipPlayer(
                            key: ValueKey(_playing != null
                                ? 'act_${_playing}_${brain.actionSignal}'
                                : 'loop_${mood}_$busy'),
                            mood: mood,
                            size: size,
                            action: _playing,
                            loop: busy,
                            onDone: () {
                              if (mounted) setState(() => _playing = null);
                            },
                          ),
                  ),
                      // Held in front of the belly unless a rendered
                      // act_alarm clip (pet already holding a clock) plays.
                      if (alarm && !PetClips.hasAction('alarm'))
                        Positioned(
                          bottom: size * 0.04,
                          child: AlarmClock(size: size * 0.62),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


/// Clean vertical stage for promo recordings (1080x1920): caption on top,
/// the pet big in the middle, care stats / chat close-up when the
/// script asks for them. No desktop, no personal data on screen.
class DemoStage extends StatefulWidget {
  final PetBrain brain;
  const DemoStage({super.key, required this.brain});

  @override
  State<DemoStage> createState() => _DemoStageState();
}

class _DemoStageState extends State<DemoStage> {
  PetBrain get brain => widget.brain;
  Alignment _spot = const Alignment(0, 0.25);
  Timer? _run;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _run = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      final running = brain.alarmText != null && !brain.demoPointer;
      final next = running
          ? Alignment(_rand.nextDouble() * 1.4 - 0.7, _rand.nextDouble() * 0.9 - 0.15)
          : (brain.alarmText != null ? _spot : const Alignment(0, 0.25));
      if (next != _spot) setState(() => _spot = next);
    });
  }

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  static const _ink = Color(0xFF6B4A2B);

  Widget _bubble(String text) => Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
          boxShadow: const [
            BoxShadow(color: Color(0x2A8A5A2B), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 38, height: 1.3, color: Colors.black87)),
      );

  Widget _stat(String label, double v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 210,
              child: Text(label,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _ink))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: v / 100),
                duration: const Duration(milliseconds: 900),
                builder: (_, x, __) => LinearProgressIndicator(
                    value: x, minHeight: 26, color: c, backgroundColor: const Color(0xFFF1E6D6)),
              ),
            ),
          ),
        ]),
      );

  Widget _chatLine(String line) {
    final user = line.startsWith('U:');
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        constraints: const BoxConstraints(maxWidth: 760),
        decoration: BoxDecoration(
          color: user ? const Color(0xFFFFE9B8) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(color: Color(0x1A8A5A2B), blurRadius: 12)],
        ),
        child: Text(line.substring(2),
            style: const TextStyle(fontSize: 36, height: 1.3, color: Colors.black87)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: brain,
      builder: (context, _) {
        final en = brain.demoLang == 'en';
        return Container(
          width: 1080,
          height: 1920,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF6E8), Color(0xFFFDE8EC)],
            ),
          ),
          child: Stack(
            children: [
              // caption
              Positioned(
                left: 60,
                right: 60,
                top: 110,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    brain.demoCaption,
                    key: ValueKey(brain.demoCaption),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 64, height: 1.25, fontWeight: FontWeight.w900, color: _ink),
                  ),
                ),
              ),
              if (brain.demoFace) ...[
                Align(
                  alignment: const Alignment(0, -0.18),
                  child: _FaceDemo(brain: brain),
                ),
                Positioned(
                  left: 70,
                  right: 70,
                  bottom: 330,
                  child: Column(children: [
                    for (final l in brain.demoChat) _chatLine(l),
                    if (brain.thinking) _chatLine(en ? 'P:…' : 'P:음… 생각 중'),
                  ]),
                ),
              ] else
                AnimatedAlign(
                  alignment: _spot,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 240,
                        child: Center(
                          child: brain.bubbleText == null
                              ? const SizedBox.shrink()
                              : _bubble(brain.bubbleText!),
                        ),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          _AnimatedPet(
                              brain: brain, layout: const PetLayout(2.6), onTap: () {}),
                          if (brain.demoPointer)
                            const Positioned(
                              right: 150,
                              bottom: 150,
                              child: Icon(Icons.back_hand, size: 150, color: Color(0xFFE8A87C)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (brain.demoStats)
                Positioned(
                  left: 90,
                  right: 90,
                  bottom: 230,
                  child: Container(
                    padding: const EdgeInsets.all(34),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Column(children: [
                      _stat(en ? '🍪 Hunger' : '🍪 배부름', brain.hunger, const Color(0xFFF4B183)),
                      _stat(en ? '💗 Happy' : '💗 행복', brain.happiness, const Color(0xFFF08FB0)),
                      _stat(en ? '🌿 Health' : '🌿 건강', brain.health, const Color(0xFF8FCB9B)),
                      _stat(en ? '⚡ Energy' : '⚡ 기운', brain.energy, const Color(0xFF9DB8F2)),
                    ]),
                  ),
                ),
              // footer
              Positioned(
                left: 0,
                right: 0,
                bottom: 90,
                child: Text(
                  en ? 'Hoodimate' : '후디메이트',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Color(0xFFB0907A)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Big round avatar for the demo chat scene, eyes on the scripted gaze.
class _FaceDemo extends StatefulWidget {
  final PetBrain brain;
  const _FaceDemo({required this.brain});

  @override
  State<_FaceDemo> createState() => _FaceDemoState();
}

class _FaceDemoState extends State<_FaceDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final x = _t.value * 2 * pi;
        final gaze = widget.brain.thinking
            ? const Offset(0.7, -0.8)
            : Offset(sin(x * 2) * 0.8, cos(x * 1.5) * 0.4);
        return FaceView(width: 620, gaze: gaze, talking: !widget.brain.thinking);
      },
    );
  }
}

/// Opaque draggable title strip (sold editions). The window buttons are drawn
/// by macOS in its left part; the title stays centred.
class _TitleStrip extends StatelessWidget {
  final PanelTheme theme;
  const _TitleStrip({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PetLayout.stripH,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.bg,
        border: Border(bottom: BorderSide(color: theme.border)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: const Text(
        'Hoodimate',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B4A2B),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
