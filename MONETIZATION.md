# MONETIZATION

## AdMob (Phase 1)
| Format | Where | Rules |
|---|---|---|
| Banner | bottom of the main screen, above navigation | loads silently; hidden until loaded; never in viewers |
| Interstitial | after the user CLOSES a file | every 4th close, min 180 s gap (remote-configurable) |
| Rewarded | unlock a premium theme for 24 h | only when the user taps "Watch ad" |
| Native (small template) | after every 4 items in lists/grids, Files home, Settings | max 6 per list, hidden until loaded, labelled "Ad" by AdMob |
| Banner + native (Dash, Apps) | bottom banner on Dash home/send/receive/transfer and on the Apps screen; native ad after every 3 files on Dash lists (remote `ads.dashNativeEvery`), after every N items on the Apps list | never blocks sending/receiving; hidden until loaded; no interstitial inside Dash |
Rewarded interstitial and app open: the ids are already in `config/fyleon_config.json` (and the test ids in `AppConfig`), but the app does not show these two formats yet (later, carefully capped).

## Which ads does a build show? (decided by the BUILD, not by editing files)
Run: GitHub > Actions > "Android Build" > Run workflow > choose **release** or **debug**.
| Choice | Ads | Files | Signed with |
|---|---|---|---|
| **release** | **REAL** ad units from `config/fyleon_config.json`, real AdMob app id in the manifest | APK (Amazon Appstore / sideload) + AAB (Google Play) | your upload key (GitHub secrets) |
| **debug** | Google **TEST** ads only, Google's sample app id | one APK (quicker, no AAB) | debug key, not for any store |
Settings > About shows `TEST ads` or `LIVE ads`, so you can always check which app you are holding.
The workflow refuses to build a release when a real id is missing in the config (or is a Google test id) or when the signing secrets are missing.
`useTestAds` in the config file only matters for builds NOT made by the workflow (`flutter run` on a computer).

## Safety rules (account protection)
- Test ids are in code (`AppConfig`). Real ids go ONLY in `config/fyleon_config.json` (ad unit ids are not secrets; keystore + passwords stay in GitHub secrets).
- Never click your own LIVE ads (can get the AdMob account banned). Test with the debug build (test ads).
- Ads must never delay opening a file or cover content.
- EU/UK/CH: UMP consent is implemented; create the consent message in the AdMob console (Privacy & messaging).
- Add a privacy policy URL in the store console and in AdMob.

## AdMob setup of this app
- Package name: **`com.fyleon.app`** (use exactly this in AdMob > Apps > App settings and in every store).
- Store listing for AdMob: Amazon Appstore link once the app is approved (add it in AdMob > App settings; then AdMob can verify the app).
- Ad units created: banner, interstitial, rewarded, native, rewarded interstitial, app open (ids are in the config file).
- Fire tablets / devices WITHOUT Google Play services do not show AdMob ads at all (Google Mobile Ads needs Play services). Phones that install from the Amazon Appstore but have Play services are fine.

## Later: subscription (Fyleon Pro)
- Must use Google Play Billing / Apple In-App Purchase. Account login alone cannot take payment.
- Prices live in the store consoles; show them from the store API. Entitlements/flags via Remote Config.
- Pro = no ads, all themes, advanced tools. Account (Google sign-in) is only needed for restore/sync, not for payment.
- Premium themes on platforms without ads (desktop) are currently open; revisit with the subscription.
