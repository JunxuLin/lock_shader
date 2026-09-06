// Fuji 2: photographic-reference study, not a geographic reconstruction.
// Photo provenance and limits: ../../web/demos/fuji2/assets/references.json.
// Standalone Shadertoy defaults. The v2 host declares these as uniforms instead.
#ifndef LOCK_SHADER_PARAMETERS
const float uSunHour = 7.5;
const float uSnowLine = 1.45;
const float uSnowCoverage = 1.0;
const vec3 uFoliageColor = vec3(0.045, 0.062, 0.054);
const float uCloudCoverage = 0.22;
const float uFogDensity = 0.14;
const float uWind = 0.85;
#endif
const vec3 HAZE = vec3(0.10, 0.18, 0.30);
const float WATER = 0.025;

float solarHeight() { return sin((uSunHour - 6.0) * 0.261799388); }
float daylight() { return smoothstep(-0.14, 0.16, solarHeight()); }
vec3 sunDirection() {
    float angle = (uSunHour - 6.0) * 0.261799388;
    return normalize(vec3(-cos(angle), sin(angle), 0.6));
}

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
               mix(hash(cell + vec2(0, 1)), hash(cell + 1.0), f.x), f.y);
}

float fbm(vec2 p) {
    float value = 0.0, amplitude = 0.5;
    mat2 turn = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = turn * p * 2.03 + 13.1;
        amplitude *= 0.5;
    }
    return value;
}

float drainage(vec2 p) {
    float radius = length(p);
    float angle = atan(p.y, p.x);
    // Long downslope channels, rather than isotropic bumps or periodic stripes.
    float bend = noise(vec2(radius * 0.42, angle * 3.0));
    return noise(vec2(angle * 12.0 + bend * 1.5, radius * 0.68))
         * 0.75 + noise(vec2(angle * 31.0 + bend, radius * 1.15)) * 0.25;
}

float mountain(vec2 p) {
    p -= vec2(-0.18, 0.08);
    float radius = length(p * vec2(0.91, 1.07));
    float angle = atan(p.y, p.x);
    radius *= 1.0 + 0.025 * sin(angle * 3.0 + 0.8);
    float profile = 3.58 * exp(-pow(radius / 2.85, 1.23));
    float relief = (drainage(p) - 0.5) * 0.10
        * smoothstep(0.2, 0.65, radius) * exp(-radius * 0.30);
    float rim = 3.32 + 0.014 * sin(p.x * 24.0) + 0.014 * noise(p * 27.0);
    profile = min(profile + relief, rim);
    profile -= 0.05 * exp(-dot(p, p) * 35.0);
    profile *= 1.0 - smoothstep(5.4, 7.6, radius);
    return profile;
}

float terrain(vec2 p) {
    float h = mountain(p);
    float left = 0.78 * exp(-dot((p - vec2(-4.7, 3.8)) * vec2(0.45, 0.62),
                                (p - vec2(-4.7, 3.8)) * vec2(0.45, 0.62)));
    float right = 0.55 * exp(-dot((p - vec2(4.5, 3.4)) * vec2(0.5, 0.65),
                                 (p - vec2(4.5, 3.4)) * vec2(0.5, 0.65)));
    float hills = max(left, right) * (0.78 + 0.36 * noise(p * 1.7));
    hills *= 1.0 - smoothstep(6.0, 7.0, max(abs(p.x), abs(p.y)));
    return max(h, hills) - 0.012;
}

vec3 terrainNormal(vec2 p, float epsilon) {
    return normalize(vec3(terrain(p - vec2(epsilon, 0)) - terrain(p + vec2(epsilon, 0)),
                          2.0 * epsilon,
                          terrain(p - vec2(0, epsilon)) - terrain(p + vec2(0, epsilon))));
}

