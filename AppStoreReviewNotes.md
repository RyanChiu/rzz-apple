# RZZ App Store Review Notes

## 1) App Summary
- App Name: `RZZ`
- Category: RSS Reader
- Platforms: `macOS` / `iOS`
- Core Function:
  - Users add custom RSS/Atom feed URLs.
  - App fetches feed metadata and article content for reading and optional offline cache.

## 2) Account / Login
- No account required.
- No third-party login.
- Reviewer can fully test all major features without credentials.

## 3) Network Behavior
- User-entered feed URLs are fetched over `URLSession`.
- Article pages are rendered in an in-app reader WebView.
- Tapped links inside article body are opened externally (system browser), not in-app navigation.

## 4) ATS / Web Content
- `NSAllowsArbitraryLoadsInWebContent = YES` is used only for user-selected web article rendering in WebView.
- `URLSession` requests remain under ATS controls (no broad arbitrary load for app networking).
- Security controls in app:
  - Reader blocks non-HTTP(S) link navigation.
  - External links are routed to system browser.
  - Feed-level controls for proxy and insecure HTTP content.

## 5) Proxy / HTTP Controls (User-Managed)
- Proxy is optional and configured per feed.
- Feed URL access and article content access have separate proxy toggles.
- Optional insecure HTTP content loading is per-feed and explicit.

## 6) Security & Local Data
- App lock available (4-6 character PIN, letters/digits).
- PIN hash stored in Keychain-backed secure storage.
- PIN hashing uses PBKDF2 + random salt + iteration count; legacy hash auto-migration supported.
- Proxy passwords are stored in Keychain and are not exported in backups.
- If persistent local database cannot be opened, app falls back to memory-only mode and shows a warning.

## 7) Backup / Import / Export
- User can export/import local data in `.json`.
- Import uses validation (size/count/schema/string limits/URL checks).
- App lock PIN and proxy passwords are not imported from backup files.

## 8) Permissions
- Local notifications are used only for optional completion messages (refresh/export) when already authorized.
- No camera/microphone/photos/contacts/location usage.

## 9) Reviewer Quick Test Steps
1. Launch app and add a public RSS URL (example: `https://hnrss.org/frontpage`).
2. Refresh feeds and open an article.
3. Tap any link in article body and verify it opens externally.
4. Enable app lock in Settings, move app to background, return and verify unlock flow.
5. Export backup, then import backup, and verify content restoration.

## 10) Review Contact
- Contact Email: `<FILL_REVIEW_CONTACT_EMAIL>`
- Optional Notes:
  - If needed, we can provide screen recording for the exact reviewer flow.
