import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { validateScene, overlayEnabled } from "../web/runtime/contract.js";
import { defaultState, parameterDefaults, ParameterTransition, stateFromURL, stateToURL } from "../web/runtime/parameters.js";
import { resolveFujiParameters as resolveFuji1 } from "../scenes/fuji-mountain/resolve.js";
import { resolveFujiParameters as resolveFuji2 } from "../scenes/fuji2/resolve.js";
import { evidenceFor } from "../web/demos/fuji2/references.js";

const read = async path => JSON.parse(await readFile(new URL(`../${path}`, import.meta.url), "utf8"));
const kinds = ["rain", "heavy-rain", "snow", "heavy-snow"];

for (const [id, resolve] of [["fuji-mountain", resolveFuji1], ["fuji2", resolveFuji2]]) {
  test(`${id}: complete weather choices, independent snow cover and URL round-trips`, async () => {
    const scene = validateScene(await read(`glsl/${id}/scene.json`));
    const profiles = await read(`glsl/${id}/profiles.json`);
    assert.deepEqual(scene.controls.weather.options, ["clear", "cloudy", "fog", ...kinds]);
    assert.deepEqual(resolve(defaultState(scene.controls), scene, profiles), parameterDefaults(scene.parameters));
    for (const season of scene.controls.season.options) {
      for (const weather of scene.controls.weather.options) {
        const state = { season, weather, timeOfDay: 14 };
        const values = resolve(state, scene, profiles);
        assert.equal(values.uSnowCoverage, profiles.seasons[season].snowCoverage);
        assert.equal(values.uSnowLine, profiles.seasons[season].snowLine);
        assert.equal(overlayEnabled(scene, values), kinds.includes(weather));
        assert.ok(values.uRainAmount === 0 || values.uSnowAmount === 0);
        const url = stateToURL(scene.controls, state, new URL("https://example.org/lock_shader/?extra=keep#view"));
        assert.deepEqual(stateFromURL(scene.controls, url).state, state);
        assert.equal(url.searchParams.get("extra"), "keep");
      }
    }
    for (const [light, heavy, name] of [["rain", "heavy-rain", "rainAmount"], ["snow", "heavy-snow", "snowAmount"]]) {
      assert.ok(profiles.weather[heavy][name] > profiles.weather[light][name]);
      assert.ok(profiles.weather[heavy].fogDensity > profiles.weather[light].fogDensity);
      assert.ok(profiles.weather[heavy].wind > profiles.weather[light].wind);
    }
  });
}

test("overlay schema rejects external sources, traversal and unsuitable activation parameters", async () => {
  const scene = await read("glsl/fuji2/scene.json");
  for (const source of ["https://example.org/rain.glsl", "/rain.glsl", "../../rain.glsl", "../shared/../rain.glsl", "rain.glsl?remote=1"]) {
    assert.throws(() => validateScene({ ...scene, overlay: { ...scene.overlay, source } }));
  }
  for (const enabledBy of [[], ["missing"], ["uFoliageColor"], ["uRainAmount", "uRainAmount"]]) {
    assert.throws(() => validateScene({ ...scene, overlay: { ...scene.overlay, enabledBy } }));
  }
  assert.throws(() => validateScene({ ...scene, overlay: null }));
  const glass = await read("glsl/ms-logo/scene.json");
  assert.equal(overlayEnabled(glass, null), false);
  assert.throws(() => validateScene({ ...glass, overlay: scene.overlay }));
});

test("rain-to-snow easing and day preview preserve precipitation values correctly", async () => {
  const scene = await read("glsl/fuji2/scene.json");
  const profiles = await read("glsl/fuji2/profiles.json");
  const resolve = weather => resolveFuji2({ season: "winter", weather, timeOfDay: 9 }, scene, profiles);
  const parameters = new ParameterTransition(scene.parameters);
  parameters.set(resolve("heavy-rain"));
  parameters.set(resolve("heavy-snow"), 2.5);
  parameters.advance(1.25);
  assert.equal(parameters.values.uRainAmount, 0.5);
  assert.equal(parameters.values.uSnowAmount, 0.5);
  parameters.advance(1.25);
  parameters.startCycle("uSunHour", 60);
  parameters.advance(15);
  assert.equal(parameters.values.uSunHour, 15);
  assert.equal(parameters.values.uRainAmount, 0);
  assert.equal(parameters.values.uSnowAmount, 1);
  parameters.set(resolve("clear"), 2.5);
  parameters.advance(2.5);
  assert.equal(overlayEnabled(scene, parameters.values), false);
});

test("precipitation stays explicitly unverified by the existing photographic references", async () => {
  const { items } = await read("web/demos/fuji2/assets/references.json");
  for (const weather of kinds) {
    assert.ok(evidenceFor({ season: "winter", weather, timeOfDay: 9 }, items).gaps.includes(weather));
  }
});
