import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The five-slot bottom bar: four destinations around a raised lime add button.
///
/// The centre button is not a destination — it is the global "log something"
/// action, which is why it is a button rather than a fifth tab.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home, label: 'Tagebuch'),
    (icon: Icons.menu_book, label: 'Rezepte'),
    (icon: Icons.insights, label: 'Verlauf'),
    (icon: Icons.person, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: 70 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      // The raised button overhangs the bar's top edge.
      clipBehavior: Clip.none,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavIcon(
            item: _items[0],
            selected: currentIndex == 0,
            onTap: () => onSelect(0),
          ),
          _NavIcon(
            item: _items[1],
            selected: currentIndex == 1,
            onTap: () => onSelect(1),
          ),
          _AddButton(onTap: onAdd),
          _NavIcon(
            item: _items[2],
            selected: currentIndex == 2,
            onTap: () => onSelect(2),
          ),
          _NavIcon(
            item: _items[3],
            selected: currentIndex == 3,
            onTap: () => onSelect(3),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(
            item.icon,
            size: 26,
            color: selected ? AppColors.lime : AppColors.navInactive,
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Semantics(
        button: true,
        label: 'Eintragen',
        child: Material(
          color: AppColors.lime,
          borderRadius: BorderRadius.circular(AppRadii.fab),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.add, size: 30, color: AppColors.bg),
            ),
          ),
        ),
      ),
    );
  }
}