float traceTerrain(vec3 ro, vec3 rd) {
    vec3 safeRay = mix(vec3(-1), vec3(1), step(vec3(0), rd)) / max(abs(rd), vec3(0.00001));
    vec3 a = (vec3(-9.0, -0.025, -8.0) - ro) * safeRay;
    vec3 b = (vec3(9.0, 3.4, 8.0) - ro) * safeRay;
    vec3 nearBound = min(a, b), farBound = max(a, b);
    float start = max(0.0, max(max(nearBound.x, nearBound.y), nearBound.z));
    float end = min(min(farBound.x, farBound.y), farBound.z);
    if (end < start) return -1.0;
    float distance = start;
    float previous = start;
    for (int i = 0; i < 240; i++) {
        vec3 p = ro + rd * distance;
        float height = p.y - terrain(p.xz);
        if (height < 0.0005) {
            // Refine crossings so shallow shoreline rays do not stall above land.
            float low = previous, high = distance;
            for (int j = 0; j < 7; j++) {
                float middle = (low + high) * 0.5;
                vec3 q = ro + rd * middle;
                if (q.y > terrain(q.xz)) low = middle;
                else high = middle;
            }
            return (low + high) * 0.5;
        }
        previous = distance;
        distance += clamp(height * 0.45, 0.06, 1.0);
        if (distance > end) break;
    }
    return -1.0;
}

vec3 sky(vec3 rd, float t, bool withClouds) {
    float elevation = max(rd.y, 0.0);
    float upper = 1.0 - exp(-elevation * 5.5);
    float twilight = exp(-pow(solarHeight() / 0.32, 2.0));
    float sunSide = sunDirection().x;
    vec3 horizon = mix(vec3(0.42, 0.54, 0.68),
        mix(vec3(0.79, 0.43, 0.25), vec3(0.39, 0.40, 0.53), smoothstep(-0.8, 0.8, -rd.x * sunSide)), twilight);
    vec3 col = mix(horizon, vec3(0.045, 0.17, 0.34), upper);
    col += vec3(0.22, 0.10, 0.025) * twilight * exp(-elevation * 5.0);
    float glow = exp(-pow((rd.x + 0.65) * 1.9, 2.0) - pow((rd.y - 0.10) * 3.0, 2.0));
    col += vec3(0.18, 0.105, 0.048) * glow * twilight;
    col = mix(col, vec3(0.29, 0.34, 0.40), uCloudCoverage * 0.45);
    if (withClouds && rd.y > 0.015) {
        vec2 uv = rd.xz / (rd.y + 0.32);
        uv = uv * vec2(1.8, 3.1) + vec2(t * 0.024, t * 0.0024);
        float warp = noise(uv * 0.65 + 19.0);
        float density = fbm(uv + vec2(warp * 0.8, 0.0));
        float band = smoothstep(0.018, 0.12, rd.y) * (1.0 - smoothstep(0.35, 0.85, rd.y));
        float threshold = mix(0.57, 0.24, uCloudCoverage);
        float cloud = smoothstep(threshold, threshold + 0.22, density) * band;
        float detail = noise(uv * 9.0);
        vec3 cloudLight = mix(vec3(0.83, 0.87, 0.91), vec3(1.10, 0.56, 0.28), twilight);
        vec3 cloudColor = mix(vec3(0.32, 0.40, 0.49), cloudLight, smoothstep(0.48, 0.72, density + detail * 0.025));
        cloudColor = mix(cloudColor, vec3(0.28, 0.33, 0.4), uCloudCoverage * 0.65);
        col = mix(col, cloudColor, cloud * 0.95);
        // Thin high-altitude wisps move independently of the lower cloud sheet.
        float wisp = fbm(uv * vec2(0.7, 3.8) + vec2(t * 0.012, 38.0));
        col += vec3(0.15, 0.14, 0.13) * smoothstep(0.56, 0.77, wisp) * band * 0.45;
    }
    col = mix(col, vec3(0.36, 0.41, 0.47), uFogDensity * 0.60 * exp(-elevation * 2.0));
    float night = 1.0 - daylight();
    vec2 starsUV = rd.xy / max(0.1, -rd.z) * 300.0;
    float star = pow(max(0.0, 1.0 - length(fract(starsUV) - 0.5) * 2.0), 5.0);
    star *= step(0.993, hash(floor(starsUV)));
    vec3 moonDir = normalize(vec3(0.32, 0.24, -1.0));
    float moon = smoothstep(0.99980, 0.99987, dot(rd, moonDir));
    col += (vec3(3.0) * star + vec3(1.9, 1.8, 1.5) * moon)
         * night * (1.0 - uCloudCoverage) * (1.0 - uFogDensity) * smoothstep(0.02, 0.1, rd.y);
    return col;
}

