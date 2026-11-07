# MONETIZATION

## AdMob (Phase 1)
| Format | Where | Rules |
|---|---|---|
| Banner | bottom of the main screen, above navigation | loads silently; hidden until loaded; never in viewers |
| Interstitial | after the user CLOSES a file | every 4th close, min 180 s gap (remote-configurable) |
| Rewarded | unlock a premium theme for 24 h | only when the user taps "Watch ad" |
| Native (small template) | after every 4 items in lists/grids, Files home, Settings | max 6 per list, hidden until loaded, labelled "Ad" by AdMob |
Other AdMob formats (app open, rewarded interstitial) come later, carefully capped.

## Safety rules (account protection)
- Test ids are in code (`AppConfig`). Real ids go ONLY in `config/fyleon_config.json`.
- `useTestAds: true` forces Google test ads even if real ids are filled in. Set it to `false` only for store builds.
- Never click your own live ads; test with test ads or registered test devices.
- Ads must never delay opening a file or cover content.
- EU/UK/CH: UMP consent is implemented; create the consent message in the AdMob console (Privacy & messaging).
- Add a privacy policy URL in Play Console and AdMob.

## Setup steps for the owner
1. Create AdMob account, add the Android app (`com.fyleon.app`), create 3 ad units (banner, interstitial, rewarded).
2. Fill `config/fyleon_config.json` (android appId + unit ids). The CI patches the manifest app id from it.
3. Keep `useTestAds: true` until internal testing; flip to `false` for the production build.

## Later: subscription (Fyleon Pro)
- Must use Google Play Billing / Apple In-App Purchase. Account login alone cannot take payment.
- Prices live in the store consoles; show them from the store API. Entitlements/flags via Remote Config.
- Pro = no ads, all themes, advanced tools. Account (Google sign-in) is only needed for restore/sync, not for payment.
- Premium themes on platforms without ads (desktop) are currently open; revisit with the subscription.
