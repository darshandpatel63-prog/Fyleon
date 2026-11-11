# UI / UX GUIDE

## Principles
- Open a file in one tap. Ads never stand in the way.
- Calm, modern, rounded (Material 3), generous spacing, color by file type.
- Motion is short and meaningful: 220-320 ms, ease-out curves.

## Design tokens
- Radius: cards 18, tiles 14, chips pill, dialogs 28 (Material default).
- Brand gradient: #4F46E5 -> #7C3AED -> #06B6D4 (indigo, violet, cyan).
- File type colors: see `FileKind.color` in `features/files/domain/file_kind.dart`.
- Typography: Material 3 defaults (system font). No runtime font downloads.

## Patterns
- Files tab: filter chips on top, list or grid below, "Open file" extended FAB.
- Sort via bottom sheet (current option highlighted with a check).
- List items fade+slide in (staggered, max 8 steps). Grid cards show image thumbnails for images.
- Viewers: own AppBar, minimal chrome; reader screens (EPUB) use reading themes independent of the app theme.
- Empty states: icon + one sentence + one action.
- Settings: grouped sections with uppercase labels; "Coming soon" items show a snackbar.

## Session 8 patterns
- Bottom bars (dock, banner, selection bars) always sit inside `SafeArea(top:false)` so Android navigation buttons never cover them.
- Viewers: overlay top bar (gradient) + optional floating pill; owner-configurable (Settings > Viewer toolbar). One tap hides the bars.
- Paged documents (PDF, PowerPoint): one continuous scroll + "3/52" pill with up/down buttons (tap the number to jump).
- Apps screen: pill tabs, filter chips, long-press = multi-select with a bottom summary (cache + size) and actions.
- Dash: animated radar rings while searching, gradient Send / Receive cards, QR + big spaced code on the sender, avatars for devices.

## Accessibility
Tooltips on icon buttons, text scaling respected, contrast from Material color schemes. Review before release.
