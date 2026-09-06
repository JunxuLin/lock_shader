// Original procedural Fuji study. Shadertoy Image pass; no channels/textures.
// References: ../../web/demos/fuji-mountain/assets/ATTRIBUTION.txt.
const vec3 SUN = vec3(-0.64, 0.48, 0.60);
const vec3 HAZE = vec3(0.12, 0.22, 0.34);
const float WATER = 0.025;

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

float mountain(vec2 p) {
    float radius = length(p * vec2(1.0, 1.08));
    float profile = 3.65 * exp(-pow(radius / 2.65, 1.18));
    float angle = atan(p.y, p.x);
    float gullies = noise(vec2(angle * 8.0 + noise(p * 1.2) * 1.4, radius * 1.6));
    gullies += 0.30 * noise(vec2(angle * 22.0 + noise(p * 0.8), radius * 3.0));
    float relief = (gullies - 0.65) * 0.12 * smoothstep(0.18, 0.7, radius) * exp(-radius * 0.22);
    profile = min(profile + relief, 3.28 + 0.045 * noise(p * 16.0));
    // Flattened summit with a small crater depression rather than a perfect cone.
    profile -= 0.075 * exp(-dot(p, p) * 45.0);
    profile *= 1.0 - smoothstep(5.1, 6.8, radius);
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
    vec3 a = (vec3(-7.0, -0.025, -7.0) - ro) * safeRay;
    vec3 b = (vec3(7.0, 3.4, 7.0) - ro) * safeRay;
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
    vec3 horizon = mix(vec3(0.80, 0.39, 0.21), vec3(0.22, 0.36, 0.57), smoothstep(-0.9, 0.8, rd.x));
    vec3 col = mix(horizon, vec3(0.025, 0.09, 0.21), upper);
    float glow = exp(-pow((rd.x + 0.65) * 1.9, 2.0) - pow((rd.y - 0.10) * 3.0, 2.0));
    col += vec3(0.18, 0.105, 0.048) * glow;
    if (withClouds && rd.y > 0.015) {
        vec2 uv = rd.xz / (rd.y + 0.32);
        uv = uv * vec2(1.8, 3.1) + vec2(t * 0.024, t * 0.0024);
        float warp = noise(uv * 0.65 + 19.0);
        float density = fbm(uv + vec2(warp * 0.8, 0.0));
        float band = smoothstep(0.018, 0.12, rd.y) * (1.0 - smoothstep(0.35, 0.85, rd.y));
        float cloud = smoothstep(0.49, 0.72, density) * band;
        float detail = noise(uv * 9.0);
        vec3 cloudColor = mix(vec3(0.22, 0.29, 0.40), vec3(0.80, 0.60, 0.44), smoothstep(0.48, 0.72, density + detail * 0.025));
        col = mix(col, cloudColor, cloud * 0.88);
        // Thin high-altitude wisps move independently of the lower cloud sheet.
        float wisp = fbm(uv * vec2(0.7, 3.8) + vec2(t * 0.012, 38.0));
        col += vec3(0.15, 0.14, 0.13) * smoothstep(0.56, 0.77, wisp) * band * 0.45;
    }
    return col;
}

vec3 distantLandscape(vec3 rd, float t) {
    vec3 col = sky(rd, t, true);
    float x = rd.x / max(0.15, -rd.z);
    float y = rd.y / max(0.15, -rd.z);
    float distant = 0.028 + 0.040 * fbm(vec2(x * 5.0, 7.0));
    float ridge = 1.0 - smoothstep(distant - 0.001, distant + 0.001, y);
    col = mix(col, vec3(0.21, 0.29, 0.40), ridge);
    float nearRidge = -0.003 + 0.038 * fbm(vec2(x * 8.0, 44.0));
    col = mix(col, vec3(0.13, 0.23, 0.31), 1.0 - smoothstep(nearRidge - 0.001, nearRidge + 0.001, y));
    return col;
}

