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

## Installing APKs
Fyleon never installs silently: it hands the APK to Android's own installer (FileProvider read-only URI). The user must allow
"install unknown apps" for Fyleon. Play Protect checks the app as usual. The SHA-256 of the file is shown so it can be compared.
Play Console: REQUEST_INSTALL_PACKAGES needs a declaration (file manager use case).

## Safe folder
PIN is stored only as a salted SHA-256 hash (prefs). Files sit in the app-private directory (other apps cannot read it
without root). Not yet encrypted at rest; 5 wrong PINs close the screen; "Forgot PIN" erases the folder. Plan: AES-GCM
with a key in Android Keystore + biometric unlock.

## Trash
Deleted items move to a hidden folder `.FyleonTrash` on the same storage (with a .nomedia file). Anyone with file access
can still read them there until they are purged (30 days) or deleted forever.

## Fyleon Dash (file sharing, session 8)
- Works only while the Send / Receive screen is open; the TCP server and the UDP beacon stop when it closes (running transfers are cut).
- Entering via QR or the 5-7 digit code = automatic accept; picking from the nearby list needs the sender's tap on Accept (90 s timeout).
  5 wrong codes from one address block it for 60 s. The code is random (Random.secure), new for every sending session.
- File names from the other device are never trusted (no folders, no leading dots, no special characters; never overwrites: "name (1).ext").
- Plain TCP sockets: **data is NOT encrypted yet** and the beacon is visible to everybody on the same network. Use own Wi-Fi / hotspot.
  Plan: ChaCha20-Poly1305 with a key carried in the QR code (and a PAKE for the typed code).
- The beacon contains device name, number/size of files and a short hash of the code (only a hash prefix; a 6-digit code can still be
  brute-forced offline from it, so the sender's approval/rate limit is the real protection, not the hash).
- Unknown files are written to `Download/Fyleon` (never executed). Tapping a received APK goes through the normal Android installer.

## Apps screen (session 8)
- Reads the list of installed apps through a launcher `<queries>` intent (no QUERY_ALL_PACKAGES by default).
- PACKAGE_USAGE_STATS is not granted by a dialog: the user switches "Usage access" on in Android settings; it gives sizes, cache and last-used only.
- Fyleon cannot and does not clear other apps' data silently; every cache clean-up goes through Android's own pages / dialog.

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
INTERNET, ACCESS_NETWORK_STATE, AD_ID (ads). Session 8: ACCESS_WIFI_STATE + CHANGE_WIFI_MULTICAST_STATE (Dash discovery), WAKE_LOCK + FOREGROUND_SERVICE + FOREGROUND_SERVICE_MEDIA_PLAYBACK + POST_NOTIFICATIONS (background audio), REQUEST_DELETE_PACKAGES (uninstall), PACKAGE_USAGE_STATS (app sizes), CAMERA via the QR scanner plugin (camera hardware not required). Optional: QUERY_ALL_PACKAGES (`features.queryAllPackages`). Optional (only if `allFilesAccess=true`): MANAGE_EXTERNAL_STORAGE,
READ_EXTERNAL_STORAGE (<= Android 12). Play restricts all-files access; a declaration form is required.

## Supply chain
- Flutter pinned to 3.47.x; `pubspec.lock` is committed by CI after the first run (review dependency updates).
- Actions used: checkout, setup-java, flutter-action, upload-artifact, softprops/action-gh-release. Pin to commit SHAs before production.
- Run `flutter pub outdated` and review release notes before upgrading plugins.

## Residual risks (honest)
- No app is "unhackable". Malicious files could exploit bugs in PDF/image libraries; keep plugins updated.
- Rewarded-theme unlock is stored locally (prefs) and can be tampered with on rooted devices. Acceptable for cosmetics.
- AI Vault (later) must use Keystore/Keychain + biometric gating; see AI_VAULT_SPEC.md.
