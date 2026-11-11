import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewer/viewer_chrome.dart';
import '../viewer/viewer_prefs.dart';

/// Owner decides which buttons are visible directly in the viewers (image, PDF, PowerPoint, Word, text...)
/// and which are inside the three-dots menu. Changes apply at once.
class ViewerToolbarScreen extends ConsumerWidget {
  const ViewerToolbarScreen({super.key});

  static String _placeLabel(ActionPlace p) {
    switch (p) {
      case ActionPlace.top:
        return 'Top bar';
      case ActionPlace.menu:
        return 'Menu';
      case ActionPlace.pill:
        return 'Bottom pill';
      case ActionPlace.off:
        return 'Hidden';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(viewerToolbarProvider);
    final n = ref.read(viewerToolbarProvider.notifier);
    final layout = s.layout(ViewerAction.values, allowPill: true);

    Widget iconsRow(List<ViewerAction> list, {required bool menu}) {
      if (list.isEmpty) return Text('nothing', style: TextStyle(color: scheme.outline, fontSize: 12.5));
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in list)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(a.icon, size: 16),
              label: Text(menu ? a.label : a.label.split(' ').first, style: const TextStyle(fontSize: 11.5)),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewer toolbar'),
        actions: [TextButton(onPressed: n.reset, child: const Text('Reset'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preview', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text('Top bar', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                iconsRow(layout.top, menu: false),
                const SizedBox(height: 10),
                Text('Three-dots menu', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                iconsRow(layout.menu, menu: true),
                const SizedBox(height: 10),
                Text('Bottom pill (photos)', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                iconsRow(layout.pill, menu: false),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text('Icons allowed on the top bar: ${s.maxTop}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Slider(
            value: s.maxTop.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '${s.maxTop}',
            onChanged: (v) => n.setMaxTop(v.round()),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Where does each button live? Extra top-bar buttons move into the menu when there is no room. '
              'The bottom pill is shown on photos; in other viewers its buttons use free spots on the top bar.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          for (final a in ViewerAction.values)
            ListTile(
              leading: Icon(a.icon, color: scheme.primary),
              title: Text(a.label),
              trailing: DropdownButton<ActionPlace>(
                value: s.placeOf(a),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(16),
                onChanged: (v) {
                  if (v != null) n.setPlace(a, v);
                },
                items: [for (final p in ActionPlace.values) DropdownMenuItem(value: p, child: Text(_placeLabel(p)))],
              ),
            ),
        ],
      ),
    );
  }
}
