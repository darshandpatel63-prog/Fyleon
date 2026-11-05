# SECURITY

## Rules
- No API keys, keystores, passwords or tokens in the repo. `.gitignore` blocks `*.jks`, `*.keystore`, `.env`, `key.properties`.
- Signing keys live only in GitHub Secrets (and the owner's safe backup). Never paste them in chat.
- AdMob ids are not secrets but still come only from `config/fyleon_config.json`.
- Files never leave the device. Fyleon has no server and no cloud storage.
- Remote config is data only (numbers/flags); no remote code.
- Parsing of untrusted files (EPUB/Office/ZIP) runs in isolates; size limits protect memory (see AppConstants).
- ZIP listing never extracts files (no zip-slip risk yet). When extraction is added: sanitize paths, limit size/ratio.

## Open with / Share (incoming files)
Fyleon registers for VIEW/SEND/SEND_MULTIPLE of any type. Incoming content:// files are copied into the app cache
(`cache/incoming/<time>/`) and opened read-only from there. Names are sanitized. Nothing is uploaded.

## Safe folder
PIN is stored only as a salted SHA-256 hash (prefs). Files sit in the app-private directory (other apps cannot read it
without root). Not yet encrypted at rest; 5 wrong PINs close the screen; "Forgot PIN" erases the folder. Plan: AES-GCM
with a key in Android Keystore + biometric unlock.

## Trash
Deleted items move to a hidden folder `.FyleonTrash` on the same storage (with a .nomedia file). Anyone with file access
can still read them there until they are purged (30 days) or deleted forever.

## Local preview server
`features/preview/local_server.dart` binds to 127.0.0.1 only (not reachable from the network), serves only files inside the
project folder (path traversal blocked), random port, stopped when the preview closes. Android allows plain HTTP for
127.0.0.1/localhost only (network_security_config.xml, written by tool/patch_android.py). Preview pages run JavaScript:
only open projects you trust.

## All files access
Optional runtime permission (Settings > Special app access). The manifest permission is controlled by
`features.allFilesAccess` in config/fyleon_config.json. Play Store needs the "All files access" declaration; if it is
rejected, set the flag to false and Fyleon falls back to the file picker.

## Permissions (Android)
INTERNET, ACCESS_NETWORK_STATE, AD_ID (ads). Optional (only if `allFilesAccess=true`): MANAGE_EXTERNAL_STORAGE,
READ_EXTERNAL_STORAGE (<= Android 12). Play restricts all-files access; a declaration form is required.

## Supply chain
- Flutter pinned to 3.47.x; `pubspec.lock` is committed by CI after the first run (review dependency updates).
- Actions used: checkout, setup-java, flutter-action, upload-artifact, softprops/action-gh-release. Pin to commit SHAs before production.
- Run `flutter pub outdated` and review release notes before upgrading plugins.

## Residual risks (honest)
- No app is "unhackable". Malicious files could exploit bugs in PDF/image libraries; keep plugins updated.
- Rewarded-theme unlock is stored locally (prefs) and can be tampered with on rooted devices. Acceptable for cosmetics.
- AI Vault (later) must use Keystore/Keychain + biometric gating; see AI_VAULT_SPEC.md.
