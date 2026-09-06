export function formatSceneHour(hour) {
  const minutes = Math.round(hour * 60) % 1440;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

export function mountDayPreview(player, scene, controls, updateReferences) {
  const button = document.querySelector("#day-preview");
  const progress = document.querySelector("#day-preview-progress");
  const status = document.querySelector("#day-preview-status");
  const timeOutput = document.querySelector('output[for="scene-timeOfDay"]');
  let active = false;
  let restorePaused = false;
  let lastUpdate = -Infinity;
  let latestCycle = null;

  function syncPlayback() {
    const state = player.state;
    button.disabled = ["context-lost", "disposed"].includes(state.reason);
    if (button.disabled) {
      cancel();
      status.textContent = "Day preview unavailable. Reload the page to resume.";
      return;
    }
    if (active) {
      status.textContent = state.playing ? "Previewing one day. Clouds and water keep their normal speed."
        : "Day preview paused; it will continue with playback.";
    }
  }

  function cancel() {
    if (!active) return;
    active = false;
    player.stopParameterCycle();
    if (restorePaused && !player.state.paused) player.toggle();
    button.textContent = "Preview day / 60s";
    button.setAttribute("aria-pressed", "false");
    progress.value = "";
    status.textContent = "Day preview stopped.";
  }

  function finish(message) {
    const state = controls.state;
    cancel();
    controls.setState(state, { immediate: true });
    status.textContent = `${message} at ${formatSceneHour(state.timeOfDay)}.`;
  }

  player.addEventListener("parametercyclechange", event => {
    const cycle = event.detail;
    if (!active || !cycle) return;
    latestCycle = cycle;
    if (!cycle.finished && cycle.elapsed - lastUpdate < 0.1) return;
    lastUpdate = cycle.elapsed;
    const step = scene.controls.timeOfDay.step;
    const hour = Math.round(cycle.value / step) * step;
    if (controls.state.timeOfDay !== hour) {
      const state = { ...controls.state, timeOfDay: hour };
      controls.setState(state, { notify: false, writeURL: false });
      updateReferences(state);
    }
    timeOutput.value = formatSceneHour(cycle.value);
    progress.value = `${formatSceneHour(cycle.value)} / ${Math.floor(cycle.elapsed)} of 60s`;
    if (cycle.finished) finish("Day preview finished");
  });
  player.addEventListener("statechange", syncPlayback);
  button.addEventListener("click", () => {
    if (active) {
      // Persist the precise current frame rounded to the URL/control's 15-minute grid.
      const step = scene.controls.timeOfDay.step;
      controls.setState({ ...controls.state, timeOfDay: Math.round(latestCycle.value / step) * step },
        { notify: false, writeURL: false });
      finish("Day preview stopped");
      return;
    }
    restorePaused = player.state.paused;
    active = true;
    lastUpdate = -Infinity;
    button.textContent = "Stop day preview";
    button.setAttribute("aria-pressed", "true");
    player.startParameterCycle("uSunHour", 60);
    if (player.state.paused) player.toggle();
    syncPlayback();
  });
  syncPlayback();
  return { cancel };
}
