# ROADMAP

Honest time estimates: one person + AI help. They assume weekly feedback loops through GitHub Actions.

| Phase | Goal | Estimate |
|---|---|---|
| 1 | Android MVP: open many file types, AdMob, themes, sort/filter, list/grid | 3-5 weeks (code written, needs CI fixes + device testing) |
| 1.5 | Play Store internal test, real AdMob, "Open with Fyleon", Firebase Remote Config | 1-2 weeks |
| 2 | iOS, Windows, macOS, Linux, tablet layouts (same code) | 3-6 months |
| 3 | Editing: code editor + live preview, EPUB reader with Kindle-level features, PDF tools | 4-8 months |
| 4 | Office-level editing, AI Vault, Google Drive backup, subscription | 6-12+ months |

## Phase 1 checklist (Android)
- [x] Project structure, docs, CI workflow, icon, splash
- [x] Viewers: PDF, EPUB, text/code, image, archive listing, DOCX/XLSX/PPTX basic
- [x] List/grid, sort, filter, search, themes (free + rewarded premium)
- [x] AdMob banner/interstitial/rewarded with test ids + consent
- [ ] First green CI build (APK + AAB)
- [ ] Device testing + bug fixes
- [ ] Open With Fyleon intent
- [ ] Real AdMob ids, privacy policy, Play listing
- [ ] Play internal testing -> production

## Later ideas
Native/rewarded-interstitial/app-open ads (AdMob 6 types, carefully capped), SVG/Markdown/HTML live preview,
APK/AAB build helpers for code projects, project folders + file creation (new PDF/DOCX/EPUB/code files),
multi-key AI Vault with failover, Drive backup, subscription (in-app purchase only), tablet split view.

## Platform reality check
- iOS cannot install or run .apk/.exe; Fyleon can only list/inspect them.
- Windows builds need Windows (GitHub `windows-latest` runner); macOS/iOS need macOS runner + Apple developer account.
- Office-level editing is the hardest part; do it last.
