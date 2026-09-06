import { createPlayer } from "../../runtime/player.js";
import { bindFullscreen, bindPlayback, showError, startClock } from "../../runtime/ui.js";
import { loadScene } from "../../runtime/contract.js";
import { stateFromURL } from "../../runtime/parameters.js";
import { mountControls } from "../../runtime/controls.js";
import { mountDayPreview } from "../../runtime/day-preview.js";
import { resolveSeaCaveParameters } from "../../../scenes/sea-cave/resolve.js";

const motion = document.querySelector("#motion");
const clean = document.querySelector("#clean");
const restore = document.querySelector("#restore");
const fullscreen = document.querySelector("#fullscreen");
const dialog = document.querySelector("#reference-dialog");
startClock("en");
bindFullscreen(fullscreen);

function toggleInterface() {
  const hidden = document.body.classList.toggle("clean");
  clean.setAttribute("aria-pressed", String(hidden));
  restore.hidden = !hidden;
  (hidden ? restore : clean).focus({ preventScroll: true });
}
function updateSceneNote(state) {
  document.querySelector(".clock-note").textContent = `${state.weather.toUpperCase()} / ${state.seaState.toUpperCase()} SEA`;
}
clean.addEventListener("click", toggleInterface);
restore.addEventListener("click", toggleInterface);
document.querySelector("#reference").addEventListener("click", () => dialog.showModal());
document.querySelector("#close-reference").addEventListener("click", () => dialog.close());

async function start() {
  const manifestUrl = new URL("../../../glsl/sea-cave/scene.json", import.meta.url);
  const scene = await loadScene(manifestUrl);
  const response = await fetch(new URL("profiles.json", manifestUrl));
  if (!response.ok) throw new Error(`Unable to load Sea Cave profiles: HTTP ${response.status}`);
  const profiles = await response.json();
  const resolve = state => resolveSeaCaveParameters(state, scene, profiles);
  const initial = stateFromURL(scene.controls, new URL(location.href)).state;
  const player = await createPlayer(document.querySelector("canvas"), manifestUrl, { parameters: resolve(initial) });
  let dayPreview;
  const controls = mountControls(document.querySelector("#scene-controls"), scene, (state, options) => {
    dayPreview?.cancel();
    player.setParameters(resolve(state), options);
    updateSceneNote(state);
  });
  dayPreview = mountDayPreview(player, scene, controls, updateSceneNote);
  document.querySelector("#download").href = player.sourceUrl.href;
  bindPlayback(player, motion, document.querySelector("#motion-status"), document.querySelector("#motion-time"));
  const syncDialog = () => player.setSuspended("reference", dialog.open);
  new MutationObserver(syncDialog).observe(dialog, { attributes: true, attributeFilter: ["open"] });
  syncDialog();
  document.addEventListener("keydown", event => {
    if (event.metaKey || event.ctrlKey || event.altKey || event.repeat || dialog.open) return;
    if (event.target.closest("input, textarea, select, [contenteditable]")) return;
    if (event.code === "KeyH") {
      event.preventDefault();
      toggleInterface();
    } else if (event.code === "KeyF" && !fullscreen.hidden) {
      event.preventDefault();
      fullscreen.click();
    } else if (event.code === "Space" && !event.target.closest("button, a, summary")) {
      event.preventDefault();
      player.toggle();
    }
  });
}
start().catch(error => {
  showError(error);
  document.querySelector("#motion-status").textContent = "RENDERING UNAVAILABLE";
});
