import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../shared/widgets/bottom_safe.dart';
import '../files/data/file_ops.dart';

// ---------------------------------------------------------------- edit model (pure, testable)

const cropLabels = ['Original', '1:1', '4:3', '3:4', '16:9', '9:16'];
const _cropRatios = <double?>[null, 1, 4 / 3, 3 / 4, 16 / 9, 9 / 16];

const filterLabels = ['Original', 'B&W', 'Sepia', 'Vivid', 'Fade', 'Drama'];

class EditParams {
  const EditParams({
    this.turns = 0,
    this.flipH = false,
    this.flipV = false,
    this.filter = 0,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.crop = 0,
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
  });

  final int turns; // quarter turns clockwise
  final bool flipH;
  final bool flipV;
  final int filter;
  final double brightness;
  final double contrast;
  final double saturation;
  final int crop;
  final double zoom;
  final double panX;
  final double panY;

  bool get isIdentity =>
      turns % 4 == 0 &&
      !flipH &&
      !flipV &&
      filter == 0 &&
      brightness == 1 &&
      contrast == 1 &&
      saturation == 1 &&
      crop == 0 &&
      zoom == 1;

  EditParams copyWith({
    int? turns,
    bool? flipH,
    bool? flipV,
    int? filter,
    double? brightness,
    double? contrast,
    double? saturation,
    int? crop,
    double? zoom,
    double? panX,
    double? panY,
  }) =>
      EditParams(
        turns: turns ?? this.turns,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        filter: filter ?? this.filter,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        crop: crop ?? this.crop,
        zoom: zoom ?? this.zoom,
        panX: panX ?? this.panX,
        panY: panY ?? this.panY,
      );
}

/// Crop rectangle (x, y, w, h) for an image of [w] x [h]. Pure math, unit tested.
List<int> cropRect(int w, int h, int cropIndex, double zoom, double panX, double panY) {
  final ratio = _cropRatios[cropIndex.clamp(0, _cropRatios.length - 1)];
  double cw = w.toDouble();
  double ch = h.toDouble();
  if (ratio != null) {
    if (w / h > ratio) {
      ch = h.toDouble();
      cw = ch * ratio;
    } else {
      cw = w.toDouble();
      ch = cw / ratio;
    }
  }
  final z = zoom < 1 ? 1.0 : zoom;
  cw /= z;
  ch /= z;
  final freeX = (w - cw) / 2;
  final freeY = (h - ch) / 2;
  final x = (freeX * (1 + panX.clamp(-1.0, 1.0))).clamp(0.0, w - cw);
  final y = (freeY * (1 + panY.clamp(-1.0, 1.0))).clamp(0.0, h - ch);
  return [x.round(), y.round(), math.max(1, cw.round()), math.max(1, ch.round())];
}

class EditJob {
  const EditJob({this.bytes, required this.path, required this.params, this.maxSide = 0, this.png = false, this.quality = 92});

  /// When set, this (already oriented + resized) picture is edited instead of reading [path].
  final Uint8List? bytes;
  final String path;
  final EditParams params;
  final int maxSide;
  final bool png;
  final int quality;
}

