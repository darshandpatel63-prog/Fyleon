# AI VAULT SPEC (Phase 4, not built yet)

## Goal
Let users bring their own AI API keys and use AI inside Fyleon (summaries, edits, code, app generation)
without Fyleon ever seeing or storing keys on a server.

## Storage and access
- Keys encrypted with a key held in Android Keystore / iOS Keychain (hardware-backed when available).
- Vault opens with fingerprint/face or device screen lock (local_auth). Auto-lock after N minutes.
- Keys never in logs, analytics, crash reports, backups in plain form, or screenshots (secure flag on vault screens).
- Optional encrypted backup to the user's OWN Google Drive (appData scope), encrypted with a key derived from a passphrase or the Keystore key; restore requires unlock.

## Data model
Provider (Gemini, Claude, ChatGPT, Kimi, Grok, others via OpenAI-compatible) -> Models -> Keys.
- Many keys per model (example: Gemini 3.1 Pro x3, Gemini 3 Flash x8).
- Per key: label, status (ok, rate-limited until T, invalid), usage counters (local only).
- Per model: ordered key list, round-robin or priority.

## Failover
On 429/quota/5xx: mark key cooldown, retry with the next key of the same model; if all keys are exhausted, optionally fall back to a user-chosen backup model. Show a small toast, never loop forever (max attempts, backoff).

## Switching in the UI
Every AI action shows a compact model chip (provider + model + key group). Tap = quick switcher sheet. The user does not need to open the vault each time; the vault stays locked while the session token (biometric-unlocked, in memory) is valid.

## Provider adapters
`AiProvider` interface: `listModels()`, `chat(stream)`, `countTokens()`, error mapping. One adapter per vendor; OpenAI-compatible adapter covers many.

## Rules
- Sending file content to an AI provider needs explicit user consent per action (and a visible "what will be sent" preview).
- Fyleon never ships developer keys. Users pay their own providers.
- Play/App Store: disclose AI use and data sharing in the privacy policy and store data safety form.
