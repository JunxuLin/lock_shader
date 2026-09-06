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

test("Fuji 1 rendering remains identical to preserved fuji-v1 version", async () => {
  const hashes = {
    "glsl/fuji-mountain/main.glsl": "2bca1e184f551acacc887b4829cdbfe7cf07868864521b755e59a9fdbf869f15",
    "glsl/fuji-mountain/profiles.json": "57d38818497484d7be4e03946635bcf21e3f6879843806eb73b6b8b41a98fff6",
    "scenes/fuji-mountain/resolve.js": "766852f57a2e255938f72028a7dacdb25e3a3430d16f240c6e9e974fe6fca252",
    "web/demos/fuji-mountain/app.js": "c0872f475a188ed4e9e0547e59555b91d4b67ffc9e58ce1030cad10b8646e736",
  };
  for (const [file, hash] of Object.entries(hashes)) assert.equal(createHash("sha256").update(await read(file)).digest("hex"), hash, file);
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
