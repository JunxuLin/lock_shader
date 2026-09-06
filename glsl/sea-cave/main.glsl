// Original, texture-free coastal study. Silhouettes follow a supplied reference.
// Layered depth supports small parallax, not free-camera cave geometry.
#ifndef LOCK_SHADER_PARAMETERS
const float uSunHour = 9.0;
const float uCloudCoverage = 0.25;
const float uFogDensity = 0.10;
const float uWind = 0.7;
const float uWaveStrength = 0.55;
#endif
const float HORIZON = 0.425;
const float STACK_BASE = 0.418;
const float PI = 3.14159265;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Value and analytic gradient: bump detail never differentiates a cutout edge.
vec3 noiseGradient(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f), du = 6.0 * f * (1.0 - f);
    float a = hash(cell), b = hash(cell + vec2(1, 0));
    float c = hash(cell + vec2(0, 1)), d = hash(cell + 1.0);
    float k = a - b - c + d;
    return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y,
        du * (vec2(b - a, c - a) + k * u.yx));
}

float noise(vec2 p) { return noiseGradient(p).x; }

float fbm(vec2 p) {
    float value = 0.0, amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = mat2(0.8, -0.6, 0.6, 0.8) * p * 2.03 + 13.1;
        amplitude *= 0.5;
    }
    return value;
}

vec3 stoneRelief(vec2 p, float footprint) {
    vec3 value = vec3(0);
    float frequency = 20.0, amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        vec3 n = noiseGradient(p * frequency + float(i) * 17.7);
        float centered = 2.0 * n.x - 1.0;
        float rounded = sqrt(centered * centered + 0.04);
        float ridge = 1.0 - rounded;
        vec2 slope = -2.0 * centered / rounded * n.yz;
        float filtered = 1.0 - smoothstep(0.18, 0.60, frequency * footprint);
        value += amplitude * filtered * vec3(ridge * ridge, 2.0 * ridge * slope * frequency);
        frequency *= 2.13;
        amplitude *= 0.46;
    }
    return value;
}

float stoneCracks(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    float first = 8.0, second = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(x, y);
            vec2 center = offset + vec2(hash(cell + offset), hash(cell + offset + 37.2)) - f;
            float d = dot(center, center);
            if (d < first) { second = first; first = d; }
            else second = min(second, d);
        }
    }
    return smoothstep(0.018, 0.085, sqrt(second) - sqrt(first));
}

float sunHeight() { return sin((uSunHour - 6.0) * PI / 12.0); }
float daylight() { return smoothstep(-0.12, 0.12, sunHeight()); }
float warmth() { return (1.0 - smoothstep(0.04, 0.55, sunHeight())) * daylight(); }
vec3 sunDirection() {
    float angle = (uSunHour - 6.0) * PI / 12.0;
    return normalize(vec3(-cos(angle), sin(angle), 0.45));
}
vec3 sunlight() {
    return mix(vec3(1.12, 1.03, 0.85), vec3(1.45, 0.65, 0.23), warmth())
        * daylight() * (1.0 - 0.78 * uCloudCoverage);
}
vec3 ambientLight() {
    return mix(vec3(0.007, 0.012, 0.025), vec3(0.20, 0.25, 0.29), daylight());
}

