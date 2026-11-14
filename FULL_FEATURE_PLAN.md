# FYLEON FULL FEATURE PLAN (features + UI + phases)

Package: `com.fyleon.app` | App version in repo: 0.8.0 | Written: 11 Nov 2026
Sources: the 8 feature specs (`Fyleon_Feature_Specs.zip`: master, video, image, music, file manager/archive, PDF/Office/eBook, code/data/3D, roadmap/QA) + `Fyleon-main` repo state (HANDOVER.md sessions 1-9).
Companion file: `FORMATS_BLUEPRINT.md` (every format, tiers, Format Packs page). Put both files in the repo root.

This is a PLAN. Status words used everywhere: `planned` -> `in progress` -> `code written` -> `CI passed` -> `device tested` -> `known limitation`.

---

## 1. Vision and product rules

Fyleon = one privacy-first app to **find, open, play, edit, create, convert and share** files, Android first, then tablet/desktop (same Flutter code).

Rules that decide many details:
1. "Open anything" is a goal, not a promise. The app says exactly what it can do with a file (R0-R4 levels, see `FORMATS_BLUEPRINT.md`).
2. Edit / Create / Convert buttons appear only when really implemented for that format.
3. Original file is never lost: Save Copy by default, atomic writes, undo, Trash.
4. Local first. Nothing is uploaded without a clear user action. No own cloud; backup only to the user's own Google Drive (later).
5. Unknown content is never executed (scripts, EXE, macros, pickles, HTML scripts).
6. Ads never block opening, playing, editing, saving or exporting, and never sit over content or controls. No interstitial during playback, editing, export, save or permission flows.
7. Small core app; extra formats come as optional Format Packs.
8. Design is Fyleon's own (no copying of other apps' UI, names or art).

---

## 2. Where we are (repo v0.8.0)

| Area | State |
|---|---|
| Build | GitHub Actions: `release` (REAL ads, signed APK+AAB) or `debug` (TEST ads). v0.8.0 APK is installed on the owner's phone, so the session-8 code compiled |
| File manager | list/grid, sort, filter, search, recents, Recent "See all", create/rename/copy/move/delete, Trash, Starred, Favorites, PIN Safe Folder (not encrypted yet) - `code written`, partly device-tested |
| Viewers | PDF (page pill 3/52), EPUB (pages, TOC, themes), text/code (highlight + editor), images (swipe, zoom, photo editor), DOCX/XLSX/PPTX basic previews, archive list + extract, web/Markdown preview - `code written` |
| Viewer toolbar | customisable (Star, Heart, Share, Edit, Details, Open with, Prev/Next) - `code written` |
| Media | audio via `just_audio` (notification + background); **video player v1 (session 11) `code written`**: gestures, subtitles, resume, queue, library; audio-track/embedded-subtitle choice, PiP, software decoders = v2 |
| Apps | installed apps, sizes/cache (Usage access), guided cache clean, uninstall, APK backup - `code written` |
| Dash | Wi-Fi/hotspot sharing: nearby list, QR, 5-7 digit code, many receivers, ads between files - `code written`, not encrypted |
| Ads | banner / interstitial / rewarded / native live; rewarded-interstitial + app-open ids stored, not shown yet |
| Not started | Format Packs, universal identify engine, video v1 gestures/subtitles, gallery timeline, music library, PDF tools, Office editing, Git, terminal, AI Vault, Drive backup, subscription |

First rule of the roadmap (from the specs): **stabilise before adding**. Every module below starts with device testing of what exists.

---

## 3. Navigation and screen skeleton

Compact phone: bottom dock. Tablet/foldable/desktop: navigation rail + two panes.

```
PHONE                                   TABLET / DESKTOP
+------------------------------+        +----+-------------------+------------------+
| Fyleon              [search] |        |Rail| Folder tree /     | Content or       |
|------------------------------|        |    | categories        | preview pane     |
|  Home content ...            |        |Home|                   |                  |
|                              |        |Files|                  |                  |
|------------------------------|        |Media|                  |                  |
| banner ad (outside content)  |        |Create|                 |                  |
| [Home][Files][Media][+][Set] |        |Proj |                  |                  |
+------------------------------+        +----+-------------------+------------------+
```

