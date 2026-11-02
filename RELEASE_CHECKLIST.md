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

## C. Before Play Store
- [ ] Real AdMob ids in `config/fyleon_config.json`; `useTestAds: false` (store build only)
- [ ] AdMob consent message (GDPR) created; app-ads.txt if you have a website
- [ ] Privacy policy URL; Data safety form (ads, no data collected by Fyleon itself); content rating
- [ ] App name/trademark check; store listing text, icon 512, feature graphic 1024x500, screenshots
- [ ] Decide `allFilesAccess`: if true, submit the "All files access" declaration with a video; else keep picker-only
- [ ] Target API level meets Play's current requirement (the Flutter 3.47 template should; verify in Play Console)
- [ ] Internal testing track first, then closed/open testing, then production (new personal accounts need a closed test period)

## D. Each release
- [ ] Bump `version:` in pubspec.yaml (name part); build number = CI run number
- [ ] Update HANDOVER.md, FEATURES.md
- [ ] Run workflow with draft release; test the signed APK; upload the signed AAB to Play; publish the GitHub draft release when ready

## E. Other platforms (later)
iOS/macOS: Apple Developer account, macOS runner, signing certs/profiles. Windows: MSIX or installer on `windows-latest`. Linux: AppImage/deb/snap.
