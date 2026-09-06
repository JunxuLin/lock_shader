import { createPlayer } from "../../runtime/player.js";
import { bindFullscreen, bindPlayback, showError, startClock } from "../../runtime/ui.js";

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
clean.addEventListener("click", toggleInterface);
restore.addEventListener("click", toggleInterface);
document.querySelector("#reference").addEventListener("click", () => dialog.showModal());
document.querySelector("#close-reference").addEventListener("click", () => dialog.close());

async function start() {
  const player = await createPlayer(document.querySelector("canvas"), new URL("../../../glsl/fuji-mountain/scene.json", import.meta.url));
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
    } else if (event.code === "Space" && !event.target.closest("button, a")) {
      event.preventDefault();
      player.toggle();
    }
  });
}
start().catch(error => {
  showError(error);
  document.querySelector("#motion-status").textContent = "RENDERING UNAVAILABLE";
});
