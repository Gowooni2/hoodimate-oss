import 'package:flutter/material.dart';

import 'profile.dart';

/// Color theme of the menu panel (chat/care/settings). The owner picks one
/// with a right-click (or Control-click) on the panel; kept per Mac.
class PanelTheme {
  final String id;
  final String ko, en, zh;
  final Color bg, border, tabBg, label, labelDim, userBubble, petBubble;
  const PanelTheme(this.id, this.ko, this.en, this.zh,
      {required this.bg,
      required this.border,
      required this.tabBg,
      required this.label,
      required this.labelDim,
      required this.userBubble,
      required this.petBubble});

  String get name => Lang.t(ko, en, zh);

  /// Unselected tab label: the old `labelDim` colors were only 2.0-2.5:1 on
  /// the tab bar (WCAG wants 3:1 for UI text); this stays visibly lighter
  /// than `label` but reads at ~4:1.
  Color get tabDim => Color.lerp(label, tabBg, 0.2)!;

  Color get shadow => label.withValues(alpha: 0.2);

  static const all = [
    PanelTheme('cream', '크림', 'Cream', '奶油',
        bg: Color(0xFFFFFAF3), border: Color(0xFFF3E3CC), tabBg: Color(0xFFF6EBDD),
        label: Color(0xFF6B4A2B), labelDim: Color(0xFFA8937D),
        userBubble: Color(0xFFFFE9B8), petBubble: Color(0xFFF1F1F1)),
    PanelTheme('strawberry', '딸기우유', 'Strawberry milk', '草莓牛奶',
        bg: Color(0xFFFFF5F8), border: Color(0xFFF8D3DF), tabBg: Color(0xFFFCE4EC),
        label: Color(0xFF9C3D5E), labelDim: Color(0xFFC98AA0),
        userBubble: Color(0xFFFFD6E3), petBubble: Color(0xFFF7EEF1)),
    PanelTheme('peach', '복숭아', 'Peach', '蜜桃',
        bg: Color(0xFFFFF6F0), border: Color(0xFFF8D9C6), tabBg: Color(0xFFFCE7DA),
        label: Color(0xFF9A4F2C), labelDim: Color(0xFFCF9A7E),
        userBubble: Color(0xFFFFD9C2), petBubble: Color(0xFFF5EFEB)),
    PanelTheme('lemon', '레몬', 'Lemon', '柠檬',
        bg: Color(0xFFFFFDF0), border: Color(0xFFF3E7A8), tabBg: Color(0xFFFBF3CC),
        label: Color(0xFF7A6514), labelDim: Color(0xFFB8A55E),
        userBubble: Color(0xFFFFF0A6), petBubble: Color(0xFFF4F2E8)),
    PanelTheme('mint', '민트', 'Mint', '薄荷',
        bg: Color(0xFFF2FBF7), border: Color(0xFFCDEBDD), tabBg: Color(0xFFDFF3EA),
        label: Color(0xFF2F6B55), labelDim: Color(0xFF7FAF9B),
        userBubble: Color(0xFFCFF0E0), petBubble: Color(0xFFEEF4F1)),
    PanelTheme('sky', '하늘', 'Sky', '天空',
        bg: Color(0xFFF3F8FF), border: Color(0xFFCFE0F7), tabBg: Color(0xFFE1ECFB),
        label: Color(0xFF2E5C8A), labelDim: Color(0xFF85A6C8),
        userBubble: Color(0xFFD3E5FF), petBubble: Color(0xFFEEF2F7)),
    PanelTheme('lavender', '라벤더', 'Lavender', '薰衣草',
        bg: Color(0xFFF8F4FF), border: Color(0xFFE0D4F5), tabBg: Color(0xFFECE3FA),
        label: Color(0xFF5B4290), labelDim: Color(0xFFA493C7),
        userBubble: Color(0xFFE4D8FF), petBubble: Color(0xFFF2EEF7)),
  ];

  static PanelTheme byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
