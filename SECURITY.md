# SECURITY

## Rules
- No API keys, keystores, passwords or tokens in the repo. `.gitignore` blocks `*.jks`, `*.keystore`, `.env`, `key.properties`.
- Signing keys live only in GitHub Secrets (and the owner's safe backup). Never paste them in chat.
- AdMob ids are not secrets but still come only from `config/fyleon_config.json`.
- Files never leave the device. Fyleon has no server and no cloud storage.
- Remote config is data only (numbers/flags); no remote code.
- Parsing of untrusted files (EPUB/Office/ZIP) runs in isolates; size limits protect memory (see AppConstants).
- ZIP listing never extracts files (no zip-slip risk yet). When extraction is added: sanitize paths, limit size/ratio.

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