vec3 sky(vec2 p, float t) {
    float altitude = clamp((p.y - HORIZON) / 0.55, 0.0, 1.0);
    vec3 horizon = mix(vec3(0.06, 0.36, 0.48), vec3(0.65, 0.25, 0.08), warmth());
    vec3 zenith = mix(vec3(0.002, 0.09, 0.29), vec3(0.09, 0.075, 0.20), warmth());
    vec3 color = mix(vec3(0.002, 0.005, 0.015),
        mix(horizon, zenith, pow(altitude, 0.38)), daylight());
    vec2 starGrid = p * 540.0, starCell = floor(starGrid);
    float starSeed = hash(starCell);
    float star = (1.0 - smoothstep(0.04, 0.25, length(fract(starGrid) - 0.5)))
        * step(0.9994, starSeed) * (1.0 - daylight());
    color += vec3(0.35, 0.40, 0.5) * star;
    vec2 cloudUV = vec2(p.x, 1.0) / max(p.y - 0.34, 0.075);
    cloudUV += vec2(t * 0.026 + uWind * 0.12 * sin(t * 0.17), t * 0.006);
    float mass = fbm(cloudUV * 1.65);
    float threshold = mix(0.72, 0.29, uCloudCoverage);
    float cloud = smoothstep(threshold - 0.025, threshold + 0.11, mass)
        * smoothstep(0.004, 0.09, p.y - HORIZON);
    vec3 cloudColor = mix(vec3(0.008, 0.013, 0.025),
        mix(vec3(0.86, 0.88, 0.84), vec3(0.85, 0.42, 0.20), warmth()), daylight());
    cloudColor *= mix(0.57, 1.0, smoothstep(0.34, 0.73, mass));
    color = mix(color, cloudColor, cloud * 0.94);
    vec3 haze = mix(vec3(0.007, 0.012, 0.02), horizon * 0.8, daylight());
    return mix(color, haze, uFogDensity * (0.7 - altitude * 0.3));
}

float caveDistance(vec2 p) {
    const vec2 outline[23] = vec2[23](
        vec2(-0.025, -0.15), vec2(1.8, -0.15), vec2(1.8, 0.32),
        vec2(0.78, 0.305), vec2(0.62, 0.293), vec2(0.43, 0.302),
        vec2(0.407, 0.36), vec2(0.447, 0.50), vec2(0.431, 0.647),
        vec2(0.37, 0.758), vec2(0.22, 0.87), vec2(0.164, 0.859),
        vec2(0.038, 0.748), vec2(-0.13, 0.65), vec2(-0.30, 0.625),
        vec2(-0.43, 0.59), vec2(-0.505, 0.54), vec2(-0.414, 0.501),
        vec2(-0.371, 0.441), vec2(-0.359, 0.357), vec2(-0.269, 0.291),
        vec2(-0.20, 0.197), vec2(-0.069, 0.107)
    );
    float squared = 100.0;
    bool inside = false;
    for (int i = 0; i < 23; i++) {
        vec2 a = outline[i], b = outline[(i + 1) % 23], edge = b - a;
        vec2 nearest = p - a - edge * clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0);
        squared = min(squared, dot(nearest, nearest));
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < a.x + (p.y - a.y) * edge.x / edge.y) inside = !inside;
        }
    }
    return sqrt(squared) * (inside ? -1.0 : 1.0);
}

vec3 caveStone(vec2 p, vec2 frame, float distanceToOpening) {
    vec3 relief = stoneRelief(p * vec2(1.0, 1.3), 1.3 / iResolution.y);
    float grain = noise(p * 310.0);
    vec2 fractureUV = p * 27.0 + vec2(noise(p * 5.0), noise(p * 5.0 + 7.0)) * 0.7;
    float cracks = stoneCracks(fractureUV);
    vec3 albedo = vec3(0.36, 0.185, 0.062) * mix(0.55, 1.3, relief.x);
    albedo *= (0.75 + 0.38 * grain)
        * mix(1.0, mix(0.82, 1.0, cracks), smoothstep(-0.10, 0.40, frame.x));
    float roof = smoothstep(0.64, 1.0, frame.y);
    vec3 normal = normalize(mix(vec3(-0.65, 0.12, 0.65), vec3(0.08, -0.85, 0.35), roof)
        + vec3(-relief.y * 0.021, -relief.z * 0.021, 0));
    float exposure = smoothstep(-0.20, 0.37, frame.x)
        * (1.0 - smoothstep(0.76, 1.04, frame.y))
        * exp(-max(distanceToOpening, 0.0) * 1.5);
    float openAmbient = exp(-max(distanceToOpening, 0.0) * 8.0);
    vec3 light = ambientLight() * (0.012 + 0.10 * openAmbient + exposure * 0.10);
    light += sunlight() * max(dot(normal, sunDirection()), 0.0) * exposure * 1.3;
    return albedo * light;
}

