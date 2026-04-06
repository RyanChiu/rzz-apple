(function () {
  const FALLBACK_CONFIG = {
    dmgUrl: "#",
    releasesUrl: "#",
    donateUrl: "#",
    feedbackEmail: "feedback@example.com",
    issuesUrl: "#",
    defaultLanguage: "en"
  };

  const cfg = Object.assign({}, FALLBACK_CONFIG, window.RZZ_SITE_CONFIG || {});

  const i18n = {
    en: {
      page_title: "RZZ - Lightweight RSS Reader for macOS & iPhone",
      page_desc: "RZZ is a lightweight RSS reader for macOS and iPhone with app lock, import/export backup, proxy controls, and smooth reading.",
      badge: "RZZ Preview • DMG Trial",
      subtitle_html: "A lightweight RSS reader for macOS + iPhone.<br />Custom feeds, per-feed proxy strategy, offline cache, and smooth reading.",
      cta_download: "Download DMG Trial",
      cta_releases: "Release Notes",
      cta_donate: "PayPal Donate",
      hero_meta_html: "Distribution channel: GitHub Release + DMG.<br />Donation is optional and does not affect feature access.",
      highlights_title: "Highlights First",
      highlight_lock_title: "App Lock (PIN)",
      highlight_lock_desc: "Require a 4-6 character PIN when returning to the app, protecting your reading workspace in shared environments.",
      highlight_backup_title: "Import / Export Backup",
      highlight_backup_desc: "Export and import feed settings, tags, and cache metadata for migration or rollback with minimal setup friction.",
      highlight_proxy_title: "Per-Feed Proxy Controls",
      highlight_proxy_desc: "Feed fetching and content loading can independently choose direct/proxy modes with shared proxy profiles.",
      core_title: "Core Features",
      core_1: "Three-pane workflow (Feeds / Articles / Reader) with collapsible sidebars.",
      core_2: "Rendered HTML reading (text, images, links, layout).",
      core_3: "Offline cache queue with retry and storage usage visibility.",
      core_4: "Read/unread, star, tags, and scope-aware filtering.",
      core_5: "Session restore for feed selection, article selection, and scroll progress.",
      core_6: "Background refresh with status summary.",
      quickstart_title: "Quick Start",
      step_1: "Download DMG and drag RZZ into Applications.",
      step_2_html: "Launch RZZ and click <code>+</code> to add your first feed URL.",
      step_3: "Optionally configure proxy strategy per feed for feed URL access and content access separately.",
      step_4: "Read articles in rendered mode, then star/tag/filter for your workflow.",
      step_5: "Use import/export backup for migration or device change.",
      channels_title: "Distribution Channels",
      table_h_channel: "Channel",
      table_h_dist: "Distribution",
      table_h_donation: "Donation",
      table_h_positioning: "Positioning",
      table_row1_c1: "DMG Trial",
      table_row1_c2: "GitHub Release",
      table_row1_c3: "External PayPal (optional)",
      table_row1_c4: "Fast trial + feedback loop",
      table_row2_c1: "App Store",
      table_row2_c2: "App Store review/release",
      table_row2_c3: "No external payment link in app binary",
      table_row2_c4: "Compliance-oriented stable release",
      feedback_title: "Feedback & Contact",
      feedback_email_label: "Questions or suggestions: ",
      feedback_issue_label: "Issue tracker: ",
      footer_disclaimer: "Disclaimer: DMG trial is intended for evaluation and feedback. Please assess your own network/data risk."
    },
    zh: {
      page_title: "RZZ - 面向 macOS 与 iPhone 的轻量 RSS 阅读器",
      page_desc: "RZZ 是轻量 RSS 阅读器，支持 App Lock、导入导出备份、代理控制和流畅阅读。",
      badge: "RZZ 预览版 • DMG 试用",
      subtitle_html: "面向 macOS + iPhone 的轻量 RSS 阅读器。<br />自定义源、按源代理策略、离线缓存、流畅阅读。",
      cta_download: "下载 DMG 试用版",
      cta_releases: "更新日志",
      cta_donate: "PayPal 赞助",
      hero_meta_html: "分发渠道：GitHub Release + DMG。<br />Donate 为自愿支持，不影响功能使用。",
      highlights_title: "优先亮点",
      highlight_lock_title: "App Lock（PIN）",
      highlight_lock_desc: "返回应用时可要求 4-6 位 PIN，保护你的阅读工作区，避免设备共用时被直接访问。",
      highlight_backup_title: "导入 / 导出备份",
      highlight_backup_desc: "可备份并恢复源配置、标签与缓存元信息，迁移设备或回滚配置时更高效。",
      highlight_proxy_title: "按源代理控制",
      highlight_proxy_desc: "Feed 拉取与正文加载可分别选择直连/代理，并支持复用共享代理配置。",
      core_title: "核心特性",
      core_1: "三栏流程（Feeds / Articles / Reader），支持侧栏折叠。",
      core_2: "HTML 渲染阅读（文本、图片、链接、排版）。",
      core_3: "离线缓存队列，支持失败重试与容量查看。",
      core_4: "Read/unread、星标、标签与范围联动筛选。",
      core_5: "恢复会话状态：源选择、文章选择、滚动位置。",
      core_6: "后台自动刷新并显示状态摘要。",
      quickstart_title: "快速上手",
      step_1: "下载 DMG，并将 RZZ 拖入 Applications。",
      step_2_html: "启动后点击 <code>+</code> 添加第一个 Feed URL。",
      step_3: "按需配置代理策略：Feed URL 访问与正文访问可分别设置。",
      step_4: "在渲染模式阅读文章，并用星标/标签/过滤器组织内容。",
      step_5: "设备迁移或重装时使用导入/导出备份。",
      channels_title: "发布渠道",
      table_h_channel: "渠道",
      table_h_dist: "分发方式",
      table_h_donation: "Donation",
      table_h_positioning: "定位",
      table_row1_c1: "DMG 试用版",
      table_row1_c2: "GitHub Release",
      table_row1_c3: "外部 PayPal（可选）",
      table_row1_c4: "快速试用 + 反馈迭代",
      table_row2_c1: "App Store 版",
      table_row2_c2: "App Store 审核发布",
      table_row2_c3: "应用内不含外部支付入口",
      table_row2_c4: "合规优先的稳定分发",
      feedback_title: "反馈与联系",
      feedback_email_label: "问题与建议：",
      feedback_issue_label: "Issue 跟踪：",
      footer_disclaimer: "免责声明：DMG 试用版用于评估与反馈，请自行评估网络与数据风险。"
    }
  };

  function applyLinks() {
    const download = document.getElementById("link-download");
    const releases = document.getElementById("link-releases");
    const donate = document.getElementById("link-donate");
    const feedbackEmail = document.getElementById("link-feedback-email");
    const issues = document.getElementById("link-issues");

    download.href = cfg.dmgUrl;
    releases.href = cfg.releasesUrl;
    donate.href = cfg.donateUrl;
    feedbackEmail.href = "mailto:" + cfg.feedbackEmail;
    feedbackEmail.textContent = cfg.feedbackEmail;
    issues.href = cfg.issuesUrl;
    issues.textContent = cfg.issuesUrl;
  }

  function setLanguage(lang) {
    const dict = i18n[lang] || i18n.en;
    document.documentElement.lang = lang;

    document.title = dict.page_title;
    const metaDescription = document.querySelector('meta[name="description"]');
    if (metaDescription) metaDescription.setAttribute("content", dict.page_desc);

    document.querySelectorAll("[data-i18n]").forEach(function (node) {
      const key = node.getAttribute("data-i18n");
      if (dict[key] != null) node.textContent = dict[key];
    });
    document.querySelectorAll("[data-i18n-html]").forEach(function (node) {
      const key = node.getAttribute("data-i18n-html");
      if (dict[key] != null) node.innerHTML = dict[key];
    });

    const enBtn = document.getElementById("lang-en");
    const zhBtn = document.getElementById("lang-zh");
    enBtn.classList.toggle("active", lang === "en");
    zhBtn.classList.toggle("active", lang === "zh");

    localStorage.setItem("rzz_site_lang", lang);
  }

  function boot() {
    applyLinks();
    document.getElementById("year").textContent = String(new Date().getFullYear());

    const preferred =
      localStorage.getItem("rzz_site_lang") ||
      cfg.defaultLanguage ||
      "en";
    const initial = preferred === "zh" ? "zh" : "en";
    setLanguage(initial);

    document.getElementById("lang-en").addEventListener("click", function () {
      setLanguage("en");
    });
    document.getElementById("lang-zh").addEventListener("click", function () {
      setLanguage("zh");
    });
  }

  boot();
})();
