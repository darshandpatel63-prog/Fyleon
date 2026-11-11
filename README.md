# Fyleon

Open anything. A universal file viewer (and later editor) for every device. Flutter, one codebase.
Package: `com.fyleon.app`. Phase 1 target: Android.

## What works now (Phase 1)
PDF, EPUB, text and code (syntax highlight), images, ZIP/JAR/APK/AAB/TAR listing, basic DOCX/XLSX/PPTX,
list + grid view, sort, filter, search, themes, AdMob (test ads), file manager + code editor, Apps screen with cache sizes,
background audio, photo editor and Fyleon Dash (send files to nearby devices over Wi-Fi / hotspot).

## Build with GitHub (no local setup)
1. Create a GitHub repo and upload everything from this ZIP (keep the `.github` folder).
   Tip: if the hidden `.github` folder does not upload from your phone, create the file
   `.github/workflows/android.yml` on github.com ("Add file > Create new file") and paste its content.
2. Open the repo: Actions > "Android Build" > Run workflow.
3. First run creates `android/` and commits it back to the branch. Later runs reuse it.
4. When finished: download the APK/AAB from the run's Artifacts, or from the DRAFT release.

Without signing secrets the files use the debug key (fine for testing; AAB is NOT valid for Play Store).
See RELEASE_CHECKLIST.md for signing.

## Local commands (if you have Flutter 3.47)
    flutter pub get
    flutter create --org com.fyleon --project-name app --platforms=android .
    python3 tool/patch_android.py
    dart run flutter_launcher_icons && dart run flutter_native_splash:create
    flutter run

## Docs
HANDOVER.md (start here), ROADMAP.md, FEATURES.md, ARCHITECTURE.md, UI_UX_GUIDE.md,
SPLASH_AND_BRANDING.md, MONETIZATION.md, SECURITY.md, AI_VAULT_SPEC.md, RELEASE_CHECKLIST.md
