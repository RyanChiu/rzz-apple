# RZZ App Store Review Notes (Template)

## 1) App Summary
- App Name: `RZZ`
- Category: RSS Reader
- Platforms: `macOS` / `iOS`
- Core Function:
  - User adds custom RSS/Atom feed URLs.
  - App fetches feed metadata and article content for reading/offline cache.

## 2) Account / Login
- No account required.
- No third-party login.
- Reviewer can fully test the app without credentials.

## 3) Network Behavior
- User-entered feed URLs are fetched over `URLSession`.
- Article pages are rendered in a reader WebView with sanitized HTML.
- Links tapped inside reader are opened externally (system browser), not in-app navigation.

## 4) ATS / Web Content Explanation
- The app sets `NSAllowsArbitraryLoadsInWebContent = YES` for user-selected web article rendering only.
- We do **not** enable broad arbitrary loads for `URLSession`.
- Security controls in place:
  - HTML sanitization for reader content.
  - Per-feed controls for content access path.
  - In-app reader blocks non-HTTP(S) link navigation.
  - Link taps are redirected to external browser.

## 5) Proxy / Insecure Content (User-Controlled)
- Proxy is optional and configured per feed.
- Feed access and article-content access have separate proxy toggles.
- Optional insecure HTTP content loading is per-feed and explicitly user-enabled.

## 6) Security & Local Data
- App lock supported (4-6 char PIN).
- PIN hash stored in Keychain-backed secure storage.
- Hashing uses PBKDF2 + random salt + iterations; legacy hashes auto-migrate.
- Proxy passwords are stored in secure storage (not plaintext export).

## 7) Backup / Import / Export
- User can export/import local data (`.json`).
- Import includes validation (file size, counts, field limits, URL/schema checks).
- Proxy passwords and app-lock PIN are not imported from backup files.

## 8) Permissions
- Local notification permission is used only for optional refresh/export completion notices.
- No camera/microphone/photos/contact/location usage.

## 9) Reviewer Quick Test Steps
1. Launch app and add a public RSS URL (e.g. `https://hnrss.org/frontpage`).
2. Refresh feeds and open an article.
3. Tap a link inside article body; confirm it opens in external browser.
4. Enable app lock in Security settings; background/return to app and verify unlock flow.
5. Export backup and import it back; confirm data restore works.

## 10) Contact for Review Questions
- Contact Email: `<YOUR_REVIEW_CONTACT_EMAIL>`
- If needed, we can provide a screen recording for the exact test flow.

