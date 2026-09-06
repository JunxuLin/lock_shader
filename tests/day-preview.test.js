import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ParameterTransition } from "../web/runtime/parameters.js";
import { formatSceneHour } from "../web/runtime/day-preview.js";

const schema = {
  uSunHour: { type: "float", min: 0, max: 24, wrap: true, default: 7.5 },
  uSnowLine: { type: "float", min: 0, max: 4, default: 1.45 },
};

test("Fuji and Sea Cave demos wire the shared day-preview controller and styles", async () => {
  for (const id of ["fuji-mountain", "fuji2", "sea-cave"]) {
    const root = new URL(`../web/demos/${id}/`, import.meta.url);
    const html = await readFile(new URL("index.html", root), "utf8");
    const app = await readFile(new URL("app.js", root), "utf8");
    assert.match(html, /id="day-preview"/);
    assert.match(html, /href="\.\.\/\.\.\/runtime\/day-preview\.css"/);
    assert.match(app, /import \{ mountDayPreview \} from "\.\.\/\.\.\/runtime\/day-preview\.js"/);
    assert.match(app, /dayPreview = mountDayPreview\(player, scene, controls,/);
    assert.match(app, /dayPreview\?\.cancel\(\)/);
  }
});

test("one day advances at a constant rate and completes once after 60 active seconds", () => {
  const parameters = new ParameterTransition(schema);
  parameters.startCycle("uSunHour", 60);
  for (let second = 1; second <= 60; second++) {
    parameters.advance(1);
    const expected = second === 60 ? 7.5 : (7.5 + second * 0.4) % 24;
    assert.ok(Math.abs(parameters.values.uSunHour - expected) < 1e-10);
    assert.equal(parameters.values.uSnowLine, 1.45);
    assert.equal(parameters.cycle.finished, second === 60);
  }
  const completed = parameters.cycle;
  parameters.advance(120);
  assert.equal(parameters.cycle, completed);
  assert.equal(parameters.values.uSunHour, 7.5);
});

test("variable frame intervals and oversized final delta do not change cycle speed", () => {
  const parameters = new ParameterTransition(schema);
  parameters.startCycle("uSunHour", 60);
  parameters.advance(0.017);
  parameters.advance(0.083);
  assert.ok(Math.abs(parameters.values.uSunHour - 7.54) < 1e-10);
  parameters.advance(14.9);
  assert.equal(parameters.values.uSunHour, 13.5);
  parameters.advance(100);
  assert.equal(parameters.values.uSunHour, 7.5);
  assert.equal(parameters.cycle.elapsed, 60);
});

test("pausing finishes ordinary transitions but never jumps or finishes a day cycle", () => {
  const parameters = new ParameterTransition(schema);
  parameters.set({ uSunHour: 23.75, uSnowLine: 2 }, 2.5);
  parameters.startCycle("uSunHour", 60);
  assert.equal(parameters.values.uSnowLine, 2);
  parameters.advance(1);
  assert.ok(Math.abs(parameters.values.uSunHour - 0.15) < 1e-10);
  const paused = structuredClone(parameters.values);
  parameters.finish();
  assert.deepEqual(parameters.values, paused);
  assert.equal(parameters.cycle.finished, false);
  parameters.advance(1);
  assert.ok(Math.abs(parameters.values.uSunHour - 0.55) < 1e-10);
});

test("stopping holds the current hour and setting parameters cancels a cycle", () => {
  const parameters = new ParameterTransition(schema);
  parameters.startCycle("uSunHour", 60);
  parameters.advance(10);
  parameters.stopCycle();
  parameters.advance(10);
  assert.equal(parameters.values.uSunHour, 11.5);
  parameters.startCycle("uSunHour", 60);
  parameters.set({ uSunHour: 17.5, uSnowLine: 2.3 });
  assert.equal(parameters.cycle, null);
  parameters.advance(10);
  assert.equal(parameters.values.uSunHour, 17.5);
});

test("invalid cycle inputs preserve the active cycle", () => {
  const parameters = new ParameterTransition(schema);
  parameters.startCycle("uSunHour", 60);
  const cycle = parameters.cycle;
  for (const duration of [0, -1, NaN, Infinity]) assert.throws(() => parameters.startCycle("uSunHour", duration));
  for (const name of ["uSnowLine", "missing"]) assert.throws(() => parameters.startCycle(name, 60));
  for (const delta of [-1, NaN, Infinity]) assert.throws(() => parameters.advance(delta));
  assert.throws(() => parameters.set({ uSunHour: 25, uSnowLine: 1 }));
  assert.equal(parameters.cycle, cycle);
});

test("cycles support the 24:00 endpoint and arbitrary wrapped ranges", () => {
  const parameters = new ParameterTransition(schema);
  parameters.set({ uSunHour: 24, uSnowLine: 1 });
  parameters.startCycle("uSunHour", 60);
  parameters.advance(30);
  assert.equal(parameters.values.uSunHour, 12);
  parameters.advance(30);
  assert.equal(parameters.values.uSunHour, 24);
  const angle = new ParameterTransition({ uAngle: { type: "float", min: -180, max: 180, wrap: true, default: 90 } });
  angle.startCycle("uAngle", 60);
  angle.advance(30);
  assert.equal(angle.values.uAngle, -90);
});

test("scene time labels carry rounded minutes correctly across midnight", () => {
  assert.equal(formatSceneHour(7.5), "07:30");
  assert.equal(formatSceneHour(7.999), "08:00");
  assert.equal(formatSceneHour(23.999), "00:00");
  assert.equal(formatSceneHour(24), "00:00");
});
