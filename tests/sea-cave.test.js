import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { validateScene } from "../web/runtime/contract.js";
import { defaultState, parameterDefaults, stateFromURL, stateToURL, ParameterTransition } from "../web/runtime/parameters.js";
import { resolveSeaCaveParameters } from "../scenes/sea-cave/resolve.js";

const read = async path => JSON.parse(await readFile(new URL(path, import.meta.url), "utf8"));
const scene = validateScene(await read("../glsl/sea-cave/scene.json"));
const profiles = await read("../glsl/sea-cave/profiles.json");
const resolve = state => resolveSeaCaveParameters(state, scene, profiles);
const defaults = defaultState(scene.controls);

test("Sea Cave standalone shader fallbacks match the manifest defaults", async () => {
  const source = await readFile(new URL("../glsl/sea-cave/main.glsl", import.meta.url), "utf8");
  assert.match(source, /#ifndef\s+LOCK_SHADER_PARAMETERS/);
  for (const [name, parameter] of Object.entries(scene.parameters)) {
    const declaration = source.match(new RegExp(`const\\s+${parameter.type}\\s+${name}\\s*=\\s*([^;]+);`));
    assert.ok(declaration, `${name} has a standalone fallback`);
    assert.equal(Number(declaration[1]), parameter.default, `${name} matches the manifest default`);
  }
});

test("Sea Cave has the exact independent v2 contract and default parameter set", () => {
  assert.equal(scene.id, "sea-cave");
  assert.equal(scene.contractVersion, 2);
  assert.equal(scene.transitionSeconds, 2.5);
  assert.equal(scene.initialTime, 24);
  assert.equal(scene.posterTime, 24);
  assert.equal(scene.pointer, true);
  assert.equal(scene.overlay, undefined);
  assert.deepEqual(scene.performance, { fps: 30, maxPixels: 1500000, minPixels: 650000, maxDpr: 1.5 });
  assert.deepEqual(defaults, { weather: "clear", seaState: "rolling", timeOfDay: 9 });
  assert.deepEqual(scene.controls.weather.options, ["clear", "cloudy", "fog"]);
  assert.deepEqual(scene.controls.seaState.options, ["calm", "rolling", "rough"]);
  assert.deepEqual(scene.controls.timeOfDay, { type: "number", label: "Scene time", min: 0, max: 24, step: 0.25, default: 9 });
  assert.deepEqual(resolve(defaults), {
    uSunHour: 9, uCloudCoverage: 0.25, uFogDensity: 0.1, uWind: 0.7, uWaveStrength: 0.55,
  });
  assert.deepEqual(resolve(defaults), parameterDefaults(scene.parameters));
  assert.deepEqual(scene.parameters.uSunHour, { type: "float", min: 0, max: 24, wrap: true, default: 9 });
});

test("every weather, sea state and quarter-hour combination resolves deterministically and shares by URL", () => {
  const url = new URL("https://example.org/lock_shader/web/demos/sea-cave/?extra=keep#view");
  for (const weather of scene.controls.weather.options) {
    for (const seaState of scene.controls.seaState.options) {
      for (let timeOfDay = 0; timeOfDay <= 24; timeOfDay += 0.25) {
        const state = { weather, seaState, timeOfDay };
        const parameters = resolve(state);
        assert.equal(parameters.uSunHour, timeOfDay);
        assert.deepEqual(parameters, resolve({ timeOfDay, seaState, weather }));
        const shared = stateToURL(scene.controls, state, url);
        assert.deepEqual(stateFromURL(scene.controls, shared), { state, issues: [] });
        assert.equal(shared.pathname, url.pathname);
        assert.equal(shared.searchParams.get("extra"), "keep");
        assert.equal(shared.hash, "#view");
      }
    }
  }
  assert.equal(url.searchParams.get("weather"), null);
});

test("all six presets are complete semantic states with the intended conditions", () => {
  assert.deepEqual(scene.presets.map(preset => preset.values), [
    { weather: "clear", seaState: "rolling", timeOfDay: 9 },
    { weather: "clear", seaState: "calm", timeOfDay: 14 },
    { weather: "clear", seaState: "rolling", timeOfDay: 17.5 },
    { weather: "cloudy", seaState: "rough", timeOfDay: 14 },
    { weather: "fog", seaState: "calm", timeOfDay: 7 },
    { weather: "clear", seaState: "rolling", timeOfDay: 22 },
  ]);
  for (const preset of scene.presets) {
    assert.deepEqual(Object.keys(preset.values).sort(), Object.keys(scene.controls).sort());
    assert.doesNotThrow(() => resolve(preset.values));
  }
});

test("sea state owns wave strength independently of weather and lighting", () => {
  const base = resolve(defaults);
  for (const [seaState, waveStrength] of Object.entries({ calm: 0.2, rolling: 0.55, rough: 1 })) {
    assert.deepEqual(resolve({ ...defaults, seaState }), { ...base, uWaveStrength: waveStrength });
    for (const weather of scene.controls.weather.options) {
      const result = resolve({ ...defaults, weather, seaState });
      assert.equal(result.uWaveStrength, waveStrength);
      assert.equal(result.uSunHour, base.uSunHour);
      assert.deepEqual({ ...result, uWaveStrength: base.uWaveStrength }, resolve({ ...defaults, weather }));
    }
  }
  assert.deepEqual(resolve({ ...defaults, timeOfDay: 22 }), { ...base, uSunHour: 22 });
  assert.ok(resolve({ ...defaults, weather: "cloudy" }).uCloudCoverage > base.uCloudCoverage);
  assert.ok(resolve({ ...defaults, weather: "fog" }).uFogDensity > base.uFogDensity);
});

test("resolver does not mutate inputs or return shared parameter objects", () => {
  const snapshot = structuredClone({ scene, profiles });
  const state = Object.freeze({ ...defaults });
  const result = resolve(state);
  result.uWaveStrength = 0;
  assert.deepEqual(resolve(state), parameterDefaults(scene.parameters));
  assert.deepEqual({ scene, profiles }, snapshot);
});

test("invalid states and missing or invalid profiles fail instead of leaking shader values", () => {
  for (const state of [
    null, {}, { weather: "clear" }, { ...defaults, extra: 1 },
    { ...defaults, weather: "rain" }, { ...defaults, seaState: "storm" },
    ...[-1, 25, 9.1, NaN, Infinity, "9", null].map(timeOfDay => ({ ...defaults, timeOfDay })),
  ]) assert.throws(() => resolve(state));
  for (const badProfiles of [
    {}, { weather: profiles.weather }, { seaStates: profiles.seaStates },
    { ...profiles, weather: { ...profiles.weather, clear: { ...profiles.weather.clear, wind: 3 } } },
    { ...profiles, seaStates: { ...profiles.seaStates, rolling: { waveStrength: NaN } } },
    { ...profiles, seaStates: { ...profiles.seaStates, rolling: {} } },
  ]) assert.throws(() => resolveSeaCaveParameters(defaults, scene, badProfiles));
});

test("invalid URL values warn per field and preserve valid independent selections", () => {
  const base = "https://example.org/lock_shader/web/demos/sea-cave/";
  assert.deepEqual(stateFromURL(scene.controls, new URL(base)), { state: defaults, issues: [] });
  const bad = stateFromURL(scene.controls, new URL(`${base}?weather=rain&seaState=storm&timeOfDay=`));
  assert.deepEqual(bad.state, defaults);
  assert.equal(bad.issues.length, 3);
  for (const value of ["NaN", "Infinity", "-1", "25", "9.1", ""]) {
    const parsed = stateFromURL(scene.controls, new URL(`${base}?weather=fog&seaState=rough&timeOfDay=${value}`));
    assert.deepEqual(parsed.state, { weather: "fog", seaState: "rough", timeOfDay: 9 });
    assert.equal(parsed.issues.length, 1);
  }
  assert.throws(() => stateToURL(scene.controls, { ...defaults, seaState: "storm" }, new URL(base)));
});

test("Sea Cave time wraps across midnight and day preview leaves weather and waves fixed", () => {
  const transition = new ParameterTransition(scene.parameters);
  const base = resolve({ weather: "fog", seaState: "rough", timeOfDay: 23 });
  transition.set(base);
  transition.set({ ...base, uSunHour: 1 }, 2.5);
  transition.advance(1.25);
  assert.deepEqual(transition.values, { ...base, uSunHour: 0 });
  transition.advance(1.25);
  assert.deepEqual(transition.values, { ...base, uSunHour: 1 });
  transition.set({ ...base, uSunHour: 24 });
  transition.startCycle("uSunHour", 60);
  transition.advance(30);
  assert.deepEqual(transition.values, { ...base, uSunHour: 12 });
  transition.advance(30);
  assert.deepEqual(transition.values, { ...base, uSunHour: 24 });
  assert.equal(transition.cycle.finished, true);
});
