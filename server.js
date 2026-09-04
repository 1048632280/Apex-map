const http = require("node:http");
const fs = require("node:fs/promises");
const path = require("node:path");

const rootDir = __dirname;
const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || 4173);
const apiUrl =
  process.env.APEXRANKED_API_URL || "https://apexranked.com/api/ranked-map";
const pollIntervalMs = 60 * 1000;
const requestTimeoutMs = 15 * 1000;

let latestState = {
  data: null,
  online: false,
  fetchedAt: null
};
let refreshPromise = null;
let pollTimer = null;
let boundaryTimer = null;

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".json": "application/json; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".jpg": "image/jpeg",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json; charset=utf-8"
};

function normalizeMap(map) {
  if (!map?.key || !map.slug || !map.name || !map.starts_at || !map.ends_at) {
    throw new Error("API 未返回完整地图数据");
  }

  const startsAt = Date.parse(map.starts_at);
  const endsAt = Date.parse(map.ends_at);
  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) || endsAt <= startsAt) {
    throw new Error("API 返回的地图时间无效");
  }

  return {
    key: map.key,
    slug: map.slug,
    name: map.name,
    starts_at: map.starts_at,
    ends_at: map.ends_at,
    duration_minutes: Number(map.duration_minutes) || Math.round((endsAt - startsAt) / 60000),
    is_current: Boolean(map.is_current)
  };
}

function normalizeSchedule(data) {
  if (!data?.current || !data?.next || !Array.isArray(data.upcoming)) {
    throw new Error("API 未返回完整的排位轮换数据");
  }

  return {
    current: normalizeMap(data.current),
    next: normalizeMap(data.next),
    upcoming: data.upcoming.slice(0, 3).map(normalizeMap),
    cycle_minutes: Number(data.cycle_minutes) || null
  };
}

function resetBoundaryTimer() {
  clearTimeout(boundaryTimer);
  boundaryTimer = null;
}

function scheduleBoundaryRefresh(data) {
  resetBoundaryTimer();

  const endAt = Date.parse(data?.current?.ends_at);
  if (!Number.isFinite(endAt)) {
    return;
  }

  const delay = Math.max(5000, endAt - Date.now() + 1500);
  boundaryTimer = setTimeout(() => {
    void refreshSchedule();
  }, delay);
}

async function refreshSchedule() {
  if (refreshPromise) {
    return refreshPromise;
  }

  refreshPromise = (async () => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);

    try {
      const response = await fetch(apiUrl, {
        cache: "no-store",
        signal: controller.signal
      });

      if (!response.ok) {
        throw new Error(`API 请求失败：${response.status}`);
      }

      const data = normalizeSchedule(await response.json());
      latestState = {
        data,
        online: true,
        fetchedAt: Date.now()
      };
      scheduleBoundaryRefresh(data);
      return latestState;
    } catch (error) {
      latestState = {
        ...latestState,
        online: false,
      };
      console.warn(`[Apex Rotation] ${error.message}`);
      return latestState;
    } finally {
      clearTimeout(timeout);
    }
  })();

  try {
    return await refreshPromise;
  } finally {
    refreshPromise = null;
  }
}

function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(() => {
    void refreshSchedule();
  }, pollIntervalMs);
  pollTimer.unref?.();
}

function getPublicState() {
  return {
    data: latestState.data,
    online: latestState.online,
    fetchedAt: latestState.fetchedAt
  };
}

function sendBody(request, response, statusCode, headers, body) {
  response.writeHead(statusCode, {
    ...headers,
    "content-length": Buffer.byteLength(body)
  });
  response.end(request.method === "HEAD" ? undefined : body);
}

function sendJson(request, response, statusCode, payload) {
  const body = JSON.stringify(payload);
  sendBody(request, response, statusCode, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8"
  }, body);
}

async function serveIndex(request, response) {
  const source = await fs.readFile(path.join(rootDir, "index.html"), "utf8");
  const state = JSON.stringify(getPublicState()).replace(/</g, "\\u003c");
  const bootScript = `<script>window.__APEX_INITIAL_STATE__=${state};</script>`;
  const html = source.replace("</head>", `${bootScript}</head>`);

  sendBody(request, response, 200, {
    "cache-control": "no-store",
    "content-type": "text/html; charset=utf-8"
  }, html);
}

async function serveStatic(request, response, pathname) {
  let relativePath;
  try {
    relativePath = decodeURIComponent(pathname.slice(1));
  } catch {
    sendBody(request, response, 400, { "content-type": "text/plain; charset=utf-8" }, "Bad Request");
    return;
  }

  const filePath = path.resolve(rootDir, relativePath);
  const relativeToRoot = path.relative(rootDir, filePath);
  if (
    relativeToRoot.startsWith("..") ||
    path.isAbsolute(relativeToRoot) ||
    path.basename(filePath).endsWith(".local.js")
  ) {
    sendBody(request, response, 404, { "content-type": "text/plain; charset=utf-8" }, "Not Found");
    return;
  }

  try {
    const body = await fs.readFile(filePath);
    sendBody(request, response, 200, {
      "cache-control": pathname.startsWith("/image/") ? "public, max-age=86400" : "no-cache",
      "content-type": contentTypes[path.extname(filePath).toLowerCase()] || "application/octet-stream"
    }, body);
  } catch (error) {
    sendBody(
      request,
      response,
      error.code === "ENOENT" ? 404 : 500,
      { "content-type": "text/plain; charset=utf-8" },
      error.code === "ENOENT" ? "Not Found" : "Internal Server Error"
    );
  }
}

const server = http.createServer(async (request, response) => {
  try {
    const requestUrl = new URL(request.url, `http://${request.headers.host || "localhost"}`);

    if (request.method !== "GET" && request.method !== "HEAD") {
      sendBody(
        request,
        response,
        405,
        { allow: "GET, HEAD", "content-type": "text/plain; charset=utf-8" },
        "Method Not Allowed"
      );
      return;
    }

    if (requestUrl.pathname === "/api/schedule") {
      if (!latestState.data) {
        sendJson(request, response, 503, getPublicState());
        return;
      }

      sendJson(request, response, 200, getPublicState());
      return;
    }

    if (requestUrl.pathname === "/healthz") {
      sendJson(request, response, 200, {
        online: latestState.online,
        hasData: Boolean(latestState.data)
      });
      return;
    }

    if (requestUrl.pathname === "/" || requestUrl.pathname === "/index.html") {
      await serveIndex(request, response);
      return;
    }

    await serveStatic(request, response, requestUrl.pathname);
  } catch (error) {
    console.warn(`[Apex Rotation] ${error.message}`);
    sendBody(
      request,
      response,
      500,
      { "content-type": "text/plain; charset=utf-8" },
      "Internal Server Error"
    );
  }
});

async function start() {
  await refreshSchedule();
  startPolling();
  server.listen(port, host, () => {
    console.log(`Apex Rotation running at http://${host}:${port}`);
  });
}

start().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
