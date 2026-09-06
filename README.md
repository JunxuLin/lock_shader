# Lock Shader

Original GLSL lockscreen studies with a lightweight, framework-free WebGL 2 gallery.

**Gallery:** https://JunxuLin.github.io/lock_shader/

- **Mount Fuji:** configurable seasons, clear/cloudy/fog weather and scene time, with snow, drifting clouds and reflected lake waves.
- **Suspended Glass:** unofficial Microsoft logo study with extruded glass, spring entrance and pointer parallax.

These are visual experiments, not operating-system locks. The Fuji landscape is
a procedural interpretation, not a photograph or geographically accurate model.

## Layout

```text
glsl/
  index.json                  Gallery registry
  fuji-mountain/
    main.glsl                 Standalone Shadertoy-compatible effect
    scene.json                Metadata + runtime contract
    profiles.json             Season/weather visual profiles (Fuji)
  ms-logo/
    main.glsl
    scene.json
web/
  index.html                  Gallery
  assets/                     Static demo posters; no live gallery render loops
  runtime/                    Shared WebGL player, contract validation and UI helpers
  demos/
    fuji-mountain/            HTML/CSS + thin UI adapter + licensed photo reference
    ms-logo/                  HTML/CSS + thin UI adapter
docs/CONTRACT.md               Uniforms, metadata, lifecycle and extension rules
scenes/fuji-mountain/resolve.js Pure state-to-parameter mapping (no DOM/WebGL)
scripts/build.mjs             Stages only public files into _site/
tests/                        Node built-in contract tests
.github/workflows/pages.yml   Validate, build and deploy
```

GLSL never depends on DOM, photography or per-demo JavaScript. Each demo keeps its
visual identity while sharing compilation, animation, pause states, reduced-motion
handling, pointer smoothing and resolution budgets. See [the v1/v2 contract](docs/CONTRACT.md).

## Configurable Fuji

Open **Season, weather & light** in the Fuji demo. Choose spring/summer/autumn/winter,
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
- `https://JunxuLin.github.io/lock_shader/web/demos/ms-logo/`

## Attribution and rights

Reference photograph: **Subramaniam K V**, “Mount Fuji from Lake Kawaguchi”,
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Mount_Fuji_from_Lake_Kawaguchi.jpg),
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), unmodified.
It appears only in the reference panel and is never sampled by the shader.
Full details: [photo attribution](web/demos/fuji-mountain/assets/ATTRIBUTION.txt).

The original shaders use general procedural graphics techniques; no Shadertoy source
code is copied. Microsoft names/logos remain their owners' trademarks; this project
is not affiliated with or endorsed by Microsoft or Apple.

No blanket source-code license has been selected yet. Public availability alone
does not grant unrestricted reuse; the photograph retains its explicit CC BY license.
