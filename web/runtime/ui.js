export function startClock(dateLocale) {
  const clock = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit", hour12: false });
  const date = new Intl.DateTimeFormat(dateLocale, { weekday: "long", month: "long", day: "numeric" });
  function update() {
    const now = new Date();
    const element = document.querySelector("#time");
    element.textContent = clock.format(now);
    element.dateTime = now.toISOString();
    document.querySelector("#date").textContent = date.format(now);
  }
  update();
  const timer = setInterval(update, 1000);
  return () => clearInterval(timer);
}

export function showError(error) {
  console.error(error);
  const panel = document.querySelector("#error");
  panel.textContent = error instanceof Error ? error.message : String(error);
  panel.hidden = false;
}

export function bindFullscreen(button) {
  button.hidden = !document.fullscreenEnabled;
  button.addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen();
    } catch (error) {
      showError(error);
    }
  });
  document.addEventListener("fullscreenchange", () => {
    button.textContent = document.fullscreenElement ? "Exit fullscreen" : "Fullscreen";
  });
}

export function bindPlayback(player, button, status, clock) {
  const messages = {
    playing: "PLAYING",
    user: "PAUSED / PRESS PLAY",
    "reduced-motion": "REDUCED MOTION / PRESS PLAY",
    reference: "PAUSED / VIEWING REFERENCE",
    hidden: "PAUSED / TAB HIDDEN",
    "context-lost": "RENDERING UNAVAILABLE",
    disposed: "PLAYER CLOSED",
  };
  function update() {
    const state = player.state;
    button.textContent = state.paused ? "Play" : "Pause";
    button.setAttribute("aria-pressed", String(state.paused));
    button.disabled = ["context-lost", "disposed"].includes(state.reason);
    status.textContent = messages[state.reason] || `PAUSED / ${state.reason}`;
    status.parentElement.dataset.state = state.playing ? "playing" : "paused";
  }
  function updateTime(second) {
    if (clock) clock.textContent = `${String(Math.floor(second / 60)).padStart(2, "0")}:${String(second % 60).padStart(2, "0")}`;
  }
  player.addEventListener("statechange", update);
  player.addEventListener("timechange", event => updateTime(event.detail));
  player.addEventListener("error", event => showError(event.detail));
  button.addEventListener("click", () => player.toggle());
  updateTime(Math.floor(player.time - player.scene.initialTime));
  update();
}
