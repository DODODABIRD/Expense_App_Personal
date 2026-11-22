(function () {
  "use strict";

  var list = document.getElementById("downloadsList");
  var yearEl = document.getElementById("downloadsYear");

  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  function formatBytes(bytes) {
    var value = Number(bytes);
    if (!Number.isFinite(value) || value <= 0) return "";
    if (value < 1024) return value + " B";
    if (value < 1024 * 1024) return (value / 1024).toFixed(1) + " KB";
    return (value / (1024 * 1024)).toFixed(1) + " MB";
  }

  function formatDate(value) {
    if (!value) return "";
    var date = new Date(String(value).slice(0, 10) + "T00:00:00");
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  }

  function safeUrl(value) {
    var url = String(value || "").trim();
    return /^(https?:\/\/|\/(?!\/))/i.test(url) ? url : "";
  }

  function requestedSlug() {
    var parts = window.location.pathname.split("/").filter(Boolean);
    if (parts[0] !== "downloads" || !parts[1]) return "";
    try {
      return decodeURIComponent(parts[1]);
    } catch (error) {
      return "";
    }
  }

  function metaLine(release) {
    return [formatBytes(release.size_bytes), formatDate(release.released_at)]
      .filter(Boolean)
      .join(" · ");
  }

  function createIcon(app) {
    var icon = document.createElement("img");
    icon.className = "download-icon";
    icon.src = safeUrl(app.icon_url) || "/asset/orlando-brand-logo.png";
    icon.alt = app.name + " icon";
    icon.loading = "lazy";
    icon.decoding = "async";
    icon.addEventListener("error", function () {
      icon.src = "/asset/orlando-brand-logo.png";
    });
    return icon;
  }

  function createLatestBox(app) {
    var box = document.createElement("div");
    box.className = "download-latest-box";

    var meta = document.createElement("div");
    meta.className = "download-latest-meta";

    if (!app.latest) {
      var empty = document.createElement("strong");
      empty.textContent = "No releases yet";
      meta.appendChild(empty);
      var note = document.createElement("span");
      note.textContent = "Check back soon for the first Android build.";
      meta.appendChild(note);
      box.appendChild(meta);
      return box;
    }

    var version = document.createElement("strong");
    version.textContent = "v" + app.latest.version;
    meta.appendChild(version);

    var details = document.createElement("span");
    details.textContent = metaLine(app.latest);
    meta.appendChild(details);

    if (app.latest.notes) {
      var notes = document.createElement("small");
      notes.textContent = app.latest.notes;
      meta.appendChild(notes);
    }

    box.appendChild(meta);

    var url = safeUrl(app.latest.url);
    if (url) {
      var download = document.createElement("a");
      download.className = "button button-yellow download-cta";
      download.href = url;
      download.setAttribute("download", app.slug + "-v" + app.latest.version + ".apk");
      download.textContent = "Download APK ↓";
      box.appendChild(download);
    }

    return box;
  }

  function createHistory(app) {
    var details = document.createElement("details");
    details.className = "release-history";

    var summary = document.createElement("summary");
    summary.textContent = "Release history (" + app.releases.length + ")";
    details.appendChild(summary);

    var releaseList = document.createElement("ul");
    releaseList.className = "release-list";

    app.releases.forEach(function (release) {
      var row = document.createElement("li");
      row.className = "release-row";

      var main = document.createElement("div");
      main.className = "release-row-main";

      var version = document.createElement("span");
      version.className = "release-version";
      version.textContent = "v" + release.version;
      main.appendChild(version);

      if (app.latest && app.latest.id === release.id) {
        var latestTag = document.createElement("span");
        latestTag.className = "badge-mini yellow";
        latestTag.textContent = "LATEST";
        main.appendChild(latestTag);
      }

      var meta = document.createElement("span");
      meta.className = "release-meta";
      meta.textContent = metaLine(release) || "No date";
      main.appendChild(meta);

      row.appendChild(main);

      var url = safeUrl(release.url);
      if (url) {
        var link = document.createElement("a");
        link.className = "release-link";
        link.href = url;
        link.setAttribute("download", app.slug + "-v" + release.version + ".apk");
        link.textContent = "Download ↓";
        row.appendChild(link);
      }

      releaseList.appendChild(row);
    });

    details.appendChild(releaseList);
    return details;
  }

  function createCard(app, slug) {
    var card = document.createElement("article");
    card.className = "download-card neo-card";
    card.id = "app-" + app.slug;

    var top = document.createElement("div");
    top.className = "download-card-top";

    var identity = document.createElement("div");
    identity.className = "download-identity";
    identity.appendChild(createIcon(app));

    var text = document.createElement("div");

    var eyebrow = document.createElement("span");
    eyebrow.className = "download-eyebrow";
    eyebrow.textContent = "ANDROID APP";
    text.appendChild(eyebrow);

    var name = document.createElement("h2");
    name.textContent = app.name;
    text.appendChild(name);

    if (app.tagline) {
      var tagline = document.createElement("p");
      tagline.className = "download-tagline";
      tagline.textContent = app.tagline;
      text.appendChild(tagline);
    }

    if (app.description) {
      var description = document.createElement("p");
      description.className = "download-tagline";
      description.textContent = app.description;
      text.appendChild(description);
    }

    identity.appendChild(text);
    top.appendChild(identity);

    if (app.latest) {
      var badge = document.createElement("span");
      badge.className = "badge-mini aqua";
      badge.textContent = "v" + app.latest.version;
      top.appendChild(badge);
    }

    card.appendChild(top);
    card.appendChild(createLatestBox(app));

    if (app.releases.length > 0) {
      card.appendChild(createHistory(app));
    }

    var actions = document.createElement("div");
    actions.className = "download-card-actions";

    var permalink = document.createElement("a");
    permalink.className = "download-permalink";
    if (slug) {
      permalink.href = "/downloads";
      permalink.textContent = "← All downloads";
    } else {
      permalink.href = "/downloads/" + encodeURIComponent(app.slug);
      permalink.textContent = "Open app page ↗";
    }
    actions.appendChild(permalink);

    if (app.slug === "unmurce") {
      var extraLinks = document.createElement("div");
      extraLinks.className = "download-card-extra-links";

      var showcaseLink = document.createElement("a");
      showcaseLink.className = "download-permalink";
      showcaseLink.href = "/projects/unmurce";
      showcaseLink.textContent = "Project Showcase ↗";
      extraLinks.appendChild(showcaseLink);

      var docsLink = document.createElement("a");
      docsLink.className = "download-permalink";
      docsLink.href = "/projects/docs";
      docsLink.textContent = "Tech Docs ↗";
      extraLinks.appendChild(docsLink);

      actions.appendChild(extraLinks);
    }

    card.appendChild(actions);
    return card;
  }

  function showMessage(message) {
    list.innerHTML = "";
    var box = document.createElement("p");
    box.className = "downloads-empty";
    box.textContent = message;
    list.appendChild(box);
  }

  async function load() {
    var slug = requestedSlug();

    var response;
    try {
      response = await fetch("/api/downloads", { cache: "no-store" });
    } catch (error) {
      showMessage("Could not load downloads. Check your connection and try again.");
      return;
    }

    if (!response.ok) {
      showMessage("Could not load downloads right now. Please try again later.");
      return;
    }

    var payload = await response.json().catch(function () {
      return null;
    });
    var apps = payload && Array.isArray(payload.apps) ? payload.apps : [];

    if (slug) {
      apps = apps.filter(function (app) {
        return app.slug === slug;
      });
      if (apps.length === 0) {
        showMessage("That app was not found. Browse all downloads instead.");
        return;
      }
      document.title = apps[0].name + " Download | Orlando Diamond Prasetyo";
    }

    if (apps.length === 0) {
      showMessage("No apps have been published yet.");
      return;
    }

    list.innerHTML = "";
    apps.forEach(function (app) {
      list.appendChild(createCard(app, slug));
    });
  }

  function initShell() {
    var headerWrapper = document.getElementById("site-header-wrapper");
    function handleScroll() {
      if (!headerWrapper) return;
      if (window.scrollY <= 20) {
        headerWrapper.classList.add("is-top");
      } else {
        headerWrapper.classList.remove("is-top");
      }
      headerWrapper.classList.remove("nav-hidden");
    }
    window.addEventListener("scroll", handleScroll, { passive: true });
    handleScroll();

    function toggleTheme() {
      var isDark = document.documentElement.getAttribute("data-theme") === "dark";
      var next = isDark ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      try {
        localStorage.setItem("theme", next);
      } catch (e) {}
    }

    var themeBtn = document.getElementById("theme-toggle-btn");
    var drawerThemeBtn = document.getElementById("drawer-theme-toggle-btn");
    if (themeBtn) themeBtn.addEventListener("click", toggleTheme);
    if (drawerThemeBtn) drawerThemeBtn.addEventListener("click", toggleTheme);

    var menuToggle = document.getElementById("mobile-menu-toggle");
    var closeDrawerBtn = document.getElementById("close-mobile-drawer");
    var mobileDrawer = document.getElementById("mobile-drawer");
    var drawerLinks = document.querySelectorAll(".mobile-drawer-link");

    function openDrawer() {
      if (!mobileDrawer) return;
      mobileDrawer.classList.add("active");
      mobileDrawer.setAttribute("aria-hidden", "false");
      if (menuToggle) menuToggle.setAttribute("aria-expanded", "true");
      document.body.style.overflow = "hidden";
    }

    function closeDrawer() {
      if (!mobileDrawer) return;
      mobileDrawer.classList.remove("active");
      mobileDrawer.setAttribute("aria-hidden", "true");
      if (menuToggle) menuToggle.setAttribute("aria-expanded", "false");
      document.body.style.overflow = "";
    }

    if (menuToggle) {
      menuToggle.addEventListener("click", function () {
        if (mobileDrawer && mobileDrawer.classList.contains("active")) {
          closeDrawer();
        } else {
          openDrawer();
        }
      });
    }
    if (closeDrawerBtn) closeDrawerBtn.addEventListener("click", closeDrawer);
    if (mobileDrawer) {
      mobileDrawer.addEventListener("click", function (event) {
        if (event.target === mobileDrawer) closeDrawer();
      });
    }
    drawerLinks.forEach(function (link) {
      link.addEventListener("click", closeDrawer);
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && mobileDrawer && mobileDrawer.classList.contains("active")) {
        closeDrawer();
      }
    });
  }

  initShell();
  load();
})();
