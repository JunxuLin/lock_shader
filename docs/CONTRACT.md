# Shader contracts v1 and v2

The GLSL is the portable effect. The browser is one host, not part of the shader.
No shared GLSL includes, bundler, textures, buffer passes or external services are
required. This deliberately small contract should remain easy to paste into Shadertoy.

## Entry point

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Always assign all four channels; output opaque display-ready RGB and alpha 1.
}
```

Target GLSL ES 3.00 / WebGL 2. Do not declare `#version`, `main`, uniforms or fragment
outputs: the host supplies them. Source is UTF-8 text in `glsl/<id>/main.glsl`.
Coordinates start at the bottom-left. No `discard`, texture channels or multipass
dependencies in v1. The host performs no extra tone mapping or gamma conversion.

| Uniform | Type | Meaning |
|---|---|---|
| `iResolution` | `vec3` | Actual framebuffer width, height, pixel aspect ratio (1), not CSS pixels |
| `iTime` | `float` | Active animation seconds plus `initialTime`; freezes when paused, hidden or suspended |
| `iMouse` | `vec4` | Damped pointer position in framebuffer pixels; z=1 when pointer interaction is enabled, otherwise 0; w=0 |

**Mouse compatibility:** v1 uses hover with spring smoothing, NOT Shadertoy's stored
click-origin semantics. In Shadertoy, the logo's `iMouse.z > 0` guard means hold/drag.
In the website it follows hover. Disabled/reduced-motion interaction produces z=0.
Shaders must look complete with no pointer input.

## Scene manifest

Each scene owns a `scene.json` next to its source; `glsl/index.json` lists gallery ids.
`web/runtime/contract.js` validates metadata in both the browser and Node tests.

```json
{
  "contractVersion": 1,
  "id": "my-scene",
  "title": "My scene",
  "description": "What it looks like.",
  "source": "main.glsl",
  "initialTime": 0,
  "posterTime": 8,
  "pointer": false,
  "performance": {
    "fps": 30,
    "maxPixels": 1500000,
    "minPixels": 650000,
    "maxDpr": 1.5
  },
  "tags": ["Landscape"],
  "attribution": "Source, author, license and trademark notes."
}
```

`id` must match its kebab-case directory. `posterTime >= initialTime` selects a
complete, non-black frame when reduced motion is enabled. `fps` is 30 or 60;
frame rate is a target, not a hardware guarantee. Pixel budgets adapt downward
on sustained slow frames. They are independent of the shader's coordinate system.

## Host responsibilities

- Fetch metadata/source, compile/link with visible errors, create a full-screen triangle.
- Update uniforms; pause on hidden tabs and modal overlays without a catch-up jump.
- Respect `prefers-reduced-motion`; explicitly pressing Play overrides initial pause.
- Display the actual playback state and an active animation clock.
- Scale the framebuffer to DPR and pixel budgets; maintain aspect ratio.
- Preserve damped hover for pointer scenes; freeze it when paused.
- Release listeners/GPU program on `dispose()`. Context loss stops playback and
  reports a reload-required error rather than pretending to recover.
- Keep clock, navigation, reference photography and keyboard controls in HTML/CSS.

`createPlayer(canvas, manifestUrl)` returns an EventTarget with `state`, `scene`,
`sourceUrl`, `toggle()`, `restart()`, `setSuspended(reason, boolean)` and `dispose()`.
Events are `statechange` (state), `timechange` (integer active seconds relative to
initialTime), and `error` (Error). Subscribe after creation, then render current state.
The current host assumes one full-screen player per demo page.

## Adding a study

1. Add `glsl/<id>/main.glsl` and `scene.json`; register the id in `glsl/index.json`.
2. Add `web/demos/<id>/index.html`, a theme stylesheet and a small UI adapter.
3. Use `createPlayer` instead of copying a WebGL render loop.
4. Add an original `web/assets/<id>.jpg` poster; the gallery never starts background shaders.
5. Add any asset attribution separately; do not assume Shadertoy code is reusable.
6. Run `npm test`, `npm run build`, then inspect real playback, mobile layout and
   reduced motion in a browser. Test under `/lock_shader/`, not only domain root.

## Future contract versions

Consider explicit texture channel descriptors, bounded parameter schemas, quality
tiers, deterministic capture controls and multi-pass render graphs only when a
scene needs them. Texture color spaces, buffer sizes, feedback lifetimes and
resource disposal would need explicit contracts. Do not silently extend v1.

## Contract v2: configurable scenes

v1 remains supported unchanged (Suspended Glass). Fuji uses v2, which adds
`controls`, `presets`, `parameters` and `transitionSeconds` to its manifest.

The separation is:

```text
HTML controls / URL -> complete semantic state
                   -> pure scene resolver + data profiles
                   -> complete typed uniform set
                   -> player transitions -> GLSL
```

`scenes/fuji-mountain/resolve.js` has no DOM/WebGL dependencies; it recomputes the
entire result from state and `profiles.json`. Season owns snow and vegetation,
weather owns clouds/fog/wind, and scene time owns the sun hour. Selection order
does not affect output. The player knows nothing about seasons or weather.

### Parameters

Each `uCapitalizedName` declares `type` (`float` or `vec3`), finite `min`/`max`,
and a `default` within those bounds. vec3 bounds apply to each component.
All color vectors are **linear RGB**, not CSS/sRGB colors. The host injects the
declarations and defines `LOCK_SHADER_PARAMETERS` before compiling source.

`float` fields may set `wrap: true` to interpolate by the shortest path over
`[min,max)`. Fuji's `uSunHour` crosses 23:00 -> 01:00 through midnight, not noon.
The shader derives a normalized light direction and daylight from this hour,
avoiding interpolation of opposing direction vectors.

`createPlayer(canvas, manifestUrl, { parameters })` validates and installs initial
values before the first draw. `player.setParameters(fullSet, { immediate: false })`
validates the entire set atomically. Unknown/missing/out-of-range values throw.
Transitions use smoothstep easing for `transitionSeconds` (0..10 seconds), retain
continuity when retargeted, and never reset `iTime`. Colors interpolate in linear RGB.

When paused/reduced-motion/suspended, new settings apply immediately. Pausing or
enabling reduced motion finishes any pending parameter transition; hidden tabs and
reference modals freeze an existing transition until resumed. The animation clock
continues to describe cloud/water time, not the selected scene hour.

### Controls and presets

Controls use `enum` (options/default) or `number` (min/max/step/default). `label` is
UI metadata. Presets have an id, label and a complete semantic `values` object.
The generic UI renders these declarations; scenes without controls get no panel.
No executable expressions or arbitrary shader code are accepted in metadata.

URL state stores only semantic values, preserving other query keys and hashes.
Missing fields use defaults. Invalid fields show a visible notice and use their
individual defaults. Browser history restoration updates both UI and renderer.
Actual system clock, selected scene time, and active `iTime` are independent.

### Standalone source

v2 sources retain typed constants inside `#ifndef LOCK_SHADER_PARAMETERS` for direct
Shadertoy use. The website injects uniforms instead. Raw GLSL download shows the
default scene, not the current URL selection; edit fallback constants to customize
it outside this host. No channels or textures are introduced by v2.
