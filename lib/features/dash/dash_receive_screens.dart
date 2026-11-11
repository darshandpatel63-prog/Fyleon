import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/remote/remote_settings.dart';
import '../../core/utils/format.dart';
import '../../core/utils/platform_utils.dart';
import '../../shared/widgets/animations.dart';
import '../ads/banner_ad_widget.dart';
import '../ads/native_ad_tile.dart';
import '../files/application/browse_controller.dart';
import '../files/application/files_providers.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../files/presentation/file_actions.dart';
import '../files/presentation/file_collection_view.dart';
import 'dash_state.dart';
import 'dash_transport.dart';
import 'dash_widgets.dart';

// ---------------------------------------------------------------------------- receive

class DashReceiveScreen extends ConsumerStatefulWidget {
  const DashReceiveScreen({super.key});

  @override
  ConsumerState<DashReceiveScreen> createState() => _DashReceiveScreenState();
}

class _DashReceiveScreenState extends ConsumerState<DashReceiveScreen> {
  DashDiscovery? _discovery;
  StreamSubscription<List<DashPeer>>? _sub;
  List<DashPeer> _peers = const [];
  bool _discoveryOk = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    final me = ref.read(dashIdentityProvider);
    final d = DashDiscovery(myId: me.id);
    final ok = await d.start();
    if (!mounted) {
      await d.stop();
      return;
    }
    _discovery = d;
    _sub = d.peers.listen((list) {
      if (mounted) setState(() => _peers = list);
    });
    setState(() => _discoveryOk = ok);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery?.stop();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _connect({required List<String> hosts, required int port, String? code, required String label}) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final me = ref.read(dashIdentityProvider);
    final dl = DashDownloader(myId: me.id, myName: me.name);
    var cancelled = false;
    final nav = Navigator.of(context);
    // dialog: connecting (the sender may have to tap "Accept")
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(child: Text(code == null ? 'Waiting for $label to accept...' : 'Connecting to $label...')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              dl.cancel();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));
    try {
      await dl.connect(hosts, port, code: code);
      if (cancelled) return;
      if (!mounted) return;
      nav.pop(); // the dialog
      await nav.push(fadeSlideRoute(DashTransferScreen(downloader: dl)));
    } catch (e) {
      await dl.close();
      if (cancelled || !mounted) return;
      nav.pop(); // the dialog
      _toast(e is DashRefused ? e.message : 'Could not connect. Are both devices on the same Wi-Fi or hotspot?');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _enterCode() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter the code'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 7,
          style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: '000 000', counterText: ''),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Connect')),
        ],
      ),
    );
    final digits = (code ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    if (digits.length < 5 || digits.length > 7) {
      _toast('The code has 5 to 7 digits.');
      return;
    }
    // the sender is found by its code (it is in the sender's broadcast); wait a few seconds for it
    DashPeer? peer;
    for (var i = 0; i < 14 && peer == null && mounted; i++) {
      peer = _discovery?.findByCode(digits);
      if (peer == null) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    if (peer == null) {
      _toast('No sender with this code found. Check that both devices use the same Wi-Fi or hotspot, or scan the QR code.');
      return;
    }
    await _connect(hosts: [peer.host], port: peer.port, code: digits, label: peer.name);
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(fadeSlideRoute(const DashQrScanScreen()));
    if (raw == null || !mounted) return;
    final link = DashLink.parse(raw);
    if (link == null) {
      _toast('This is not a Fyleon Dash code.');
      return;
    }
    await _connect(hosts: link.hosts, port: link.port, code: link.code.isEmpty ? null : link.code, label: link.name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      bottomNavigationBar: const SafeArea(top: false, child: BannerAdWidget()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Center(child: RadarPulse(size: 170, icon: Icons.south_west_rounded)),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _peers.isEmpty ? 'Looking for nearby senders...' : 'Tap a device to receive its files',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          if (!_discoveryOk)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Automatic search is not available here. Scan the QR code or type the code.', textAlign: TextAlign.center, style: TextStyle(color: scheme.error, fontSize: 12.5)),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (isAndroid || isIOS)
                Expanded(child: FilledButton.icon(onPressed: _connecting ? null : _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan QR'))),
              if (isAndroid || isIOS) const SizedBox(width: 10),
              Expanded(child: FilledButton.tonalIcon(onPressed: _connecting ? null : _enterCode, icon: const Icon(Icons.pin_rounded), label: const Text('Enter code'))),
            ],
          ),
          const SizedBox(height: 16),
          for (final peer in _peers)
            FadeSlideIn(
              index: 0,
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: const DeviceAvatar(),
                  title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${peer.files} file${peer.files == 1 ? '' : 's'} - ${formatSize(peer.bytes)}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _connecting ? null : () => _connect(hosts: [peer.host], port: peer.port, label: peer.name),
                ),
              ),
            ),
          const NativeAdTile(),
          const SizedBox(height: 8),
          Text(
            'Tip: the other device must have Send open. Both devices need the same Wi-Fi, or one hotspot. No internet needed.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- QR scanner

class DashQrScanScreen extends StatefulWidget {
  const DashQrScanScreen({super.key});

  @override
  State<DashQrScanScreen> createState() => _DashQrScanScreenState();
}

class _DashQrScanScreenState extends State<DashQrScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Scan the QR code')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              onDetect: (capture) {
                if (_done) return;
                for (final b in capture.barcodes) {
                  final v = b.rawValue;
                  if (v != null && DashLink.parse(v) != null) {
                    _done = true;
                    Navigator.of(context).pop(v);
                    return;
                  }
                }
              },
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(28)),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Text('Point the camera at the QR code shown on the sending device', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- transfer (receiving)

class DashTransferScreen extends ConsumerStatefulWidget {
  const DashTransferScreen({super.key, required this.downloader});

  final DashDownloader downloader;

  @override
  ConsumerState<DashTransferScreen> createState() => _DashTransferScreenState();
}

class _DashTransferScreenState extends ConsumerState<DashTransferScreen> {
  DashProgress _progress = const DashProgress();
  final Set<int> _doneIdx = {};
  Map<int, String> _saved = const {};
  String? _error;
  bool _finished = false;
  String _dir = '';
  double _speed = 0; // bytes per second
  int _lastBytes = 0;
  DateTime _lastTime = DateTime.now();

  DashDownloader get _dl => widget.downloader;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      _dir = await dashSaveDir();
      final saved = await _dl.download(_dir, (pr) {
        if (!mounted) return;
        final now = DateTime.now();
        final dt = now.difference(_lastTime).inMilliseconds;
        if (dt >= 500) {
          _speed = (pr.doneBytes - _lastBytes) * 1000 / dt;
          _lastBytes = pr.doneBytes;
          _lastTime = now;
        }
        setState(() {
          _progress = pr;
          if (pr.fileSize > 0 && pr.fileBytes >= pr.fileSize) _doneIdx.add(pr.fileIndex);
        });
      });
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _finished = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is DashRefused ? e.message : 'The connection was lost. Ask the sender to keep Send open and try again.');
      }
    } finally {
      await _dl.close();
    }
  }

  @override
  void dispose() {
    _dl.cancel();
    _dl.close();
    super.dispose();
  }

  void _openSaved(int fileIndex) {
    final path = _saved[fileIndex];
    if (path == null) return;
    final item = FileItem.tryFromPath(path);
    if (item != null) openFile(context, ref, item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final files = _dl.files;
    final total = files.fold<int>(0, (a, f) => a + f.size);
    final done = _progress.doneBytes;
    final value = total == 0 ? (_finished ? 1.0 : 0.0) : (done / total).clamp(0.0, 1.0);
    final remote = ref.watch(remoteSettingsProvider);
    final adsOn = adsSupported && remote.nativeEnabled;
    final slots = AdSlots(files.length, every: remote.dashNativeEveryNItems, max: adsOn ? remote.nativeMaxPerList : 0);

    return PopScope(
      canPop: _finished || _error != null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final stop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel receiving?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel')),
            ],
          ),
        );
        if (stop == true) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_dl.senderName.isEmpty ? 'Receiving' : 'From ${_dl.senderName}')),
        bottomNavigationBar: const SafeArea(top: false, child: BannerAdWidget()),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        _error != null ? 'Stopped' : (_finished ? 'Done' : '${(value * 100).floor()}%'),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Text(
                        _finished || _error != null ? '${formatSize(done)} of ${formatSize(total)}' : '${formatSize(done)} of ${formatSize(total)}  -  ${formatSize(_speed.round())}/s',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: value, minHeight: 10, color: _error != null ? scheme.error : null)),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
                  ],
                  if (_finished && _dir.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Saved in $_dir', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        ref.read(browsePathProvider.notifier).open(_dir);
                        ref.read(homeTabProvider.notifier).set(0);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Show in Files'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: slots.total,
                itemBuilder: (context, i) {
                  if (slots.isAd(i)) return const NativeAdTile();
                  final f = files[slots.itemIndex(i)];
                  return _incomingTile(f, scheme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incomingTile(DashFile f, ColorScheme scheme) {
    final kind = kindForExtension(extensionOf(f.name));
    final isDone = _doneIdx.contains(f.index);
    final isCurrent = !isDone && _progress.fileIndex == f.index && !_finished && _error == null;
    final frac = isCurrent && _progress.fileSize > 0 ? (_progress.fileBytes / _progress.fileSize).clamp(0.0, 1.0) : null;
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: kind.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
        child: Icon(kind.icon, color: kind.color, size: 22),
      ),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: isCurrent
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: frac, minHeight: 5)),
            )
          : Text(isDone ? 'Received - ${formatSize(f.size)}' : formatSize(f.size), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
      trailing: isDone ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)) : null,
      onTap: _finished && isDone ? () => _openSaved(f.index) : null,
    );
  }

}
