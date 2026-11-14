import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'audio_engine.dart';
import '../video/video_player_screen.dart';
import 'viewer_chrome.dart';
import 'viewer_prefs.dart';

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

/// Plays audio (MP3, M4A, FLAC, WAV...) and video (MP4, MKV, WEBM...).
/// Audio keeps playing in the background (notification controls). A video can be switched
/// to "audio only" and also does this by itself when the app is minimised (Settings > Background play).
class MediaPlayerScreen extends StatelessWidget {
  const MediaPlayerScreen({super.key, required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    // videos have their own full player (gestures, subtitles, resume, queue...)
    if (item.kind != FileKind.audio) return VideoPlayerScreen(item: item);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 17)),
        actions: [ViewerActions(item: item, color: scheme.onSurface)],
      ),
      body: _AudioPane(item: item),
    );
  }
}

// ---------------------------------------------------------------- shared controls

class _Controls extends StatelessWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.playing,
    required this.speed,
    required this.onSeek,
    required this.onToggle,
    required this.onSkip,
    required this.onSpeed,
    required this.fg,
    required this.dark,
    this.extra = const [],
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final double speed;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggle;
  final ValueChanged<int> onSkip;
  final ValueChanged<double> onSpeed;
  final Color fg;
  final bool dark;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final pos = position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      decoration: dark
          ? const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_fmt(position), style: TextStyle(color: fg, fontSize: 12.5)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: (total == 0 ? 1 : total).toDouble(),
                  value: pos.toDouble(),
                  onChanged: (x) => onSeek(Duration(milliseconds: x.round())),
                ),
              ),
              Text(_fmt(duration), style: TextStyle(color: fg, fontSize: 12.5)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(iconSize: 30, color: fg, icon: const Icon(Icons.replay_10_rounded), onPressed: () => onSkip(-10)),
              const SizedBox(width: 8),
              IconButton.filled(
                iconSize: 40,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: onToggle,
              ),
              const SizedBox(width: 8),
              IconButton(iconSize: 30, color: fg, icon: const Icon(Icons.forward_10_rounded), onPressed: () => onSkip(10)),
              const SizedBox(width: 12),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: speed,
                onSelected: onSpeed,
                itemBuilder: (context) => [for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: s, child: Text('${s}x'))],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${speed}x', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                ),
              ),
              ...extra,
            ],
          ),
        ],
      ),
    );
  }
}

Widget _audioArt(BuildContext context, FileItem item, {String? note, Color? fg}) {
  final scheme = Theme.of(context).colorScheme;
  final sub = fg?.withValues(alpha: 0.75) ?? scheme.onSurfaceVariant;
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: const Icon(Icons.music_note_rounded, size: 96, color: Colors.white),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(item.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
        ),
        const SizedBox(height: 4),
        Text(formatSize(item.size), style: TextStyle(color: sub)),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note, style: TextStyle(color: sub, fontSize: 12.5)),
        ],
        const SizedBox(height: 120),
      ],
    ),
  );
}

// ---------------------------------------------------------------- audio

class _AudioPane extends ConsumerStatefulWidget {
  const _AudioPane({required this.item});

  final FileItem item;

  @override
  ConsumerState<_AudioPane> createState() => _AudioPaneState();
}

class _AudioPaneState extends ConsumerState<_AudioPane> with WidgetsBindingObserver {
  final AudioPlayer _p = AudioEngine.instance.player;
  String? _error;
  bool _ready = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      await AudioEngine.instance.load(widget.item.path, widget.item.name);
      if (!mounted) return;
      setState(() => _ready = true);
      unawaited(_p.play());
    } catch (e) {
      if (mounted) setState(() => _error = 'This audio file could not be played on this device.\n$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // owner switched "Background play" off: pause when the app is left
    if (state == AppLifecycleState.paused && !ref.read(backgroundPlayProvider)) _p.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioEngine.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final bg = ref.watch(backgroundPlayProvider);
    return Stack(
      children: [
        Positioned.fill(child: _audioArt(context, widget.item, note: bg ? 'Keeps playing in the background' : null)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BottomSafe(
            child: StreamBuilder<PlayerState>(
              stream: _p.playerStateStream,
              builder: (context, stateSnap) {
                final st = stateSnap.data;
                final playing = (st?.playing ?? false) && st?.processingState != ProcessingState.completed;
                return StreamBuilder<Duration>(
                  stream: _p.positionStream,
                  builder: (context, posSnap) {
                    final dur = _p.duration ?? Duration.zero;
                    return _Controls(
                      position: posSnap.data ?? Duration.zero,
                      duration: dur,
                      playing: playing,
                      speed: _speed,
                      fg: scheme.onSurface,
                      dark: false,
                      onSeek: (d) => _p.seek(d),
                      onToggle: () {
                        if (st?.processingState == ProcessingState.completed) {
                          _p.seek(Duration.zero);
                          _p.play();
                        } else {
                          playing ? _p.pause() : _p.play();
                        }
                      },
                      onSkip: (s) {
                        final t = (_p.position) + Duration(seconds: s);
                        _p.seek(t < Duration.zero ? Duration.zero : (t > dur ? dur : t));
                      },
                      onSpeed: (s) {
                        setState(() => _speed = s);
                        _p.setSpeed(s);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