Tabs: **Home**, **Files**, **Media** (Photos / Videos / Music), **Create (+)**, **Projects** (code), **Settings**. Today the repo has Files / Recent / Settings; Media, Create and Projects arrive with their modules.

Rules: back button always works, bottom bars sit inside SafeArea, every gesture has a visible button, minimum 48 dp touch targets, light/dark/AMOLED/high-contrast themes, font scaling, screen-reader labels.

---

## 4. Universal open pipeline

```
 tap / Share / Open with / archive entry / picker
        |
        v
 [1 Source]   keep the URI (SAF / content:// / path); do not assume a real path
        |
        v
 [2 Identify] extension + MIME + magic bytes (bounded prefix) -> format + confidence
        |
        v
 [3 Inspect]  bounded metadata (size, dims, duration, pages, entries)
        |
        v
 [4 Route]    format registry -> best handler (several? show chooser)
        |
        +--> handler ready ........ open (R2/R3)
        +--> pack missing ......... sheet: [Download and open][Open with other app][Info/Hex]
        +--> unknown / T3 ......... Info + Hex + hash + [Open with] + [Save copy]
```
Handler contract (each viewer/editor): `canHandle`, `open`, `buildPreview`, `buildEditor`, `save(atomic)`, `export`, `dispose`, capability flags (`canOpen canPreview canEdit canCreate canConvert canExtract requiresPermission knownLimitations`). The dispatcher uses a registry, never a giant `switch`.

Actions available for every file: open, open as, open with, share, send (Dash), save copy, rename, move, copy, duplicate, delete to Trash/restore, Star/Favorite, details (type, size, dates, checksum, dimensions/duration/pages), select many.

---

## 5. Module plans

Each module: goal, features by phase, UI, engine/risks, acceptance tests. "v1" = first usable release, "later" = after v1 is device-tested.

### 5.1 Home and File Manager

**Goal:** fast, clear browsing and safe file operations.

**v1 (mostly code written; needs device tests + gaps)**
- Home: search, storage rings (internal, SD, USB), Recent (+See all), Categories (Downloads, Images, Videos, Audio, Documents, Apps, Archives...), Collections (Starred, Favorites, Safe, Trash), Dash card.
- Browse: breadcrumb, back/forward/up, list/compact/grid/details, sort (name, ext, size, modified, opened; folders-first, natural order), filters, hidden-files toggle.
- Operations: new folder/file, rename (extension warning), copy/move with progress + cancel + conflict (skip/replace/keep both), Trash + restore + auto-purge, batch rename with preview, checksum (SHA-256 default; MD5/SHA-1 labelled legacy).
- Multi-select everywhere (range select, select all).
- Access model: SAF + Photo Picker first; "All files access" optional with picker fallback; clear message when Android blocks `Android/data`.

**Later**
- Dual-pane (tablet/desktop), tabs, pinned folders/bookmarks, saved searches, colour tags, long-press quick preview.
- Content search (opt-in): text/PDF/Office/EPUB, bounded.
- Cleanup: large files, duplicates (size + checksum, never auto-delete), empty files/folders, old downloads; storage analyzer by category/folder; "not enough space" check before copy/extract/convert/record.
- Network locations (FTP/SFTP/SMB/WebDAV/UPnP) as separate opt-in providers, credentials in Keystore.
- Safe Folder with real encryption (AEAD, per-file nonce, key in Android Keystore, biometric/PIN, auto-lock, excluded from search/recents/thumbnails). Until then it is called **"hidden"**, never "encrypted".

**UI**
```
FILES (list)                              SELECTION MODE
+--------------------------------------+  +--------------------------------------+
| < Internal > Download > Work   [sort]|  | X  3 selected        [all] [...]     |
| [search........................] [v]  |  |--------------------------------------|
| chips: All | Docs | Images | Big ...  |  | [v] report.pdf     2.1 MB            |
|--------------------------------------|  | [v] photo.jpg      4.0 MB            |
| [icon] report.pdf       2.1 MB  *    |  | [ ] notes.txt      1 KB              |
| [icon] photo.jpg        4.0 MB       |  |--------------------------------------|
| [icon] notes.txt        1 KB         |  | [Copy][Move][Share][Dash][Delete][..]|
|--------------------------------------|  +--------------------------------------+
| banner                               |
| [Home][Files][Media][+][Settings]    |
+--------------------------------------+
```
**Acceptance:** SAF file from cloud/USB/SD, no raw-path assumption; copy of a large file with low storage, revoked permission, process killed; duplicate names, emoji/Unicode names, case-only rename; Trash restore when the original path is taken; system folders never shown if Android denies access.

