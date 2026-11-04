# ROADMAP

Honest time estimates: one person + AI help. They assume weekly feedback loops through GitHub Actions.

| Phase | Goal | Estimate |
|---|---|---|
| 1 | Android MVP: open many file types, AdMob, themes, sort/filter, list/grid | 3-5 weeks (code written, needs CI fixes + device testing) |
| 1.5 | Play Store internal test, real AdMob, "Open with Fyleon", Firebase Remote Config | 1-2 weeks |
| 2 | iOS, Windows, macOS, Linux, tablet layouts (same code) | 3-6 months |
| 3 | Editing: code editor + live preview, EPUB reader with Kindle-level features, PDF tools | 4-8 months |
| 4 | Office-level editing, AI Vault, Google Drive backup, subscription | 6-12+ months |

## Product vision v2 (owner decision, Nov 2026)
Fyleon is not only a viewer. It is **a complete file manager + file creator + code workspace** for every device:
1. **File manager**: browse all folders (optional "all files access"), create/rename/copy/move/delete, search, sort, list/grid.
2. **Create anything**: text, Markdown, HTML/CSS/JS, code in any language, then PDF/DOCX/XLSX/PPTX/EPUB (later phases).
3. **Code workspace (GitHub/VS Code style)**: project folders, many files, editor with syntax colors, search/replace,
   multi-tab, git basics later; **live preview** of web projects in phone / tablet / desktop views.
4. **App projects**: write Flutter/Android/Rust/etc. code and build it in the cloud (user's own GitHub Actions); Fyleon
   cannot run those apps itself (honest limit). Web projects run in the built-in preview.
5. **Best-in-class viewers/editors per format** (Kindle for EPUB, Office for documents, Acrobat for PDF, ZArchiver for archives).
6. Free with AdMob, premium themes by rewarded ad, subscription later, AI Vault with the user's own keys, backup to the user's own Google Drive.

## Phase 1 checklist (Android)
- [x] Project structure, docs, CI workflow, icon, splash
- [x] Viewers: PDF, EPUB, text/code, image, archive listing, DOCX/XLSX/PPTX basic
- [x] List/grid, sort, filter, search, themes (free + rewarded premium)
- [x] AdMob banner/interstitial/rewarded with test ids + consent
- [ ] First green CI build (APK + AAB)
- [ ] Device testing + bug fixes
- [x] File manager basics (create/rename/copy/move/delete), code editor, web preview (code written, untested)
- [x] EPUB pages + page-flip, PPTX slide renderer (code written, untested)
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
