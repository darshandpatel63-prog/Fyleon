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

## Session 6 (code written, awaiting device test)
- [x] Google-Files-style home: recent, categories with sizes, collections, storage with free space
- [x] Trash with restore/undo/auto-purge, Starred, Favorites, Safe folder (PIN)
- [x] Audio and video player (MP3, M4A, FLAC, WAV, MP4, MKV, WEBM...)
- [x] Fyleon appears in Open with / Share / Send to (any file type)
- [ ] Installed apps list, biometric unlock for Safe folder, encryption of the Safe folder, Save to / Download in
- [ ] Create new PDF/DOCX/XLSX/PPTX/EPUB files + their editors (next big block)

## Session 7 (code written, awaiting device test)
- [x] Open by content (extension-less files), archives with folders + open/extract, APK install screen, three-dots menus
- [x] Native ads between files, editor: find/replace, comment toggle, suggestions, color swatches, problems panel
- [x] Sample files generator, floating dock + responsive rail, storage ring hero, new transitions
- [ ] Git (clone/commit/push), multi-file tabs, terminal, installed-apps list, multi-select, compress to ZIP, create PDF/DOCX/XLSX/PPTX/EPUB

## Session 8 (code written, awaiting first compile + device test)
- [x] Dock + banner above the Android navigation buttons; Recent "See all"
- [x] Image viewer: swipe to neighbouring pictures, zoom, hide bars, photo editor (crop, rotate, flip, filters, adjust)
- [x] Viewer toolbar customisable in Settings (star, heart, share, edit, details, open with, previous/next: top bar / menu / pill / hidden)
- [x] PDF and PowerPoint: all pages in one scroll with "3/52" page pill
- [x] Apps screen: installed / system / APK files, large / unused / games, sizes, cache sizes, guided cache clearing, uninstall, APK backup/share
- [x] Background audio + video sound (notification controls), "Audio only" mode for videos, Settings switch
- [x] Fyleon Dash: send/receive over Wi-Fi or hotspot, QR code, 5-7 digit code, nearby list, many receivers, progress, ads between files
- [ ] Dash: Bluetooth / Wi-Fi Direct (Nearby Connections), encryption, resume, desktop tests
- [ ] Viewer toolbar in EPUB/archive viewers, image lens/OCR, free-hand crop, multi-select picker in Dash

## Session 11: Video player v1 (code written, awaiting first compile + device test)
- [x] Own player screen: gestures (seek, brightness, volume, pinch zoom, double-tap skip, hold 2x), aspect modes, lock, rotate, speed, repeat, shuffle, folder queue, resume
- [x] Subtitles SRT / VTT / ASS-SSA: auto sidecar, choose file, delay, size, colour, outline, background; remembered per video
- [x] Video library: All / Folders / Recent / Favorites, search, sort, list/grid, thumbnails + duration, watched progress, multi-select actions
- [x] Details sheet (container, tracks), playlist sheet, honest unsupported-codec screen, Settings > Media > Video player
- [ ] v2 (needs a stronger engine): audio-track + embedded-subtitle selection, Picture-in-Picture, frame-step, chapters, software decoders, network streams, trim/convert tools

## Ideas taken from other file managers
(From general knowledge of Google Files, Xiaomi/MIUI, Samsung My Files, Oppo/Realme (ColorOS), iOS Files, Windows Explorer,
macOS Finder, Linux file managers. Own UI and names; nothing copied.)
| Seen in | Idea | Status in Fyleon |
|---|---|---|
| Google Files | Recent "See all", Apps screen with Large/Unused/Games, quick image actions, swipe between pictures | done (session 8) |
| Google / Samsung | Quick Share style nearby sending | done as Fyleon Dash (Wi-Fi/hotspot), Nearby later |
| Xiaomi, Oppo, Realme | Cleaner (cache, junk, large files), app manager | cache sizes + guided clear done; large-file/duplicate cleaner planned |
| Samsung My Files | Storage analysis, APK backup of installed apps | APK backup done; storage analysis planned |
| Windows Explorer | Quick access / pinned folders, tabs, dual pane, details pane | pinned folders + tabs/dual pane planned (tablet/desktop) |
| macOS Finder | Colour tags, Quick Look preview, column view | tags + long-press preview planned |
| iOS Files | Recents/Shared/Tags, "On My iPhone" structure | Recent tab exists; tags planned |
| Linux (Nautilus, Dolphin) | Bookmarks sidebar, split view, bulk rename | planned (bulk rename, split view) |

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
