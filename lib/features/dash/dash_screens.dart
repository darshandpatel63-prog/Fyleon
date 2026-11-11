import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/native/native_bridge.dart';
import '../../core/remote/remote_settings.dart';
import '../../core/utils/format.dart';
import '../../core/utils/platform_utils.dart';
import '../../shared/widgets/animations.dart';
import '../ads/banner_ad_widget.dart';
import '../ads/native_ad_tile.dart';
import '../files/application/collections_providers.dart';
import '../files/application/files_providers.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../files/presentation/file_collection_view.dart';
import 'dash_receive_screens.dart';
import 'dash_state.dart';
import 'dash_transport.dart';
import 'dash_widgets.dart';

/// Opens the sender with these files already added (used by "Send with Dash" in the file menu).
Future<void> sendWithDash(BuildContext context, List<String> paths) {
  return Navigator.of(context).push(fadeSlideRoute(DashSendScreen(initialPaths: paths)));
}

// ---------------------------------------------------------------------------- home

class DashHomeScreen extends ConsumerWidget {
  const DashHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(dashIdentityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(dashName)),
      bottomNavigationBar: const SafeArea(top: false, child: BannerAdWidget()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Center(child: RadarPulse(size: 190)),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: () => _rename(context, ref, me.name),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text('This device: ${me.name}'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _BigAction(
                  icon: Icons.north_east_rounded,
                  title: 'Send',
                  subtitle: 'Choose files and share them',
                  onTap: () => Navigator.of(context).push(fadeSlideRoute(const DashSendScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigAction(
                  icon: Icons.south_west_rounded,
                  title: 'Receive',
                  subtitle: 'Find a sender nearby',
                  onTap: () => Navigator.of(context).push(fadeSlideRoute(const DashReceiveScreen())),
                ),
              ),
            ],
          ),
          const NativeAdTile(),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How it works', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                const Text(
                  '1. Put both devices on the same Wi-Fi, OR turn on the hotspot of one phone and connect the other to it. No internet is needed.\n'
                  '2. On one device tap Send, on the other tap Receive.\n'
                  '3. Pick the device from the list, scan its QR code, or type its 5-7 digit code. '
                  'Many devices can receive at the same time.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                if (isAndroid) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => NativeBridge.instance.openHotspotSettings(),
                        icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                        label: const Text('Hotspot'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => NativeBridge.instance.openWifiSettings(),
                        icon: const Icon(Icons.wifi_rounded, size: 18),
                        label: const Text('Wi-Fi'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Good to know: the files are sent as they are (not encrypted yet), so use your own Wi-Fi or hotspot, '
                  'not a public one. Bluetooth / Wi-Fi Direct for places without any network is coming in a later version.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(controller: c, autofocus: true, maxLength: 30, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) await ref.read(dashIdentityProvider.notifier).rename(name);
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 34),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- send

class DashSendScreen extends ConsumerStatefulWidget {
  const DashSendScreen({super.key, this.initialPaths = const []});

  final List<String> initialPaths;

  @override
  ConsumerState<DashSendScreen> createState() => _DashSendScreenState();
}

class _DashSendScreenState extends ConsumerState<DashSendScreen> {
  DashSender? _sender;
  StreamSubscription<void>? _sub;
  List<String> _ips = const [];
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _add(widget.initialPaths));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sender?.stop();
    super.dispose();
  }

  List<SendItem> _toItems(List<String> paths) {
    final out = <SendItem>[];
    for (final path in paths) {
      final f = File(path);
      try {
        if (!f.existsSync()) continue;
        out.add(SendItem(path, safeFileName(path.split(Platform.pathSeparator).last), f.lengthSync()));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _add(List<String> paths) async {
    final items = _toItems(paths).where((i) => _sender == null || !_sender!.files.any((f) => f.path == i.path)).toList();
    if (items.isEmpty) return;
    final existing = _sender;
    if (existing != null) {
      existing.addFiles(items);
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final me = ref.read(dashIdentityProvider);
      final s = DashSender(deviceId: me.id, deviceName: me.name, files: items);
      await s.start();
      _ips = await localIps();
      _sub = s.changes.listen((_) {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await s.stop();
        return;
      }
      setState(() {
        _sender = s;
        _starting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Could not start sharing: $e';
        });
      }
    }
  }

  Future<void> _refreshIps() async {
    final ips = await localIps();
    if (mounted) setState(() => _ips = ips);
  }

  // ---- adding files

  Future<void> _addSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.folder_open_rounded), title: const Text('Pick a file'), subtitle: const Text('Opens the file picker, one file at a time'), onTap: () => Navigator.pop(ctx, 'pick')),
            ListTile(leading: const Icon(Icons.history_rounded), title: const Text('From recent files'), subtitle: const Text('Choose many at once'), onTap: () => Navigator.pop(ctx, 'recent')),
            ListTile(leading: const Icon(Icons.star_rounded), title: const Text('From starred files'), onTap: () => Navigator.pop(ctx, 'starred')),
            ListTile(leading: const Icon(Icons.new_releases_rounded), title: const Text('Newest files on this device'), onTap: () => Navigator.pop(ctx, 'new')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'pick':
        await _pickOne();
      case 'recent':
        await _pickMany('Recent files', ref.read(recentsProvider).map((r) => r.item).toList());
      case 'starred':
        final items = ref.read(starredProvider).map(FileItem.tryFromPath).whereType<FileItem>().where((f) => !f.isDir).toList();
        await _pickMany('Starred files', items);
      case 'new':
        final scan = ref.read(storageScanProvider).valueOrNull;
        await _pickMany('Newest files', scan?.recentAll ?? const []);
    }
  }

  Future<void> _pickOne() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the file picker.')));
      return;
    }
    final path = picked?.path;
    if (path != null) await _add([path]);
  }

