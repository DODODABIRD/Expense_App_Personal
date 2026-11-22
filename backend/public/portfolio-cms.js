(function () {
  "use strict";

  function getPath(source, path) {
    return String(path || "")
      .split(".")
      .reduce(function (value, key) {
        return value && value[key] !== undefined ? value[key] : undefined;
      }, source);
  }

  function formatBytes(bytes) {
    var value = Number(bytes);
    if (!Number.isFinite(value) || value <= 0) return "";
    if (value < 1024) return value + " B";
    if (value < 1024 * 1024) return (value / 1024).toFixed(1) + " KB";
    return (value / (1024 * 1024)).toFixed(1) + " MB";
  }

  function formatDate(value) {
    if (!value) return "";
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  }

  function applyProfile(content) {
    document.querySelectorAll("[data-cms]").forEach(function (element) {
      var value = getPath(content, element.dataset.cms);
      if (value === undefined || value === null) return;
      element.textContent = String(value);
    });

    document.querySelectorAll("[data-cms-href]").forEach(function (element) {
      var value = getPath(content, element.dataset.cmsHref);
      if (typeof value === "string" && value.trim()) {
        element.setAttribute("href", value);
      }
    });
  }

  function applyApk(apk) {
    apk = apk || {};

    document.querySelectorAll("[data-apk-version]").forEach(function (element) {
      var version = String(apk.version || "").trim();
      element.textContent = version ? (/^v/i.test(version) ? version : "v" + version) : "";
    });
    document.querySelectorAll("[data-apk-size]").forEach(function (element) {
      element.textContent = formatBytes(apk.size_bytes);
    });
    document.querySelectorAll("[data-apk-date]").forEach(function (element) {
      element.textContent = formatDate(apk.released_at);
    });
    document.querySelectorAll("[data-apk-notes]").forEach(function (element) {
      element.textContent = apk.notes || "";
    });
    document.querySelectorAll("[data-apk-link]").forEach(function (element) {
      if (apk.url) {
        element.setAttribute("href", apk.url);
        element.setAttribute("download", "Unmurce-Android.apk");
      }
    });
  }

  function renderProjects(projects) {
    var grid = document.getElementById("cms-project-grid");
    var heading = document.getElementById("cms-projects-heading");
    if (!grid) return;

    var items = Array.isArray(projects)
      ? projects.filter(function (project) {
          return project && project.name && project.hidden !== true;
        })
      : [];

    grid.innerHTML = "";
    if (heading) heading.hidden = items.length === 0;
    grid.hidden = items.length === 0;
    if (items.length === 0) return;

    items.forEach(function (project, index) {
      var card = document.createElement("div");
      card.className = "project-card neo-card";

      var visual = document.createElement("div");
      visual.className = "project-visual placeholder-visual tech-stack-visual";

      var visualTag = document.createElement("span");
      visualTag.className = "visual-tag";
      visualTag.textContent = project.status || "PROJECT";
      visual.appendChild(visualTag);

      var header = document.createElement("div");
      header.className = "tech-stack-header";

      var badge = document.createElement("div");
      badge.className = "badge-tag";
      badge.textContent = "PROJECT " + String(index + 1).padStart(2, "0");
      header.appendChild(badge);

      var title = document.createElement("h3");
      title.textContent = project.name;
      header.appendChild(title);

      var description = document.createElement("p");
      description.className = "preview-text";
      description.textContent = project.description || "";
      header.appendChild(description);

      visual.appendChild(header);

      if (Array.isArray(project.tags) && project.tags.length > 0) {
        var tagGrid = document.createElement("div");
        tagGrid.className = "tech-stack-grid";
        project.tags.slice(0, 6).forEach(function (tag) {
          var chip = document.createElement("span");
          chip.className = "tech-chip chip-aqua";
          chip.textContent = tag;
          tagGrid.appendChild(chip);
        });
        visual.appendChild(tagGrid);
      }

      var info = document.createElement("div");
      info.className = "project-info";

      var infoText = document.createElement("div");
      var number = document.createElement("p");
      number.className = "project-number";
      number.textContent = String(index + 1).padStart(2, "0");
      infoText.appendChild(number);

      var infoTitle = document.createElement("h3");
      infoTitle.textContent = project.name;
      infoText.appendChild(infoTitle);

      var infoDescription = document.createElement("p");
      infoDescription.textContent = project.description || "";
      infoText.appendChild(infoDescription);

      var actions = document.createElement("div");
      actions.className = "project-card-actions";

      if (project.url) {
        var liveLink = document.createElement("a");
        liveLink.className = "button button-aqua";
        liveLink.href = project.url;
        liveLink.target = "_blank";
        liveLink.rel = "noreferrer";
        liveLink.textContent = "Open project ↗";
        actions.appendChild(liveLink);
      }
      if (project.repo) {
        var repoLink = document.createElement("a");
        repoLink.className = "button button-white";
        repoLink.href = project.repo;
        repoLink.target = "_blank";
        repoLink.rel = "noreferrer";
        repoLink.textContent = "Source ↗";
        actions.appendChild(repoLink);
      }
      if (actions.children.length > 0) infoText.appendChild(actions);

      info.appendChild(infoText);

      var arrow = document.createElement("span");
      arrow.className = "project-arrow";
      arrow.setAttribute("aria-hidden", "true");
      arrow.textContent = "↗";
      info.appendChild(arrow);

      card.appendChild(visual);
      card.appendChild(info);
      grid.appendChild(card);
    });
  }

  function renderTimeline(experience) {
    var container = document.getElementById("cms-timeline");
    if (!container || !Array.isArray(experience) || experience.length === 0) {
      return;
    }

    container.innerHTML = "";

    experience.forEach(function (item) {
      var wrapper = document.createElement("div");
      wrapper.className = "timeline-item";

      var badgeWrapper = document.createElement("div");
      badgeWrapper.className = "timeline-badge-wrapper";
      var yearBadge = document.createElement("div");
      yearBadge.className = "timeline-year-badge neo-card";
      yearBadge.textContent = item.year || "";
      badgeWrapper.appendChild(yearBadge);
      wrapper.appendChild(badgeWrapper);

      var card = document.createElement("div");
      card.className = "timeline-card neo-card";
      if (item.accent === "aqua") card.classList.add("neo-card-aqua");
      if (item.accent === "yellow") card.classList.add("neo-card-yellow");

      var header = document.createElement("div");
      header.className = "timeline-card-header";
      var period = document.createElement("span");
      period.className = "timeline-tag";
      period.textContent = item.period || "";
      header.appendChild(period);
      var role = document.createElement("span");
      role.className = "timeline-role";
      role.textContent = item.role || "";
      header.appendChild(role);
      card.appendChild(header);

      var title = document.createElement("h3");
      title.textContent = item.title || "";
      card.appendChild(title);

      var description = document.createElement("p");
      description.textContent = item.description || "";
      card.appendChild(description);

      if (Array.isArray(item.tags) && item.tags.length > 0) {
        var tags = document.createElement("div");
        tags.className = "timeline-tech-tags";
        item.tags.forEach(function (tag) {
          var span = document.createElement("span");
          span.textContent = tag;
          tags.appendChild(span);
        });
        card.appendChild(tags);
      }

      wrapper.appendChild(card);
      container.appendChild(wrapper);
    });
  }

  async function hydrate() {
    var response;
    try {
      response = await fetch("/api/portfolio", { cache: "no-store" });
      if (!response.ok) return;
    } catch (error) {
      return;
    }

    var payload = await response.json().catch(function () {
      return null;
    });
    var content = payload && payload.content;
    if (!content) return;

    applyProfile(content);
    applyApk(content.apk);
    renderProjects(content.projects);
    renderTimeline(content.experience);

    var appSlug = (document.body && document.body.dataset.downloadApp) || "unmurce";
    try {
      var downloadResponse = await fetch(
        "/api/downloads/" + encodeURIComponent(appSlug),
        { cache: "no-store" }
      );
      if (!downloadResponse.ok) return;
      var downloadPayload = await downloadResponse.json();
      var latest = downloadPayload && downloadPayload.app && downloadPayload.app.latest;
      if (latest) applyApk(latest);
    } catch (error) {
      // Keep the portfolio APK fallback when the downloads endpoint is unavailable.
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydrate);
  } else {
    hydrate();
  }
})();
