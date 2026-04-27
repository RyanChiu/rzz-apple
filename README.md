# rzz-apple

RZZ is a lightweight RSS reader for Apple platforms (macOS + iPhone), designed for custom feed URLs, structured feed management, and smooth reading.

## Highlights

- One codebase for macOS and iOS.
- Add any valid RSS URL and cache articles locally.
- Feed organization with folders (default `New Added` + custom folders).
- Per-feed proxy control with two independent switches:
  - Feed URL access can use direct/proxy.
  - Article content access can use direct/proxy.
- Full article reading with rendered HTML (text, images, links, layout).
- Reading workflow tools: read/unread, star, tag, filters, restore last session.
- Optional app lock (PIN) when re-entering app.

## Core Features

### Feed and Folder Management

- Add, edit, refresh, and delete feeds.
- Duplicate feed URL prevention.
- Delete confirmation for feeds.
- Folder support:
  - Default folder: `New Added`.
  - Create custom folders.
  - Rename/delete custom folders from folder context menu.
  - Deleting a folder moves its feeds back to `New Added`.

### Network and Proxy

- Proxy types: `HTTP(S)` and `SOCKS5`.
- Shared proxy profile per feed (`host`, `port`, optional auth).
- Independent toggles:
  - `Use Proxy for Feed URL Access`
  - `Use Proxy for Content Access`
- Friendly network error diagnostics (including DNS/host failures).

### Reading Experience

- Three-pane layout:
  - Feeds/folders scope
  - Article list
  - Article detail
- Article detail uses WebKit HTML rendering for browser-like result.
- Actions per article:
  - Mark read/unread
  - Star/unstar
  - Open original link in browser
  - Assign/remove tags
- Lightweight loading feedback and skeleton transition in detail pane.

### Filtering and Organization

- Feed scope:
  - `All`
  - One feed
  - Multiple feeds
- Article filter:
  - `All`
  - `Starred`
- Tag filter:
  - `Any Tag` or one selected tag
  - Tag icon integrated beside `All/Starred`
  - `Manage Tags…` inside tag menu
- Tag management:
  - Create, rename, delete tags
  - Max 5 tags

### Session Restore

On relaunch, RZZ restores previous state as much as possible:

- Selected feed scope (`All` / selected feeds)
- Selected article filter (`All` / `Starred`)
- Selected article
- Article reading scroll progress

### Security

- Optional app lock with 4-6 character PIN.
- Lock triggers when app resigns active and user returns.

## Quick Start

1. Build and run the app.
2. Click `+` and add your first feed URL.
3. Optionally choose folder and proxy settings per feed.
4. Click refresh to fetch latest articles.
5. Select an article to read rendered content.
6. Use star/tag/filter to organize reading.

## Build

From repository root:

```bash
xcodebuild -project RZZ.xcodeproj -scheme RZZ -destination 'platform=macOS' build
xcodebuild -project RZZ.xcodeproj -scheme RZZ -destination 'generic/platform=iOS' build
```

## Release Channels

Recommended release split:

- `release/direct`: DMG trial distribution (can include external donate link in website/app channel).
- `release/appstore`: App Store submission build (no external payment link in app binary).

For static DMG landing page files, see `site/`.
The site supports EN/中文 switch and reads deployment links from `site/config.js`.

## DMG Release Automation

This repo includes a GitHub Actions workflow:

- `.github/workflows/release-dmg.yml`
- `scripts/build_dmg.sh`

How to publish a DMG release:

1. Push a tag like `v1.0.1`.
2. GitHub Actions builds an unsigned macOS Release app and packages `dist/RZZ-<version>-macOS.dmg`.
3. Workflow also creates a latest alias: `dist/RZZ-latest-macOS.dmg`.
4. Workflow generates SHA256 files for both DMGs (`*.dmg.sha256`).
5. All files are attached to the GitHub Release asset for that tag.

Example:

```bash
git tag v1.0.1
git push origin v1.0.1
```

Important:

- If the repository is private, release asset links require GitHub authentication.
- To provide a public download link via GitHub Releases, the repository must be public.
- This DMG flow is currently unsigned/not notarized. For production distribution, use Apple Developer ID signing + notarization.

## Security Reporting

Please report vulnerabilities responsibly via [SECURITY.md](SECURITY.md).

## Project Structure

- `RZZ/ContentView.swift`: main UI, feed/folder/article interactions, filters, dialogs
- `RZZ/Models.swift`: SwiftData models (`Feed`, `Article`, `Tag`) and proxy types
- `RZZ/RSSService.swift`: networking, RSS parsing, diagnostics
- `RZZ/WebKitRSSFallback.swift`: fallback loading path for problematic feeds
- `RZZ/RZZApp.swift`: app entry and model container setup

## Current Scope

This repository currently targets a practical V1/V1+ workflow for personal RSS reading and management on Apple devices, with emphasis on reliability, proxy flexibility, and efficient daily reading.