vec3 distantLandscape(vec3 rd, float t) {
    vec3 col = sky(rd, t, true);
    float x = rd.x / max(0.15, -rd.z);
    float y = rd.y / max(0.15, -rd.z);
    float distant = -0.046 + 0.023 * fbm(vec2(x * 5.0, 7.0));
    float ridge = 1.0 - smoothstep(distant - 0.001, distant + 0.001, y);
    col = mix(col, vec3(0.21, 0.29, 0.40), ridge);
    float nearRidge = -0.065 + 0.023 * fbm(vec2(x * 8.0, 44.0));
    col = mix(col, vec3(0.13, 0.23, 0.31), 1.0 - smoothstep(nearRidge - 0.001, nearRidge + 0.001, y));
    return col;
}

vec3 shadeTerrain(vec3 p, vec3 rd, float distance, float t) {
    float pixelSize = max(0.025, distance / iResolution.y * 0.35);
    vec3 n = terrainNormal(p.xz, pixelSize);
    vec3 light = sunDirection();
    float diffuse = max(0.0, dot(n, light)) * (1.0 - uCloudCoverage * 0.65);
    float fine = fbm(p.xz * 14.0);
    float grain = noise(p.xz * 90.0);
    float channel = drainage(p.xz - vec2(-0.18, 0.08))
        + (noise(p.xz * 3.2) - 0.5) * 0.18;
    float snowLine = uSnowLine + (channel - 0.43) * 0.85
        + (fbm(p.xz * 3.5) - 0.5) * 0.45;
    float snow = smoothstep(snowLine - 0.035, snowLine + 0.08, p.y + (fine - 0.5) * 0.07);
    snow *= smoothstep(0.28, 0.64, n.y);
    float exposed = smoothstep(0.54, 0.72, channel)
        * smoothstep(1.65, 2.65, p.y) * (0.25 + 0.75 * fbm(p.xz * 3.0));
    snow *= 1.0 - exposed;
    snow *= uSnowCoverage;
    vec3 rock = mix(vec3(0.065, 0.056, 0.058), vec3(0.19, 0.155, 0.14), fine);
    rock *= 0.76 + channel * 0.46;
    float warm = exp(-pow(solarHeight() / 0.38, 2.0));
    vec3 snowColor = vec3(0.88, 0.92, 0.97);
    vec3 material = mix(rock, snowColor, snow);
    vec3 illumination = vec3(0.34, 0.43, 0.57)
        + mix(vec3(0.72, 0.70, 0.64), vec3(0.94, 0.50, 0.25), warm) * diffuse;
    vec3 col = material * illumination;
    float treeLine = 1.0 - smoothstep(1.15, 1.85, p.y + noise(p.xz * 2.0) * 0.15);
    float deciduous = smoothstep(0.35, 0.68, fbm(p.xz * 1.4 + 53.0));
    vec3 forest = mix(vec3(0.027, 0.066, 0.051), uFoliageColor, deciduous)
        * mix(0.6, 1.3, fine);
    forest *= 0.70 + 0.55 * diffuse + grain * 0.13;
    col = mix(col, forest, treeLine * 0.92);
    col *= 0.94 + grain * 0.08;
    // Mist collects at the base; the summit stays crisp against the sky.
    float atmosphere = 1.0 - exp(-distance * 0.009);
    atmosphere += 0.035 * exp(-max(p.y, 0.0) * 1.8);
    float lowCloud = smoothstep(0.38, 0.72, fbm(vec2(p.x * 0.55 - t * 0.013, p.y * 3.0 + 8.0)));
    atmosphere += lowCloud * exp(-pow((p.y - 0.48) * 3.7, 2.0)) * (0.15 + uFogDensity * 0.6);
    atmosphere += uFogDensity * (1.0 - exp(-distance * 0.07)) * exp(-p.y * 0.22);
    vec3 air = mix(HAZE, vec3(0.34, 0.39, 0.45), uFogDensity);
    air = mix(air, vec3(0.41, 0.33, 0.34), warm * 0.25);
    col = mix(col, air, clamp(atmosphere, 0.0, 0.95));
    return col;
}