---

### 5.2 Archive manager

**Goal:** browse, extract and create archives safely (ZArchiver-class, own design).

**v1:** ZIP/JAR/WAR/AAR/APK/AAB/IPA/TAR/TGZ/GZ/BZ2/XZ browse; extract all or selected; **create ZIP** (levels store/fast/normal/max, name, include folders); folder-like navigation, entry search, preview of entries through the normal handlers (streamed to a bounded private cache); progress, cancel, free-space check, overwrite policy.
**Later (packs):** 7z, RAR (read-only), ZST/LZ4/LZMA, CAB, ISO, CPIO, RPM; password ZIP (AES) after library audit; split volumes; update/add/remove inside an archive where safe.
**Security (non-negotiable):** canonicalise every path (no `..`, absolute, drive prefixes), block symlink escapes and name collisions, limits on total size, ratio, entry count, depth and time (zip-bomb defence), never extract to protected paths, never run extracted files, warn for APK/EXE/JS/PS1.
**APK inspector:** package, label, version, SDK, ABIs, permissions, signing digest, hash; install only via the Android installer with user confirmation.

```
ARCHIVE BROWSER
+--------------------------------------+
| < backup.zip  > photos >    [search] |
|--------------------------------------|
| [dir]  2024                 12 items |
| [img]  IMG_001.jpg   3.1 MB  (1.9)   |   (size, packed size)
| [txt]  readme.txt    2 KB            |
|--------------------------------------|
| 148 files | 1.2 GB -> 640 MB | AES   |
| [Extract all] [Extract selected] [+] |
+--------------------------------------+
```
**Acceptance:** traversal, symlink, zip-bomb, corrupt, encrypted, split and huge-entry-count fixtures; extraction CRC check before "done".

---

### 5.3 Video player  (v1: `code written` in session 11, see HANDOVER.md; v2/v3 below still `planned`)

**Goal:** a dependable local player first, advanced network player later. (VLC / MX-class capability, original design.)

**v1 (next big slice, on the current `video_player` engine)**
- Play/pause, seek bar with elapsed/remaining, 5/10/15/30 s skip, previous/next in folder, resume per file (ask after long gap), repeat one/all, shuffle, keep screen on, orientation (auto/lock/landscape), immersive full screen.
- Speed 0.25x-2x.
- Gestures (all configurable, all with button alternatives): horizontal swipe seek with time preview, left side vertical = brightness, right side vertical = volume, pinch zoom + pan, double tap left/right skip, double tap centre play/pause, tap show/hide, long press 2x. Left/right-hand layout.
- Aspect modes: Fit, Fill, Crop, Stretch, Original, 16:9, 4:3.
- External subtitles SRT/VTT (sidecar auto-detect, browse via SAF), delay +/- ms, size/colour/outline/position; Unicode incl. Gujarati/Hindi.
- Background/"Audio only", notification + lock-screen controls (done in session 8), audio focus.
- Library: All videos, Folders, Recent, Favorites, sort/search/filter, details sheet (container, codec, resolution, fps, bitrate, duration), thumbnails with cache limit, multi-select.
- Honest errors: "unsupported codec: HEVC not decodable on this phone" with [Open with another app].

**v2 (needs a stronger engine: custom Media3 plugin or optional software decoder pack)**
- Embedded audio-track and subtitle-track selection, ASS/SSA styling, audio delay, decoder diagnostics (decoder, codec, dropped frames), Picture-in-Picture with controls, floating mini-player (permission explained), frame step, chapters.
- HDR indicator, 360 video, software-decode fallback (heavy: only as optional pack/Full flavor).
- Network: HTTP/HLS/DASH links, SMB/SFTP/FTP/WebDAV/DLNA, casting. Never bypass DRM or scrape.

**v3 tools:** trim, extract frame/audio, mute, rotate, transcode presets with size estimate, merge compatible clips, batch queue, burn-in/mux subtitles. Output is always a new file.

