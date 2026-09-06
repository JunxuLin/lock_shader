const own = (object, key) => Object.hasOwn(object, key);

export function validateParameterSchema(schema) {
  if (!schema || typeof schema !== "object" || Array.isArray(schema) || !Object.keys(schema).length) {
    throw new Error("Parameter schema must be a non-empty object.");
  }
  for (const [name, field] of Object.entries(schema)) {
    if (!/^u[A-Z][A-Za-z0-9]*$/.test(name) || !field || !["float", "vec3"].includes(field.type)) {
      throw new Error(`Invalid parameter declaration: ${name}`);
    }
    if (!Number.isFinite(field.min) || !Number.isFinite(field.max) || field.min >= field.max) {
      throw new Error(`Invalid parameter bounds: ${name}`);
    }
    if (field.wrap !== undefined && (field.wrap !== true || field.type !== "float")) {
      throw new Error(`Only float parameters support wrap: ${name}`);
    }
  }
  validateParameters(schema, parameterDefaults(schema));
}

export function parameterDefaults(schema) {
  return Object.fromEntries(Object.entries(schema).map(([name, field]) => [name,
    Array.isArray(field.default) ? [...field.default] : field.default]));
}

export function validateParameters(schema, values) {
  if (!values || typeof values !== "object" || Object.keys(values).length !== Object.keys(schema).length) {
    throw new Error("Supply one complete parameter set.");
  }
  for (const [name, field] of Object.entries(schema)) {
    const value = values[name];
    const parts = field.type === "vec3" ? value : [value];
    if (!own(values, name) || !Array.isArray(parts) || parts.length !== (field.type === "vec3" ? 3 : 1)
        || !parts.every(v => Number.isFinite(v) && v >= field.min && v <= field.max)) {
      throw new Error(`Invalid parameter value: ${name}`);
    }
  }
  return values;
}

export function validateState(controls, state) {
  if (!state || typeof state !== "object" || Object.keys(state).length !== Object.keys(controls).length) {
    throw new Error("Supply one complete scene state.");
  }
  for (const [name, control] of Object.entries(controls)) {
    const value = state[name];
    if (!own(state, name) || (control.type === "enum"
      ? !control.options.includes(value)
      : !Number.isFinite(value) || value < control.min || value > control.max)) {
      throw new Error(`Invalid scene setting: ${name}`);
    }
    if (control.type === "number") {
      const steps = (value - control.min) / control.step;
      if (Math.abs(steps - Math.round(steps)) > 0.000001) throw new Error(`Invalid scene step: ${name}`);
    }
  }
  return state;
}

export function defaultState(controls) {
  return Object.fromEntries(Object.entries(controls).map(([key, control]) => [key, control.default]));
}

export function stateFromURL(controls, url) {
  const state = defaultState(controls);
  const issues = [];
  for (const [key, control] of Object.entries(controls)) {
    const raw = url.searchParams.get(key);
    if (raw === null) continue;
    const value = control.type === "number" && raw.trim() !== "" ? Number(raw) : raw;
    try {
      validateState(controls, { ...state, [key]: value });
      state[key] = value;
    } catch {
      issues.push(`Invalid ${key} in URL; using ${control.default}.`);
    }
  }
  return { state, issues };
}

export function stateToURL(controls, state, url) {
  validateState(controls, state);
  const result = new URL(url);
  for (const [key, value] of Object.entries(state)) result.searchParams.set(key, String(value));
  return result;
}

export class ParameterTransition {
  constructor(schema) {
    this.schema = schema;
    this.values = parameterDefaults(schema);
    this.target = structuredClone(this.values);
    this.duration = 0;
    this.elapsed = 0;
  }
  set(values, duration = 0) {
    validateParameters(this.schema, values);
    if (!Number.isFinite(duration) || duration < 0) throw new Error("Invalid transition duration.");
    this.start = structuredClone(this.values);
    this.target = structuredClone(values);
    this.elapsed = 0;
    this.duration = duration;
    if (!duration) this.finish();
  }
  finish() {
    this.values = structuredClone(this.target);
    this.duration = 0;
  }
  advance(delta) {
    if (!this.duration) return;
    this.elapsed += delta;
    if (this.elapsed >= this.duration) return this.finish();
    const fraction = this.elapsed / this.duration;
    const weight = fraction * fraction * (3 - 2 * fraction);
    for (const [name, field] of Object.entries(this.schema)) {
      const from = this.start[name], to = this.target[name];
      if (field.type === "vec3") {
        this.values[name] = from.map((v, i) => v + (to[i] - v) * weight);
      } else if (field.wrap) {
        const period = field.max - field.min;
        const difference = ((to - from + period * 1.5) % period) - period * 0.5;
        this.values[name] = ((from - field.min + difference * weight + period) % period) + field.min;
      } else {
        this.values[name] = from + (to - from) * weight;
      }
    }
  }
}
