# rzz-apple

RZZ is a lightweight RSS reader for Apple platforms (macOS + iPhone), focused on:

- adding custom feed URLs
- managing subscriptions
- reading and organizing articles quickly

## Current V1 Features

- Feed management
  - Add feed by URL
  - Edit existing feed (name/url/proxy config with prefilled form values)
  - Delete feed with confirmation dialog
  - Prevent duplicate feed URLs
- Per-feed network config
  - Optional proxy per feed
  - Proxy types: HTTP(S), SOCKS5
  - Proxy host/port/username/password settings
  - Validation for proxy host and port range
- Refreshing and parsing
  - Refresh selected feed or all feeds
  - RSS XML parsing into local article cache
  - Deduplication using guid/link/title+date key strategy
  - Feed title auto-updates from parsed channel title
- Error handling and diagnostics
  - DNS and host resolution diagnostics
  - Multiple network-path diagnostics for hard-to-reach feeds
  - Better user-facing error messages in refresh flow
- Reading experience
  - Sidebar with collapsible `Feed -> Articles` tree
  - Article detail supports rendered HTML (images, links, layout) via WebKit
  - Read/unread toggle
  - Star/unstar toggle
  - Starred filter entry to view only starred articles
  - “All Articles” and filtered navigation states
- Data model
  - SwiftData models: `Feed`, `Article`
  - Cascade delete from feed to its cached articles

## Platform Notes

- Designed to run on macOS and iOS from one codebase.
- iOS deployment target is set to 17.0 for broader device compatibility.
- macOS sandbox network client entitlement is enabled for outbound feed requests.

## Build

From project root:

```bash
xcodebuild -project RZZ.xcodeproj -scheme RZZ -destination 'platform=macOS' build
xcodebuild -project RZZ.xcodeproj -scheme RZZ -destination 'generic/platform=iOS' build
```

## Project Structure

- `RZZ/ContentView.swift`: main UI, feed/article interactions, filtering, forms
- `RZZ/Models.swift`: SwiftData models and proxy-related types
- `RZZ/RSSService.swift`: network fetch + RSS parse + diagnostics
- `RZZ/WebKitRSSFallback.swift`: WebKit-based fallback path for problematic feed loading cases
- `RZZApp.swift`: app entry