**Engine decision (needs a proof of concept):**

| Option | Good | Cost |
|---|---|---|
| Keep `video_player` (ExoPlayer inside) | already works, small | no track selection, limited subtitles, no PiP |
| Own Media3 platform plugin | full control, official | native code to write and maintain |
| LibVLC / mpv based plugin | widest formats | big native size, licensing, ABI work |
Plan: v1 on `video_player`; start a Media3 PoC for v2; LibVLC only as optional engine.

```
VIDEO PLAYER (landscape)
+----------------------------------------------------------+
| <  holiday.mp4                       [CC][audio][...]    |  <- fades after 3 s
|                                                          |
|   (left swipe: brightness)   VIDEO   (right swipe: vol)  |
|                    <<10   [ > / || ]   10>>               |
|                                                          |
| 00:12 =====o----------------------------- 03:45  [1.0x]  |
| [lock] [aspect] [rotate] [audio only] [PiP*]             |
+----------------------------------------------------------+
 * v2
Ads: never in this screen.
```
**Acceptance:** MP4 H.264/AAC, HEVC, MKV multi-track, WebM VP9/Opus, MOV, AVI, big file (streamed, not loaded in RAM); sync, resume, rotation, background/foreground, Bluetooth buttons, call interruption; corrupt, zero-byte, truncated, revoked URI; screen reader, tablet, font scale.

---

### 5.4 Gallery, photo viewer and editor

**Goal:** a fast gallery plus a safe, non-destructive editor (Google Photos / Snapseed / Aves-class capability, original design).

**v1**
- Media tab > Photos: timeline grouped by day/month/year, Albums (device folders), Favorites, Screenshots, Camera, Downloads, GIF/animation, RAW (listed), Recently deleted (Trash).
- Index through MediaStore / Photo Picker (no broad access just to show photos). Thumbnail cache with LRU + size limit + "clear cache"; never decode full-size bitmaps in the grid.
- Viewer (exists): swipe, pinch/double-tap zoom, rotate/flip, bars toggle, details sheet with EXIF summary, animated GIF/WebP play/pause, SVG safe render, RAW embedded preview (pack).
- Editor (basic exists): crop presets, rotate/flip, 6 filters, brightness/contrast/colour -> extend with straighten, exposure, highlights/shadows, warmth/tint, saturation/vibrance, sharpen, vignette, **before/after compare**, **undo/redo/revert**, Save Copy (default) or replace.
- Markup: pen, highlighter, arrows, shapes, text; pixelate/redact (warning: decorative blur is not secure redaction).
- Metadata: EXIF/IPTC/XMP viewer; **remove GPS before sharing** (on a copy); hash + signature in inspector.
- Multi-select: share, move, copy, delete, favorite, add to album, batch rename.

**Later**
- Curves/levels, healing/clone, selective/radial/gradient, layers/stickers/frames, collage maker with templates, wallpaper/contact image, slideshow.
- Batch: resize, compress, convert (JPEG/PNG/WebP/AVIF where supported), strip metadata, watermark, queue with pause/cancel/retry and loss warnings.
- Duplicate / similar images (local perceptual hash, never auto-delete), map view of GPS photos (opt-in, offline-first), calendar jump.
- Private album with real encryption. On-device search by objects/people only after a privacy review and opt-in. C2PA display only with a maintained verifier.
- Formats: HEIC/AVIF (device decoder or pack), TIFF multipage, JXL, RAW preview (packs), PSD/XCF/KRA flattened preview (design pack).

```
TIMELINE                                  EDITOR
+------------------------------------+    +------------------------------------+
| Photos            [search] [map*]  |    | X                 [undo][redo] Save|
| chips: All|Albums|Fav|Screenshots  |    |                                    |
|------------------------------------|    |           (image canvas)           |
| November 2026                      |    |        [hold = before / after]     |
| [ ][ ][ ][ ]                       |    |                                    |
| [ ][ ][ ][ ]                       |    |------------------------------------|
| October 2026                       |    | Crop Rotate Light Color Detail Fx  |
| [ ][ ][ ][ ]                       |    | Exposure  ----o------------  +0.4  |
|------------------------------------|    | [Save copy v]  (copy | replace)    |
| banner                             |    +------------------------------------+
| [Home][Files][Media][+][Settings]  |
+------------------------------------+
```
**Acceptance:** EXIF orientation JPEG, transparent PNG, animated GIF/WebP, HEIC/AVIF, SVG, multipage TIFF, huge panorama, RAW sample; corrupt image never crashes; edits non-destructive; Save Copy keeps original; output size/alpha/orientation/EXIF/GPS checked per converter; rapid scroll + low memory stress.

