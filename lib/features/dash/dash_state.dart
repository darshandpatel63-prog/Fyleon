import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/native/native_bridge.dart';
import '../../core/storage/prefs.dart';
import '../../core/utils/platform_utils.dart';
import '../files/application/browse_controller.dart';
import 'dash_transport.dart';

/// Product name of the file sharing feature.
const dashName = 'Fyleon Dash';

class DashIdentity {
  const DashIdentity(this.id, this.name);

  final String id;
  final String name;
}

/// Who this device is on the network: a random id (stays the same) and a name the owner can change.
class DashIdentityNotifier extends Notifier<DashIdentity> {
  static const _idKey = 'dash_id_v1';
  static const _nameKey = 'dash_name_v1';

  @override
  DashIdentity build() {
    final prefs = ref.read(sharedPrefsProvider);
    var id = prefs.getString(_idKey);
    if (id == null || id.isEmpty) {
      id = randomToken();
      prefs.setString(_idKey, id);
    }
    final stableId = id;
    final saved = prefs.getString(_nameKey);
    if (saved == null) {
      // first start: use the phone's own name ("Pixel 8", "Galaxy A54"...)
      NativeBridge.instance.deviceName().then((n) {
        if (n.isNotEmpty && prefs.getString(_nameKey) == null) state = DashIdentity(stableId, n);
      });
    }
    return DashIdentity(stableId, saved ?? (isAndroid ? 'My phone' : 'My computer'));
  }

  Future<void> rename(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    state = DashIdentity(state.id, n);
    await ref.read(sharedPrefsProvider).setString(_nameKey, n);
  }
}

final dashIdentityProvider = NotifierProvider<DashIdentityNotifier, DashIdentity>(DashIdentityNotifier.new);

/// Folder where received files are saved: Download/Fyleon (or the app folder when the phone does not allow it).
Future<String> dashSaveDir() async {
  try {
    if (isAndroid) {
      final roots = storageRoots();
      if (roots.isNotEmpty && await hasAllFilesAccess()) {
        final d = Directory(p.join(roots.first.path, 'Download', 'Fyleon'));
        d.createSync(recursive: true);
        return d.path;
      }
    } else if (isDesktop) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final d = Directory(p.join(home, 'Downloads', 'Fyleon'));
        d.createSync(recursive: true);
        return d.path;
      }
    }
  } catch (_) {}
  final docs = await getApplicationDocumentsDirectory();
  final d = Directory(p.join(docs.path, 'Received'))..createSync(recursive: true);
  return d.path;
}
