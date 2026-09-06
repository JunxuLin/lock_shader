import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { validateScene } from "../web/runtime/contract.js";
import { defaultState, parameterDefaults, stateFromURL, stateToURL, validateState, ParameterTransition } from "../web/runtime/parameters.js";
import { resolveFujiParameters } from "../scenes/fuji-mountain/resolve.js";

const read = async path => JSON.parse(await readFile(new URL(path, import.meta.url), "utf8"));
const scene = validateScene(await read("../glsl/fuji-mountain/scene.json"));
const profiles = await read("../glsl/fuji-mountain/profiles.json");
const resolve = state => resolveFujiParameters(state, scene, profiles);

test("Fuji defaults agree with parameter defaults; all supported combinations resolve", () => {
  assert.deepEqual(resolve(defaultState(scene.controls)), parameterDefaults(scene.parameters));
  for (const season of scene.controls.season.options) {
    for (const weather of scene.controls.weather.options) {
      for (let hour = 0; hour <= 24; hour += 0.25) {
        const state = { season, weather, timeOfDay: hour };
        const result = resolve(state);
        assert.equal(result.uSunHour, hour);
        assert.deepEqual(result, resolve({ timeOfDay: hour, weather, season }));
      }
    }
  }
  for (const preset of scene.presets) assert.doesNotThrow(() => resolve(preset.values));
});

test("season and weather own independent parameters", () => {
  const winter = resolve({ season: "winter", weather: "clear", timeOfDay: 7.5 });
  const summer = resolve({ season: "summer", weather: "clear", timeOfDay: 7.5 });
  const fog = resolve({ season: "winter", weather: "fog", timeOfDay: 7.5 });
  assert.ok(winter.uSnowLine < summer.uSnowLine);
  assert.ok(winter.uSnowCoverage > summer.uSnowCoverage);
  assert.equal(fog.uSnowLine, winter.uSnowLine);
  assert.ok(fog.uFogDensity > winter.uFogDensity);
  assert.equal(summer.uCloudCoverage, winter.uCloudCoverage);
});

test("URL state is validated, preserves other query keys and restores defaults visibly", () => {
  const url = new URL("https://example.org/lock_shader/web/demos/fuji-mountain/?season=autumn&weather=fog&timeOfDay=17.5&extra=keep#view");
  const parsed = stateFromURL(scene.controls, url);
  assert.equal(parsed.issues.length, 0);
  assert.deepEqual(parsed.state, { season: "autumn", weather: "fog", timeOfDay: 17.5 });
  const roundtrip = stateToURL(scene.controls, parsed.state, url);
  assert.equal(roundtrip.searchParams.get("extra"), "keep");
  assert.equal(roundtrip.hash, "#view");
  assert.deepEqual(stateFromURL(scene.controls, roundtrip).state, parsed.state);
  const bad = stateFromURL(scene.controls, new URL("https://example.org/?season=nope&weather=rain&timeOfDay="));
  assert.equal(bad.issues.length, 3);
  assert.deepEqual(bad.state, defaultState(scene.controls));
  for (const value of ["NaN", "Infinity", "-1", "25", "7.999"]) {
    assert.equal(stateFromURL(scene.controls, new URL(`https://example.org/?timeOfDay=${value}`)).issues.length, 1);
  }
  assert.throws(() => validateState(scene.controls, { season: "winter" }));
});

test("transitions interpolate, retarget continuously and cross midnight by the short path", () => {
  const transition = new ParameterTransition(scene.parameters);
  const base = parameterDefaults(scene.parameters);
  transition.set({ ...base, uSunHour: 23 });
  transition.set({ ...base, uSunHour: 1, uSnowCoverage: 0 }, 2);
  transition.advance(1);
  assert.equal(transition.values.uSunHour, 0);
  assert.equal(transition.values.uSnowCoverage, 0.5);
  const before = structuredClone(transition.values);
  transition.set({ ...base, uSunHour: 3 }, 2);
  assert.deepEqual(transition.values, before);
  transition.advance(2);
  assert.equal(transition.values.uSunHour, 3);
  assert.equal(transition.duration, 0);
  transition.set(base, 4);
  transition.finish();
  assert.deepEqual(transition.values, base);
  assert.throws(() => transition.set({ ...base, uWind: 100 }, 1));
  assert.deepEqual(transition.values, base);
});

test("v2 rejects unbounded uniforms, malformed controls and invalid presets", () => {
  const invalid = [
    { parameters: { ...scene.parameters, "uBad;code": { type: "float", min: 0, max: 1, default: 0 } } },
    { parameters: { uBad: { type: "sampler2D", min: 0, max: 1, default: 0 } } },
    { parameters: { uBad: { type: "vec3", min: 0, max: 1, default: [1, 2, 3] } } },
    { controls: { season: { type: "enum", label: "Season", options: [], default: "" } } },
    { transitionSeconds: -1 },
    { presets: [{ id: "bad", label: "Bad", values: { season: "summer" } }] },
  ];
  for (const change of invalid) assert.throws(() => validateScene({ ...scene, ...change }));
});
