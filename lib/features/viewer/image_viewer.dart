import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../files/domain/file_item.dart';
import 'file_neighbors.dart';
import 'image_editor_screen.dart';
import 'viewer_chrome.dart';
import 'viewer_prefs.dart';

/// Image viewer: swipe left / right to open the next / previous picture of the same folder,
/// pinch or double-tap to zoom, tap once to hide / show the bars.
/// Top bar + bottom pill are chosen by the owner in Settings > Viewer toolbar.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late List<FileItem> _items = [widget.item];
  late PageController _pc = PageController();
  int _index = 0;
  bool _chrome = true;
  bool _zoomed = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSiblings(widget.item.path));
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _loadSiblings(String keepPath) async {
    final list = await loadSiblings(ref, widget.item);
    if (!mounted) return;
    var idx = list.indexWhere((f) => f.path == keepPath);
    if (idx < 0) idx = 0;
    final old = _pc;
    setState(() {
      _items = list;
      _index = idx;
      _pc = PageController(initialPage: idx);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _edit() async {
    final cur = _items[_index];
    final saved = await Navigator.of(context).push<bool>(fadeSlideRoute(ImageEditorScreen(path: cur.path)));
    if (saved == true && mounted) {
      await FileImage(File(cur.path)).evict();
      setState(() => _rev++);
      await _loadSiblings(cur.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _items[_index];
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    // "previous / next file" is not needed here: the owner swipes instead
    const hide = {ViewerAction.neighbors};

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              key: ValueKey('pages-${_items.length}'),
              controller: _pc,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (context, i) => _ZoomPage(
                key: ValueKey('${_items[i].path}#$_rev'),
                item: _items[i],
                onTap: () => setState(() => _chrome = !_chrome),
                onZoomChanged: (z) {
                  if (z != _zoomed && i == _index) setState(() => _zoomed = z);
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  padding: EdgeInsets.only(top: topPad, bottom: 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        IconButton(color: Colors.white, icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cur.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              Text(
                                '${_index + 1} of ${_items.length}  -  ${formatSize(cur.size)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        ViewerActions(item: cur, color: Colors.white, hide: hide, onEdit: _edit),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18 + bottomPad,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                offset: _chrome ? Offset.zero : const Offset(0, 1.5),
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Center(child: ViewerPill(item: cur, hide: hide, onEdit: _edit)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One picture: pinch / double-tap zoom. Tells the parent when it is zoomed in.
class _ZoomPage extends StatefulWidget {
  const _ZoomPage({super.key, required this.item, required this.onTap, required this.onZoomChanged});

  final FileItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Offset _tapAt = Offset.zero;

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _notify() => widget.onZoomChanged(_tc.value.getMaxScaleOnAxis() > 1.02);

  void _doubleTap() {
    final zoomedIn = _tc.value.getMaxScaleOnAxis() > 1.02;
    final begin = _tc.value.clone();
    final end = Matrix4.identity();
    if (!zoomedIn) {
      const s = 2.6;
      end
        ..translate(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1))
        ..scale(s);
    }
    final tween = Matrix4Tween(begin: begin, end: end);
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    void tick() => _tc.value = tween.evaluate(curve);
    _anim
      ..reset()
      ..addListener(tick);
    _anim.forward().whenComplete(() {
      _anim.removeListener(tick);
      _notify();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 8,
        onInteractionEnd: (_) => _notify(),
        child: SizedBox.expand(
          child: Image.file(
            File(widget.item.path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This image could not be decoded.', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