---

### 5.5 Music player and audio tools

**Goal:** a polished offline music app (Poweramp / Musicolet / foobar-class capability, original design).

**v1**
- Library from MediaStore + chosen folders: Songs, Albums, Artists, Genres, Folders, Playlists, Recently added/played, Most played, Favorites; fast A-Z index; search; sort.
- Player: queue (play next, add, save, restore), repeat/shuffle, notification + lock screen + Bluetooth buttons, audio focus, resume after process death, sleep timer (time / end of track / N tracks, fade), speed for spoken word.
- Playlists: create/edit/reorder, import/export M3U/M3U8/PLS, smart playlists.
- Lyrics: embedded + `.lrc` synced with offset, plain text; full-screen lyrics.
- Tags/artwork: viewer first, then editor (single + multiple files, art replace/remove), only on supported tag formats; always preserve on Save Copy.

**Later:** gapless + crossfade, ReplayGain, equalizer (presets, 5/10/15 bands, per-output presets), bass/treble/balance, limiter + clipping meter, multiple queues, waveform + spectrum visualiser (low/medium/high CPU), widgets, Android Auto (separate tested step), podcasts/audiobooks (chapters, bookmarks, silence skip, RSS later), internet radio and network shares (opt-in).
**Audio tools:** record (WAV/AAC/M4A/Opus; mic permission only on start), trim/join/fade/normalise/silence-trim, convert (bitrate/sample rate), extract audio from video, waveform editor, batch convert; presets (voice note, podcast, music, small share). Output is always a copy.

**Honest limits:** decoders depend on the phone; MIDI needs a soundfont (pack); Hi-Res/USB DAC only when the output path really supports it (show real rate/bit depth); DTS/Dolby need licences.

```
NOW PLAYING                                LIBRARY
+------------------------------------+     +------------------------------------+
| v                    [queue] [...] |     | Music            [search]          |
|        +----------------+          |     | Songs|Albums|Artists|Folders|Lists  |
|        |   album art    |          |     |------------------------------------|
|        +----------------+          |     | A  [art] Aaj ka din      3:41      |
| Song title                         |     |    [art] Alone           4:02      |
| Artist - Album                     |     | B  ...                             |
| 1:12 =====o--------------- 3:41    |     |------------------------------------|
| [shuf] [<<] [ > / || ] [>>] [rep]  |     | [mini player ...........  > / || ] |
| [EQ] [lyrics] [timer] [fav]        |     | banner / [Home][Files][Media]...   |
+------------------------------------+     +------------------------------------+
```
**Acceptance:** MP3 CBR/VBR, FLAC, WAV, AAC/M4A, Opus, OGG, ALAC; screen off, incoming call, navigation prompt, Bluetooth reconnect, process recreation; gapless/crossfade fixtures; tag edit without corruption; Indic lyrics rendering; route change without loud transient.

---

### 5.6 Documents: PDF, Office, eBooks

**PDF v1 (viewer exists, `pdfium`):** single/continuous/facing/book modes, fit width/page, zoom, thumbnails, page slider and "3/52" pill (done), text search with result list, select/copy, outline/bookmarks, links (confirm external), reading modes (night/sepia as overlay), recent page.
**PDF v2 tools:** highlight/underline/strike, pen, notes, text box, stamps, shapes; forms (AcroForm fill, Save filled copy); signature draw/type/import (no legal claim); merge, split, extract, reorder, rotate, delete pages; compress presets; watermark/page numbers; images <-> PDF; password open/create; OCR (on-device, language packs = data packs; searchable output); **true redaction** (remove underlying text, verified by re-search); never break certified signatures silently.

