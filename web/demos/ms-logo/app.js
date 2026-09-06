import { createPlayer } from "../../runtime/player.js";
import { bindFullscreen, bindPlayback, showError, startClock } from "../../runtime/ui.js";

const motion = document.querySelector("#motion");
const clock = document.querySelector("#clock-toggle");
const replay = document.querySelector("#replay");
const fullscreen = document.querySelector("#fullscreen");
startClock();
bindFullscreen(fullscreen);
clock.addEventListener("click", () => {
  const hidden = document.querySelector(".clock").classList.toggle("hidden");
  clock.setAttribute("aria-pressed", String(!hidden));
});

async function start() {
  const player = await createPlayer(document.querySelector("canvas"), new URL("../../../glsl/ms-logo/scene.json", import.meta.url));
  document.querySelector("#download").href = player.sourceUrl.href;
  bindPlayback(player, motion, document.querySelector("#motion-status"), document.querySelector("#motion-time"));
  replay.disabled = false;
  replay.addEventListener("click", () => player.restart());
  document.addEventListener("keydown", event => {
    if (event.metaKey || event.ctrlKey || event.altKey || event.repeat) return;
    if (event.target.closest("input, textarea, select, [contenteditable]")) return;
    const controls = { Space: motion, KeyH: clock, KeyR: replay, KeyF: fullscreen };
    if (event.code === "Space" && event.target.closest("button, a")) return;
    const button = controls[event.code];
    if (button && !button.hidden) {
      event.preventDefault();
      button.click();
    }
  });
}
start().catch(error => {
  showError(error);
  document.querySelector("#motion-status").textContent = "RENDERING UNAVAILABLE";
});
