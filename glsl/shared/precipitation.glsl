// Shared screen-space precipitation; premultiplied display-RGB + alpha.
// Standalone Image-pass example: rain over black. The host supplies scene values.
#ifndef LOCK_SHADER_PARAMETERS
const float uRainAmount = 0.4;
const float uSnowAmount = 0.0;
const float uSunHour = 9.0;
const float uWind = 1.1;
#endif

vec3 weatherRandom(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.xxy + q.yzz) * q.zyx);
}

float weatherHash(vec2 p) {
    return weatherRandom(p).x;
}

float weatherNoise(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(weatherHash(cell), weatherHash(cell + vec2(1, 0)), f.x),
        mix(weatherHash(cell + vec2(0, 1)), weatherHash(cell + 1.0), f.x), f.y);
}

float precipitationPatch(vec2 uv, float t) {
    float broad = weatherNoise(uv * vec2(2.1, 1.1) + vec2(t * 0.019, t * 0.047));
    float detail = weatherNoise(uv * vec2(5.0, 2.4) + vec2(t * 0.013, t * 0.11) + 31.0);
    return 0.15 + 0.85 * smoothstep(0.25, 0.75, broad * 0.8 + detail * 0.2);
}

float rainLayer(vec2 uv, float t, float layer, float density) {
    vec2 cells = layer < 0.5 ? vec2(85, 22) : layer < 1.5 ? vec2(48, 14) : vec2(22, 8);
    float slant = 0.07 + uWind * 0.12 + 0.025 * sin(t * 0.29 + layer);
    float gust = (0.006 + 0.007 * uWind) * sin(t * 0.38 + layer * 0.7)
        + 0.003 * sin(t * 0.91 + uv.y * 2.0);
    float streamX = (uv.x + uv.y * slant + t * 0.012 + gust) * cells.x + layer * 17.3;
    float pixel = 1.0 / iResolution.y;
    float result = 0.0;
    // Neighbor streams allow slanted streaks to cross cells without clipped edges.
    for (int j = -1; j <= 1; j++) {
        float lane = floor(streamX) + float(j);
        float laneSeed = weatherHash(vec2(lane, layer + 73.0));
        float rate = mix(5.0, 10.0, laneSeed) * (1.0 + layer * 0.3);
        float y = uv.y * cells.y + t * rate + laneSeed * 31.0;
        vec2 id = vec2(lane, floor(y)) + layer * 37.0;
        vec3 shape = weatherRandom(id), appearance = weatherRandom(id + 51.9);
        float occupied = smoothstep(appearance.x - 0.05, appearance.x + 0.05, uRainAmount * density * 0.88);
        vec2 d = vec2(streamX - lane - mix(0.08, 0.92, shape.x),
            fract(y) - mix(0.35, 0.65, shape.y)) / cells;
        float span = min(0.5, rate * mix(0.022, 0.045, shape.z)) / cells.y;
        if (abs(d.y) > span * 0.5 + pixel || occupied == 0.0) continue;
        float across = abs(d.x + d.y * mix(-0.10, 0.10, appearance.y));
        float width = mix(0.00015, 0.00045, shape.z) * (1.0 + layer * 0.8);
        float streak = 1.0 - smoothstep(width, width + pixel * (1.0 + layer * 0.4), across);
        float along = d.y / span;
        streak *= smoothstep(-0.5, -0.35, along) * (1.0 - smoothstep(0.05, 0.5, along));
        float opacity = mix(0.07, 0.38, layer * 0.5) * mix(0.3, 1.0, appearance.z);
        result += streak * occupied * opacity;
    }
    return result * smoothstep(0.0, 0.2, uRainAmount);
}

