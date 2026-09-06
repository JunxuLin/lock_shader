# Shader contract v1

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