vec3 stackDistance(vec2 p, bool large) {
    const vec2 smallOutline[12] = vec2[12](
        vec2(-0.080, 0), vec2(-0.061, 0.025), vec2(-0.051, 0.074),
        vec2(-0.039, 0.090), vec2(-0.045, 0.100), vec2(-0.031, 0.119),
        vec2(-0.009, 0.129), vec2(0.008, 0.119), vec2(0.015, 0.097),
        vec2(0.042, 0.085), vec2(0.066, 0.073), vec2(0.068, 0)
    );
    const vec2 largeOutline[12] = vec2[12](
        vec2(-0.110, 0), vec2(-0.081, 0.025), vec2(-0.073, 0.072),
        vec2(-0.052, 0.124), vec2(-0.016, 0.145), vec2(0.012, 0.164),
        vec2(0.027, 0.146), vec2(0.049, 0.079), vec2(0.077, 0.065),
        vec2(0.086, 0.038), vec2(0.112, 0.009), vec2(0.115, 0)
    );
    float squared = 10.0;
    vec4 span = vec4(10, -10, 0, 0);
    bool inside = false;
    for (int i = 0; i < 12; i++) {
        vec2 a = large ? largeOutline[i] : smallOutline[i];
        vec2 b = large ? largeOutline[(i + 1) % 12] : smallOutline[(i + 1) % 12];
        vec2 edge = b - a;
        vec2 nearest = p - a - edge * clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0);
        squared = min(squared, dot(nearest, nearest));
        if ((a.y > p.y) != (b.y > p.y)) {
            float intersection = a.x + (p.y - a.y) * edge.x / edge.y;
            if (p.x < intersection) inside = !inside;
            if (intersection < span.x) { span.x = intersection; span.z = edge.x / edge.y; }
            if (intersection > span.y) { span.y = intersection; span.w = edge.x / edge.y; }
        }
    }
    float direction = inside ? -1.0 : 1.0;
    // A varying elliptical cross-section gives each silhouette a convex depth surface.
    float halfWidth = max((span.y - span.x) * 0.5, 0.001);
    float across = clamp((p.x - (span.x + span.y) * 0.5) / halfWidth, -0.98, 0.98);
    vec2 slope = 0.42 * vec2(across, -(span.w - span.z) * 0.5 - across * (span.z + span.w) * 0.5)
        / sqrt(1.0 - across * across);
    return vec3(sqrt(squared) * direction, slope);
}

vec4 seaStacks(vec2 p, float framing, float scale) {
    vec4 result = vec4(0);
    for (int i = 0; i < 2; i++) {
        bool large = i == 1;
        vec2 local = (p - vec2((large ? 0.155 : -0.185) * framing, STACK_BASE)) / scale;
        if (abs(local.x) > 0.125 || local.y < -0.004 || local.y > 0.17) continue;
        float detail = fbm(local * 100.0 + float(i) * 7.3);
        vec3 shape = stackDistance(local, large);
        float distance = shape.x + (detail - 0.5) * 0.003;
        float edge = 1.3 / (iResolution.y * scale);
        float mask = 1.0 - smoothstep(-edge, edge, distance);
        if (mask == 0.0) continue;
        vec3 relief = stoneRelief(local * 6.0 + float(i) * 11.3, 6.0 / (iResolution.y * scale));
        float layers = sin((local.y + local.x * 0.12) * 210.0 + detail * 3.0);
        vec3 albedo = vec3(0.52, 0.32, 0.13) * (0.65 + detail * 0.55)
            * mix(0.78, 1.0, smoothstep(-0.9, -0.5, layers));
        if (large) {
            float grass = smoothstep(0.078, 0.13, local.y + (detail - 0.5) * 0.07)
                * (1.0 - smoothstep(0.012, 0.04, local.x));
            albedo = mix(albedo, vec3(0.10, 0.17, 0.035) * (0.6 + detail), grass);
            float recess = length((local - vec2(0.01, 0.009)) / vec2(0.015, 0.022));
            albedo *= mix(0.12, 1.0, smoothstep(0.65, 1.1, recess));
        }
        vec3 normal = normalize(vec3(shape.yz - relief.yz * 0.009 + vec2(-0.12, 0.05), 1.0));
        vec3 color = albedo * (ambientLight() * 0.6
            + sunlight() * max(dot(normal, sunDirection()), 0.0));
        vec3 haze = mix(vec3(0.004, 0.01, 0.018), vec3(0.19, 0.32, 0.35), daylight());
        color = mix(color, haze, 0.05 + uFogDensity * 0.78);
        result = vec4(mix(result.rgb, color, mask), max(result.a, mask));
    }
    return result;
}