float treeHeight(float x) {
    float cell = floor(x * 17.0);
    float center = 0.25 + hash(vec2(cell, 18.0)) * 0.5;
    float crown = sqrt(max(0.0, 1.0 - pow((fract(x * 17.0) - center) * 2.8, 2.0)));
    float size = 0.025 + hash(vec2(cell, 3.0)) * 0.095;
    return 0.07 + noise(vec2(x * 0.7, 12.0)) * 0.20
         + noise(vec2(x * 12.0, 17.0)) * 0.035 + crown * size;
}

float buildingHeight(float x) {
    float cell = floor(x * 3.4);
    float building = step(0.76, hash(vec2(cell, 71.0)));
    float width = step(abs(fract(x * 3.4) - 0.5), 0.34);
    return building * width * (0.18 + hash(vec2(cell, 13.0)) * 0.24);
}

float traceShore(vec3 ro, vec3 rd) {
    if (rd.z > -0.0001) return -1.0;
    float distance = (6.1 - ro.z) / rd.z;
    if (distance <= 0.0) return -1.0;
    vec3 p = ro + rd * distance;
    return p.y < max(treeHeight(p.x), buildingHeight(p.x)) && p.y > -0.05 ? distance : -1.0;
}

vec3 shadeShore(vec3 p) {
    float tree = hash(vec2(floor(p.x * 17.0), 3.0));
    float branches = noise(vec2(p.x * 75.0, p.y * 120.0));
    vec3 col = uFoliageColor * mix(0.25, 0.85, tree);
    col *= 0.8 + branches * 0.4;
    col += vec3(0.025, 0.036, 0.047) * smoothstep(0.1, 0.24, p.y);
    if (p.y > treeHeight(p.x) && p.y < buildingHeight(p.x)) {
        float windows = step(0.48, fract(p.x * 55.0)) * step(0.5, fract(p.y * 48.0));
        col = vec3(0.18, 0.17, 0.145) * (0.8 - windows * 0.36);
        float occupied = step(0.64, hash(floor(vec2(p.x * 55.0, p.y * 48.0))));
        col += vec3(2.6, 1.4, 0.45) * windows * occupied * (1.0 - daylight());
    }
    col = mix(col, vec3(0.25, 0.32, 0.38), uFogDensity * 0.7);
    return col;
}

vec3 landAndSky(vec3 ro, vec3 rd, float t) {
    float distance = traceTerrain(ro, rd);
    float shore = traceShore(ro, rd);
    if (shore > 0.0 && (distance < 0.0 || shore < distance)) return shadeShore(ro + rd * shore);
    if (distance > 0.0) return shadeTerrain(ro + rd * distance, rd, distance, t);
    return distantLandscape(rd, t);
}

float wave(vec2 p, float t) {
    float height = sin(p.x * 2.0 + p.y * 3.1 - t * 0.47) * 0.45;
    height += sin(p.x * -3.7 + p.y * 5.5 + t * 0.32) * 0.24;
    height += sin(p.x * 8.6 + p.y * 10.8 - t * 0.66) * 0.10;
    height += sin(p.x * -17.0 + p.y * 19.1 + t * 0.78) * 0.035;
    return height;
}