  Future<void> _pickMany(String title, List<FileItem> items) async {
    final files = items.where((f) => !f.isDir).toList();
    if (files.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No files here yet.')));
      return;
    }
    final chosen = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, i) {
                final f = files[i];
                return CheckboxListTile(
                  dense: true,
                  value: chosen.contains(f.path),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatSize(f.size)),
                  onChanged: (v) => setLocal(() => v == true ? chosen.add(f.path) : chosen.remove(f.path)),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text('Add ${chosen.length}')),
          ],
        ),
      ),
    );
    if (ok == true) await _add(chosen.toList());
  }

  // ---- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _sender;
    final busy = s != null && s.clients.any((c) => c.status == ClientStatus.connected && c.currentBytes < c.currentSize);

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final stop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Stop sharing?'),
            content: const Text('Some files are still being sent.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep sending')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
            ],
          ),
        );
        if (stop == true) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Send'),
          actions: [
            if (s != null) IconButton(tooltip: 'Add files', icon: const Icon(Icons.add_rounded), onPressed: _addSheet),
          ],
        ),
        bottomNavigationBar: const SafeArea(top: false, child: BannerAdWidget()),
        body: _starting
            ? const Center(child: CircularProgressIndicator())
            : s == null
                ? _empty(scheme)
                : _running(s, scheme),
      ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RadarPulse(size: 150, active: false),
            const SizedBox(height: 16),
            const Text('Choose what to send', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Add one or more files. Then other devices can find you.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _addSheet, icon: const Icon(Icons.add_rounded), label: const Text('Add files')),
          ],
        ),
      ),
    );
  }

  Widget _running(DashSender s, ColorScheme scheme) {
    final remote = ref.watch(remoteSettingsProvider);
    final every = remote.dashNativeEveryNItems;
    final files = s.files;
    final adsOn = adsSupported && remote.nativeEnabled;
    final slots = AdSlots(files.length, every: every, max: adsOn ? remote.nativeMaxPerList : 0);
    final link = _ips.isEmpty ? null : buildDashLink(hosts: _ips, port: s.port, code: s.code, name: s.deviceName);
    final pretty = '${s.code.substring(0, 3)} ${s.code.substring(3)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // ---- pairing card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
          child: Column(
            children: [
              Text('${files.length} file${files.length == 1 ? '' : 's'} - ${formatSize(s.totalBytes)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (link != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: QrImageView(data: link, size: 190, backgroundColor: Colors.white),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 40),
                      const SizedBox(height: 8),
                      const Text('Connect to Wi-Fi or turn on your hotspot, then tap Refresh.', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonal(onPressed: _refreshIps, child: const Text('Refresh')),
                          if (isAndroid) OutlinedButton(onPressed: () => NativeBridge.instance.openHotspotSettings(), child: const Text('Hotspot')),
                          if (isAndroid) OutlinedButton(onPressed: () => NativeBridge.instance.openWifiSettings(), child: const Text('Wi-Fi')),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: s.code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(pretty, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4)),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              Text('Scan the QR code or type this code on the other device.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              if (_ips.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Address: ${_ips.join(', ')}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ---- receivers
        Row(
          children: [
            Text('Receivers', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${s.clients.length}', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        if (s.clients.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 12),
                Expanded(child: Text('Waiting for devices... they find you automatically while "Receive" is open.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
              ],
            ),
          ),
        for (final c in s.clients) _ClientTile(client: c, sender: s, fileCount: files.length),
        const SizedBox(height: 14),
        // ---- files (native ad after every few files)
        Row(
          children: [
            Text('Files', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(onPressed: _addSheet, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
          ],
        ),
        for (var i = 0; i < slots.total; i++)
          if (slots.isAd(i))
            const NativeAdTile()
          else
            _fileRow(files[slots.itemIndex(i)], scheme),
      ],
    );
  }

  Widget _fileRow(SendItem f, ColorScheme scheme) {
    final item = FileItem.tryFromPath(f.path);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: item == null ? const Icon(Icons.insert_drive_file_rounded) : _Thumb(item: item),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatSize(f.size), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.kind.color;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Icon(item.kind.icon, color: color, size: 22),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.sender, required this.fileCount});

  final DashClient client;
  final DashSender sender;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = client;
    String status;
    Widget? trailing;
    double? progress;
    switch (c.status) {
      case ClientStatus.pending:
        status = 'Wants to receive your files';
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: 'Decline', icon: Icon(Icons.close_rounded, color: scheme.error), onPressed: () => sender.deny(c.id)),
            IconButton.filled(tooltip: 'Accept', icon: const Icon(Icons.check_rounded), onPressed: () => sender.approve(c.id)),
          ],
        );
      case ClientStatus.connected:
        final sending = c.currentSize > 0 && c.currentBytes < c.currentSize;
        status = sending
            ? 'Sending file ${c.currentIndex + 1} of $fileCount - ${(c.currentBytes * 100 / c.currentSize).floor()}%'
            : (c.filesDone >= fileCount && fileCount > 0 ? 'All files sent' : 'Connected');
        progress = fileCount == 0 || sender.totalBytes == 0 ? null : (c.sentBytes / (sender.totalBytes)).clamp(0.0, 1.0);
        if (c.filesDone >= fileCount && fileCount > 0) trailing = const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A));
      case ClientStatus.done:
        status = 'Received ${c.filesDone} file${c.filesDone == 1 ? '' : 's'}';
        trailing = const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A));
      case ClientStatus.denied:
        status = 'Declined';
        trailing = Icon(Icons.block_rounded, color: scheme.outline);
      case ClientStatus.failed:
        status = 'Connection lost';
        trailing = Icon(Icons.error_outline_rounded, color: scheme.error);
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const DeviceAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(status, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  if (progress != null && c.status == ClientStatus.connected) ...[
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, minHeight: 6)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