vec3 shore(vec2 p, float t, float framing, float stackScale) {
    float z = 0.20 / max(HORIZON - p.y, 0.001);
    vec2 ground = vec2(p.x * z / 0.9, z);
    float footprint = z * z / (0.20 * iResolution.y);
    float visibleWave = 1.0 - smoothstep(0.12, 0.65, footprint);
    // Parameter changes alter bounded displacement, never accumulated time.
    float waveTime = t * 0.95 + (uWaveStrength - 0.55) * 0.35 * sin(t * 0.31);
    float bend = fbm(vec2(ground.x * 1.4, z * 0.65));
    float phase = z * 8.0 + waveTime * 1.65 + bend * 4.0;
    float crossWave = z * 13.7 + waveTime * 2.1 + ground.x * 1.8;
    float rawSwell = 0.65 * sin(phase) + 0.35 * sin(crossWave);
    float swell = 0.65 * sin(phase) * exp(-32.0 * footprint * footprint)
        + 0.35 * sin(crossWave) * exp(-94.0 * footprint * footprint);
    float swashPhase = t * 0.70 + noise(vec2(ground.x * 0.65, 7.0)) * 0.7;
    float front = 2.65 - mix(0.16, 0.53, uWaveStrength) * sin(swashPhase)
        + 0.32 * noise(vec2(ground.x * 3.4, t * 0.08));
    float shoreDistance = z - front;
    float water = smoothstep(-0.025 - footprint, 0.025 + footprint, shoreDistance);
    // The same advancing front drives foam, thin-film reflections and damp sand.
    float film = 1.0 - smoothstep(0.0, 0.80, -shoreDistance);
    float damp = max(film, smoothstep(1.85, 2.65, z) * 0.45);
    float grain = (noise(ground * 150.0) - 0.5)
        * (1.0 - smoothstep(0.005, 0.025, footprint));
    vec3 sand = vec3(0.48, 0.285, 0.12) * (0.90 + noise(ground * 7.0) * 0.15 + grain * 0.10);
    float shadowLine = 0.13 + 0.09 * p.x + 0.025 * cos((uSunHour - 6.0) * PI / 12.0);
    float sunlitSand = smoothstep(shadowLine - 0.009, shadowLine + 0.009, p.y);
    sand *= ambientLight() * mix(0.18, 0.7, sunlitSand)
        + sunlight() * max(sunDirection().y, 0.0) * sunlitSand;
    sand *= 1.0 - damp * 0.30;
    vec2 reflectionPoint = vec2(p.x, 2.0 * STACK_BASE - p.y);
    reflectionPoint.x += rawSwell * visibleWave * water * (0.002 + uWaveStrength * 0.035);
    reflectionPoint.y += sin(phase + 1.2) * visibleWave * water * (0.001 + uWaveStrength * 0.008);
    vec3 reflectedSky = sky(vec2(reflectionPoint.x, max(reflectionPoint.y, HORIZON + 0.005)), t);
    vec4 reflectedRock = seaStacks(reflectionPoint, framing, stackScale);
    vec3 reflection = mix(reflectedSky, reflectedRock.rgb, reflectedRock.a * 0.92);
    vec3 ocean = mix(vec3(0.008, 0.045, 0.060), vec3(0.05, 0.20, 0.21), swell * 0.5 + 0.5);
    ocean *= mix(0.06, 1.0, daylight());
    ocean = mix(ocean, reflection, 0.46);
    sand = mix(sand, reflection, film * 0.48);
    float breakup = noise(vec2(ground.x * 32.0, shoreDistance * 39.0 + t * 0.6));
    float foam = exp(-abs(shoreDistance - 0.025) * 14.0)
        * (0.45 + 0.55 * breakup) * mix(0.4, 1.0, uWaveStrength);
    float crestAA = min(0.45, footprint * 4.0);
    float crest = smoothstep(mix(0.78, 0.40, uWaveStrength) - crestAA * 0.2,
        0.93 + crestAA, rawSwell);
    float whitecaps = smoothstep(0.30, 0.64, fbm(ground * vec2(1.8, 6.0) + vec2(t * 0.04, -t * 0.15)));
    foam += crest * visibleWave * water * smoothstep(0.08, 0.65, shoreDistance)
        * whitecaps * (0.7 + 1.3 * noise(ground * vec2(8.0, 3.0) + vec2(waveTime * 0.2, 0)));
    vec3 color = mix(sand, ocean, water);
    vec3 foamColor = vec3(0.70, 0.78, 0.73) * (ambientLight() + sunlight() * 0.65);
    color = mix(color, foamColor, clamp(foam, 0.0, 0.86));
    vec3 normal = normalize(vec3(0.03 * cos(crossWave),
        1.0, (cos(phase) * 0.10 + cos(crossWave) * 0.04) * uWaveStrength));
    vec3 view = normalize(vec3(-ground.x, 0.2, -z));
    float highlight = pow(max(dot(reflect(-sunDirection(), normal), view), 0.0), 96.0);
    color += sunlight() * highlight * (water + film * 0.2) * visibleWave * 0.6;
    return color;
}

