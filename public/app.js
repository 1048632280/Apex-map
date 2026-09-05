let activeSchedule = null;
let reloadTimer = null;
let retryTimer = null;
let requestInFlight = false;
let mapCatalog = new Map();

const scheduleEndpoint = "./api/schedule";
const mapCatalogUrl = "./image/maps.json";
const ringRadius = 50;
const ringCircumference = 2 * Math.PI * ringRadius;

const elements = {
  countdown: document.querySelector("#countdown"),
  currentTitle: document.querySelector("#current-title"),
  currentSubtitle: document.querySelector("#current-subtitle"),
  nextTitle: document.querySelector("#next-title"),
  nextSubtitle: document.querySelector("#next-subtitle"),
  nextStart: document.querySelector("#next-start"),
  progressRing: document.querySelector("#progress-ring-value"),
  progressPercent: document.querySelector("#progress-percent"),
  statusLabel: document.querySelector("#status-label"),
  statusPill: document.querySelector("#status-pill"),
  timeline: document.querySelector("#timeline"),
  currentMapArt: document.querySelector("#current-map-art"),
  currentMapImage: document.querySelector("#current-map-image"),
  nextMapThumb: document.querySelector("#next-map-thumb"),
  nextMapImage: document.querySelector("#next-map-image")
};

function pad(value) {
  return String(value).padStart(2, "0");
}

function formatClock(timestamp, options = {}) {
  if (!Number.isFinite(timestamp)) {
    return options.seconds ? "--:--:--" : "--:--";
  }

  const date = new Date(timestamp);
  const base = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  return options.seconds ? `${base}:${pad(date.getSeconds())}` : base;
}

function formatTimeRange(startsAt, endsAt) {
  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt)) {
    return "--";
  }

  return `${formatClock(startsAt)} - ${formatClock(endsAt)}`;
}

function formatCountdown(milliseconds) {
  if (!Number.isFinite(milliseconds)) {
    return "--:--:--";
  }

  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
}

function parseApiTime(value) {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function normalizeApiMap(map) {
  if (!map?.name || !map?.slug || !map?.starts_at || !map?.ends_at) {
    throw new Error("排位轮换数据不完整");
  }

  const startsAt = parseApiTime(map.starts_at);
  const endsAt = parseApiTime(map.ends_at);

  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) || endsAt <= startsAt) {
    throw new Error("排位轮换时间无效");
  }

  return {
    code: map.key || map.slug,
    name: map.name,
    slug: map.slug,
    startsAt,
    endsAt,
    durationMs: endsAt - startsAt,
    current: Boolean(map.is_current),
    placeholder: false
  };
}

function normalizeTimelineMap(map) {
  if (map?.placeholder) {
    return createPlaceholderMap();
  }

  return normalizeApiMap(map);
}

function createPlaceholderMap() {
  return {
    name: "--",
    startsAt: null,
    endsAt: null,
    durationMs: null,
    current: false,
    placeholder: true
  };
}

