import 'package:flutter/material.dart';

class DockItem {
  const DockItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating pill navigation: a soft highlight slides to the chosen tab and the icon pops.
class FloatingDock extends StatelessWidget {
  const FloatingDock({super.key, required this.index, required this.items, required this.onChanged});

  final int index;
  final List<DockItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 22, offset: const Offset(0, 8))],
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth / items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: index * w + 6,
                  top: 6,
                  bottom: 6,
                  width: w - 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () => onChanged(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                scale: i == index ? 1.18 : 1.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutBack,
                                child: Icon(
                                  i == index ? items[i].selectedIcon : items[i].icon,
                                  size: 24,
                                  color: i == index ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                                  color: i == index ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                ),
                                child: Text(items[i].label),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
