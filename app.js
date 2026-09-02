let activeSchedule = null;
let reloadTimer = null;
let retryTimer = null;
let mapCatalog = new Map();

const mapCatalogUrl = "./image/maps.json";
const rotationStoreKey = "apex-ranked-rotation-v2";
const rotationMemoryMaxAgeMs = 30 * 24 * 60 * 60 * 1000;
const ringRadius = 50;
const ringCircumference = 2 * Math.PI * ringRadius;

const elements = {
  localTime: document.querySelector("#local-time"),
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

function normalizeApiMap(map) {
  if (!map || !map.map || !map.code || !map.start || !map.end) {
    throw new Error("排位轮换数据不完整");
  }

  const startsAt = Number(map.start) * 1000;
  const endsAt = Number(map.end) * 1000;

  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) || endsAt <= startsAt) {
    throw new Error("排位轮换时间无效");
  }

  return {
    code: map.code,
    name: map.map,
    asset: map.asset,
    startsAt,
    endsAt,
    durationMs: endsAt - startsAt
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
    mapCatalog.get(normalizeLookupValue(map.code)) ||
    mapCatalog.get(normalizeLookupValue(map.name)) ||
    null
  );
}

function getMapImage(map) {
  const entry = getMapEntry(map);
  return entry?.images?.official || map?.asset || "";
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
  image.src = src;
}

function createEmptyRotationStore(epochStartedAt = Date.now()) {
  return {
    version: 2,
    epochStartedAt,
    transitions: {}
  };
}

function readRotationStore() {
  try {
    const saved = JSON.parse(localStorage.getItem(rotationStoreKey) || "null");
    if (!saved || saved.version !== 2 || typeof saved.transitions !== "object") {
      return createEmptyRotationStore();
    }

    return saved;
  } catch {
    return createEmptyRotationStore();
  }
}

function writeRotationStore(store) {
  try {
    localStorage.setItem(rotationStoreKey, JSON.stringify(store));
  } catch {
    return;
  }
}

function pruneRotationStore(store) {
  const now = Date.now();
  Object.keys(store.transitions).forEach((code) => {
    const transition = store.transitions[code];
    if (!transition?.updatedAt || now - transition.updatedAt > rotationMemoryMaxAgeMs) {
      delete store.transitions[code];
    }
  });

  if (!Object.keys(store.transitions).length) {
    store.epochStartedAt = now;
  }

  return store;
}

function updateRotationStore(current, next) {
  let store = pruneRotationStore(readRotationStore());
  const transitionKeys = Object.keys(store.transitions);
  const knownTransition = store.transitions[current.code];
  const changedTransition = knownTransition && knownTransition.code !== next.code;
  const trustedButUnknownCurrent = !knownTransition && transitionKeys.length >= 3;

  if (changedTransition || trustedButUnknownCurrent) {
    store = createEmptyRotationStore(current.startsAt);
  }

  store.transitions[current.code] = {
    code: next.code,
    name: next.name,
    asset: next.asset,
    durationMs: next.durationMs,
    startsAt: next.startsAt,
    endsAt: next.endsAt,
    updatedAt: Date.now()
  };

  writeRotationStore(store);
  return store;
}

function getLearnedThirdMap(store, next) {
  const learned = store.transitions[next.code];
  const now = Date.now();

  if (
    !learned ||
    !learned.code ||
    !learned.name ||
    !Number.isFinite(learned.durationMs) ||
    learned.updatedAt < store.epochStartedAt ||
    now - learned.updatedAt > rotationMemoryMaxAgeMs
  ) {
    return null;
  }

  return {
    code: learned.code,
    name: learned.name,
    asset: learned.asset,
    startsAt: next.endsAt,
    endsAt: next.endsAt + learned.durationMs,
    durationMs: learned.durationMs,
    current: false,
    placeholder: false
  };
}

function createScheduleFromApi(data) {
  const ranked = data.ranked;
  if (!ranked?.current || !ranked?.next) {
    throw new Error("排位轮换数据不完整");
  }

  const current = normalizeApiMap(ranked.current);
  const next = normalizeApiMap(ranked.next);
  const store = updateRotationStore(current, next);
  const third = getLearnedThirdMap(store, next) || {
    name: "--",
    startsAt: null,
    endsAt: null,
    durationMs: null,
    current: false,
    placeholder: true
  };

  return {
    current,
    next,
    upcoming: [
      { ...current, current: true, placeholder: false },
      { ...next, current: false, placeholder: false },
      third
    ]
  };
}

function setOfflineState() {
  activeSchedule = null;
  document.body.classList.add("is-offline");
  elements.statusPill.classList.add("is-offline");
  elements.statusLabel.textContent = "OFFLINE";
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

async function loadSchedule() {
  const config = window.APP_CONFIG || {};

  if (!config.apexApiKey || !config.apexApiUrl) {
    setOfflineState();
    scheduleRetry();
    return;
  }

  try {
    const apiUrl = new URL(config.apexApiUrl, window.location.href);
    apiUrl.searchParams.set("auth", String(config.apexApiKey).trim());

    const response = await fetch(apiUrl.toString(), { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`API 请求失败：${response.status}`);
    }

    activeSchedule = createScheduleFromApi(await response.json());
    clearRetryTimer();
    setOnlineState();
    renderTimeline();
    render();
    scheduleReloadAtMapEnd();
    preloadMapImage(activeSchedule.next);
  } catch (error) {
    console.warn(error);
    setOfflineState();
    scheduleRetry();
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
  const thumbSrc = item.placeholder ? "" : getMapImage(item);

  if (thumbSrc) {
    const image = document.createElement("img");
    image.src = thumbSrc;
    image.alt = "";
    image.decoding = "async";
    image.loading = index === 0 ? "eager" : "lazy";
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
    { name: "--", startsAt: null, endsAt: null, placeholder: true },
    { name: "--", startsAt: null, endsAt: null, placeholder: true },
    { name: "--", startsAt: null, endsAt: null, placeholder: true }
  ];

  elements.timeline.replaceChildren(...items.map(createTimelineItem));
}

function render() {
  elements.localTime.textContent = formatClock(Date.now(), { seconds: true });

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
setOfflineState();
render();
loadMapCatalog();
loadSchedule();
window.setInterval(render, 1000);

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    loadSchedule();
  }
});

window.addEventListener("online", loadSchedule);
