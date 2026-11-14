import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../core/native/native_bridge.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../files/domain/file_item.dart';
import '../viewer/audio_engine.dart';
import '../viewer/file_neighbors.dart';
import '../viewer/viewer_chrome.dart';
import '../viewer/viewer_prefs.dart';
import 'subtitle_parser.dart';
import 'video_models.dart';
import 'video_prefs.dart';
import 'video_settings_screen.dart';

List<String> _listFileNames(String dir) {
  try {
    return Directory(dir).listSync().whereType<File>().map((f) => p.basename(f.path)).toList();
  } catch (_) {
    return const [];
  }
}

class _Hud {
  const _Hud(this.icon, this.text, {this.value, this.alignment = Alignment.center});

  final IconData icon;
  final String text;
  final double? value;
  final Alignment alignment;
}

/// Video player v1: own gestures, subtitles, aspect modes, resume, folder queue, audio-only.
/// The picture is decoded by the phone's own decoders (video_player / ExoPlayer).
/// No ads are ever shown on this screen.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});

  final FileItem item;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> with WidgetsBindingObserver {
  late final VideoHistoryNotifier _history = ref.read(videoHistoryProvider.notifier);
  late VideoSettings _s = ref.read(videoSettingsProvider);
  late FileItem _item = widget.item;

  VideoPlayerController? _c;
  VideoInfo? _info;
  String? _error;
  bool _loading = true;
  bool _ended = false;
  bool _completing = false;
  bool _lastPlaying = false;

  // queue
  List<FileItem> _queue = [];
  List<int> _order = [];
  int _qIndex = 0;
  VideoRepeat _repeat = VideoRepeat.off;
  bool _shuffle = false;

  // display
  late AspectMode _aspect = _s.defaultAspect;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _speed = 1;
  Size _box = Size.zero;

  // controls
  final ValueNotifier<Duration> _pos = ValueNotifier(Duration.zero);
  final ValueNotifier<int?> _scrub = ValueNotifier(null);
  final ValueNotifier<_Hud?> _hud = ValueNotifier(null);
  bool _controls = true;
  bool _locked = false;
  bool _showRemaining = false;
  Timer? _hideTimer;
  Timer? _hudTimer;
  Duration? _resumedAt;
  Timer? _bannerTimer;
  int _lastSaveSec = 0;

  // gestures
  int _dragMode = 0; // 0 none, 1 seek, 2 brightness, 3 volume, 4 pan, 5 pinch
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;
  double _startPanX = 0;
  double _startPanY = 0;
  Duration _seekStart = Duration.zero;
  Duration? _seekTarget;
  double _bright = 0.5;
  double _vol = 0.5;
  double _startBright = 0.5;
  double _startVol = 0.5;
  Offset _tapAt = Offset.zero;
  double _speedBeforeLongPress = 1;

  // subtitles
  List<SubCue> _cues = [];
  String? _subPath;
  int _subDelayMs = 0;
  String _subEncoding = 'auto';
  bool _subOn = true;
  List<String> _sidecars = [];

  // audio-only mode (sound continues in the audio engine: notification + background)
  bool _audioMode = false;
  bool _autoAudio = false;
  bool _audioPlaying = false;
  StreamSubscription<Duration>? _audioPosSub;
  StreamSubscription<PlayerState>? _audioStateSub;

  AudioPlayer get _ap => AudioEngine.instance.player;

  bool get _isPlaying => _audioMode ? _audioPlaying : (_c?.value.isPlaying ?? false);

  Duration get _duration => _c?.value.duration ?? Duration.zero;

  // ------------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_s.keepScreenOn) NativeBridge.instance.keepScreenOn(true);
    NativeBridge.instance.getBrightness().then((v) => _bright = v);
    NativeBridge.instance.getVolume().then((v) => _vol = v ?? _vol);
    _open(widget.item);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQueue());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _bannerTimer?.cancel();
    _audioPosSub?.cancel();
    _audioStateSub?.cancel();
    _saveProgress();
    final c = _c;
    c?.removeListener(_onTick);
    c?.dispose();
    if (_audioMode) AudioEngine.instance.stop();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    NativeBridge.instance.keepScreenOn(false);
    NativeBridge.instance.setBrightness(-1);
    _pos.dispose();
    _scrub.dispose();
    _hud.dispose();
    super.dispose();
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

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  // ------------------------------------------------------------------ queue

  Future<void> _loadQueue() async {
    final list = await loadSiblings(ref, widget.item);
    if (!mounted) return;
    final idx = list.indexWhere((f) => f.path == _item.path);
    setState(() {
      _queue = list;
      _qIndex = idx < 0 ? 0 : idx;
      _order = buildOrder(list.length, shuffle: _shuffle, first: _qIndex, seed: DateTime.now().millisecondsSinceEpoch);
    });
  }

  int? get _nextIndex => nextInOrder(_order, _qIndex, wrap: _repeat == VideoRepeat.all);

  int? get _prevIndex => previousInOrder(_order, _qIndex, wrap: _repeat == VideoRepeat.all);

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _qIndex = index;
    await _open(_queue[index]);
  }

  // ------------------------------------------------------------------ opening

  Future<void> _open(FileItem item) async {
    await _saveProgress();
    final old = _c;
    old?.removeListener(_onTick);
    _c = null;
    if (_audioMode) await _toVideoCleanup();
    setState(() {
      _item = item;
      _loading = true;
      _error = null;
      _ended = false;
      _completing = false;
      _info = null;
      _cues = [];
      _subPath = null;
      _subDelayMs = 0;
      _sidecars = [];
      _zoom = 1;
      _panX = 0;
      _panY = 0;
      _resumedAt = null;
      _pos.value = Duration.zero;
    });
    await old?.dispose();

    if (item.size == 0) {
      setState(() {
        _loading = false;
        _error = 'This file is empty (0 bytes), so there is nothing to play.';
      });
      return;
    }

    final c = VideoPlayerController.file(File(item.path));
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      final info = await NativeBridge.instance.videoInfo(item.path);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _info = info;
        _error = explainPlaybackError(info);
      });
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    _c = c;
    c.addListener(_onTick);
    await c.setLooping(_repeat == VideoRepeat.one);
    await c.setPlaybackSpeed(_speed);
    _applyOrientation(c);
    _lastPlaying = false;
    _lastSaveSec = 0;
    setState(() => _loading = false);

    unawaited(_afterOpen(item, c));

    // resume point
    final record = _history.of(item.path);
    final resume = record == null ? null : resumePoint(Duration(milliseconds: record.positionMs), c.value.duration);
    if (resume != null && _s.resumeMode != ResumeMode.never) {
      var doResume = true;
      if (_s.resumeMode == ResumeMode.ask) {
        doResume = await _askResume(resume) ?? true;
      }
      if (doResume && mounted) {
        await c.seekTo(resume);
        _showResumeBanner(resume);
      }
    }
    if (!mounted) return;
    await c.play();
    _scheduleHide();
  }

  Future<bool?> _askResume(Duration at) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Continue watching?'),
        content: Text('You stopped at ${formatClock(at)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Start over')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Resume ${formatClock(at)}')),
        ],
      ),
    );
  }

  void _showResumeBanner(Duration at) {
    setState(() => _resumedAt = at);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _resumedAt = null);
    });
  }

  Future<void> _afterOpen(FileItem item, VideoPlayerController c) async {
    final info = await NativeBridge.instance.videoInfo(item.path);
    if (mounted && _item.path == item.path) setState(() => _info = info);

    // subtitles next to the video
    final names = await compute(_listFileNames, p.dirname(item.path));
    if (!mounted || _item.path != item.path) return;
    final found = findSidecarNames(item.name, names).map((n) => p.join(p.dirname(item.path), n)).toList();
    setState(() => _sidecars = found);
    final record = _history.of(item.path);
    if (record?.subtitle != null && File(record!.subtitle!).existsSync()) {
      _subDelayMs = record.subDelayMs;
      await _loadSubtitleFile(record.subtitle!, quiet: true);
    } else if (_s.subAuto && found.isNotEmpty) {
      await _loadSubtitleFile(found.first, quiet: true);
    }
  }

  void _applyOrientation(VideoPlayerController c) {
    switch (_s.orientation) {
      case OrientationMode.auto:
        final wide = c.value.aspectRatio >= 1;
        SystemChrome.setPreferredOrientations(wide
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      case OrientationMode.sensor:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      case OrientationMode.landscape:
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      case OrientationMode.portrait:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _rotate() {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      landscape ? [DeviceOrientation.portraitUp] : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
    _scheduleHide();
  }

  // ------------------------------------------------------------------ ticking

  void _onTick() {
    final c = _c;
    if (c == null) return;
    final v = c.value;
    if (!_audioMode) _pos.value = v.position;
    if (v.hasError && _error == null && mounted) {
      setState(() => _error = 'Playback stopped: ${v.errorDescription ?? 'unknown error'}');
      return;
    }
    if (v.isPlaying != _lastPlaying) {
      _lastPlaying = v.isPlaying;
      if (mounted) setState(() {});
      if (v.isPlaying) _scheduleHide();
    }
    if (!_completing &&
        !_audioMode &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 300) &&
        !v.isPlaying &&
        !v.isLooping) {
      _completing = true;
      _onCompleted();
    }
    if (v.isPlaying && (v.position.inSeconds - _lastSaveSec).abs() >= 8) {
      _lastSaveSec = v.position.inSeconds;
      _saveProgress();
    }
  }

  Future<void> _onCompleted() async {
    final c = _c;
    if (c != null) {
      // finished: next time it starts from the beginning
      await _history.record(_item.path, position: Duration.zero, duration: c.value.duration, subtitle: _subPath, subDelayMs: _subDelayMs);
    }
    final next = _nextIndex;
    if (next != null && (_s.autoNext || _repeat == VideoRepeat.all)) {
      await _playIndex(next);
    } else if (mounted) {
      setState(() {
        _ended = true;
        _controls = true;
      });
    }
  }

  Future<void> _saveProgress() async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration;
    if (dur <= Duration.zero) return;
    final pos = _audioMode ? _pos.value : c.value.position;
    await _history.record(
      _item.path,
      position: pos > dur - const Duration(seconds: 10) ? Duration.zero : pos,
      duration: dur,
      subtitle: _subPath,
      subDelayMs: _subDelayMs,
    );
  }

  // ------------------------------------------------------------------ playback helpers

  Future<void> _togglePlay() async {
    final c = _c;
    if (c == null) return;
    if (_ended) {
      setState(() {
        _ended = false;
        _completing = false;
      });
      await _seekTo(Duration.zero);
    }
    if (_audioMode) {
      _audioPlaying ? await _ap.pause() : await _ap.play();
    } else {
      c.value.isPlaying ? await c.pause() : await c.play();
    }
    _scheduleHide();
    if (mounted) setState(() {});
  }

  Future<void> _seekTo(Duration target) async {
    final c = _c;
    if (c == null) return;
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    if (t > c.value.duration) t = c.value.duration;
    _completing = false;
    if (_audioMode) {
      await _ap.seek(t);
    } else {
      await c.seekTo(t);
    }
    _pos.value = t;
  }

  Future<void> _seekBy(int seconds, {Alignment hudAt = Alignment.center}) async {
    final cur = _pos.value;
    await _seekTo(cur + Duration(seconds: seconds));
    _showHud(_Hud(seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, '${seconds > 0 ? '+' : ''}$seconds s', alignment: hudAt));
    _scheduleHide();
  }

  Future<void> _setSpeed(double s) async {
    _speed = s;
    final c = _c;
    if (c == null) return;
    if (_audioMode) {
      await _ap.setSpeed(s);
    } else {
      await c.setPlaybackSpeed(s);
    }
    if (mounted) setState(() {});
  }

  void _cycleRepeat() {
    final next = VideoRepeat.values[(_repeat.index + 1) % VideoRepeat.values.length];
    setState(() => _repeat = next);
    _c?.setLooping(next == VideoRepeat.one);
    _toast(next == VideoRepeat.off ? 'Repeat off' : (next == VideoRepeat.one ? 'Repeat this video' : 'Repeat all'));
  }

  void _toggleShuffle() {
    setState(() {
      _shuffle = !_shuffle;
      _order = buildOrder(_queue.length, shuffle: _shuffle, first: _qIndex, seed: DateTime.now().millisecondsSinceEpoch);
    });
    _toast(_shuffle ? 'Shuffle on' : 'Shuffle off');
  }

  // ------------------------------------------------------------------ audio only / background

  Future<void> _toAudio({required bool auto}) async {
    final c = _c;
    if (c == null || _audioMode) return;
    final pos = c.value.position;
    _audioMode = true;
    _autoAudio = auto;
    await c.pause();
    if (mounted) setState(() {});
    try {
      await AudioEngine.instance.load(_item.path, _item.name, start: pos);
      await _ap.setSpeed(_speed);
      _audioPosSub = _ap.positionStream.listen((d) => _pos.value = d);
      _audioStateSub = _ap.playerStateStream.listen((st) {
        final playing = st.playing && st.processingState != ProcessingState.completed;
        if (playing != _audioPlaying && mounted) setState(() => _audioPlaying = playing);
      });
      unawaited(_ap.play());
    } catch (_) {
      _audioMode = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toVideoCleanup() async {
    await _audioPosSub?.cancel();
    await _audioStateSub?.cancel();
    _audioPosSub = null;
    _audioStateSub = null;
    await AudioEngine.instance.stop();
    _audioMode = false;
    _autoAudio = false;
    _audioPlaying = false;
  }

  Future<void> _toVideo() async {
    final c = _c;
    if (c == null || !_audioMode) return;
    final pos = _ap.position;
    await _toVideoCleanup();
    await c.seekTo(pos);
    await c.play();
    if (mounted) setState(() {});
    _scheduleHide();
  }

  // ------------------------------------------------------------------ subtitles

  Future<void> _loadSubtitleFile(String path, {bool quiet = false}) async {
    try {
      final bytes = await File(path).readAsBytes();
      final text = decodeSubtitleBytes(bytes, encoding: _subEncoding);
      final cues = parseSubtitles(text, ext: p.extension(path).replaceFirst('.', ''));
      if (cues.isEmpty) {
        if (!quiet) _toast('No subtitles found in this file.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _cues = cues;
        _subPath = path;
        _subOn = true;
      });
      unawaited(_saveProgress());
    } catch (_) {
      if (!quiet) _toast('Could not read this subtitle file.');
    }
  }

  Future<void> _browseSubtitle() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } catch (_) {
      _toast('Could not open the file picker.');
      return;
    }
    final path = picked?.path;
    if (path == null) return;
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!subtitleExtensions.contains(ext)) {
      _toast('Choose a subtitle file: .srt, .vtt, .ass or .ssa');
      return;
    }
    await _loadSubtitleFile(path);
  }

  void _openSubtitleSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void both(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          Future<void> style(VideoSettings Function(VideoSettings) f) async {
            await ref.read(videoSettingsProvider.notifier).update(f);
            both(() => _s = ref.read(videoSettingsProvider));
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Show subtitles'),
                    value: _subOn,
                    onChanged: _cues.isEmpty ? null : (v) => both(() => _subOn = v),
                  ),
                  if (_sidecars.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text('Found next to the video', style: TextStyle(fontWeight: FontWeight.w700))),
                    for (final path in _sidecars)
                      ListTile(
                        dense: true,
                        leading: Icon(_subPath == path ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                        title: Text(sidecarLabel(p.basename(path), _item.name)),
                        subtitle: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () async {
                          await _loadSubtitleFile(path);
                          setSheet(() {});
                        },
                      ),
                  ],
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded),
                    title: const Text('Choose a subtitle file...'),
                    subtitle: Text(_subPath == null ? 'SRT, VTT, ASS, SSA' : 'Now: ${p.basename(_subPath!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      await _browseSubtitle();
                      setSheet(() {});
                    },
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Delay: ${_subDelayMs >= 0 ? '+' : ''}${(_subDelayMs / 1000).toStringAsFixed(1)} s', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final ms in const [-1000, -100, 100, 1000])
                          OutlinedButton(
                            onPressed: () {
                              both(() => _subDelayMs += ms);
                              _saveProgress();
                            },
                            child: Text('${ms > 0 ? '+' : ''}${ms.abs() >= 1000 ? '${ms ~/ 1000} s' : '$ms ms'}'),
                          ),
                        TextButton(
                          onPressed: () {
                            both(() => _subDelayMs = 0);
                            _saveProgress();
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Size: ${_s.subSize}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Slider(
                    value: _s.subSize.toDouble(),
                    min: 12,
                    max: 48,
                    divisions: 18,
                    onChanged: (v) => style((s) => s.copyWith(subSize: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text('Colour', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        for (var i = 0; i < subtitleColors.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () => style((s) => s.copyWith(subColor: i)),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Color(subtitleColors[i]),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _s.subColor == i ? Theme.of(context).colorScheme.primary : Colors.black26, width: _s.subColor == i ? 3 : 1),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Outline'),
                    value: _s.subOutline,
                    onChanged: (v) => style((s) => s.copyWith(subOutline: v)),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Dark background'),
                    value: _s.subBackground,
                    onChanged: (v) => style((s) => s.copyWith(subBackground: v)),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Height from the bottom: ${_s.subBottom}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Slider(
                    value: _s.subBottom.toDouble(),
                    min: 0,
                    max: 200,
                    onChanged: (v) => style((s) => s.copyWith(subBottom: v.round())),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('Old subtitle file shows strange letters?'),
                    subtitle: Text(_subEncoding == 'auto' ? 'Tap to read it as Latin-1 (Windows-1252)' : 'Reading as Latin-1. Tap to go back to automatic'),
                    onTap: () async {
                      both(() => _subEncoding = _subEncoding == 'auto' ? 'latin1' : 'auto');
                      if (_subPath != null) await _loadSubtitleFile(_subPath!);
                      setSheet(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(_scheduleHide);
  }

  // ------------------------------------------------------------------ controls visibility + HUD

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: _s.controlsHideSeconds), () {
      if (mounted && _isPlaying && _scrub.value == null) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _showHud(_Hud h, {int ms = 900}) {
    _hud.value = h;
    _hudTimer?.cancel();
    _hudTimer = Timer(Duration(milliseconds: ms), () => _hud.value = null);
  }

  // ------------------------------------------------------------------ gestures

  void _onScaleStart(ScaleStartDetails d) {
    if (_locked) return;
    _startFocal = d.localFocalPoint;
    _startZoom = _zoom;
    _startPanX = _panX;
    _startPanY = _panY;
    _dragMode = 0;
    NativeBridge.instance.getVolume().then((v) {
      if (v != null) _vol = v;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_locked || !_s.gestures || _audioMode) return;
    final c = _c;
    if (c == null) return;

    if (d.pointerCount >= 2) {
      if (!_s.pinchZoom) return;
      _dragMode = 5;
      final z = (_startZoom * d.scale).clamp(1.0, 6.0);
      final delta = d.localFocalPoint - _startFocal;
      final size = _contentSize(c);
      final pan = clampPan(_startPanX + delta.dx, _startPanY + delta.dy, contentW: size.$1, contentH: size.$2, boxW: _box.width, boxH: _box.height, scale: z);
      setState(() {
        _zoom = z;
        _panX = pan.$1;
        _panY = pan.$2;
      });
      _showHud(_Hud(Icons.zoom_in_rounded, '${(z * 100).round()}%'), ms: 700);
      return;
    }

    final delta = d.localFocalPoint - _startFocal;
    if (_dragMode == 0) {
      if (delta.distance < 14) return;
      if (_zoom > 1.01) {
        _dragMode = 4;
      } else if (delta.dx.abs() > delta.dy.abs()) {
        if (!_s.seekGesture) return;
        _dragMode = 1;
        _seekStart = _pos.value;
      } else {
        final leftHalf = _startFocal.dx < _box.width / 2;
        final brightnessSide = _s.leftHanded ? !leftHalf : leftHalf;
        if (brightnessSide) {
          if (!_s.brightnessGesture) return;
          _dragMode = 2;
          _startBright = _bright;
        } else {
          if (!_s.volumeGesture) return;
          _dragMode = 3;
          _startVol = _vol;
        }
      }
    }

    switch (_dragMode) {
      case 1:
        final deltaMs = seekDeltaMs(delta.dx, _box.width, _duration.inMilliseconds, _s.sensitivity);
        var target = _seekStart + Duration(milliseconds: deltaMs);
        if (target < Duration.zero) target = Duration.zero;
        if (target > _duration) target = _duration;
        _seekTarget = target;
        final diff = target - _seekStart;
        _showHud(
          _Hud(diff.isNegative ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
              '${diff.isNegative ? '-' : '+'}${formatClock(diff.abs())}\n${formatClock(target)} / ${formatClock(_duration)}'),
          ms: 1200,
        );
      case 2:
        final bright = adjustFraction(_startBright, delta.dy, _box.height, _s.sensitivity);
        _bright = bright;
        NativeBridge.instance.setBrightness(bright);
        _showHud(_Hud(Icons.brightness_6_rounded, '${(bright * 100).round()}%', value: bright, alignment: _s.leftHanded ? Alignment.centerRight : Alignment.centerLeft), ms: 900);
      case 3:
        final vol = adjustFraction(_startVol, delta.dy, _box.height, _s.sensitivity);
        _vol = vol;
        NativeBridge.instance.setVolume(vol);
        _showHud(_Hud(vol == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '${(vol * 100).round()}%', value: vol, alignment: _s.leftHanded ? Alignment.centerLeft : Alignment.centerRight), ms: 900);
      case 4:
        final contentSize = _contentSize(c);
        final panned = clampPan(_startPanX + delta.dx, _startPanY + delta.dy, contentW: contentSize.$1, contentH: contentSize.$2, boxW: _box.width, boxH: _box.height, scale: _zoom);
        setState(() {
          _panX = panned.$1;
          _panY = panned.$2;
        });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragMode == 1 && _seekTarget != null) {
      _seekTo(_seekTarget!);
    }
    if (_dragMode == 5 && _zoom < 1.02) {
      setState(() {
        _zoom = 1;
        _panX = 0;
        _panY = 0;
      });
    }
    _seekTarget = null;
    _dragMode = 0;
  }

  (double, double) _contentSize(VideoPlayerController c) {
    final vs = c.value.size;
    return displaySizeFor(_aspect,
        videoW: vs.width, videoH: vs.height, boxW: _box.width, boxH: _box.height, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
  }

  void _onDoubleTap() {
    if (_locked || !_s.gestures) return;
    final w = _box.width;
    final x = _tapAt.dx;
    if (_s.doubleTapSkip && x < w * 0.35) {
      _seekBy(-_s.skipSeconds, hudAt: Alignment.centerLeft);
    } else if (_s.doubleTapSkip && x > w * 0.65) {
      _seekBy(_s.skipSeconds, hudAt: Alignment.centerRight);
    } else {
      _togglePlay();
      _showHud(_Hud(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, _isPlaying ? 'Pause' : 'Play'), ms: 600);
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_locked || !_s.gestures || !_s.longPressSpeed || _audioMode) return;
    _speedBeforeLongPress = _speed;
    _setSpeed(_s.longPressRate);
    _showHud(_Hud(Icons.speed_rounded, '${_s.longPressRate}x'), ms: 60000);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_locked || !_s.gestures || !_s.longPressSpeed || _audioMode) return;
    _setSpeed(_speedBeforeLongPress);
    _hud.value = null;
  }

  // ------------------------------------------------------------------ sheets

  void _showInfo() {
    final i = _info;
    final scheme = Theme.of(context).colorScheme;
    String line(String a, String b) => '$a: $b';
    final rows = <String>[
      line('Name', _item.name),
      line('Size', formatSize(_item.size)),
      line('Folder', p.dirname(_item.path)),
      if (i != null) ...[
        if (i.mime != null) line('Container', i.mime!),
        line('Duration', formatClock(i.duration)),
        if (i.width > 0) line('Resolution', '${i.width} x ${i.height}${i.rotation != 0 ? '  (rotated ${i.rotation} deg)' : ''}'),
        if (i.fps != null) line('Frame rate', '${i.fps!.toStringAsFixed(1)} fps'),
        if (i.bitrate > 0) line('Bit rate', '${(i.bitrate / 1000000).toStringAsFixed(2)} Mbit/s'),
        for (final t in i.video) line('Video', '${codecLabel(t.mime)}${t.width != null ? '  ${t.width}x${t.height}' : ''}${t.fps != null ? '  ${t.fps!.toStringAsFixed(1)} fps' : ''}'),
        for (final t in i.audio) line('Audio', '${codecLabel(t.mime)}${t.lang != null && t.lang != 'und' ? '  ${t.lang}' : ''}${t.channels != null ? '  ${t.channels} ch' : ''}${t.sampleRate != null ? '  ${t.sampleRate} Hz' : ''}'),
        for (final t in i.text) line('Subtitle track', '${codecLabel(t.mime)}${t.lang != null && t.lang != 'und' ? '  ${t.lang}' : ''}'),
      ] else
        'Stream details are not available for this file.',
      line('Decoder', 'the phone\'s own (hardware when available)'),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            shrinkWrap: true,
            children: [
              const Text('Video details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final r in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: SelectableText(r, style: TextStyle(color: scheme.onSurface, fontSize: 13.5))),
              if (i != null && i.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Subtitle tracks inside the video cannot be shown yet. Use a .srt/.vtt/.ass file instead.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                ),
              if (i != null && i.audio.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('This video has several audio tracks. Choosing a track needs the next engine step.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueue() {
    if (_queue.isEmpty) {
      _toast('No other videos in this folder.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _queue.length,
            itemBuilder: (context, i) {
              final f = _queue[i];
              final current = i == _qIndex;
              return ListTile(
                dense: true,
                selected: current,
                leading: Icon(current ? Icons.play_circle_rounded : Icons.movie_rounded),
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatSize(f.size)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!current) _playIndex(i);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    _hideTimer?.cancel();
    await Navigator.of(context).push(fadeSlideRoute(const VideoSettingsScreen()));
    if (!mounted) return;
    setState(() => _s = ref.read(videoSettingsProvider));
    final c = _c;
    if (c != null) _applyOrientation(c);
    NativeBridge.instance.keepScreenOn(_s.keepScreenOn);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _toast('The screen is locked. Hold the lock button to unlock.');
      },
      child: Scaffold(backgroundColor: Colors.black, body: _body()),
    );
  }

  Widget _body() {
    if (_error != null) return _errorView();
    final c = _c;
    if (_loading || c == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return LayoutBuilder(
      builder: (context, cons) {
        _box = Size(cons.maxWidth, cons.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTapDown: (d) => _tapAt = d.localPosition,
                onDoubleTap: _onDoubleTap,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: ColoredBox(color: Colors.black, child: _audioMode ? _audioArt() : _picture(c)),
              ),
            ),
            if (!_audioMode) _subtitleLayer(),
            _hudLayer(),
            _resumeBanner(),
            if (_ended)
              Center(
                child: IconButton.filled(
                  iconSize: 56,
                  icon: const Icon(Icons.replay_rounded),
                  tooltip: 'Play again',
                  onPressed: _togglePlay,
                ),
              ),
            _controlsLayer(),
          ],
        );
      },
    );
  }

  Widget _picture(VideoPlayerController c) {
    final vs = c.value.size;
    final (dw, dh) = displaySizeFor(_aspect,
        videoW: vs.width, videoH: vs.height, boxW: _box.width, boxH: _box.height, devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    return ClipRect(
      child: Center(
        child: Transform.translate(
          offset: Offset(_panX, _panY),
          child: Transform.scale(
            scale: _zoom,
            child: SizedBox(width: dw, height: dh, child: VideoPlayer(c)),
          ),
        ),
      ),
    );
  }

  Widget _audioArt() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.headphones_rounded, size: 76, color: Colors.white),
          ),
          const SizedBox(height: 18),
          const Text('Audio only', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Keeps playing in the background', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _subtitleLayer() {
    if (!_subOn || _cues.isEmpty) return const SizedBox.shrink();
    final color = Color(subtitleColors[_s.subColor.clamp(0, subtitleColors.length - 1)]);
    return Positioned(
      left: 24,
      right: 24,
      bottom: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder<Duration>(
          valueListenable: _pos,
          builder: (context, pos, _) {
            final active = cuesAt(_cues, pos, delay: Duration(milliseconds: _subDelayMs));
            if (active.isEmpty) return const SizedBox.shrink();
            final text = active.map((c) => c.text).join('\n');
            final size = _s.subSize.toDouble();
            final fill = TextStyle(fontSize: size, height: 1.25, fontWeight: FontWeight.w600, color: color);
            final stroke = TextStyle(
              fontSize: size,
              height: 1.25,
              fontWeight: FontWeight.w600,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.2
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.black,
            );
            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.only(bottom: _s.subBottom.toDouble() + (_controls ? 96 : 0)),
              child: Container(
                padding: _s.subBackground ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : EdgeInsets.zero,
                decoration: _s.subBackground ? BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)) : null,
                child: Stack(
                  children: [
                    if (_s.subOutline) Text(text, textAlign: TextAlign.center, style: stroke),
                    Text(text, textAlign: TextAlign.center, style: fill),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _hudLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<_Hud?>(
          valueListenable: _hud,
          builder: (context, h, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: h == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Align(
                      key: ValueKey('${h.icon.codePoint}${h.alignment}'),
                      alignment: h.alignment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(18)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(h.icon, color: Colors.white, size: 30),
                              const SizedBox(height: 6),
                              Text(h.text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                              if (h.value != null) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: 90,
                                  child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: h.value, minHeight: 5)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _resumeBanner() {
    final at = _resumedAt;
    if (at == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 120,
      child: Center(
        child: Material(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Resumed at ${formatClock(at)}', style: const TextStyle(color: Colors.white)),
                TextButton(
                  onPressed: () {
                    _seekTo(Duration.zero);
                    setState(() => _resumedAt = null);
                  },
                  child: const Text('Start over'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return SafeArea(
      child: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(color: Colors.white, icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop())),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 56),
                    const SizedBox(height: 14),
                    Text(_item.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.35)),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => NativeBridge.instance.openWith(_item.path),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Open with another app'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showInfo,
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('Details'),
                        ),
                        if (_nextIndex != null)
                          OutlinedButton.icon(
                            onPressed: () => _playIndex(_nextIndex!),
                            icon: const Icon(Icons.skip_next_rounded),
                            label: const Text('Next video'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ controls overlay

  Widget _controlsLayer() {
    if (_locked) {
      return Positioned.fill(
        child: IgnorePointer(
          ignoring: !_controls,
          child: AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    onLongPress: () {
                      setState(() => _locked = false);
                      _toast('Unlocked');
                      _scheduleHide();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, color: Colors.white, size: 28),
                          SizedBox(height: 4),
                          Text('Hold to\nunlock', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final c = _c!;
    final queueText = _queue.length > 1 ? '${_qIndex + 1} / ${_queue.length}' : null;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Column(
            children: [
              // ---- top bar
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent])),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(color: Colors.white, icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                            if (queueText != null) Text(queueText, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Subtitles',
                        color: _cues.isNotEmpty && _subOn ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
                        icon: const Icon(Icons.closed_caption_rounded),
                        onPressed: _openSubtitleSheet,
                      ),
                      ViewerActions(item: _item, color: Colors.white, hide: const {ViewerAction.neighbors}),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // ---- centre buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    tooltip: 'Previous video',
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: _prevIndex == null ? null : () => _playIndex(_prevIndex!),
                  ),
                  const SizedBox(width: 10),
                  IconButton(iconSize: 40, color: Colors.white, tooltip: 'Back ${_s.skipSeconds} s', icon: _SkipIcon(back: true, seconds: _s.skipSeconds), onPressed: () => _seekBy(-_s.skipSeconds)),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    iconSize: 46,
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                    icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 10),
                  IconButton(iconSize: 40, color: Colors.white, tooltip: 'Forward ${_s.skipSeconds} s', icon: _SkipIcon(back: false, seconds: _s.skipSeconds), onPressed: () => _seekBy(_s.skipSeconds)),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 36,
                    color: Colors.white,
                    tooltip: 'Next video',
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: _nextIndex == null ? null : () => _playIndex(_nextIndex!),
                  ),
                ],
              ),
              const Spacer(),
              // ---- bottom bar
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)])),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _seekBar(c),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            _btn(Icons.lock_open_rounded, 'Lock screen', () {
                              setState(() {
                                _locked = true;
                                _controls = true;
                              });
                              _scheduleHide();
                              _toast('Locked. Hold the lock button to unlock.');
                            }),
                            _chip(Icons.aspect_ratio_rounded, _aspect.label, () {
                              setState(() {
                                _aspect = AspectMode.values[(_aspect.index + 1) % AspectMode.values.length];
                                _zoom = 1;
                                _panX = 0;
                                _panY = 0;
                              });
                              _showHud(_Hud(Icons.aspect_ratio_rounded, _aspect.label), ms: 700);
                              _scheduleHide();
                            }),
                            PopupMenuButton<double>(
                              tooltip: 'Speed',
                              initialValue: _speed,
                              onOpened: () => _hideTimer?.cancel(),
                              onSelected: (v) {
                                _setSpeed(v);
                                _scheduleHide();
                              },
                              itemBuilder: (context) => [for (final s in const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0]) PopupMenuItem(value: s, child: Text('${s}x'))],
                              child: _chipBody(Icons.speed_rounded, '${_speed}x'),
                            ),
                            _btn(Icons.screen_rotation_rounded, 'Rotate', _rotate),
                            _btn(_repeat == VideoRepeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, 'Repeat', _cycleRepeat, on: _repeat != VideoRepeat.off),
                            _btn(Icons.shuffle_rounded, 'Shuffle', _toggleShuffle, on: _shuffle),
                            _btn(_audioMode ? Icons.videocam_rounded : Icons.headphones_rounded, _audioMode ? 'Show video' : 'Audio only (plays in the background)', () => _audioMode ? _toVideo() : _toAudio(auto: false), on: _audioMode),
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              iconColor: Colors.white,
                              onOpened: () => _hideTimer?.cancel(),
                              onSelected: (v) {
                                switch (v) {
                                  case 'info':
                                    _showInfo();
                                  case 'queue':
                                    _showQueue();
                                  case 'settings':
                                    _openSettings();
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'info', child: Text('Video details')),
                                PopupMenuItem(value: 'queue', child: Text('Playlist (this folder)')),
                                PopupMenuItem(value: 'settings', child: Text('Player settings')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seekBar(VideoPlayerController c) {
    return ListenableBuilder(
      listenable: Listenable.merge([_pos, _scrub]),
      builder: (context, _) {
        final dur = c.value.duration;
        final maxMs = math.max(1, dur.inMilliseconds);
        final shownMs = (_scrub.value ?? _pos.value.inMilliseconds).clamp(0, maxMs);
        final left = Duration(milliseconds: shownMs);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(formatClock(left), style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: maxMs.toDouble(),
                  value: shownMs.toDouble(),
                  onChangeStart: (v) => _hideTimer?.cancel(),
                  onChanged: (v) => _scrub.value = v.round(),
                  onChangeEnd: (v) async {
                    await _seekTo(Duration(milliseconds: v.round()));
                    _scrub.value = null;
                    _scheduleHide();
                  },
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showRemaining = !_showRemaining),
                child: Text(_showRemaining ? formatClock(left - dur) : formatClock(dur), style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {bool on = false}) {
    return IconButton(
      tooltip: tip,
      color: on ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: _chipBody(icon, label));
  }

  Widget _chipBody(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SkipIcon extends StatelessWidget {
  const _SkipIcon({required this.back, required this.seconds});

  final bool back;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(back ? Icons.replay_rounded : Icons.refresh_rounded, size: 40),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$seconds', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

/// Plain-language reason why a video did not start (also used by tests).
String explainPlaybackError(VideoInfo? info) {
  if (info == null || (info.tracks.isEmpty && info.durationMs == 0)) {
    return 'This file could not be read. It may be damaged, cut short or not a video at all.';
  }
  final v = info.video.isEmpty ? null : info.video.first;
  final a = info.audio.isEmpty ? null : info.audio.first;
  final parts = <String>[
    if (v != null) 'video ${codecLabel(v.mime)}',
    if (a != null) 'audio ${codecLabel(a.mime)}',
  ];
  final what = parts.isEmpty ? 'its streams' : parts.join(', ');
  return 'This phone could not play this video ($what). '
      'The phone\'s decoder may not support this format, or the file is damaged. '
      'You can open it with another player.';
}
