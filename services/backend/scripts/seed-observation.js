const fs = require("fs");
const path = require("path");

const API_BASE_URL = process.env.DRONEWATCH_BACKEND_URL || "http://127.0.0.1:3100";
const EXAMPLE_PATH =
  process.env.DRONEWATCH_OBSERVATION_EXAMPLE ||
  path.join(
    __dirname,
    "..",
    "..",
    "..",
    "packages",
    "contracts",
    "observation-package",
    "v1",
    "examples",
    "successful-tracked-observation.json"
  );

async function main() {
  const body = fs.readFileSync(EXAMPLE_PATH, "utf8");
  const response = await fetch(`${API_BASE_URL}/observations`, {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body
  });

  const payload = await response.json();
  if (!response.ok) {
    console.error(JSON.stringify(payload, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(payload, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
