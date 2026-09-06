// Shared screen-space precipitation; premultiplied display-RGB + alpha.
// Standalone Image-pass example: rain over black. The host supplies scene values.
#ifndef LOCK_SHADER_PARAMETERS
const float uRainAmount = 0.4;
const float uSnowAmount = 0.0;
const float uSunHour = 9.0;
const float uWind = 1.1;
#endif

float weatherHash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float rainLayer(vec2 uv, float t, float layer) {
    float depth = 1.0 - layer * 0.25;
    float slant = 0.12 + uWind * 0.12;
    vec2 p = vec2(uv.x + uv.y * slant, uv.y) * vec2(82.0, 14.0) * depth;
    p += vec2(layer * 17.3, t * (5.8 + layer * 1.8));
    // Independent stream phases avoid synchronized horizontal rows of rain.
    p.y += weatherHash(vec2(floor(p.x), layer + 73.0)) * 31.0;
    vec2 cell = floor(p), local = fract(p);
    float seed = weatherHash(cell + layer * 37.0);
    float center = 0.20 + 0.60 * weatherHash(cell + 31.0);
    float width = mix(0.016, 0.040, layer * 0.5);
    float edge = max(fwidth(p.x), 0.012);
    float streak = 1.0 - smoothstep(width, width + edge, abs(local.x - center));
    float start = 0.06 + 0.30 * weatherHash(cell + 51.0);
    float span = 0.25 + 0.20 * weatherHash(cell + 92.0);
    streak *= smoothstep(start, start + 0.06, local.y)
        * (1.0 - smoothstep(start + span * 0.65, start + span, local.y));
    float occupied = smoothstep(seed - 0.06, seed + 0.06, uRainAmount * 0.78);
    return streak * occupied * uRainAmount * (0.14 + layer * 0.08);
}

float snowLayer(vec2 uv, float t, float layer) {
    float scale = 34.0 - layer * 10.0;
    vec2 p = uv * scale + vec2(layer * 23.6, t * (1.3 + layer * 0.45));
    p.x += uv.y * uWind * 1.6;
    p.y += weatherHash(vec2(floor(p.x), layer + 93.0)) * 19.0;
    vec2 cell = floor(p), local = fract(p);
    float seed = weatherHash(cell + layer * 47.0);
    vec2 center = vec2(weatherHash(cell + 7.1), weatherHash(cell + 19.7)) * 0.45 + 0.275;
    center.x += sin(t * 0.8 + seed * 6.28318) * (0.07 + uWind * 0.07);
    float radius = (0.035 + 0.055 * seed) * (1.0 + layer * 0.18);
    float edge = max(scale / iResolution.y, 0.014);
    float flake = 1.0 - smoothstep(radius * 0.30, radius + edge, length(local - center));
    float occupied = smoothstep(seed - 0.08, seed + 0.08, uSnowAmount);
    return flake * occupied * sqrt(uSnowAmount) * (0.35 + layer * 0.22);
}

float rainRipples(vec2 uv, float t) {
    vec2 p = uv * vec2(32.0, 100.0);
    vec2 cell = floor(p), local = fract(p) - 0.5;
    float seed = weatherHash(cell + 8.2);
    float age = fract(t * 1.7 + seed);
    float ring = abs(length(local) - age * 0.43);
    float ripple = (1.0 - smoothstep(0.018, 0.08, ring)) * pow(1.0 - age, 2.0);
    return ripple * step(seed, uRainAmount * 0.5) * uRainAmount * 0.10;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.y;
    float t = max(iTime, 0.0);
    float rain = 0.0, snow = 0.0;
    for (int i = 0; i < 3; i++) {
        if (uRainAmount > 0.0) rain += rainLayer(uv, t, float(i));
        if (uSnowAmount > 0.0) snow += snowLayer(uv, t, float(i));
    }
    // Restrict schematic impacts to the lower lake foreground, not the mountain.
    if (uRainAmount > 0.0) {
        rain += rainRipples(uv, t) * (1.0 - smoothstep(0.20, 0.30, fragCoord.y / iResolution.y));
    }
    float day = smoothstep(-0.14, 0.16, sin((uSunHour - 6.0) * 0.261799388));
    vec3 rainColor = mix(vec3(0.32, 0.40, 0.50), vec3(0.72, 0.80, 0.86), day);
    vec3 snowColor = mix(vec3(0.46, 0.54, 0.66), vec3(0.94, 0.96, 0.98), day);
    float alpha = min(rain + snow, 0.92);
    vec3 color = (rainColor * rain + snowColor * snow) / max(rain + snow, 0.0001);
    float veil = uRainAmount * 0.15;
    vec3 veilColor = mix(vec3(0.10, 0.12, 0.16), vec3(0.24, 0.28, 0.32), day);
    fragColor = vec4(color * alpha + veilColor * veil * (1.0 - alpha),
        alpha + veil * (1.0 - alpha));
}
