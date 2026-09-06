import { loadScene } from "./contract.js";
import { ParameterTransition } from "./parameters.js";

function createProgram(gl, source, scene) {
  const shaders = [];
  const program = gl.createProgram();
  try {
    for (const [type, code] of [
      [gl.VERTEX_SHADER, `#version 300 es
        void main() {
          vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
          gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }`],
      [gl.FRAGMENT_SHADER, `#version 300 es
        precision highp float;
        uniform vec3 iResolution;
        uniform float iTime;
        uniform vec4 iMouse;
        ${scene.contractVersion === 2 ? "#define LOCK_SHADER_PARAMETERS\n" + Object.entries(scene.parameters)
          .map(([name, field]) => `uniform ${field.type} ${name};`).join("\n") : ""}
        out vec4 outputColor;
        #line 1
        ${source}
        void main() { mainImage(outputColor, gl_FragCoord.xy); }`],
    ]) {
      const shader = gl.createShader(type);
      shaders.push(shader);
      gl.shaderSource(shader, code);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error(`Shader compilation failed:\n${gl.getShaderInfoLog(shader)}`);
      }
      gl.attachShader(program, shader);
    }
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(`Shader link failed:\n${gl.getProgramInfoLog(program)}`);
    }
    return program;
  } catch (error) {
    gl.deleteProgram(program);
    throw error;
  } finally {
    for (const shader of shaders) gl.deleteShader(shader);
  }
}

export async function createPlayer(canvas, manifestUrl, options = {}) {
  const scene = await loadScene(manifestUrl);
  const sourceUrl = new URL(scene.source, manifestUrl);
  const response = await fetch(sourceUrl, { cache: "no-store" });
  if (!response.ok) throw new Error(`Unable to load GLSL: HTTP ${response.status} (${sourceUrl})`);
  const source = await response.text();
  const gl = canvas.getContext("webgl2", { alpha: false, antialias: false, depth: false });
  if (!gl) throw new Error("WebGL 2 is unavailable. Enable browser hardware acceleration.");
  const parameters = scene.contractVersion === 2 ? new ParameterTransition(scene.parameters) : null;
  if (options.parameters) {
    if (!parameters) throw new Error("Parameters require contract v2.");
    parameters.set(options.parameters);
  }
  const program = createProgram(gl, source, scene);
  return new ShaderPlayer(canvas, gl, program, scene, sourceUrl, parameters);
}

class ShaderPlayer extends EventTarget {
  constructor(canvas, gl, program, scene, sourceUrl, parameters) {
    super();
    this.canvas = canvas;
    this.gl = gl;
    this.program = program;
    this.scene = scene;
    this.sourceUrl = sourceUrl;
    this.parameters = parameters;
    this.motionPreference = matchMedia("(prefers-reduced-motion: reduce)");
    this.paused = this.motionPreference.matches;
    this.pauseReason = this.paused ? "reduced-motion" : "user";
    this.time = this.paused ? scene.posterTime : scene.initialTime;
    this.suspensions = new Set();
    this.frame = 0;
    this.lastDraw = -Infinity;
    this.previous = performance.now();
    this.contextLost = false;
    this.disposed = false;
    this.pixelBudget = scene.performance.maxPixels;
    this.slowWindows = 0;
    this.samples = 0;
    this.cost = 0;
    this.lastSecond = -1;
    this.pointer = { x: 0, y: 0, vx: 0, vy: 0, targetX: 0, targetY: 0 };
    this.listeners = new AbortController();
    const options = { signal: this.listeners.signal };
    gl.useProgram(program);
    this.uniforms = Object.fromEntries(["iTime", "iResolution", "iMouse"].map(name => [name, gl.getUniformLocation(program, name)]));
    this.parameterUniforms = Object.fromEntries(Object.keys(scene.parameters || {}).map(name => [name, gl.getUniformLocation(program, name)]));
    window.addEventListener("resize", () => this.resize(), options);
    document.addEventListener("visibilitychange", () => this.sync(), options);
    window.addEventListener("pageshow", () => this.sync(), options);
    this.motionPreference.addEventListener("change", () => {
      this.paused = this.motionPreference.matches;
      this.pauseReason = this.paused ? "reduced-motion" : "user";
      if (this.paused) {
        this.parameters?.finish();
        this.time = Math.max(this.time, scene.posterTime);
        Object.keys(this.pointer).forEach(key => { this.pointer[key] = 0; });
        this.draw();
      }
      this.sync();
    }, options);
    window.addEventListener("pointermove", event => {
      if (!scene.pointer || this.motionPreference.matches || this.paused) return;
      const bounds = canvas.getBoundingClientRect();
      this.pointer.targetX = Math.max(-1, Math.min(1, (event.clientX - bounds.left) / bounds.width * 2 - 1));
      this.pointer.targetY = Math.max(-1, Math.min(1, 1 - (event.clientY - bounds.top) / bounds.height * 2));
    }, { ...options, passive: true });
    document.documentElement.addEventListener("pointerleave", () => {
      this.pointer.targetX = this.pointer.targetY = 0;
    }, options);
    canvas.addEventListener("webglcontextlost", event => {
      event.preventDefault();
      this.contextLost = true;
      canvas.dataset.ready = "false";
      this.sync();
      this.dispatchEvent(new CustomEvent("error", { detail: new Error("Graphics context lost. Reload this page to resume.") }));
    }, options);
    this.resize();
    this.sync();
    canvas.dataset.ready = "true";
  }