**Word / documents:** v1 viewer for DOCX/ODT/RTF/TXT/MD/HTML; v2 editor subset: styles, fonts, lists, tables, images, headers/footers, links, find/replace, word count, undo/redo, autosave, export DOCX/PDF/TXT/MD with fidelity warnings; later comments + tracked changes. Keep unmodified OOXML parts; warn about SmartArt/macros/embedded objects; macros never run. Legacy DOC/WPS/WPD via packs.
**Spreadsheets:** v1 viewer XLSX/ODS/CSV/TSV (tabs, frozen panes, virtualised grid, formula vs value); v2 edit: cells, formula bar, documented formula subset (SUM, AVERAGE, MIN, MAX, COUNT, IF, AND, OR, CONCAT, ROUND, DATE, lookups), formats, sort/filter, CSV import preview (delimiter/encoding/decimal), export CSV/XLSX/ODS/PDF; unsupported formulas shown as errors, never silently replaced; VBA never runs.
**Presentations:** v1 slide viewer (all-slides list + slide show, notes); v2 edit: add/duplicate/reorder slides, text boxes, images, shapes, tables, notes, align/group; export PDF/images; PPTX export only after round-trip tests; warn about transitions/animations/fonts/media.
**eBook reader (exists basic):** v2 Kindle-class features: shelf (series/author/collections), reflow settings (font, line height, margins, themes, hyphenation), fixed-layout, tap zones, page slider, TOC, footnotes, progress + time left, highlights (colours) + notes + bookmarks, search, dictionary/translate by user action, export notes to MD/TXT/CSV, TTS (Android voices, rate/pitch), OpenDyslexic where licensed, comics (CBZ/CBR/CB7/CBT). DRM is never bypassed.
**Create:** templates (blank, report, resume, invoice, notes), Save As via SAF, reopen-validate the produced file before "Done". Fonts: Gujarati, Hindi, other Indic, Arabic, CJK, RTL fallbacks.

```
PDF VIEWER                                 DOCUMENT EDITOR
+------------------------------------+     +------------------------------------+
| < report.pdf     [*][share][...]   |     | < letter.docx  [undo][redo] [Save] |
|------------------------------------|     |------------------------------------|
|                                    |     |  Heading 1                         |
|          (all pages scroll)        |     |  Body text with **bold** ...       |
|                                    |     |  | table | table |                 |
|                          [ 3/52 ]  |     |------------------------------------|
|                          [ ^ ][ v ]|     | B I U | A+ A- | list | table | img |
| [tools: Highlight Draw Note Sign]  |     +------------------------------------+
+------------------------------------+
```
**Acceptance:** text and scanned PDFs, large/encrypted/form/signed/damaged PDFs; DOCX with tables/images/RTL/Indic; XLSX multi-sheet + formulas; PPTX shapes/notes; EPUB reflow + fixed + RTL + big book; round-trip against Office/LibreOffice; no macro execution; redaction verified; OCR search works.

---

### 5.7 Code workspace and data tools

**Goal:** a phone-sized VS Code/Acode: project folders, tabs, search, preview.

**v1 (editor + web preview exist):** syntax highlight for ~40 core languages, line numbers, bracket matching, indent guides, word wrap, undo/redo, find/replace, go to line, encoding + line-ending choice, large-file safe mode, autosave drafts, external-change warning, HTML/CSS/JS + Markdown/SVG preview in sandbox (phone/tablet/desktop viewports, refresh, console).
**v2 workspace:** open folder as project, explorer tree, **multi-tab + split view**, recent projects, project search/replace (regex), file templates, outline/symbols, folding, snippets, colour picker, diagnostics list, format document (where a formatter exists), pinned workspace restore. Preview server: localhost only, project root only, no traversal.
**Later:** LSP client (user-approved servers), Git (status, diff, add, commit, pull, push, branch, stash; credentials in Keystore), SFTP/FTP project access, GitHub Actions trigger + log/artifact viewer ("cloud build", because Fyleon cannot build Android/iOS/Windows apps on the phone), optional sandboxed Python/JS runner with limits, optional terminal in a separate sandbox (off by default, network off, destructive commands confirmed).
**Data tools:** JSON/XML/YAML/TOML tree + validate + format + minify + diff, JSON Schema/OpenAPI preview, CSV/TSV grid (delimiter detect, sort/filter, export), **SQLite browser** (read-only default, SQL editor, explain plan, export; backup before edits), Jupyter viewer (no execution), HAR viewer (auth/cookies redacted), NumPy/Parquet/HDF5/FITS explorers (packs), hex viewer + hash + metadata inspector, diff for text/JSON/XML.
**Specialist viewers (packs):** 3D (orbit, wireframe, scene tree, animations, metadata), DXF/G-code/Gerber, GPX/KML/GeoJSON/shapefile maps, DICOM slices, fonts, email (EML/MBOX/MSG) in a sandbox, ICS/VCF (confirm before importing), certificates (metadata first, private keys behind a reveal step), AI model metadata (never unpickle, never run).