/// Reads the picture, fixes its rotation (EXIF), optionally shrinks it. Runs in an isolate.
Uint8List? prepareBase(EditJob job) {
  final src = File(job.path).readAsBytesSync();
  var im = img.decodeImage(src);
  if (im == null) return null;
  im = img.bakeOrientation(im);
  if (job.maxSide > 0 && (im.width > job.maxSide || im.height > job.maxSide)) {
    im = im.width >= im.height ? img.copyResize(im, width: job.maxSide) : img.copyResize(im, height: job.maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Applies all edits and returns the encoded picture. Runs in an isolate.
Uint8List? applyEdits(EditJob job) {
  img.Image? im;
  if (job.bytes != null) {
    im = img.decodeImage(job.bytes!);
  } else {
    im = img.decodeImage(File(job.path).readAsBytesSync());
    if (im != null) im = img.bakeOrientation(im);
  }
  if (im == null) return null;
  final e = job.params;

  final turns = ((e.turns % 4) + 4) % 4;
  if (turns != 0) im = img.copyRotate(im, angle: 90.0 * turns);
  if (e.flipH) im = img.flip(im, direction: img.FlipDirection.horizontal);
  if (e.flipV) im = img.flip(im, direction: img.FlipDirection.vertical);

  if (e.crop != 0 || e.zoom > 1) {
    final r = cropRect(im.width, im.height, e.crop, e.zoom, e.panX, e.panY);
    im = img.copyCrop(im, x: r[0], y: r[1], width: r[2], height: r[3]);
  }

  switch (e.filter) {
    case 1:
      im = img.grayscale(im);
    case 2:
      im = img.sepia(im);
    case 3:
      im = img.adjustColor(im, saturation: 1.45, contrast: 1.1);
    case 4:
      im = img.adjustColor(im, saturation: 0.8, contrast: 0.86, brightness: 1.08);
    case 5:
      im = img.adjustColor(im, saturation: 0.9, contrast: 1.3, brightness: 0.95);
    default:
      break;
  }
  if (e.brightness != 1 || e.contrast != 1 || e.saturation != 1) {
    im = img.adjustColor(im, brightness: e.brightness, contrast: e.contrast, saturation: e.saturation);
  }
  final out = job.png ? img.encodePng(im) : img.encodeJpg(im, quality: job.quality);
  return Uint8List.fromList(out);
}

// ---------------------------------------------------------------- screen

/// Small photo editor. Pops with `true` when the file was saved.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key, required this.path});

  final String path;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  Uint8List? _base;
  Uint8List? _preview;
  EditParams _e = const EditParams();
  bool _failed = false;
  bool _saving = false;
  int _tool = 0; // 0 crop, 1 rotate, 2 filters, 3 adjust
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    try {
      final b = await compute(prepareBase, EditJob(path: widget.path, params: const EditParams(), maxSide: 1280));
      if (!mounted) return;
      if (b == null) {
        setState(() => _failed = true);
        return;
      }
      setState(() {
        _base = b;
        _preview = b;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _set(EditParams next, {bool render = true}) {
    setState(() => _e = next);
    if (render) _render();
  }

  Future<void> _render() async {
    final base = _base;
    if (base == null) return;
    final gen = ++_gen;
    try {
      final out = await compute(applyEdits, EditJob(bytes: base, path: widget.path, params: _e, quality: 88));
      if (!mounted || gen != _gen || out == null) return;
      setState(() => _preview = out);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_e.isIdentity) {
      Navigator.of(context).pop(false);
      return;
    }
    final ext = p.extension(widget.path).toLowerCase();
    final canReplace = ext == '.jpg' || ext == '.jpeg' || ext == '.png';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Save as a copy'),
              subtitle: const Text('Keeps the original picture'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            if (canReplace)
              ListTile(
                leading: const Icon(Icons.save_rounded),
                title: const Text('Replace the original'),
                subtitle: const Text('The old picture is overwritten'),
                onTap: () => Navigator.pop(ctx, 'replace'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final png = ext == '.png';
      final bytes = await compute(applyEdits, EditJob(path: widget.path, params: _e, png: png, quality: 94));
      if (bytes == null) throw const FileOpException('This picture could not be edited.');
      final String target;
      if (choice == 'replace') {
        target = widget.path;
      } else {
        final dir = p.dirname(widget.path);
        final base = p.basenameWithoutExtension(widget.path);
        target = uniquePath(dir, '${base}_edited${png ? '.png' : '.jpg'}');
      }
      await File(target).writeAsBytes(bytes, flush: true);
      messenger.showSnackBar(SnackBar(content: Text('Saved: ${p.basename(target)}')));
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
        title: const Text('Edit photo'),
        actions: [
          TextButton(
            onPressed: _e.isIdentity ? null : () => _set(const EditParams()),
            child: const Text('Reset'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: (_base == null || _saving) ? null : _save,
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
            ),
          ),
        ],
      ),
      body: _failed
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This picture format cannot be edited here.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _preview == null
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: Image.memory(_preview!, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                ),
                BottomSafe(
                  child: Container(
                    color: scheme.surfaceContainerHigh,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 150, child: _panel(scheme)),
                        Row(
                          children: [
                            for (final t in const [
                              (Icons.crop_rounded, 'Crop'),
                              (Icons.rotate_90_degrees_cw_rounded, 'Rotate'),
                              (Icons.auto_awesome_rounded, 'Filters'),
                              (Icons.tune_rounded, 'Adjust'),
                            ].indexed)
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _tool = t.$1),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(t.$2.$1, color: _tool == t.$1 ? scheme.primary : scheme.onSurfaceVariant),
                                        const SizedBox(height: 2),
                                        Text(
                                          t.$2.$2,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: _tool == t.$1 ? FontWeight.w800 : FontWeight.w500,
                                            color: _tool == t.$1 ? scheme.primary : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _panel(ColorScheme scheme) {
    switch (_tool) {
      case 0:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < cropLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cropLabels[i]),
                        selected: _e.crop == i,
                        onSelected: (_) => _set(_e.copyWith(crop: i, panX: 0, panY: 0)),
                      ),
                    ),
                ],
              ),
            ),
            _slider('Zoom', _e.zoom, 1, 3, (v) => setState(() => _e = _e.copyWith(zoom: v)), (v) => _render()),
            if (_e.zoom > 1 || _e.crop != 0) ...[
              _slider('Move left / right', _e.panX, -1, 1, (v) => setState(() => _e = _e.copyWith(panX: v)), (v) => _render()),
              _slider('Move up / down', _e.panY, -1, 1, (v) => setState(() => _e = _e.copyWith(panY: v)), (v) => _render()),
            ],
          ],
        );
      case 1:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _toolButton(Icons.rotate_left_rounded, 'Left', () => _set(_e.copyWith(turns: _e.turns - 1))),
            _toolButton(Icons.rotate_right_rounded, 'Right', () => _set(_e.copyWith(turns: _e.turns + 1))),
            _toolButton(Icons.flip_rounded, 'Flip', () => _set(_e.copyWith(flipH: !_e.flipH))),
            _toolButton(Icons.flip_rounded, 'Mirror', () => _set(_e.copyWith(flipV: !_e.flipV)), turns: 1),
          ],
        );
      case 2:
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(14),
          children: [
            for (var i = 0; i < filterLabels.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => _set(_e.copyWith(filter: i)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _e.filter == i ? scheme.primary : scheme.outlineVariant, width: _e.filter == i ? 2.5 : 1),
                      gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]),
                    ),
                    alignment: Alignment.center,
                    child: Text(filterLabels[i], style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                  ),
                ),
              ),
          ],
        );
      default:
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          children: [
            _slider('Brightness', _e.brightness, 0.5, 1.5, (v) => setState(() => _e = _e.copyWith(brightness: v)), (v) => _render()),
            _slider('Contrast', _e.contrast, 0.5, 1.5, (v) => setState(() => _e = _e.copyWith(contrast: v)), (v) => _render()),
            _slider('Color', _e.saturation, 0.0, 2.0, (v) => setState(() => _e = _e.copyWith(saturation: v)), (v) => _render()),
          ],
        );
    }
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, ValueChanged<double> onEnd) {
    return Row(
      children: [
        SizedBox(width: 108, child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: onEnd)),
      ],
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap, {int turns = 0}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(quarterTurns: turns, child: Icon(icon, size: 30)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
