import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../viewer/viewer_prefs.dart';
import 'video_models.dart';
import 'video_prefs.dart';
import 'video_thumbs.dart';

/// Settings > Media > Video player (also reachable from the player's menu).
class VideoSettingsScreen extends ConsumerWidget {
  const VideoSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(videoSettingsProvider);
    final n = ref.read(videoSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(t, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13)),
        );

    Widget sw(String title, bool value, VideoSettings Function(VideoSettings, bool) f, {String? sub, bool enabled = true}) => SwitchListTile(
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          value: value,
          onChanged: enabled ? (v) => n.update((x) => f(x, v)) : null,
        );

    Widget dropdown<T>(String title, T value, List<(T, String)> items, VideoSettings Function(VideoSettings, T) f) => ListTile(
          title: Text(title),
          trailing: DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(16),
            onChanged: (v) {
              if (v != null) n.update((x) => f(x, v));
            },
            items: [for (final it in items) DropdownMenuItem<T>(value: it.$1, child: Text(it.$2))],
          ),
        );

    final g = s.gestures;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video player'),
        actions: [TextButton(onPressed: n.reset, child: const Text('Reset'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          section('PLAYBACK'),
          dropdown<int>('Skip button / double tap', s.skipSeconds, const [(5, '5 s'), (10, '10 s'), (15, '15 s'), (30, '30 s')], (x, v) => x.copyWith(skipSeconds: v)),
          dropdown<ResumeMode>('Continue where I stopped', s.resumeMode, const [(ResumeMode.auto, 'Automatically'), (ResumeMode.ask, 'Ask me'), (ResumeMode.never, 'Never')], (x, v) => x.copyWith(resumeMode: v)),
          sw('Play next video automatically', s.autoNext, (x, v) => x.copyWith(autoNext: v), sub: 'Next video of the same folder'),
          sw('Keep the screen on while playing', s.keepScreenOn, (x, v) => x.copyWith(keepScreenOn: v)),
          dropdown<AspectMode>('Default picture size', s.defaultAspect, [for (final a in AspectMode.values) (a, a.label)], (x, v) => x.copyWith(defaultAspect: v)),
          dropdown<OrientationMode>('Screen rotation', s.orientation, const [
            (OrientationMode.auto, 'Follow the video'),
            (OrientationMode.sensor, 'Sensor'),
            (OrientationMode.landscape, 'Landscape'),
            (OrientationMode.portrait, 'Portrait'),
          ], (x, v) => x.copyWith(orientation: v)),
          ListTile(title: Text('Hide the controls after ${s.controlsHideSeconds} s')),
          Slider(value: s.controlsHideSeconds.toDouble(), min: 2, max: 10, divisions: 8, onChanged: (v) => n.update((x) => x.copyWith(controlsHideSeconds: v.round()))),
          Consumer(
            builder: (context, ref, _) => SwitchListTile(
              title: const Text('Keep sound playing in the background'),
              subtitle: const Text('Video turns into audio-only when you leave the app'),
              value: ref.watch(backgroundPlayProvider),
              onChanged: (v) => ref.read(backgroundPlayProvider.notifier).set(v),
            ),
          ),
          section('GESTURES'),
          sw('Use gestures', s.gestures, (x, v) => x.copyWith(gestures: v), sub: 'Every gesture also has a button'),
          sw('Swipe left / right to seek', s.seekGesture, (x, v) => x.copyWith(seekGesture: v), enabled: g),
          sw('Swipe up / down for brightness', s.brightnessGesture, (x, v) => x.copyWith(brightnessGesture: v), enabled: g),
          sw('Swipe up / down for volume', s.volumeGesture, (x, v) => x.copyWith(volumeGesture: v), enabled: g),
          sw('Pinch to zoom, drag to move', s.pinchZoom, (x, v) => x.copyWith(pinchZoom: v), enabled: g),
          sw('Double tap left / right to skip', s.doubleTapSkip, (x, v) => x.copyWith(doubleTapSkip: v), sub: 'Double tap in the middle = play / pause', enabled: g),
          sw('Hold to play faster', s.longPressSpeed, (x, v) => x.copyWith(longPressSpeed: v), enabled: g),
          dropdown<double>('Hold speed', s.longPressRate, const [(1.5, '1.5x'), (2.0, '2x'), (3.0, '3x'), (4.0, '4x')], (x, v) => x.copyWith(longPressRate: v)),
          sw('Left-handed layout', s.leftHanded, (x, v) => x.copyWith(leftHanded: v), sub: 'Swaps the brightness and volume sides', enabled: g),
          ListTile(title: Text('Gesture sensitivity: ${s.sensitivity.toStringAsFixed(1)}x')),
          Slider(value: s.sensitivity, min: 0.4, max: 2.5, divisions: 21, onChanged: g ? (v) => n.update((x) => x.copyWith(sensitivity: double.parse(v.toStringAsFixed(1)))) : null),
          section('SUBTITLES'),
          sw('Load subtitles found next to the video', s.subAuto, (x, v) => x.copyWith(subAuto: v), sub: 'movie.srt, movie.en.srt, movie.vtt ...'),
          ListTile(title: Text('Text size: ${s.subSize}')),
          Slider(value: s.subSize.toDouble(), min: 12, max: 48, divisions: 18, onChanged: (v) => n.update((x) => x.copyWith(subSize: v.round()))),
          sw('Outline', s.subOutline, (x, v) => x.copyWith(subOutline: v)),
          sw('Dark background', s.subBackground, (x, v) => x.copyWith(subBackground: v)),
          ListTile(title: Text('Height from the bottom: ${s.subBottom}')),
          Slider(value: s.subBottom.toDouble(), min: 0, max: 200, onChanged: (v) => n.update((x) => x.copyWith(subBottom: v.round()))),
          section('DATA ON THIS PHONE'),
          const _ThumbTile(),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Clear watch history'),
            subtitle: Text('${ref.watch(videoHistoryProvider).length} videos remembered (resume points, subtitle choices)'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear watch history?'),
                  content: const Text('Resume points and "Recently played" will be forgotten. Your videos are not touched.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) await ref.read(videoHistoryProvider.notifier).clear();
            },
          ),
        ],
      ),
    );
  }
}

class _ThumbTile extends StatefulWidget {
  const _ThumbTile();

  @override
  State<_ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<_ThumbTile> {
  late Future<int> _size = VideoThumbCache.instance.diskBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _size,
      builder: (context, snap) => ListTile(
        leading: const Icon(Icons.image_rounded),
        title: const Text('Clear video thumbnails'),
        subtitle: Text(snap.hasData ? '${formatSize(snap.data!)} used (limit ${formatSize(VideoThumbCache.maxDiskBytes)})' : 'Measuring...'),
        onTap: () async {
          await VideoThumbCache.instance.clear();
          if (mounted) setState(() => _size = VideoThumbCache.instance.diskBytes());
        },
      ),
    );
  }
}