```
PROJECT WORKSPACE (tablet)                       PHONE
+----------+-------------------------------+     +------------------------------+
| EXPLORER | main.dart | app.dart | x |  [>]|     | <  app.dart *        [...]   |
| v lib    |-------------------------------|     | [tabs: main | app | +]        |
|   main   |  1 import 'x';                |     |------------------------------|
|   app    |  2 void main() {              |     |  1 import 'x';               |
| v test   |  3   runApp(...);             |     |  2 void main() {             |
|----------|  4 }                          |     |------------------------------|
| SEARCH   |-------------------------------|     | [Tab][ ( ][ { ][ ; ][undo]   |  <- code key row
| PROBLEMS | preview | console | git       |     +------------------------------+
+----------+-------------------------------+
```
**Acceptance:** save/reopen/Unicode/large file across a language suite; preview path-traversal/script/network tests; JSON/XML/YAML round trips; CSV quoting + encodings; SQLite read-only + transaction + rollback + WAL; notebook preview without execution; every Run/Build/Install/Connect needs an explicit user action.

---

### 5.8 Sharing and device tools (already started)

- **Fyleon Dash** (done, code written): Wi-Fi/hotspot, QR, 5-7 digit code, nearby list, many receivers, progress, ads between files. Next: encryption (key in the QR), resume, Nearby Connections (Bluetooth + Wi-Fi Direct, no common network), desktop checks. Also: local web transfer from a PC browser (user starts/stops, QR + one-time token, session expiry; never an open server).
- **Apps manager** (done, code written): sizes, cache, last used, guided clean, uninstall, APK backup/share. Honest limit: no silent cache clearing of other apps; needs Usage access (and "Allow restricted settings" for APK-installed builds).
- **Cloud (later):** Google Drive backup of the user's own settings/data; OneDrive/Dropbox/WebDAV through user-authorised connections.

---

### 5.9 Settings

```
SETTINGS
+--------------------------------------+
| Appearance   themes, AMOLED, contrast|
| Files        default view, sort, hidden, trash days, all-files access |
| Viewer toolbar   (done)              |
| Format Packs     (new)  -> FORMATS_BLUEPRINT.md |
| Media        background play, gestures, subtitles, decoder, resume |
| Gallery      thumbnails cache, GPS handling, slideshow |
| Music        scan folders, EQ, sleep timer, lyrics, artwork |
| Editor       font, tabs, autosave, large-file limit |
| Privacy      permission dashboard, history, Safe Folder, clear caches |
| Tools        Dash, Apps and cache      |
| Ads          (consent, remove ads later)|
| About        version, TEST/LIVE ads, supported formats, licences |
+--------------------------------------+
```
Permission dashboard lists each permission with "why" and a link to Android settings.

---

### 5.10 Monetisation and ads (per screen)

- Banner at the bottom outside content on Home/Files/list screens, Dash, Apps. Native ads between list items (every N items, capped; Dash every 3 files).
- Interstitial: only at calm moments (leaving a viewer after several opens, cooldown, never on first open, never during playback/editing/export/save/permissions).
- Rewarded: optional (premium theme unlock, extra tools). Never required to open or save the user's own file; no pack needs an ad.
- Rewarded-interstitial and app-open: ids are in the config; add only after the above is stable, tightly capped.
- Release build = real ads; debug build = test ads (Settings > About shows which). Never click your own live ads.
- Later: subscription (remove ads, premium themes, advanced tools) through Play/Amazon billing only.

