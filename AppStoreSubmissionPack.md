# RZZ App Store Submission Pack

Updated: 2026-03-10

## 1) Release Readiness Checklist

### A. Build / Version
- [ ] Confirm `MARKETING_VERSION` for this release (current: `1.0`).
- [ ] Confirm `CURRENT_PROJECT_VERSION` build number bump (current: `1`).
- [x] Bundle ID is stable: `sivaz.RZZ`.
- [x] Export compliance is set: `ITSAppUsesNonExemptEncryption = NO`.
- [x] ATS baseline is tightened:
  - `NSAllowsArbitraryLoads = NO`
  - `NSAllowsArbitraryLoadsForMedia = NO`
  - `NSAllowsArbitraryLoadsInWebContent = YES` (for reader WebView only)

### B. Security / Privacy
- [x] App lock PIN uses PBKDF2 + salt + iterations.
- [x] PIN hash stored in Keychain-backed storage.
- [x] Proxy passwords stored in Keychain.
- [x] Non-HTTP(S) WebView navigations are blocked.
- [x] External links open in system browser.
- [x] Backup import validation is enabled (size/count/schema/field limits).
- [x] Persistent-store fallback warning is shown if app starts in memory-only mode.

### C. Functionality Smoke Test (Manual)
- [ ] Add feed, refresh, read article detail.
- [ ] Test per-feed proxy toggles:
  - feed access direct/proxy
  - content access direct/proxy
- [ ] Test starred + tag filter paths.
- [ ] Test offline modes (`off` / `metadata` / `full content`) and retry offline.
- [ ] Test lock/unlock flow after app background/foreground.
- [ ] Test export/import backup and verify restore.
- [ ] Test auto-refresh status display and details panel.

### D. App Store Connect Assets
- [ ] App icon (final production icon) uploaded.
- [ ] iPhone screenshots uploaded.
- [ ] macOS screenshots uploaded.
- [ ] App description / keywords / subtitle finalized.
- [ ] Support URL filled.
- [ ] Privacy Policy URL filled.

### E. Notes for Current Local CLI Environment
- Release CLI build checks can be affected by local simulator service instability.
- Final release/archive validation should be done in Xcode GUI on host machine before submission.

---

## 2) App Store Metadata Draft (EN / 中文)

### App Name
- EN: `RZZ`
- 中文: `RZZ`

### Subtitle (<= 30 chars)
- EN: `RSS Reader with Proxy Control`
- 中文: `可控代理的 RSS 阅读器`

### Promotional Text (optional)
- EN: `Read your custom RSS feeds on Mac and iPhone with per-feed proxy, offline cache, and app lock.`
- 中文: `在 Mac 和 iPhone 上阅读自定义 RSS，支持逐源代理、离线缓存与应用锁。`

### Keywords (comma-separated)
- EN: `rss,reader,feed,news,offline,proxy,star,tag`
- 中文: `RSS,阅读器,订阅,资讯,离线,代理,收藏,标签`

### Description (EN)
RZZ is a focused RSS reader for Apple platforms.  
Add your own feed URLs, organize feeds with folders, and read article content in a clean WebView reader.

Key features:
- Custom feed URL subscription and management
- Per-feed network controls (feed access proxy + content access proxy)
- Optional offline caching modes
- Star and tag based filtering
- Session restore across launches
- Optional app lock with PIN
- Backup export/import for local data migration

RZZ is designed for users who need reliable RSS reading with practical network controls and lightweight daily workflow.

### 描述（中文）
RZZ 是一款专注于 Apple 平台的 RSS 阅读器。  
你可以添加自定义订阅源 URL、按文件夹管理源，并在清爽的 WebView 阅读界面中浏览文章内容。

核心能力：
- 自定义 RSS 源添加与管理
- 按源配置网络访问（源访问代理 + 内容访问代理）
- 可选离线缓存模式
- 收藏（Star）与标签（Tag）筛选
- 重启后恢复阅读状态
- 可选 PIN 码应用锁
- 本地数据导出/导入备份

RZZ 面向对 RSS 可靠性、网络可控性和日常阅读效率有要求的用户。

### What’s New (v1.0 draft)
- EN:
  - Added per-feed proxy controls for both feed access and article content access.
  - Added offline caching modes and retry actions.
  - Added app lock with secure PIN storage.
  - Added backup export/import and refresh status details.
- 中文：
  - 新增按源代理控制：源访问与内容访问可独立配置。
  - 新增离线缓存模式与失败重试。
  - 新增应用锁与安全 PIN 存储。
  - 新增备份导出/导入与刷新详情查看。

### Review Contact Placeholders
- Contact Email: `<FILL_REVIEW_CONTACT_EMAIL>`
- Support URL: `<FILL_SUPPORT_URL>`
- Privacy Policy URL: `<FILL_PRIVACY_POLICY_URL>`

