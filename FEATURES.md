# FEATURES

Legend: [x] done in code (untested on device) | [ ] planned

## Phase 1 - Viewing
- [x] PDF (pdfrx: zoom, text selection)
- [x] EPUB basic: chapter per page, TOC, text size, line spacing, paper/sepia/night
- [x] Text + code with syntax highlighting (30+ languages), font size, word wrap
- [x] Images with pinch zoom (JPG, PNG, GIF, WEBP, BMP)
- [x] Archive listing: ZIP, JAR, WAR, AAR, APK, AAB, IPA, TAR, TGZ
- [x] DOCX, XLSX, PPTX basic text/table preview
- [ ] Open With Fyleon from other apps
- [ ] Markdown/HTML/SVG rendered preview (Phase 3 live preview)

## Phase 1 - App
- [x] List view and grid view, animated
- [x] Sort: last opened, name A-Z, Z-A, recently modified, oldest, recently added, size (both), type
- [x] Filter chips: All, PDF, Docs, Books, Code, Images, Archives, Other; search by name
- [x] Themes: Auto, Fyleon Light, Fyleon Dark, AMOLED (free); Ocean, Emerald Forest, Sunset, Royal Purple, Rose Gold, Neon Cyber (rewarded ad)
- [x] AdMob banner, interstitial (after closing a file), rewarded (premium themes)
- [x] Splash, smooth transitions
- [ ] Browse device folders (needs all-files access decision)

## Added in session 4 (code written, awaiting first device test)
- [x] Optional all-files access, real file manager: browse every folder, new folder/file/web project, rename, copy, cut/move, paste, delete, details
- [x] Code editor: syntax colors while typing, line numbers, undo/redo, save, symbol bar, auto indent
- [x] Web preview (HTML, SVG, Markdown) in Phone / Tablet / Desktop views, relative CSS/JS/images, unsaved text
- [x] EPUB: real pages that fit the screen, page-turn flip animation, tap/drag, page slider
- [x] PowerPoint: slide rendering with positions, fills, text, bullets, pictures, tables
- [ ] Next: multi-file project view with tabs, search/replace, console panel in preview, Markdown/HTML split view,
      create PDF/DOCX/XLSX/PPTX/EPUB files, Open With Fyleon, text selection in the EPUB reader

## Benchmarks to beat (later phases)
- EPUB: Kindle - highlights, notes, bookmarks, dictionary/translate, X-ray style info, fonts, themes, brightness, reading progress/stats, cloud-free sync through the user's Drive.
- Office: Microsoft Word/Excel/PowerPoint - full layout, styles, tables, charts, tracked changes, formulas, slide show; plus extras (AI assist via AI Vault).
- PDF: Acrobat/Xodo - annotate, sign, fill forms, merge/split, OCR.
- Code: VS Code/Acode - editor, tabs, search/replace, git basics, live preview, project templates, build helpers.
- Archives: ZArchiver - extract, create, password ZIP.
- Create new files: PDF, DOCX, XLSX, PPTX, EPUB, code projects (HTML/JS/Dart/Flutter/Rust/Java...) from templates.

## Honest limits
- iOS cannot run APK/EXE. Building apps on-device (APK/AAB/EXE) is not realistic on phones; code projects can be written, previewed and exported, and built with GitHub Actions.
- Full Office parity is a multi-year effort; we ship in steps.
