import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { validateScene } from "../web/runtime/contract.js";
import { defaultState, parameterDefaults } from "../web/runtime/parameters.js";
import { resolveFujiParameters } from "../scenes/fuji2/resolve.js";
import { evidenceFor, timeBand } from "../web/demos/fuji2/references.js";

const root = new URL("../", import.meta.url);
const read = path => readFile(new URL(path, root));
const json = async path => JSON.parse(await read(path));

test("Fuji 1 base shader and legacy profile values remain preserved", async () => {
  const hashes = {
    "glsl/fuji-mountain/main.glsl": "2bca1e184f551acacc887b4829cdbfe7cf07868864521b755e59a9fdbf869f15",
  };
  for (const [file, hash] of Object.entries(hashes)) assert.equal(createHash("sha256").update(await read(file)).digest("hex"), hash, file);
  const profiles = await json("glsl/fuji-mountain/profiles.json");
  assert.deepEqual(profiles.seasons, {
    spring: { snowLine: 1.8, snowCoverage: 0.85, foliageColor: [0.065, 0.16, 0.08] },
    summer: { snowLine: 2.85, snowCoverage: 0.3, foliageColor: [0.025, 0.125, 0.05] },
    autumn: { snowLine: 2.2, snowCoverage: 0.75, foliageColor: [0.24, 0.09, 0.025] },
    winter: { snowLine: 1.15, snowCoverage: 1, foliageColor: [0.04, 0.08, 0.095] },
  });
  for (const [name, expected] of Object.entries({
    clear: [0.22, 0.1, 0.85], cloudy: [0.9, 0.25, 1.3], fog: [0.65, 0.88, 0.4],
  })) {
    const weather = profiles.weather[name];
    assert.deepEqual([weather.cloudCoverage, weather.fogDensity, weather.wind], expected);
    assert.equal(weather.rainAmount + weather.snowAmount, 0);
  }
});

test("gallery exposes exactly Fuji 1, Fuji 2 and MS Logo", async () => {
  const ids = await json("glsl/index.json");
  assert.deepEqual(ids, ["fuji-mountain", "fuji2", "ms-logo"]);
  const scenes = await Promise.all(ids.map(id => json(`glsl/${id}/scene.json`)));
  assert.deepEqual(scenes.map(scene => scene.title), ["Fuji 1", "Fuji 2", "MS Logo"]);
});

test("Fuji 2 profiles are independent and every selectable combination is valid", async () => {
  const scene = validateScene(await json("glsl/fuji2/scene.json"));
  const profiles = await json("glsl/fuji2/profiles.json");
  assert.deepEqual(resolveFujiParameters(defaultState(scene.controls), scene, profiles), parameterDefaults(scene.parameters));
  for (const season of scene.controls.season.options) {
    for (const weather of scene.controls.weather.options) {
      for (let timeOfDay = 0; timeOfDay <= 24; timeOfDay += 0.25) {
        assert.doesNotThrow(() => resolveFujiParameters({ season, weather, timeOfDay }, scene, profiles));
      }
    }
  }
  assert.notDeepEqual(profiles, await json("glsl/fuji-mountain/profiles.json"));
  const source = (await read("glsl/fuji2/main.glsl")).toString();
  for (const [name, parameter] of Object.entries(scene.parameters)) {
    if (scene.overlay.enabledBy.includes(name)) continue;
    const declaration = source.match(new RegExp(`const ${parameter.type} ${name} = ([^;]+);`));
    assert.ok(declaration, `${name} has a standalone fallback`);
    const value = parameter.type === "vec3"
      ? declaration[1].slice(5, -1).split(",").map(Number)
      : Number(declaration[1]);
    assert.deepEqual(value, parameter.default, `${name} matches standalone defaults`);
  }
});

test("photographic references have local images, provenance and explicit limitations", async () => {
  const catalog = await json("web/demos/fuji2/assets/references.json");
  assert.ok(catalog.items.length >= 4);
  assert.equal(new Set(catalog.items.map(item => item.id)).size, catalog.items.length);
  for (const item of catalog.items) {
    for (const field of ["id", "title", "author", "captured", "license", "observations", "limitations"]) {
      assert.ok(typeof item[field] === "string" && item[field].trim(), `${item.id}: ${field}`);
    }
    assert.ok(/^[a-z0-9-]+\.jpg$/.test(item.file));
    for (const field of ["sourceUrl", "licenseUrl"]) assert.equal(new URL(item[field]).protocol, "https:");
    for (const axis of ["seasons", "weather", "times"]) assert.ok(Array.isArray(item.covers[axis]));
    const image = await read(`web/demos/fuji2/assets/references/${item.file}`);
    assert.equal(image[0], 0xff);
    assert.equal(image[1], 0xd8);
  }
  const summer = evidenceFor({ season: "summer", weather: "clear", timeOfDay: 12 }, catalog.items);
  assert.ok(summer.related.length > 0);
  assert.ok(!summer.gaps.includes("summer"));
});

test("reference selector reports gaps rather than implying exact photographic proof", () => {
  const items = [{ id: "day", covers: { seasons: ["summer"], weather: ["clear"], times: ["day"] } }];
  const result = evidenceFor({ season: "winter", weather: "fog", timeOfDay: 0 }, items);
  assert.deepEqual(result.gaps, ["winter", "fog", "night"]);
  assert.equal(result.related.length, 0);
  assert.equal(timeBand(24), "night");
  assert.equal(timeBand(7.5), "morning");
  assert.equal(timeBand(17.5), "evening");
});
