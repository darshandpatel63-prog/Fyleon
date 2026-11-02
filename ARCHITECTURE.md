# ARCHITECTURE

## Folders
    lib/
      main.dart, app.dart            entry, MaterialApp, theme wiring
      core/                          config, constants, theme, storage (prefs), utils, remote settings
      shared/widgets/                animations, empty state, file tiles/cards
      features/
        splash/                      animated splash
        ads/                         AdService (AdMob), banner widget
        files/
          domain/                    FileKind, FileItem, sort/filter logic (pure Dart, unit tested)
          application/               Riverpod providers (view mode, sort, filter, recents, browse)
          presentation/              home, recent view, browse view, collection view (list/grid)
        viewer/                      one file per viewer + viewer_screen.dart (router)
        settings/                    settings, themes
    config/fyleon_config.json        owner-filled config (AdMob ids, flags, remote url)
    tool/                            make_icons.py, patch_android.py
    .github/workflows/android.yml    CI

## Rules
- Features never import each other's presentation code, except through `viewer_screen.dart` and `file_actions.dart`.
- Pure logic lives in `domain/` and has unit tests (no plugins) so it can run anywhere.
- Heavy parsing (EPUB, Office, archives, directory listing) runs in isolates via `compute()`.
- Every viewer is a standalone screen taking a `FileItem`. Adding a type = new viewer + one case in `ViewerScreen`
  + one entry in `file_kind.dart`.
- State: Riverpod 2 `Notifier`s; persistence via SharedPreferences only for small settings.

## Adding later phases
- Editing: add `features/editor/` (code editor first). Viewers stay read-only.
- AI Vault: `features/ai_vault/` + secure storage adapter (Keystore/Keychain) + provider adapters.
- Backup: `features/backup/` (Google Drive appData scope, user's own account, encrypted).
- Platforms: `flutter create --platforms=ios,windows,macos,linux .` then platform CI workflows.

## Remote changes
`core/remote/remote_settings.dart` reads a GitHub-hosted JSON (URL in config). Firebase Remote Config will
use the same `RemoteSettings` class later. Cached values are used when offline.
Example JSON:
    {"ads":{"banner":true,"interstitial":true,"rewarded":true,
            "interstitialEveryNFileCloses":4,"interstitialMinGapSeconds":180},
     "themes":{"premiumUnlockHours":24}}

## Known technical debt
- `package:flutter/material.dart` migration to `material_ui` (deprecated in Fall 2026 stable).
- Android file access is picker-based (cache copies) until SAF persistent URIs are added.
