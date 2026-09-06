# Lock Shader

Original GLSL lockscreen studies with a lightweight, framework-free WebGL 2 gallery.

**Gallery:** https://JunxuLin.github.io/lock_shader/

- **Fuji 1:** preserved stylized edition, with configurable seasons, weather and scene time.
- **Fuji 2:** independently forked photographic-reference study, with source photographs and explicit evidence gaps.
- **MS Logo:** unofficial Microsoft logo study with extruded glass, spring entrance and pointer parallax.

These are visual experiments, not operating-system locks. The Fuji landscape is
a procedural interpretation, not a photograph or geographically accurate model.

## Layout

```text
glsl/
  index.json                  Gallery registry
  fuji-mountain/
    main.glsl                 Preserved Fuji 1 standalone effect
    scene.json                Metadata + runtime contract
    profiles.json             Season/weather visual profiles (Fuji)
  fuji2/                      Independent shader, manifest and visual profiles
  ms-logo/
    main.glsl
    scene.json
web/
  index.html                  Gallery
  assets/                     Static demo posters; no live gallery render loops
  runtime/                    Shared WebGL player, contract validation and UI helpers
  demos/
    fuji-mountain/            HTML/CSS + thin UI adapter + licensed photo reference
    fuji2/                    Independent demo + photographic-reference catalog
    ms-logo/                  HTML/CSS + thin UI adapter
docs/CONTRACT.md               Uniforms, metadata, lifecycle and extension rules
scenes/fuji-mountain/resolve.js Pure state-to-parameter mapping (no DOM/WebGL)
scenes/fuji2/resolve.js        Independent Fuji 2 state-to-parameter mapping
scripts/build.mjs             Stages only public files into _site/
tests/                        Node built-in contract tests
.github/workflows/pages.yml   Validate, build and deploy
```

GLSL never depends on DOM, photography or per-demo JavaScript. Each demo keeps its
visual identity while sharing compilation, animation, pause states, reduced-motion
handling, pointer smoothing and resolution budgets. See [the v1/v2 contract](docs/CONTRACT.md).

## Configurable Fuji

Open **Season, weather & light** in either Fuji demo. Choose spring/summer/autumn/winter,
clear/cloudy/fog, or a scene time from 00:00 to 24:00. Presets include winter morning,
spring mist, summer noon, autumn sunset and winter night. Rain/snow particles are
not implemented; snow cover is independent of weather.

Selections update the URL, so copy the address to share:

`web/demos/fuji-mountain/?season=winter&weather=clear&timeOfDay=7.5`

The HTML clock still shows local system time. The landscape holds the selected
lighting while clouds/water animate independently. Parameter changes ease over
2.5 seconds without restarting animation; paused or reduced-motion players update
immediately. Invalid URL values show a warning and use the relevant default.
The astronomical lighting and seasonal vegetation are artistic approximations,
not a date/location-based solar simulation.

**Fuji 2 day preview:** open **Season, weather & light**, then select
**Preview day / 60s**. One complete 24-hour cycle starts at the selected scene hour
and advances at a constant rate: one real second represents 24 scene minutes.
Clouds, water and the system clock keep their normal speed. The scene hour moves
continuously, without the usual parameter easing or extra rendering loop.

Pause, hidden tabs and the reference dialog freeze preview progress rather than
skipping ahead. Explicitly starting a preview also starts a paused/reduced-motion
player. If it started from pause, finishing or stopping returns to pause; otherwise
the current Play/Pause choice is kept. The preview runs
once and returns to the starting hour. **Stop day preview** saves the nearest
15-minute setting; manually changing controls or restoring browser history cancels
the preview. The slider follows progress, but the URL is only saved when the
preview stops/completes or the user changes a setting.

## Two Fuji editions

The annotated tag **`fuji-v1`** preserves the complete original configurable release
(`f00a4f5`). Fuji 1 keeps its existing `fuji-mountain` URL, shader, visual profiles,
resolver and player adapter; only its gallery label changes. Fuji 2 has separate
`glsl/fuji2`, `scenes/fuji2` and `web/demos/fuji2` folders, so subsequent artistic
changes do not replace Fuji 1. Shared runtime additions are opt-in; Fuji 1 keeps its
original playback behavior.

