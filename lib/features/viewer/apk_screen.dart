import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../core/native/native_bridge.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/domain/file_item.dart';
import 'archive_viewer.dart';

/// Tap an APK: install it, check it with Play Protect, or look inside it.
class ApkScreen extends StatefulWidget {
  const ApkScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<ApkScreen> createState() => _ApkScreenState();
}

class _ApkScreenState extends State<ApkScreen> {
  String? _sha;

  @override
  void initState() {
    super.initState();
    _hash();
  }

  Future<void> _hash() async {
    try {
      final digest = await sha256.bind(File(widget.item.path).openRead()).first;
      if (mounted) setState(() => _sha = digest.toString());
    } catch (_) {}
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _install() async {
    final r = await NativeBridge.instance.installApk(widget.item.path);
    if (!mounted) return;
    if (r == 'need_permission') {
      _toast('Allow Fyleon to install apps in the screen that opened, then tap Install again.');
    } else if (r != 'started') {
      _toast('Could not start the installer ($r).');
    }
  }

  Future<void> _protect() async {
    final ok = await NativeBridge.instance.openPlayProtect();
    if (mounted && !ok) _toast('Play Protect could not be opened on this phone.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: const Text('APK')),
      body: BottomSafe(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: const Color(0xFF3DDC84).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.android_rounded, size: 56, color: Color(0xFF3DDC84)),
                ),
                const SizedBox(height: 16),
                Text(item.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${formatSize(item.size)} - ${formatDate(item.modified)}', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                if (_sha != null)
                  InkWell(
                    onTap: () => _toast('SHA-256: $_sha'),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text('SHA-256  ${_sha!.substring(0, 16)}...', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontFamily: 'monospace')),
                    ),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(onPressed: _install, icon: const Icon(Icons.install_mobile_rounded), label: const Text('Install')),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(onPressed: _protect, icon: const Icon(Icons.verified_user_rounded), label: const Text('Scan with Play Protect')),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(fadeSlideRoute(ArchiveViewerScreen(item: item))),
                    icon: const Icon(Icons.folder_zip_rounded),
                    label: const Text('Unpack / browse contents'),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Only install apps from sources you trust. Android also checks the app with Play Protect when you install it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
