import { validateParameterSchema, validateState, defaultState } from "./parameters.js";

export function validateScene(scene) {
  if (!scene || typeof scene !== "object" || ![1, 2].includes(scene.contractVersion)) {
    throw new Error("Unsupported scene contract. Expected contractVersion: 1 or 2.");
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
  if (scene.contractVersion === 2) {
    validateParameterSchema(scene.parameters);
    if (!scene.controls || typeof scene.controls !== "object" || Array.isArray(scene.controls)
        || !Object.keys(scene.controls).length) throw new Error("Missing scene controls.");
    for (const [name, control] of Object.entries(scene.controls)) {
      if (!/^[a-z][A-Za-z0-9]*$/.test(name) || !control || !["enum", "number"].includes(control.type)
          || typeof control.label !== "string" || !control.label.trim()) throw new Error(`Invalid control: ${name}`);
      if (control.type === "enum" && (!Array.isArray(control.options) || !control.options.length
          || !control.options.every(v => typeof v === "string" && /^[a-z][a-z0-9-]*$/.test(v))
          || new Set(control.options).size !== control.options.length)) throw new Error(`Invalid options: ${name}`);
      if (control.type === "number" && (!Number.isFinite(control.min) || !Number.isFinite(control.max)
          || control.min >= control.max || !Number.isFinite(control.step) || control.step <= 0)) {
        throw new Error(`Invalid range: ${name}`);
      }
    }
    validateState(scene.controls, defaultState(scene.controls));
    if (!Array.isArray(scene.presets) || new Set(scene.presets.map(preset => preset.id)).size !== scene.presets.length) {
      throw new Error("Invalid scene presets.");
    }
    for (const preset of scene.presets) {
      if (typeof preset.id !== "string" || !/^[a-z][a-z0-9-]*$/.test(preset.id)
          || typeof preset.label !== "string" || !preset.label.trim()) throw new Error("Invalid preset label or id.");
      validateState(scene.controls, preset.values);
    }
    if (!Number.isFinite(scene.transitionSeconds) || scene.transitionSeconds < 0 || scene.transitionSeconds > 10) {
      throw new Error("Invalid transitionSeconds.");
    }
  }
  if (scene.overlay !== undefined) {
    const overlay = scene.overlay;
    if (scene.contractVersion !== 2 || !overlay
        || typeof overlay.source !== "string"
        || !/^(?:\.\.\/)?(?:[a-z0-9-]+\/)*[a-z0-9-]+\.glsl$/.test(overlay.source)
        || !Array.isArray(overlay.enabledBy) || !overlay.enabledBy.length
        || new Set(overlay.enabledBy).size !== overlay.enabledBy.length
        || !overlay.enabledBy.every(name => typeof name === "string"
          && scene.parameters[name]?.type === "float" && scene.parameters[name].min >= 0)) {
      throw new Error("Invalid v2 overlay: expected a local GLSL source and non-negative float activation parameters.");
    }
  }
  return scene;
}

export function overlayEnabled(scene, values) {
  return Boolean(scene.overlay && scene.overlay.enabledBy.some(name => values[name] > 0));
}

export async function loadScene(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Unable to load scene: HTTP ${response.status} (${url})`);
  return validateScene(await response.json());
}
