import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../combat/weapon_art.dart';
import '../combat/weapons.dart';
import '../game/umbra_game.dart';

class WeaponRadialOverlay extends StatelessWidget {
  const WeaponRadialOverlay({super.key, required this.game});
  final UmbraGame game;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => game.closeWeaponRadial(),
      child: Material(
        color: const Color(0x33000000),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: game.closeWeaponRadial,
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Center(
              child: TweenAnimationBuilder<double>(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                tween: Tween(begin: .88, end: 1),
                builder: (_, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: SizedBox(
                  width: 310,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 116,
                        height: 116,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xC70A0B0C),
                          border: Border.all(color: Colors.white70),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'CHOOSE\nWEAPON',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            letterSpacing: 1.5,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      for (var slot = 0; slot < 3; slot++) _radialSlot(slot),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _radialSlot(int slot) {
    final family = game.weapons.equipped[slot];
    final angle = -math.pi / 2 + slot * math.pi * 2 / 3;
    return Align(
      alignment: Alignment(math.cos(angle) * .82, math.sin(angle) * .82),
      child: Semantics(
        button: true,
        selected: game.weapons.activeSlot == slot,
        label: family == null
            ? 'Empty weapon slot ${slot + 1}'
            : WeaponCatalog.familyLabel(family),
        child: GestureDetector(
          onTap: family == null ? null : () => game.selectWeapon(slot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xD9101112),
              border: Border.all(
                color: game.weapons.activeSlot == slot
                    ? Colors.white
                    : Colors.white54,
                width: game.weapons.activeSlot == slot ? 3 : 1,
              ),
            ),
            child: family == null
                ? const Icon(Icons.remove, color: Colors.white38)
                : WeaponIcon(family: family, size: 42),
          ),
        ),
      ),
    );
  }
}

class WeaponPickupOverlay extends StatelessWidget {
  const WeaponPickupOverlay({super.key, required this.game});
  final UmbraGame game;

  @override
  Widget build(BuildContext context) {
    final weapon = game.pendingWeaponPickup;
    if (weapon == null) return const SizedBox.shrink();
    final needsSlot =
        !game.weapons.equipped.contains(weapon.family) &&
        !game.weapons.equipped.contains(null);
    return PopScope(
      canPop: false,
      child: Material(
        color: const Color(0x7A000000),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: SafeArea(
            minimum: const EdgeInsets.all(20),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 540),
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                decoration: BoxDecoration(
                  color: const Color(0xDB0B0C0D),
                  border: Border.all(color: Colors.white70),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'WEAPON PICKUP',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        letterSpacing: 3,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    WeaponIcon(family: weapon.family, size: 70),
                    const SizedBox(height: 12),
                    Text(
                      weapon.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 24,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'TIER ${weapon.tier}  ·  ${weapon.description}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (needsSlot) ...[
                      const Text(
                        'REPLACE A SLOT OR STORE IT',
                        style: TextStyle(fontSize: 11, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var slot = 0; slot < 3; slot++)
                            _WhiteAction(
                              label: 'SLOT ${slot + 1}',
                              onTap: () =>
                                  game.finishWeaponPickup(replaceSlot: slot),
                            ),
                          _WhiteAction(
                            label: 'STORE',
                            onTap: game.finishWeaponPickup,
                          ),
                        ],
                      ),
                    ] else
                      _WhiteAction(
                        label: 'CONTINUE',
                        onTap: game.finishWeaponPickup,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ArmoryPanel extends StatefulWidget {
  const ArmoryPanel({super.key, required this.game, required this.onBack});
  final UmbraGame game;
  final VoidCallback onBack;

  @override
  State<ArmoryPanel> createState() => _ArmoryPanelState();
}

class _ArmoryPanelState extends State<ArmoryPanel> {
  @override
  Widget build(BuildContext context) {
    final inventory = widget.game.weapons;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ARMORY',
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: 30,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap an unlocked weapon, then choose one of three slots.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * .52, 350),
            child: GridView.builder(
              itemCount: WeaponFamily.values.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                childAspectRatio: 2.55,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (_, index) {
                final family = WeaponFamily.values[index];
                final tier = inventory.tiers[family];
                final selected = inventory.equipped.contains(family);
                return Opacity(
                  opacity: tier == null ? .34 : 1,
                  child: OutlinedButton(
                    onPressed: tier == null ? null : () => _chooseSlot(family),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: selected ? Colors.white : Colors.white38,
                        width: selected ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Row(
                      children: [
                        WeaponIcon(family: family, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tier == null
                                ? 'LOCKED'
                                : '${WeaponCatalog.familyLabel(family).toUpperCase()}  ·  T$tier',
                            style: const TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 11,
                              letterSpacing: .6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _WhiteAction(label: 'BACK', onTap: widget.onBack),
        ],
      ),
    );
  }

  Future<void> _chooseSlot(WeaponFamily family) async {
    final slot = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xF20B0C0D),
        title: Text(
          'EQUIP ${WeaponCatalog.familyLabel(family).toUpperCase()}',
          style: const TextStyle(fontFamily: 'Cinzel', fontSize: 17),
        ),
        content: Wrap(
          spacing: 10,
          children: [
            for (var i = 0; i < 3; i++)
              _WhiteAction(
                label: 'SLOT ${i + 1}',
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (slot != null) {
      await widget.game.equipWeapon(family, slot);
      if (mounted) setState(() {});
    }
  }
}

class WeaponIcon extends StatelessWidget {
  const WeaponIcon({super.key, required this.family, required this.size});
  final WeaponFamily family;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _WeaponPainter(family));
}

class _WeaponPainter extends CustomPainter {
  const _WeaponPainter(this.family);
  final WeaponFamily family;
  @override
  void paint(Canvas canvas, Size size) => WeaponArt.draw(
    canvas,
    size.center(Offset.zero),
    size.shortestSide * .82,
    family,
  );
  @override
  bool shouldRepaint(_WeaponPainter oldDelegate) =>
      oldDelegate.family != family;
}

class _WhiteAction extends StatelessWidget {
  const _WhiteAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontFamily: 'Cinzel', letterSpacing: 1.5),
      ),
    ),
  );
}