function normalizeLookupValue(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function indexMapCatalog(maps) {
  const catalog = new Map();

  maps.forEach((map) => {
    [
      map.name,
      map.slug,
      ...(map.apexStatusCodes || []),
      ...(map.aliases || [])
    ].forEach((key) => {
      const normalized = normalizeLookupValue(key);
      if (normalized) {
        catalog.set(normalized, map);
      }
    });
  });

  return catalog;
}

async function loadMapCatalog() {
  try {
    const response = await fetch(mapCatalogUrl, { cache: "force-cache" });
    if (!response.ok) {
      throw new Error(`地图资源读取失败：${response.status}`);
    }

    const data = await response.json();
    mapCatalog = indexMapCatalog(data.maps || []);
    renderTimeline();
    render();
  } catch (error) {
    console.warn(error);
  }
}

function getMapEntry(map) {
  if (!map) {
    return null;
  }

  return (
    mapCatalog.get(normalizeLookupValue(map.slug)) ||
    mapCatalog.get(normalizeLookupValue(map.code)) ||
    mapCatalog.get(normalizeLookupValue(map.name)) ||
    null
  );
}

function getMapImage(map) {
  return getMapEntry(map)?.images?.official || "";
}

function getMapThumbnail(map) {
  return getMapEntry(map)?.images?.thumbnail || "";
}

function setMapImage(imageElement, containerElement, map, hideContainer = false) {
  const src = getMapImage(map);

  if (containerElement) {
    containerElement.classList.toggle("has-image", Boolean(src));
    if (hideContainer) {
      containerElement.hidden = !src;
    }
  }

  if (!imageElement) {
    return;
  }

  if (!src) {
    imageElement.hidden = true;
    imageElement.removeAttribute("src");
    return;
  }

  if (imageElement.getAttribute("src") !== src) {
    imageElement.decoding = "async";
    imageElement.loading = imageElement === elements.currentMapImage ? "eager" : "lazy";
    imageElement.fetchPriority = imageElement === elements.currentMapImage ? "high" : "low";
    imageElement.src = src;
  }
  imageElement.hidden = false;
}

function preloadMapImage(map) {
  const src = getMapImage(map);
  if (!src) {
    return;
  }

  const image = new Image();
  image.decoding = "async";
  image.fetchPriority = "low";
  image.src = src;
}

function createScheduleFromApi(data) {
  if (!data?.current || !data?.next || !Array.isArray(data.upcoming)) {
    throw new Error("API 未返回完整的排位轮换数据");
  }

  const current = {
    ...normalizeApiMap(data.current),
    current: true
  };
  const next = {
    ...normalizeApiMap(data.next),
    current: false
  };
  const upcoming = data.upcoming.slice(0, 3).map(normalizeTimelineMap);

  return {
    current,
    next,
    upcoming: [
      current,
      next,
      upcoming[2] ? { ...upcoming[2], current: false } : createPlaceholderMap()
    ]
  };
}

function setOfflineState(preserveSchedule = false) {
  document.body.classList.add("is-offline");
  elements.statusPill.classList.add("is-offline");
  elements.statusLabel.textContent = "OFFLINE";

  if (preserveSchedule && activeSchedule) {
    renderTimeline();
    render();
    return;
  }

  activeSchedule = null;
  elements.currentTitle.textContent = "--";
  elements.currentSubtitle.textContent = "--";
  elements.countdown.textContent = "--:--:--";
  elements.nextTitle.textContent = "--";
  elements.nextSubtitle.textContent = "--";
  elements.nextStart.textContent = "--:--";
  elements.progressRing.style.strokeDashoffset = String(ringCircumference);
  elements.progressPercent.textContent = "--";
  setMapImage(elements.currentMapImage, elements.currentMapArt, null);
  setMapImage(elements.nextMapImage, elements.nextMapThumb, null, true);
  renderTimeline();
}

function setOnlineState() {
  document.body.classList.remove("is-offline");
  elements.statusPill.classList.remove("is-offline");
  elements.statusLabel.textContent = "RANKED";
}

function clearRetryTimer() {
  window.clearTimeout(retryTimer);
  retryTimer = null;
}

function scheduleRetry(delay = 60000) {
  clearRetryTimer();
  retryTimer = window.setTimeout(loadSchedule, delay);
}

function applyServerState(serverState) {
  if (!serverState?.data) {
    setOfflineState();
    return;
  }

  activeSchedule = createScheduleFromApi(serverState.data);
  if (serverState.online) {
    setOnlineState();
  } else {
    setOfflineState(true);
  }
  renderTimeline();
  render();
  scheduleReloadAtMapEnd();
  preloadMapImage(activeSchedule.next);
}

async function loadSchedule() {
  if (requestInFlight) {
    return;
  }

  requestInFlight = true;

  try {
    const response = await fetch(scheduleEndpoint, { cache: "no-store" });
    const serverState = await response.json().catch(() => null);
    if (!response.ok && !serverState) {
      throw new Error(`服务器请求失败：${response.status}`);
    }

    applyServerState(serverState);
    if (serverState?.online) {
      clearRetryTimer();
    } else {
      scheduleRetry();
    }
  } catch (error) {
    console.warn(error);
    setOfflineState();
    scheduleRetry();
  } finally {
    requestInFlight = false;
  }
}

function scheduleReloadAtMapEnd() {
  window.clearTimeout(reloadTimer);
  if (!activeSchedule?.current?.endsAt) {
    return;
  }

  const delay = Math.max(5000, activeSchedule.current.endsAt - Date.now() + 1500);
  reloadTimer = window.setTimeout(loadSchedule, delay);
}

function getTimelineLabel(item, index) {
  if (item.placeholder) {
    return "--";
  }

  if (index === 0) {
    return "当前";
  }

  if (index === 1) {
    return "下一张";
  }

  return "后续";
}

function createTimelineItem(item, index) {
  const article = document.createElement("article");
  article.className = `timeline-item${item.current ? " is-current" : ""}`;

  const thumb = document.createElement("div");
  thumb.className = "timeline-thumb";
  const thumbSrc = item.placeholder ? "" : getMapThumbnail(item);

  if (thumbSrc) {
    const image = document.createElement("img");
    image.src = thumbSrc;
    image.alt = "";
    image.decoding = "async";
    image.loading = index === 0 ? "eager" : "lazy";
    image.fetchPriority = "low";
    thumb.append(image);
  } else {
    thumb.classList.add("is-empty");
  }

  const body = document.createElement("div");
  body.className = "timeline-body";

  const time = document.createElement("div");
  time.className = "timeline-time";
  time.textContent = item.placeholder ? "--" : formatTimeRange(item.startsAt, item.endsAt);

  const map = document.createElement("div");
  map.className = "timeline-map";
  map.textContent = item.name || "--";

  const label = document.createElement("div");
  label.className = "timeline-label";
  label.textContent = getTimelineLabel(item, index);

  body.append(time, map, label);
  article.append(body, thumb);
  return article;
}

function renderTimeline() {
  const items = activeSchedule?.upcoming || [
    createPlaceholderMap(),
    createPlaceholderMap(),
    createPlaceholderMap()
  ];

  elements.timeline.replaceChildren(...items.map(createTimelineItem));
}

function render() {
  if (!activeSchedule) {
    return;
  }

  const now = Date.now();
  const remaining = activeSchedule.current.endsAt - now;
  const duration = activeSchedule.current.durationMs;
  const progress = Math.min(1, Math.max(0, (now - activeSchedule.current.startsAt) / duration));

  elements.countdown.textContent = formatCountdown(remaining);
  elements.currentTitle.textContent = activeSchedule.current.name;
  elements.currentSubtitle.textContent = formatTimeRange(
    activeSchedule.current.startsAt,
    activeSchedule.current.endsAt
  );
  elements.nextTitle.textContent = activeSchedule.next.name;
  elements.nextSubtitle.textContent = formatTimeRange(
    activeSchedule.next.startsAt,
    activeSchedule.next.endsAt
  );
  elements.nextStart.textContent = formatClock(activeSchedule.next.startsAt);
  elements.progressRing.style.strokeDashoffset = String(ringCircumference * (1 - progress));
  elements.progressPercent.textContent = `${Math.round(progress * 100)}%`;
  setMapImage(elements.currentMapImage, elements.currentMapArt, activeSchedule.current);
  setMapImage(elements.nextMapImage, elements.nextMapThumb, activeSchedule.next, true);
}

elements.progressRing.style.strokeDasharray = String(ringCircumference);
const initialMapCatalog = window.__APEX_MAP_CATALOG__;
const hasInitialMapCatalog = Array.isArray(initialMapCatalog?.maps);
if (hasInitialMapCatalog) {
  mapCatalog = indexMapCatalog(initialMapCatalog.maps);
}

const initialState = window.__APEX_INITIAL_STATE__;
if (initialState?.data) {
  applyServerState(initialState);
} else {
  setOfflineState();
  render();
}

if (!hasInitialMapCatalog) {
  loadMapCatalog();
}
loadSchedule();
window.setInterval(render, 1000);

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    loadSchedule();
  }
});

window.addEventListener("online", loadSchedule);
