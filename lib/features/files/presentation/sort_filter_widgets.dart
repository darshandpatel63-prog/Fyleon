import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/files_providers.dart';
import '../domain/file_kind.dart';
import '../domain/files_logic.dart';

class FilterChipsRow extends ConsumerWidget {
  const FilterChipsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(kindFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: KindFilter.values.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = KindFilter.values[i];
          return ChoiceChip(
            label: Text(f.label),
            selected: f == selected,
            onSelected: (_) => ref.read(kindFilterProvider.notifier).set(f),
          );
        },
      ),
    );
  }
}

Future<void> showSortSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final current = ref.watch(sortProvider);
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Sort by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (final o in SortOption.values)
                  ListTile(
                    leading: Icon(o.icon, color: o == current ? scheme.primary : null),
                    title: Text(
                      o.label,
                      style: TextStyle(
                        fontWeight: o == current ? FontWeight.w700 : FontWeight.w400,
                        color: o == current ? scheme.primary : null,
                      ),
                    ),
                    trailing: o == current ? Icon(Icons.check_rounded, color: scheme.primary) : null,
                    onTap: () {
                      ref.read(sortProvider.notifier).set(o);
                      Navigator.of(ctx).pop();
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ),
  );
}
