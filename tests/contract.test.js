import test from "node:test";
import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import { validateScene } from "../web/runtime/contract.js";

const root = new URL("../", import.meta.url);
const read = path => readFile(new URL(path, root), "utf8");
const ids = JSON.parse(await read("glsl/index.json"));

test("registry contains unique safe scene ids", () => {
  assert.ok(ids.length > 0);
  assert.equal(new Set(ids).size, ids.length);
  assert.ok(ids.every(id => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id)));
});

for (const id of ids) {
  test(`${id}: valid standalone shader, manifest and demo`, async () => {
    const scene = validateScene(JSON.parse(await read(`glsl/${id}/scene.json`)));
    assert.equal(scene.id, id);
    const shader = await read(`glsl/${id}/${scene.source}`);
    assert.match(shader, /void\s+mainImage\s*\(\s*out\s+vec4\s+\w+\s*,\s*in\s+vec2\s+\w+\s*\)/);
    const code = shader.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, "");
    assert.doesNotMatch(code, /#version|\buniform\b|\bsampler\w*\b|\biChannel\d\b|\bvoid\s+main\s*\(/);
    if (scene.overlay) {
      const overlayUrl = new URL(scene.overlay.source, new URL(`glsl/${id}/scene.json`, root));
      const overlay = await readFile(overlayUrl, "utf8");
      assert.match(overlay, /void\s+mainImage\s*\(/);
      assert.doesNotMatch(overlay, /#version|\buniform\b|\bsampler\w*\b|\btraceTerrain\b/);
    }
    for (const path of [`web/demos/${id}/index.html`, `web/demos/${id}/app.js`, `web/assets/${id}.jpg`]) {
      await access(new URL(path, root));
    }
    const html = await read(`web/demos/${id}/index.html`);
    assert.match(html, /id="download"/);
    assert.match(await read(`web/demos/${id}/app.js`), /runtime\/player\.js/);
  });
}

test("contract rejects invalid metadata and unsupported features", async () => {
  const valid = JSON.parse(await read("glsl/fuji-mountain/scene.json"));
  const invalid = [
    { contractVersion: 3 }, { id: "../escape" }, { source: "https://example.com/shader" },
    { initialTime: -1 }, { posterTime: 0 }, { pointer: "true" }, { title: "" }, { tags: [null] },
    { performance: { ...valid.performance, fps: 0 } },
    { performance: { ...valid.performance, minPixels: valid.performance.maxPixels + 1 } },
  ];
  for (const change of invalid) assert.throws(() => validateScene({ ...valid, ...change }));
  assert.throws(() => validateScene(null));
});