float snowLayer(vec2 uv, float t, float layer, float density) {
    float scale = layer < 0.5 ? 47.0 : layer < 1.5 ? 23.0 : 9.0;
    float depth = layer < 0.5 ? 1.0 : layer < 1.5 ? 2.5 : 6.25;
    // Bounded gust displacement changes wind without multiplying time by changing speed.
    float gust = 0.05 * sin(t * 0.17 + layer * 0.8)
        + 0.018 * sin(t * 0.61 + uv.y * 2.0 + layer * 3.0);
    float drift = (t * 0.012 + gust * (0.35 + uWind)) * (0.7 + layer * 0.6);
    float streamX = (uv.x + drift) * scale + layer * 23.6;
    float pixel = 1.0 / iResolution.y;
    float result = 0.0;
    for (int j = -1; j <= 1; j++) {
        float lane = floor(streamX) + float(j);
        float laneSeed = weatherHash(vec2(lane, layer + 93.0));
        float rate = mix(0.011, 0.031, laneSeed) * (1.0 + layer * 0.65) * scale;
        float y = uv.y * scale + t * rate + laneSeed * 19.0;
        vec2 id = vec2(lane, floor(y)) + layer * 47.0;
        vec3 motion = weatherRandom(id), appearance = weatherRandom(id + 19.7);
        float occupied = smoothstep(appearance.x - 0.05, appearance.x + 0.05,
            uSnowAmount * density * (0.8 - layer * 0.2));
        float radius = mix(0.00065, 0.0018, motion.z * motion.z) * depth;
        float sway = 0.16 + layer * 0.12;
        float x = streamX - lane - mix(0.12, 0.88, motion.x);
        if (abs(x) > sway + (radius * 1.5 + pixel) * scale || occupied == 0.0) continue;
        x -= sin(t * mix(0.25, 1.05, motion.z) + motion.x * 6.28318) * sway;
        float flutter = sin(t * mix(0.3, 0.8, motion.x) + motion.y * 6.28318) * 0.10;
        vec2 d = vec2(x, fract(y) - mix(0.38, 0.62, motion.y) - flutter) / scale;
        if (length(d) > radius * 1.5 + pixel) continue;
        float turn = t * mix(0.16, 0.58, appearance.y) + motion.z * 6.28318;
        float c = cos(turn), s = sin(turn);
        vec2 rotated = vec2(c * d.x + s * d.y, -s * d.x + c * d.y);
        float ellipse = length(rotated / vec2(radius, radius * (0.45 + 0.55 * abs(s))));
        float core = layer < 1.5 ? 0.45 : 0.08;
        float flake = 1.0 - smoothstep(core, 1.0 + pixel / radius, ellipse);
        float opacity = layer < 0.5 ? 0.2 : layer < 1.5 ? 0.55 : 0.32;
        opacity *= mix(0.35, 1.0, appearance.z) * (0.55 + 0.45 * abs(c));
        result += flake * occupied * opacity;
    }
    return result * smoothstep(0.0, 0.12, uSnowAmount);
}

float rainRipples(vec2 uv, float t) {
    vec2 p = uv * vec2(32.0, 100.0);
    vec2 cell = floor(p);
    float seed = weatherHash(cell + 8.2);
    float clock = t * mix(0.7, 1.8, seed) + seed;
    float age = fract(clock);
    vec3 event = weatherRandom(cell + floor(clock) * 17.3);
    vec2 local = fract(p) - mix(vec2(0.35), vec2(0.65), event.xy);
    float ring = abs(length(local) - age * mix(0.16, 0.30, event.z));
    float ripple = (1.0 - smoothstep(0.015, 0.065, ring))
        * smoothstep(0.0, 0.12, age) * pow(1.0 - age, 2.0);
    return ripple * smoothstep(seed - 0.05, seed + 0.05, uRainAmount * 0.55)
        * uRainAmount * mix(0.015, 0.06, event.z);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.y;
    float t = max(iTime, 0.0);
    float rain = 0.0, snow = 0.0;
    float rainDensity = uRainAmount > 0.0 ? precipitationPatch(uv, t) : 0.0;
    float snowDensity = uSnowAmount > 0.0 ? precipitationPatch(uv + 17.0, t * 0.65) : 0.0;
    for (int i = 0; i < 3; i++) {
        if (uRainAmount > 0.0) rain += rainLayer(uv, t, float(i), rainDensity);
        if (uSnowAmount > 0.0) snow += snowLayer(uv, t, float(i), snowDensity);
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
