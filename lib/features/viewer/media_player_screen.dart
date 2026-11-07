import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';

/// Plays video (MP4, MKV, WEBM...) and audio (MP3, M4A, FLAC, WAV...).
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _c;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;
  double _speed = 1.0;

  bool get _isAudio => widget.item.kind == FileKind.audio;

  @override
  void initState() {
    super.initState();
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
      if (mounted) {
        setState(() => _error = 'This ${_isAudio ? 'audio' : 'video'} file could not be played on this device.\n$e');
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_isAudio) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  void _seekBy(int seconds) {
    final c = _c;
    if (c == null) return;
    final target = c.value.position + Duration(seconds: seconds);
    final max = c.value.duration;
    c.seekTo(target < Duration.zero ? Duration.zero : (target > max ? max : target));
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final scheme = Theme.of(context).colorScheme;
    final dark = !_isAudio;
    final bg = dark ? Colors.black : scheme.surface;
    final fg = dark ? Colors.white : scheme.onSurface;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 17)),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: fg))))
          : c == null
              ? Center(child: CircularProgressIndicator(color: fg))
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isAudio ? null : _toggleControls,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _isAudio ? _audioArt(scheme) : Center(child: AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio, child: VideoPlayer(c)))),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedOpacity(
                          opacity: (_showControls || _isAudio) ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: IgnorePointer(ignoring: !(_showControls || _isAudio), child: BottomSafe(child: _controls(c, fg, dark))),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _audioArt(ColorScheme scheme) {
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
            child: Text(widget.item.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Text(formatSize(widget.item.size), style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _controls(VideoPlayerController c, Color fg, bool dark) {
    final v = c.value;
    final total = v.duration.inMilliseconds;
    final pos = v.position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
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
              Text(_fmt(v.position), style: TextStyle(color: fg, fontSize: 12.5)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: (total == 0 ? 1 : total).toDouble(),
                  value: pos.toDouble(),
                  onChanged: (x) => c.seekTo(Duration(milliseconds: x.round())),
                  onChangeEnd: (_) => _scheduleHide(),
                ),
              ),
              Text(_fmt(v.duration), style: TextStyle(color: fg, fontSize: 12.5)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(iconSize: 30, color: fg, icon: const Icon(Icons.replay_10_rounded), onPressed: () => _seekBy(-10)),
              const SizedBox(width: 8),
              IconButton.filled(
                iconSize: 40,
                icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: () {
                  v.isPlaying ? c.pause() : c.play();
                  _scheduleHide();
                },
              ),
              const SizedBox(width: 8),
              IconButton(iconSize: 30, color: fg, icon: const Icon(Icons.forward_10_rounded), onPressed: () => _seekBy(10)),
              const SizedBox(width: 12),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: _speed,
                onSelected: (s) {
                  setState(() => _speed = s);
                  c.setPlaybackSpeed(s);
                },
                itemBuilder: (context) => [for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: s, child: Text('${s}x'))],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${_speed}x', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
