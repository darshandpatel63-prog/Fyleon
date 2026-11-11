# RELEASE CHECKLIST

## A. First CI build
- [ ] Repo created, ZIP content uploaded (incl. `.github/workflows/android.yml`)
- [ ] Actions > Android Build > Run workflow (draft release ON)
- [ ] Green build; download APK; install; test every viewer; note bugs in HANDOVER.md

## B. Create the upload keystore (once, on a computer or Termux)
    keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias fyleon
Back it up safely (password manager + offline copy). Losing it = painful (Play App Signing can reset upload keys, but plan ahead).
Then add GitHub Secrets (Settings > Secrets and variables > Actions):
- `ANDROID_KEYSTORE_BASE64`  = output of `base64 -w0 upload.jks`
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (fyleon), `ANDROID_KEY_PASSWORD`
Never commit the keystore. Never paste it in chat.

## B2. R8 / code shrinking
Currently OFF (`build.shrinkCode=false` in config) because R8 broke WorkManager at startup. Before the store release:
set it to true, run "Android Smoke Test"; if the app starts, keep it (smaller, obfuscated app). If not, leave it off.

## C. Before Play Store
- [ ] Real AdMob ids in `config/fyleon_config.json`; `useTestAds: false` (store build only)
- [ ] AdMob consent message (GDPR) created; app-ads.txt if you have a website
- [ ] Privacy policy URL; Data safety form (ads, no data collected by Fyleon itself); content rating
- [ ] App name/trademark check; store listing text, icon 512, feature graphic 1024x500, screenshots
- [ ] Decide `allFilesAccess`: if true, submit the "All files access" declaration with a video; else keep picker-only
- [ ] Target API level meets Play's current requirement (the Flutter 3.47 template should; verify in Play Console)
- [ ] Internal testing track first, then closed/open testing, then production (new personal accounts need a closed test period)

## C2. Play Console declarations for this app
- All files access (MANAGE_EXTERNAL_STORAGE): core feature = file manager. Prepare a short video and justification.
- Intent filters for VIEW/SEND with any MIME type are allowed for file managers/viewers.
- If an installed-apps list is added later: QUERY_ALL_PACKAGES needs its own declaration (or use a narrower approach).
- REQUEST_INSTALL_PACKAGES (install APK from the file manager): declaration + short video.
- PACKAGE_USAGE_STATS ("Usage access") is a special permission the user turns on; explain in the listing that it is used only for app sizes.
- FOREGROUND_SERVICE_MEDIA_PLAYBACK: declare "media playback" use (background audio/video sound).
- Camera (QR scanner) and local network use (Dash) belong in the privacy policy / Data safety text (nothing is uploaded).
- QUERY_ALL_PACKAGES stays OFF unless the owner wants the full system-app list (file managers may declare it).
- Data safety: no data leaves the device except AdMob (ads) and optional Google Drive backup (later).

## D. Each release
- [ ] Bump `version:` in pubspec.yaml (name part); build number = CI run number
- [ ] Update HANDOVER.md, FEATURES.md
- [ ] Run workflow with draft release; test the signed APK; upload the signed AAB to Play; publish the GitHub draft release when ready

## E. Other platforms (later)
iOS/macOS: Apple Developer account, macOS runner, signing certs/profiles. Windows: MSIX or installer on `windows-latest`. Linux: AppImage/deb/snap.