  get state() {
    const reason = this.disposed ? "disposed" : this.contextLost ? "context-lost"
      : this.paused ? this.pauseReason : document.hidden ? "hidden"
      : this.suspensions.size ? [...this.suspensions][0] : "playing";
    return { reason, playing: reason === "playing", paused: this.paused, time: this.time };
  }

  toggle() {
    this.paused = !this.paused;
    if (this.paused) {
      this.parameters?.finish();
      this.draw();
    }
    this.pauseReason = "user";
    this.sync();
  }

  restart() {
    this.paused = this.motionPreference.matches;
    this.pauseReason = this.paused ? "reduced-motion" : "user";
    this.time = this.paused ? this.scene.posterTime : this.scene.initialTime;
    this.draw();
    this.sync();
  }

  setSuspended(reason, suspended) {
    if (suspended) this.suspensions.add(reason);
    else this.suspensions.delete(reason);
    this.sync();
  }

  setParameters(values, { immediate = false } = {}) {
    if (!this.parameters) throw new Error("Parameters require contract v2.");
    if (this.disposed || this.contextLost) throw new Error("Player is unavailable.");
    const duration = immediate || !this.state.playing || this.motionPreference.matches ? 0 : this.scene.transitionSeconds;
    this.parameters.set(values, duration);
    this.draw();
  }

  sync() {
    cancelAnimationFrame(this.frame);
    this.previous = performance.now();
    this.samples = this.cost = 0;
    this.dispatchEvent(new CustomEvent("statechange", { detail: this.state }));
    if (this.state.playing) this.frame = requestAnimationFrame(now => this.tick(now));
  }

  draw() {
    if (this.contextLost || this.disposed) return;
    const { gl, canvas, uniforms } = this;
    gl.uniform3f(uniforms.iResolution, canvas.width, canvas.height, 1);
    gl.uniform1f(uniforms.iTime, this.time);
    if (this.parameters) {
      for (const [name, value] of Object.entries(this.parameters.values)) {
        const location = this.parameterUniforms[name];
        if (this.scene.parameters[name].type === "vec3") gl.uniform3fv(location, value);
        else gl.uniform1f(location, value);
      }
    }
    // Contract v1 uses damped hover, not Shadertoy's click-origin mouse semantics.
    gl.uniform4f(uniforms.iMouse,
      (this.pointer.x * 0.5 + 0.5) * canvas.width,
      (this.pointer.y * 0.5 + 0.5) * canvas.height,
      this.scene.pointer && !this.motionPreference.matches ? 1 : 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    const second = Math.floor(this.time - this.scene.initialTime);
    if (second !== this.lastSecond) {
      this.lastSecond = second;
      this.dispatchEvent(new CustomEvent("timechange", { detail: second }));
    }
  }

  resize() {
    if (this.disposed || this.contextLost) return;
    const { width, height } = this.canvas.getBoundingClientRect();
    if (!width || !height) return;
    const scale = Math.min(devicePixelRatio || 1, this.scene.performance.maxDpr, Math.sqrt(this.pixelBudget / (width * height)));
    this.canvas.width = Math.max(1, Math.round(width * scale));
    this.canvas.height = Math.max(1, Math.round(height * scale));
    this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    this.draw();
  }

  tick(now) {
    if (!this.state.playing) return;
    const delta = Math.max(0, (now - this.previous) / 1000);
    this.previous = now;
    this.time += delta;
    this.parameters?.advance(delta);
    const p = this.pointer;
    const integrationTime = Math.min(delta, 0.1);
    const steps = Math.max(1, Math.ceil(integrationTime * 120));
    const step = integrationTime / steps;
    for (let i = 0; i < steps; i++) {
      p.vx += ((p.targetX - p.x) * 65 - p.vx * 13) * step;
      p.vy += ((p.targetY - p.y) * 65 - p.vy * 13) * step;
      p.x += p.vx * step;
      p.y += p.vy * step;
    }
    this.cost += delta;
    if (++this.samples === 120) {
      this.slowWindows = this.cost / this.samples > 1.25 / this.scene.performance.fps ? this.slowWindows + 1 : 0;
      if (this.slowWindows >= 2 && this.pixelBudget > this.scene.performance.minPixels) {
        this.pixelBudget = Math.max(this.scene.performance.minPixels, Math.round(this.pixelBudget * 0.75));
        this.resize();
        this.slowWindows = 0;
      }
      this.samples = this.cost = 0;
    }
    if (now - this.lastDraw >= 1000 / this.scene.performance.fps - 1) {
      this.draw();
      this.lastDraw = now;
    }
    this.frame = requestAnimationFrame(next => this.tick(next));
  }

  dispose() {
    this.disposed = true;
    this.sync();
    this.listeners.abort();
    this.gl.deleteProgram(this.program);
    this.canvas.dataset.ready = "false";
  }
}