### 5.11 Privacy, security, permissions
- SAF + Photo Picker first; all-files access optional and justified; request camera/mic/notification only at the moment of use with a "why".
- No upload, AI call, backup or network scan without an explicit action and destination.
- Untrusted input: ZIP/RAR/Office/PDF/EPUB/SVG/HTML/media metadata. HTML/SVG previews are sandboxed, no file or network access by default.
- Secrets (API keys, passwords, private keys) in Keystore-backed storage; never in logs, crash reports or analytics. No filenames, paths, contents or hashes in analytics.
- AI Vault (later): own API keys, biometric/PIN, several keys per provider with failover.
- Remote config may change numbers/flags and disable things, never download or enable code.

---

## 6. Roadmap

| Phase | Goal | Contents |
|---|---|---|
| **P0 Stabilise** | trust the base | device-test v0.8.0 (list in HANDOVER); fix crashes/data loss first; first **release** build for Amazon; privacy policy; fixture set for each viewer |
| **P1 Identify + Packs foundation** | every file gets a clear answer | F0-F3 of `FORMATS_BLUEPRINT.md` (catalog, identify engine, hex/hash/metadata inspector, Format Packs page, installer, grammar/OCR/font data packs) |
| **P2 Media quality** | the two biggest user-visible upgrades | **Video player v1** (5.3) + **Gallery v1** (5.4) first, then Music v1 (5.5) |
| **P3 Files power** | file manager depth | multi-select everywhere, cleanup + storage analyzer, ZIP create, archive packs, Safe Folder encryption, dual-pane/tabs |
| **P4 Documents** | productivity | PDF annotate/forms/merge/split/OCR, EPUB study features, DOCX/XLSX/PPTX edit subsets |
| **P5 Developer + specialist** | power users | project workspace, Git, data tools, SQLite, 3D/CAD/GIS/science packs |
| **P6 Services** | optional | Dash phase 2 (Nearby, encryption), network folders, AI Vault, Drive backup, subscription, iOS + desktop |

Time is not promised. Each step ends with: code -> CI build (debug) -> phone test -> HANDOVER/FEATURES updated only after the test passes.

### Next work order (requested by the owner)
1. (Docs, now) Put `FORMATS_BLUEPRINT.md` and `FULL_FEATURE_PLAN.md` in the repo root; merge the format plan into the blueprint.
2. ~~Video player v1~~ code written (session 11); phone test pending.
3. **Gallery v1** from 5.4 (timeline, albums, metadata sheet, editor extensions with undo/redo + compare).
4. Then P1 (identify engine + Format Packs page) and Music v1.

---

## 7. Quality gate for every feature ("Done")
Works on a real phone and supported Android versions; handles valid, malformed, large, truncated files; has loading/empty/permission-denied/unsupported/error states; loses no data on app close or process death; has automated tests for parsers, state and file operations; has a written list of tested formats + limitations; meets accessibility and privacy rules; memory and speed measured.

QA matrix per format: integrity (valid, corrupt, truncated, zero-byte, wrong extension) x size (tiny...near limit) x encoding (UTF-8, BOM, legacy, Unicode names) x storage (internal, SD, USB, SAF cloud, archive entry) x permission (granted, denied, revoked) x lifecycle (rotate, background, process kill, low memory) x action (view, edit, save, save copy, convert, share, delete/restore) x security (traversal, malicious refs, bombs) x accessibility (screen reader, font scale, contrast, keyboard).

Local diagnostics only unless the user opts in: launch success, open success per type, first-render time, peak memory, dropped frames, conversion success, archive rejections.

---

## 8. Release checklist (short)
Package `com.fyleon.app`; version + build number; signed release from the workflow; real AdMob ids (release only); permissions match features and store declarations; dependency + licence audit; test on one low-end and one new phone; 16 KB page-size check for native libraries; Safe Folder claims match reality; privacy policy and data-safety text; publish the tested format matrix and changelog.

---

## 9. Open questions
1. Pack repo public? Which store rules for downloaded packs (Amazon first)?
2. Video engine: stay on `video_player` for v1 and run a Media3 PoC, or go straight to a custom plugin?
3. Minimum Android version?
4. Priority order inside P2: Video first, then Gallery, then Music (as above)?
5. Do you want the "Full" GitHub flavor (all heavy engines) in addition to the small store build?
