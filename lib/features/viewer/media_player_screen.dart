import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'audio_engine.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final isAudio = item.kind == FileKind.audio;
    final bg = isAudio ? scheme.surface : Colors.black;
    final fg = isAudio ? scheme.onSurface : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 17)),
        actions: [ViewerActions(item: item, color: fg)],
      ),
      body: isAudio ? _AudioPane(item: item) : _VideoPane(item: item),
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

// ---------------------------------------------------------------- video

class _VideoPane extends ConsumerStatefulWidget {
  const _VideoPane({required this.item});

  final FileItem item;

  @override
  ConsumerState<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends ConsumerState<_VideoPane> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;
  double _speed = 1.0;

  /// true while the sound is played by the audio engine (screen locked / app left / "audio only")
  bool _audioMode = false;
  bool _autoAudio = false;

  AudioPlayer get _ap => AudioEngine.instance.player;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.item.path));
    try {
      await c.initialize();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      await c.play();
      _scheduleHide();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = 'This video could not be played on this device.\n$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_audioMode && c.value.isPlaying) {
        if (ref.read(backgroundPlayProvider)) {
          _toAudio(auto: true);
        } else {
          c.pause();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_audioMode && _autoAudio) _toVideo();
    }
  }

  /// Sound continues in the audio engine (notification + background), picture is paused.
  Future<void> _toAudio({required bool auto}) async {
    final c = _c;
    if (c == null || _audioMode) return;
    final pos = c.value.position;
    _audioMode = true;
    _autoAudio = auto;
    await c.pause();
    if (mounted) setState(() {});
    try {
      await AudioEngine.instance.load(widget.item.path, widget.item.name, start: pos);
      await _ap.setSpeed(_speed);
      unawaited(_ap.play());
    } catch (_) {
      _audioMode = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toVideo() async {
    final c = _c;
    if (c == null || !_audioMode) return;
    final pos = _ap.position;
    await AudioEngine.instance.stop();
    _audioMode = false;
    _autoAudio = false;
    await c.seekTo(pos);
    await c.play();
    if (mounted) setState(() {});
    _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    if (_audioMode) AudioEngine.instance.stop();
    _c?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _seekBy(int seconds) {
    final c = _c;
    if (c == null) return;
    final cur = _audioMode ? _ap.position : c.value.position;
    final target = cur + Duration(seconds: seconds);
    final max = c.value.duration;
    final to = target < Duration.zero ? Duration.zero : (target > max ? max : target);
    if (_audioMode) {
      _ap.seek(to);
    } else {
      c.seekTo(to);
    }
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))));
    }
    if (c == null) return const Center(child: CircularProgressIndicator(color: Colors.white));

    final audioButton = IconButton(
      tooltip: _audioMode ? 'Show video' : 'Audio only (plays in the background)',
      color: Colors.white,
      icon: Icon(_audioMode ? Icons.videocam_rounded : Icons.headphones_rounded),
      onPressed: () => _audioMode ? _toVideo() : _toAudio(auto: false),
    );

    if (_audioMode) {
      return Stack(
        children: [
          Positioned.fill(
            child: _audioArt(context, widget.item, note: 'Audio only - keeps playing in the background', fg: Colors.white),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomSafe(
              child: StreamBuilder<PlayerState>(
                stream: _ap.playerStateStream,
                builder: (context, stateSnap) {
                  final playing = stateSnap.data?.playing ?? false;
                  return StreamBuilder<Duration>(
                    stream: _ap.positionStream,
                    builder: (context, posSnap) => _Controls(
                      position: posSnap.data ?? Duration.zero,
                      duration: c.value.duration,
                      playing: playing,
                      speed: _speed,
                      fg: Colors.white,
                      dark: true,
                      onSeek: (d) => _ap.seek(d),
                      onToggle: () => playing ? _ap.pause() : _ap.play(),
                      onSkip: _seekBy,
                      onSpeed: (s) {
                        setState(() => _speed = s);
                        _ap.setSpeed(s);
                      },
                      extra: [audioButton],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    final v = c.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(c)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: BottomSafe(
                  child: _Controls(
                    position: v.position,
                    duration: v.duration,
                    playing: v.isPlaying,
                    speed: _speed,
                    fg: Colors.white,
                    dark: true,
                    onSeek: (d) => c.seekTo(d),
                    onToggle: () {
                      v.isPlaying ? c.pause() : c.play();
                      _scheduleHide();
                    },
                    onSkip: _seekBy,
                    onSpeed: (s) {
                      setState(() => _speed = s);
                      c.setPlaybackSpeed(s);
                    },
                    extra: [audioButton],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