vec3 lake(vec3 ro, vec3 rd, float distance, float t) {
    vec3 p = ro + rd * distance;
    float fade = smoothstep(2.0, 18.0, distance);
    float epsilon = 0.015;
    float waterTime = t * 1.8;
    float dx = wave(p.xz + vec2(epsilon, 0), waterTime) - wave(p.xz - vec2(epsilon, 0), waterTime);
    float dz = wave(p.xz + vec2(0, epsilon), waterTime) - wave(p.xz - vec2(0, epsilon), waterTime);
    float strength = mix(0.0045, 0.0015, fade) * uWind;
    vec3 n = normalize(vec3(-dx * strength / epsilon, 1.0, -dz * strength / epsilon));
    vec3 reflectedRay = reflect(rd, n);
    vec3 reflected = landAndSky(p + vec3(0, 0.007, 0), reflectedRay, t);
    float fresnel = 0.035 + 0.965 * pow(1.0 - max(dot(-rd, n), 0.0), 4.5);
    vec3 waterColor = mix(vec3(0.035, 0.085, 0.11), vec3(0.15, 0.23, 0.28), fade);
    vec3 col = mix(waterColor, reflected * vec3(0.88, 0.94, 0.98), 0.20 + 0.72 * fresnel);
    float ripple = wave(p.xz * 2.3, waterTime * 0.75);
    col += vec3(0.055, 0.076, 0.085) * ripple * (1.0 - fade * 0.65);
    float glint = pow(max(dot(reflect(-sunDirection(), n), -rd), 0.0), 180.0) * daylight();
    col += vec3(1.0, 0.79, 0.54) * glint * 0.6;
    col = mix(col, vec3(0.27, 0.34, 0.40), uFogDensity * fade * 0.45);
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - iResolution.xy * 0.5) / iResolution.y;
    float t = max(0.0, iTime);
    // A continuous, tiny camera arc: no resetting video loop or oscillating zoom.
    float drift = sin(t * 0.017) * 0.15;
    vec3 ro = vec3(drift, 1.10 + sin(t * 0.023) * 0.018, 20.0 + cos(t * 0.013) * 0.08);
    vec3 target = vec3(drift * 0.15, 1.42, 0.0);
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0, 1, 0)));
    vec3 up = cross(right, forward);
    // Wider vertical field on portrait screens keeps the entire summit visible.
    float focal = mix(1.18, 1.65, smoothstep(0.5, 1.25, iResolution.x / iResolution.y));
    vec3 rd = normalize(forward * focal + right * uv.x + up * uv.y);
    float groundDistance = traceTerrain(ro, rd);
    float shoreDistance = traceShore(ro, rd);
    float waterDistance = rd.y < -0.0001 ? (WATER - ro.y) / rd.y : 10000.0;
    vec3 col;
    if (shoreDistance > 0.0 && shoreDistance < waterDistance && (groundDistance < 0.0 || shoreDistance < groundDistance)) {
        col = shadeShore(ro + rd * shoreDistance);
    } else if (groundDistance > 0.0 && groundDistance < waterDistance) {
        col = shadeTerrain(ro + rd * groundDistance, rd, groundDistance, t);
    } else if (waterDistance < 500.0) {
        col = (ro + rd * waterDistance).z < 6.0
            ? distantLandscape(rd, t)
            : lake(ro, rd, waterDistance, t);
    } else {
        col = distantLandscape(rd, t);
    }
    col = max(col, 0.0);
    col *= mix(vec3(0.065, 0.105, 0.20), vec3(1.0), daylight());
    // Gentle filmic contrast preserves snow highlights and deep lake blues.
    col = col / (col + 0.60);
    col = pow(col, vec3(0.92, 0.98, 1.04));
    vec2 screen = fragCoord / iResolution.xy;
    float vignette = 1.0 - 0.16 * pow(length((screen - 0.5) * vec2(1.2, 1.0)), 1.6);
    col *= vignette;
    col = pow(col, vec3(1.0 / 2.2));
    col += (hash(fragCoord) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
