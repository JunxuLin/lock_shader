export function validateScene(scene) {
  if (!scene || typeof scene !== "object" || scene.contractVersion !== 1) {
    throw new Error("Unsupported scene contract. Expected contractVersion: 1.");
  }
  if (typeof scene.id !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(scene.id)) {
    throw new Error("Scene id must be a lowercase kebab-case identifier.");
  }
  for (const key of ["title", "description", "attribution"]) {
    if (typeof scene[key] !== "string" || !scene[key].trim()) throw new Error(`Missing scene ${key}.`);
  }
  if (scene.source !== "main.glsl") throw new Error("Contract v1 requires a local main.glsl source.");
  for (const key of ["initialTime", "posterTime"]) {
    if (!Number.isFinite(scene[key]) || scene[key] < 0) throw new Error(`Invalid scene ${key}.`);
  }
  if (scene.posterTime < scene.initialTime) throw new Error("posterTime must not precede initialTime.");
  if (typeof scene.pointer !== "boolean") throw new Error("Scene pointer must be a boolean.");
  if (!Array.isArray(scene.tags) || !scene.tags.every(tag => typeof tag === "string" && tag.trim())) {
    throw new Error("Scene tags must be an array of non-empty strings.");
  }
  const p = scene.performance;
  if (!p || ![30, 60].includes(p.fps) || !Number.isInteger(p.minPixels) || !Number.isInteger(p.maxPixels)
      || p.minPixels < 1 || p.maxPixels < p.minPixels || !Number.isFinite(p.maxDpr) || p.maxDpr <= 0 || p.maxDpr > 2) {
    throw new Error("Invalid scene performance budget.");
  }
  return scene;
}

export async function loadScene(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Unable to load scene: HTTP ${response.status} (${url})`);
  return validateScene(await response.json());
}
