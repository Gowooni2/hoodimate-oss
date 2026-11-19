import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/onboarding.dart';
import '../models/panel_theme.dart';
import '../services/pet_brain.dart';

/// First-run walkthrough inside the panel (sold editions): pick one of the
/// Hoodies, then a few one-line care cards. Skippable from the second page.
/// [onDone] fires on "Let's go" or "Skip"; the caller marks it done.
class OnboardingFlow extends StatefulWidget {
  final PetBrain brain;
  final PanelTheme theme;
  final VoidCallback onDone;
  const OnboardingFlow({super.key, required this.brain, required this.theme, required this.onDone});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  /// 0 = character picker, 1.. = [Onboarding.careCards].
  int _page = 0;

  bool get _last => _page == Onboarding.careCards.length;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return AnimatedBuilder(
      animation: widget.brain,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Center(child: _page == 0 ? _picker(t) : _card(t, Onboarding.careCards[_page - 1])),
              ),
            ),
            const SizedBox(height: 6),
            _dots(t),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_page > 0)
                  TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: widget.onDone,
                    child: Text(Onboarding.skip, style: TextStyle(fontSize: 12.5, color: t.label.withValues(alpha: 0.7))),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('onboarding-next'),
                  style: FilledButton.styleFrom(backgroundColor: t.label),
                  onPressed: _last ? widget.onDone : () => setState(() => _page++),
                  child: Text(_last ? Onboarding.start : Onboarding.next, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots(PanelTheme t) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i <= Onboarding.careCards.length; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _page ? t.label : t.label.withValues(alpha: 0.2),
              ),
            ),
        ],
      );

  Widget _picker(PanelTheme t) {
    final packs = Character.available.isEmpty ? [Character.fallback] : Character.available;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(Onboarding.pickTitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.label)),
        const SizedBox(height: 4),
        Text(Onboarding.pickHint,
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: t.label.withValues(alpha: 0.7))),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in packs)
              GestureDetector(
                key: Key('pick-${c.id}'),
                onTap: () => widget.brain.setCharacter(c.id),
                child: Container(
                  width: 82,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: c.id == Character.current.id ? Colors.white : t.tabBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: c.id == Character.current.id ? t.label : Colors.transparent, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: Image.asset(c.sprite('idle'),
                            fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                      const SizedBox(height: 2),
                      Text(c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.label)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _card(PanelTheme t, String card) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Onboarding.emoji(card), style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          Text(Onboarding.title(card),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.label)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(Onboarding.line(card),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: t.label)),
          ),
        ],
      );
}