Fuji 2's **References** panel shows licensed photographs, dates when available,
observed features, source links and limits. The settings panel explicitly flags
conditions without direct reference coverage. "Related" means a photograph informs
one aspect of the scene, **not** that it verifies the selected combination.
Photographs are never sampled as textures.

The six-reference set includes a mostly bare July Fuji from **Lake Yamanaka**
(a different viewpoint), October snow with autumn leaves, an autumn sunset,
August clouds, an evening/night town view, and the original snowy clear-day
Kawaguchi photograph. Changes include a wider asymmetric cone and smaller
summit rim, downslope snow/rock breakup, bare summer upper slopes, patchy
deciduous foliage rather than an entirely orange mountain, lower distant ridges,
blue atmospheric separation, a populated shoreline and stronger broken water
reflections. Still photographs guide appearance, not animation speed.

**Evidence gaps:** the set does not establish a winter capture, spring conditions,
fog or full overcast. Those settings are explicitly marked as inferred. The sunset
photo's description and recorded hour conflict; both are preserved in its caption.
The night photo is a summer town view with exposure effects, not evidence for the
shader's winter midnight, moon or stars.

Season presets represent illustrative conditions, not seasonal guarantees. Snow
varies within a season and between years; exposure, lens and viewpoint change the
appearance. Terrain is not a DEM, scene hours are not astronomical predictions,
and the moon, weather interpolation and unreferenced conditions are invented.
This is not a live camera, an accurate historical reconstruction or a claim of
photographic fidelity.

## Local preview

From the **repository root** (no npm installation needed):

```sh
python3 -m http.server 8080 --bind 127.0.0.1
```

Open http://127.0.0.1:8080/ . Do not open HTML through `file://`; shader loading uses
`fetch`. Paths are relative, including project-subpath GitHub Pages deployments.

```sh
npm test
npm run build
python3 -m http.server 8080 --bind 127.0.0.1 --directory _site
```

Node 22+ is required for the repository commands. The deployed site needs only a
browser with WebGL 2, JavaScript and hardware acceleration.

## Controls and motion

Space pauses/resumes when focus is outside a button/link. F toggles fullscreen.
Fuji: H hides/restores the interface. Glass: H toggles the clock, R replays the entrance.
Buttons retain normal keyboard behavior when focused.

Reduced-motion users start on a completed still frame with an explicit explanation;
Play opts into animation. Reference dialogs and hidden tabs suspend rendering.
Each player shows state and active animation time. Fuji targets 30 FPS, glass 60 FPS,
with DPR caps and adaptive pixel budgets; these are not performance guarantees.

## GitHub Pages

In **Settings > Pages > Build and deployment > Source**, choose **GitHub Actions**.
Pushes to `main` run the contract tests, stage `index.html`, `web/`, `glsl/`, `scenes/`, and
deploy that artifact. Pull requests validate/build but do not deploy.
If Pages has not been enabled, select the source once and rerun the workflow.

Live paths:

- `https://JunxuLin.github.io/lock_shader/web/demos/fuji-mountain/`
- `https://JunxuLin.github.io/lock_shader/web/demos/fuji2/`
- `https://JunxuLin.github.io/lock_shader/web/demos/ms-logo/`

## Attribution and rights

Reference photograph: **Subramaniam K V**, “Mount Fuji from Lake Kawaguchi”,
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Mount_Fuji_from_Lake_Kawaguchi.jpg),
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), unmodified.
It appears only in the reference panel and is never sampled by the shader.
Full details: [photo attribution](web/demos/fuji-mountain/assets/ATTRIBUTION.txt).

Fuji 2's individual photo credits and licenses are recorded in
[`references.json`](web/demos/fuji2/assets/references.json) and displayed alongside
each photo. The locally stored previews are resized, without compositing or color
edits. Each photograph retains its own license, independently of the original code.

The original shaders use general procedural graphics techniques; no Shadertoy source
code is copied. Microsoft names/logos remain their owners' trademarks; this project
is not affiliated with or endorsed by Microsoft or Apple.

No blanket source-code license has been selected yet. Public availability alone
does not grant unrestricted reuse; reference photographs retain their explicit licenses.
