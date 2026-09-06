import { defaultState, stateFromURL, stateToURL, validateState } from "./parameters.js";

export function mountControls(container, scene, onChange) {
  let state = defaultState(scene.controls);
  const fields = new Map();
  const form = document.createElement("div");
  form.className = "scene-fields";
  const presetLabel = document.createElement("label");
  presetLabel.textContent = "Preset";
  const presets = document.createElement("select");
  presets.id = "scene-preset";
  presets.add(new Option("Custom", ""));
  for (const preset of scene.presets) presets.add(new Option(preset.label, preset.id));
  presetLabel.append(presets);
  form.append(presetLabel);
  for (const [key, control] of Object.entries(scene.controls)) {
    const label = document.createElement("label");
    label.textContent = control.label;
    const field = document.createElement(control.type === "enum" ? "select" : "input");
    field.id = `scene-${key}`;
    if (control.type === "enum") {
      for (const option of control.options) field.add(new Option((option[0].toUpperCase() + option.slice(1)).replaceAll("-", " "), option));
    } else {
      field.type = "range";
      field.min = control.min;
      field.max = control.max;
      field.step = control.step;
    }
    label.append(field);
    const output = document.createElement("output");
    output.htmlFor = field.id;
    if (control.type === "number") label.append(output);
    fields.set(key, { field, output });
    field.addEventListener("input", () => {
      apply({ ...state, [key]: control.type === "number" ? Number(field.value) : field.value });
    });
    form.append(label);
  }
  const notice = document.createElement("p");
  notice.className = "scene-notice";
  notice.setAttribute("role", "status");
  const hint = document.createElement("p");
  hint.textContent = "Scene time changes the light, not the clock. Copy the page URL to share this selection.";
  hint.className = "scene-hint";
  container.append(form, notice, hint);
  function apply(next, { writeURL = true, immediate = false, notify = true } = {}) {
    validateState(scene.controls, next);
    if (notify) onChange(next, { immediate });
    state = { ...next };
    for (const [key, { field, output }] of fields) {
      field.value = String(state[key]);
      if (scene.controls[key].type === "number") {
        output.value = key === "timeOfDay"
          ? `${String(Math.floor(state[key])).padStart(2, "0")}:${String(Math.round(state[key] % 1 * 60)).padStart(2, "0")}`
          : String(state[key]);
      }
    }
    presets.value = scene.presets.find(p => Object.keys(state).every(key => p.values[key] === state[key]))?.id || "";
    notice.textContent = "";
    if (writeURL) history.replaceState(null, "", stateToURL(scene.controls, state, new URL(location.href)));
  }
  presets.addEventListener("change", () => {
    const preset = scene.presets.find(p => p.id === presets.value);
    if (preset) apply(preset.values);
  });
  function restore() {
    const parsed = stateFromURL(scene.controls, new URL(location.href));
    apply(parsed.state, { writeURL: false, immediate: true });
    notice.textContent = parsed.issues.join(" ");
  }
  window.addEventListener("popstate", restore);
  restore();
  return { get state() { return { ...state }; }, setState: apply };
}
