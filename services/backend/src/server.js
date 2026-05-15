const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PORT = Number(process.env.PORT || 3100);
const HOST = process.env.HOST || "127.0.0.1";
const DATA_DIR = process.env.DRONEWATCH_BACKEND_DATA_DIR || path.join(__dirname, "..", ".local-data");
const STORE_PATH = path.join(DATA_DIR, "observations.jsonl");

function ensureStore() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(STORE_PATH)) {
    fs.writeFileSync(STORE_PATH, "", "utf8");
  }
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 2_000_000) {
        request.destroy();
        reject(new Error("Payload too large"));
      }
    });
    request.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    request.on("error", reject);
  });
}

function sendJson(response, statusCode, payload) {
  const body = JSON.stringify(payload, null, 2);
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  response.end(body);
}

function validateObservationPackage(packageBody) {
  const errors = [];

  if (packageBody.schemaVersion !== "observation_package.v1") {
    errors.push("schemaVersion must be observation_package.v1");
  }
  if (!packageBody.packageId || typeof packageBody.packageId !== "string") {
    errors.push("packageId is required");
  }
  if (packageBody.sourceType !== "civilian_report") {
    errors.push("sourceType must be civilian_report");
  }
  if (packageBody.packageKind !== "observation_package") {
    errors.push("packageKind must be observation_package");
  }
  for (const key of ["captureSession", "humanReport", "evidence", "derivedEvidence", "validationJoin"]) {
    if (!packageBody[key] || typeof packageBody[key] !== "object") {
      errors.push(`${key} object is required`);
    }
  }

  return errors;
}

function toStoredObservation(packageBody) {
  const observationId = packageBody.packageId;
  const captureSession = packageBody.captureSession || {};
  const validationJoin = packageBody.validationJoin || {};
  const derivedEvidence = packageBody.derivedEvidence || {};

  return {
    observationId,
    storageVersion: "backend_observation_record.v1",
    receivedAt: new Date().toISOString(),
    packageHash: hashPackage(packageBody),
    metadata: {
      schemaVersion: packageBody.schemaVersion,
      sourceType: packageBody.sourceType,
      packageKind: packageBody.packageKind,
      createdAt: packageBody.createdAt,
      captureSessionId: captureSession.captureSessionId,
      captureMode: captureSession.captureMode,
      appPlatform: captureSession.appPlatform
    },
    humanReport: packageBody.humanReport,
    evidence: packageBody.evidence,
    derivedFeatures: derivedEvidence,
    validationJoin: {
      timeWindow: validationJoin.timeWindow,
      observerLocation: validationJoin.observerLocation,
      roughBearingDegrees: validationJoin.roughBearingDegrees,
      spatialUncertaintyMeters: validationJoin.spatialUncertaintyMeters,
      joinKeys: validationJoin.joinKeys
    },
    privacy: packageBody.privacy || {},
    originalPackage: packageBody
  };
}

function hashPackage(packageBody) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(packageBody))
    .digest("hex");
}

function appendObservation(record) {
  ensureStore();
  fs.appendFileSync(STORE_PATH, `${JSON.stringify(record)}\n`, "utf8");
}

function readObservations() {
  ensureStore();
  return fs
    .readFileSync(STORE_PATH, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function toMapItem(record) {
  const location = record.validationJoin.observerLocation;
  return {
    observationId: record.observationId,
    sourceType: record.metadata.sourceType,
    observedAt: record.validationJoin.timeWindow?.startedAt || record.metadata.createdAt,
    qualityScore: record.derivedFeatures.qualityScore,
    qualityTier: record.derivedFeatures.qualityTier,
    reasonCodes: record.derivedFeatures.reasonCodes || [],
    location: location
      ? {
          lat: location.lat,
          lon: location.lon,
          accuracyMeters: location.accuracyMeters
        }
      : null,
    roughBearingDegrees: record.validationJoin.roughBearingDegrees,
    spatialUncertaintyMeters: record.validationJoin.spatialUncertaintyMeters
  };
}

async function handleRequest(request, response) {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);

  if (request.method === "GET" && url.pathname === "/health") {
    sendJson(response, 200, { ok: true, service: "dronewatch-backend", storePath: STORE_PATH });
    return;
  }

  if (request.method === "POST" && url.pathname === "/observations") {
    try {
      const packageBody = await readJsonBody(request);
      const errors = validateObservationPackage(packageBody);
      if (errors.length > 0) {
        sendJson(response, 400, { error: "invalid_observation_package", details: errors });
        return;
      }

      const record = toStoredObservation(packageBody);
      appendObservation(record);
      sendJson(response, 201, {
        observationId: record.observationId,
        receivedAt: record.receivedAt,
        packageHash: record.packageHash,
        storedSections: ["metadata", "humanReport", "evidence", "derivedFeatures", "validationJoin", "privacy"]
      });
    } catch (error) {
      sendJson(response, 400, { error: "bad_request", message: error.message });
    }
    return;
  }

  if (request.method === "GET" && url.pathname === "/observations") {
    const observations = readObservations().map((record) => ({
      observationId: record.observationId,
      receivedAt: record.receivedAt,
      metadata: record.metadata,
      derivedFeatures: record.derivedFeatures,
      validationJoin: record.validationJoin
    }));
    sendJson(response, 200, { observations });
    return;
  }

  const observationMatch = url.pathname.match(/^\/observations\/([^/]+)$/);
  if (request.method === "GET" && observationMatch) {
    const observationId = decodeURIComponent(observationMatch[1]);
    const record = readObservations().find((item) => item.observationId === observationId);
    if (!record) {
      sendJson(response, 404, { error: "not_found", observationId });
      return;
    }
    sendJson(response, 200, record);
    return;
  }

  if (request.method === "GET" && url.pathname === "/map-feed") {
    const items = readObservations()
      .filter((record) => record.validationJoin.observerLocation)
      .map(toMapItem);
    sendJson(response, 200, { items });
    return;
  }

  sendJson(response, 404, { error: "not_found" });
}

if (require.main === module) {
  ensureStore();
  const server = http.createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      sendJson(response, 500, { error: "internal_error", message: error.message });
    });
  });

  server.listen(PORT, HOST, () => {
    console.log(`DroneWatch backend listening on http://${HOST}:${PORT}`);
    console.log(`Observation store: ${STORE_PATH}`);
  });
}

module.exports = {
  validateObservationPackage,
  toStoredObservation,
  toMapItem
};