vec3 displayColor(vec3 color, vec2 uv) {
    color *= 1.0 - 0.10 * dot(uv - 0.5, uv - 0.5);
    color = pow(max(color, 0.0) / (1.0 + max(color, 0.0) * 0.2), vec3(1.0 / 2.2));
    return clamp(color + (hash(uv * iResolution.xy) - 0.5) / 255.0, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    float framing = clamp(aspect / 1.65, 0.40, 1.0);
    float stackScale = mix(0.72, 1.0, smoothstep(0.5, 1.6, aspect));
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
    float t = max(iTime, 0.0);
    vec2 drift = vec2(sin(t * 0.11) * 0.007, sin(t * 0.13 + 1.0) * 0.003);
    if (iMouse.z > 0.0) drift += (iMouse.xy / iResolution.xy - 0.5) * vec2(0.016, 0.010);
    vec2 foreground = p + drift;
    vec2 frame = vec2(foreground.x / framing, foreground.y);
    float openingDistance = caveDistance(frame)
        + (fbm(foreground * 70.0) - 0.5) * 0.0035
        + (noise(foreground * 22.0) - 0.5) * 0.004;
    float edge = 1.2 / (iResolution.y * framing);
    if (openingDistance > edge) {
        fragColor = vec4(displayColor(caveStone(foreground, frame, openingDistance), uv), 1);
        return;
    }
    vec2 distant = p + drift * 0.12;
    vec3 color;
    if (distant.y < HORIZON) {
        color = shore(distant, t, framing, stackScale);
    } else {
        color = sky(distant, t);
    }
    vec4 stacks = seaStacks(distant, framing, stackScale);
    color = mix(color, stacks.rgb, stacks.a);
    float cave = smoothstep(-edge, edge, openingDistance);
    if (cave > 0.0) color = mix(color, caveStone(foreground, frame, openingDistance), cave);
    fragColor = vec4(displayColor(color, uv), 1);
}
