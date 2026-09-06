import { validateState, validateParameters } from "../../web/runtime/parameters.js";

export function resolveSeaCaveParameters(state, scene, profiles) {
  validateState(scene.controls, state);
  const weather = profiles.weather?.[state.weather];
  const sea = profiles.seaStates?.[state.seaState];
  if (!weather || !sea) throw new Error("Missing Sea Cave weather or sea-state profile.");
  return validateParameters(scene.parameters, {
    uSunHour: state.timeOfDay,
    uCloudCoverage: weather.cloudCoverage,
    uFogDensity: weather.fogDensity,
    uWind: weather.wind,
    uWaveStrength: sea.waveStrength,
  });
}
