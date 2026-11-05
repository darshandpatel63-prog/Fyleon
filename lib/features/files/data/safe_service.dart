import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Safe folder: files live in Fyleon's private storage (other apps cannot see them) and
/// the folder opens only with the user's PIN. NOTE: not encrypted at rest yet, and the
/// files are removed if Fyleon is uninstalled.
class SafeService {
  SafeService(this._prefs);

  final SharedPreferences _prefs;
  static const _kSalt = 'safe_pin_salt';
  static const _kHash = 'safe_pin_hash';

  bool get hasPin => _prefs.getString(_kHash) != null;

  String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    await _prefs.setString(_kSalt, salt);
    await _prefs.setString(_kHash, _hash(pin, salt));
  }

  bool verify(String pin) {
    final salt = _prefs.getString(_kSalt);
    final hash = _prefs.getString(_kHash);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<Directory> directory() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'safe'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// "Forgot PIN": erases the safe folder and the PIN (nothing can be recovered).
  Future<void> resetAndErase() async {
    final d = await directory();
    try {
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
    await _prefs.remove(_kSalt);
    await _prefs.remove(_kHash);
  }
}