vec3 shadeTerrain(vec3 p, vec3 rd, float distance, float t) {
    float pixelSize = max(0.025, distance / iResolution.y * 0.35);
    vec3 n = terrainNormal(p.xz, pixelSize);
    vec3 light = normalize(SUN);
    float diffuse = max(0.0, dot(n, light));
    float fine = fbm(p.xz * 28.0);
    float grain = noise(p.xz * 160.0);
    float radial = length(p.xz);
    float angle = atan(p.z, p.x);
    float channel = noise(vec2(angle * 8.0 + noise(p.xz * 1.2) * 1.4, radial * 1.6));
    float snowLine = 1.64 + 0.48 * fbm(p.xz * 3.7) + 0.46 * channel;
    float snow = smoothstep(snowLine - 0.08, snowLine + 0.12, p.y + (fine - 0.5) * 0.17);
    snow *= smoothstep(0.28, 0.64, n.y);
    vec3 rock = mix(vec3(0.022, 0.044, 0.082), vec3(0.09, 0.12, 0.17), fine);
    vec3 snowColor = mix(vec3(0.28, 0.41, 0.60), vec3(0.96, 0.82, 0.66), diffuse);
    vec3 material = mix(rock, snowColor, snow);
    vec3 illumination = vec3(0.42, 0.52, 0.66) + vec3(0.82, 0.70, 0.55) * diffuse;
    vec3 col = material * illumination;
    float treeLine = 1.0 - smoothstep(0.35, 1.22, p.y);
    vec3 forest = mix(vec3(0.010, 0.033, 0.045), vec3(0.045, 0.092, 0.10), fine);
    forest *= 0.70 + 0.55 * diffuse + grain * 0.13;
    col = mix(col, forest, treeLine * 0.92);
    col *= 0.94 + grain * 0.08;
    // Mist collects at the base; the summit stays crisp against the sky.
    float atmosphere = 1.0 - exp(-distance * 0.0035);
    atmosphere += 0.035 * exp(-max(p.y, 0.0) * 1.8);
    float lowCloud = smoothstep(0.38, 0.72, fbm(vec2(p.x * 0.55 - t * 0.013, p.y * 3.0 + 8.0)));
    atmosphere += lowCloud * exp(-pow((p.y - 0.48) * 3.7, 2.0)) * 0.22;
    col = mix(col, HAZE, clamp(atmosphere, 0.0, 0.4));
    return col;
}

float treeHeight(float x) {
    float cell = floor(x * 17.0);
    float center = 0.25 + hash(vec2(cell, 18.0)) * 0.5;
    float crown = max(0.0, 1.0 - abs(fract(x * 17.0) - center) * 3.2);
    float size = 0.015 + hash(vec2(cell, 3.0)) * 0.070;
    return 0.07 + noise(vec2(x * 0.7, 12.0)) * 0.13
         + noise(vec2(x * 12.0, 17.0)) * 0.025 + crown * size;
}

float traceShore(vec3 ro, vec3 rd) {
    if (rd.z > -0.0001) return -1.0;
    float distance = (6.1 - ro.z) / rd.z;
    if (distance <= 0.0) return -1.0;
    vec3 p = ro + rd * distance;
    return p.y < treeHeight(p.x) && p.y > -0.05 ? distance : -1.0;
}

vec3 shadeShore(vec3 p) {
    float tree = hash(vec2(floor(p.x * 17.0), 3.0));
    float branches = noise(vec2(p.x * 75.0, p.y * 120.0));
    vec3 col = mix(vec3(0.012, 0.030, 0.037), vec3(0.035, 0.073, 0.083), tree);
    col *= 0.8 + branches * 0.4;
    col += vec3(0.025, 0.036, 0.047) * smoothstep(0.1, 0.24, p.y);
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
    float strength = mix(0.0020, 0.00085, fade);
    vec3 n = normalize(vec3(-dx * strength / epsilon, 1.0, -dz * strength / epsilon));
    vec3 reflectedRay = reflect(rd, n);
    vec3 reflected = landAndSky(p + vec3(0, 0.007, 0), reflectedRay, t);
    float fresnel = 0.035 + 0.965 * pow(1.0 - max(dot(-rd, n), 0.0), 4.5);
    vec3 waterColor = mix(vec3(0.052, 0.13, 0.16), vec3(0.19, 0.27, 0.32), fade);
    vec3 col = mix(waterColor, reflected * vec3(0.88, 0.94, 0.98), 0.42 + 0.50 * fresnel);
    float ripple = wave(p.xz * 2.3, waterTime * 0.75);
    col += vec3(0.055, 0.076, 0.085) * ripple * (1.0 - fade * 0.65);
    float glint = pow(max(dot(reflect(-normalize(SUN), n), -rd), 0.0), 180.0);
    col += vec3(1.0, 0.79, 0.54) * glint * 0.6;
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
