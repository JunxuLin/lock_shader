import { validateState, validateParameters } from "../../web/runtime/parameters.js";

// No DOM, WebGL or mutable state: the same selection always produces the same frame parameters.
export function resolveFujiParameters(state, scene, profiles) {
  validateState(scene.controls, state);
  const season = profiles.seasons?.[state.season];
  const weather = profiles.weather?.[state.weather];
  if (!season || !weather) throw new Error("Missing Fuji season or weather profile.");
  return validateParameters(scene.parameters, {
    uSunHour: state.timeOfDay,
    uSnowLine: season.snowLine,
    uSnowCoverage: season.snowCoverage,
    uFoliageColor: [...season.foliageColor],
    uCloudCoverage: weather.cloudCoverage,
    uFogDensity: weather.fogDensity,
    uWind: weather.wind,
  });
}
