// Shadertoy Image pass. No textures or channels required.
// iMouse is optional: hold/drag in Shadertoy; hover in the web preview.
const vec3 HALF_SIZE = vec3(0.094, 0.094, 0.026);
const float BEVEL = 0.006;
mat3 tileRotation[4];
vec3 tilePosition[4];
float tileVisibility[4];

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

mat3 rotateX(float a) {
    float c = cos(a), s = sin(a);
    return mat3(1, 0, 0, 0, c, s, 0, -s, c);
}

mat3 rotateY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c, 0, -s, 0, 1, 0, s, 0, c);
}

mat3 rotateZ(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c, s, 0, -s, c, 0, 0, 0, 1);
}

vec3 tileColor(int tile) {
    if (tile == 0) return vec3(1.0, 0.12, 0.028);
    if (tile == 1) return vec3(0.30, 0.85, 0.025);
    if (tile == 2) return vec3(0.012, 0.40, 1.0);
    return vec3(1.0, 0.61, 0.018);
}

vec2 quadrant(int tile) {
    return vec2((tile == 0 || tile == 2) ? -1.0 : 1.0, tile < 2 ? 1.0 : -1.0);
}

float spring(float t) {
    // An underdamped step response: overshoot, return, then smoothly settle.
    return 1.0 - exp(-3.9 * t) * (cos(6.5 * t) + 0.6 * sin(6.5 * t));
}

float roundedBox(vec3 p) {
    vec3 q = abs(p) - (HALF_SIZE - BEVEL);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - BEVEL;
}

float intersectTile(vec3 ro, vec3 rd, out vec3 hit, out vec3 normal) {
    // Analytic bounds skip empty space; sphere tracing only resolves the bevel.
    vec3 inverseRay = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), rd)) / max(abs(rd), vec3(0.00001));
    vec3 a = (-HALF_SIZE - ro) * inverseRay;
    vec3 b = ( HALF_SIZE - ro) * inverseRay;
    vec3 nearPlane = min(a, b), farPlane = max(a, b);
    float start = max(max(nearPlane.x, nearPlane.y), nearPlane.z);
    float end = min(min(farPlane.x, farPlane.y), farPlane.z);
    if (end < max(start, 0.0)) return -1.0;
    float distance = max(start, 0.0);
    for (int stepIndex = 0; stepIndex < 32; stepIndex++) {
        hit = ro + rd * distance;
        float d = roundedBox(hit);
        if (d < 0.00008) {
            vec3 q = abs(hit) - (HALF_SIZE - BEVEL);
            normal = normalize(sign(hit) * max(q, vec3(0.000001)));
            return distance;
        }
        distance += d;
        if (distance > end) break;
    }
    return -1.0;
}

vec3 environment(vec3 direction) {
    vec3 col = vec3(0.018, 0.028, 0.052);
    float strip = exp(-pow((direction.x + 0.36 * direction.y + 0.32) / 0.11, 2.0));
    strip *= smoothstep(-0.55, 0.65, direction.y);
    float top = exp(-pow((direction.y - 0.72) / 0.10, 2.0));
    float rim = exp(-pow((direction.x - 0.80) / 0.055, 2.0));
    col += vec3(1.0, 1.12, 1.3) * strip * 1.6;
    col += vec3(0.65, 0.80, 1.0) * top * 1.1;
    col += vec3(0.32, 0.56, 1.0) * rim * 1.8;
    return col;
}

void arrangeTiles(float t, vec2 pointer) {
    float entrance = 1.0 - spring(t * 0.8);
    mat3 root = rotateY(-0.38 + 0.16 * sin(t * 0.32) + pointer.x * 0.58 - entrance * 0.5)
              * rotateX(0.25 + 0.09 * sin(t * 0.41) - pointer.y * 0.42)
              * rotateZ(-0.07 + 0.045 * sin(t * 0.24));
    for (int i = 0; i < 4; i++) {
        float id = float(i);
        float age = max(0.0, t - id * 0.16);
        float arrive = spring(age);
        float apart = 1.0 - arrive;
        vec2 side = quadrant(i);
        float spread = 0.095 * max(apart, 0.0) + 0.025 * min(apart, 0.0);
        vec3 position = vec3(side * (0.109 + spread), 0.0);
        position.y += 0.009 * sin(t * 0.75 + id * 0.85);
        position.z = 0.014 * sin(t * 0.65 + id * 1.2) + apart * (0.12 + id * 0.025);
        tilePosition[i] = root * position;
        tilePosition[i].y += 0.009 * sin(t * 0.5);
        tileRotation[i] = root
            * rotateY(side.x * (0.65 * apart + 0.045 * sin(t * 0.55 + id)))
            * rotateX(side.y * (-0.50 * apart + 0.04 * cos(t * 0.62 + id)))
            * rotateZ(side.x * side.y * apart * 0.25);
        tileVisibility[i] = smoothstep(0.0, 0.55, age);
    }
}

vec3 background(vec2 p, float t) {
    vec3 col = vec3(0.0015, 0.003, 0.007);
    col += vec3(0.006, 0.010, 0.019) * exp(-dot(p, p) * 2.3);
    for (int i = 0; i < 4; i++) {
        vec2 q = p - tilePosition[i].xy * 1.25;
        col += tileColor(i) * exp(-dot(q, q) * 17.0) * 0.014 * tileVisibility[i];
        // Colored elliptical caustics sit behind and below the floating blocks.
        vec2 c = p - vec2(tilePosition[i].x * 1.2, -0.28 + tilePosition[i].z * 0.3);
        float streak = exp(-pow(c.x / 0.19, 2.0) - pow(c.y / 0.022, 2.0));
        col += tileColor(i) * streak * 0.012 * tileVisibility[i];
    }
    float shadow = exp(-pow(p.x / 0.26, 2.0) - pow((p.y + 0.24) / 0.07, 2.0));
    col *= 1.0 - shadow * 0.45;
    float ribbon = p.y + 0.35 + 0.055 * sin(p.x * 3.0 + t * 0.09);
    col += vec3(0.008, 0.016, 0.029) * exp(-abs(ribbon) * 38.0) * exp(-p.x * p.x * 2.0);
    return col;
}

vec3 shadeGlass(int id, vec3 position, vec3 localHit, vec3 normal, vec3 rd, float t) {
    vec3 tint = tileColor(id);
    vec3 localNormal = transpose(tileRotation[id]) * normal;
    vec3 view = -rd;
    float facing = max(dot(normal, view), 0.0);
    float fresnel = 0.045 + 0.955 * pow(1.0 - facing, 4.0);
    vec3 refraction = refract(transpose(tileRotation[id]) * rd, localNormal, 1.0 / 1.46);
    vec3 inverseRay = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), refraction)) / max(abs(refraction), vec3(0.00001));
    vec3 farPlane = max((-HALF_SIZE - localHit) * inverseRay, (HALF_SIZE - localHit) * inverseRay);
    float thickness = max(0.0, min(min(farPlane.x, farPlane.y), farPlane.z));
    vec3 absorption = exp(-(vec3(1.0) - tint) * thickness * 34.0);
    vec3 interior = localHit + refraction * thickness;
    float edgeDistance = min(HALF_SIZE.x - abs(interior.x), HALF_SIZE.y - abs(interior.y));
    float innerRim = exp(-max(edgeDistance, 0.0) * 420.0);
    float gradient = smoothstep(-0.12, 0.14, interior.y - interior.x * 0.4);
    float satin = 0.5 + 0.5 * sin(interior.x * 18.0 + interior.y * 24.0 + t * 0.23);
    vec3 body = absorption * (tint * (0.22 + gradient * 0.25) + vec3(0.025, 0.032, 0.045));
    body += tint * innerRim * 0.35 + tint * satin * 0.04;
    float front = smoothstep(0.25, 0.95, abs(localNormal.z));
    body *= mix(0.32, 1.0, front);
    // Neighbor proximity darkens the gaps and gives the staggered depths weight.
    float occlusion = 1.0;
    for (int other = 0; other < 4; other++) {
        if (other == id) continue;
        float separation = roundedBox(transpose(tileRotation[other]) * (position - tilePosition[other]));
        occlusion *= 0.72 + 0.28 * smoothstep(0.0, 0.045, separation);
    }
    body *= occlusion;
    vec3 reflection = environment(reflect(rd, normal));
    vec3 light = normalize(vec3(-0.65, 0.95, 1.1));
    float specular = pow(max(dot(normal, normalize(light + view)), 0.0), 100.0);
    vec3 col = body * (1.0 - fresnel * 0.55) + reflection * (0.10 + fresnel * 0.85);
    col += specular * vec3(1.4, 1.55, 1.7);
    // A thin polished chamfer wraps around a darker, visibly extruded sidewall.
    float bevel = 1.0 - smoothstep(0.93, 0.999, abs(localNormal.z));
    col += mix(tint, vec3(0.75, 0.86, 1.0), 0.6) * bevel
         * pow(max(dot(normal, light), 0.0), 3.0) * 0.65;
    return col;
}

vec3 renderScene(vec2 p, float t) {
    vec3 col = background(p, t);
    vec3 ro = vec3(0.0, 0.0, 1.6);
    vec3 rd = normalize(vec3(p, -1.6));
    float nearest = 100.0;
    vec3 bestHit = vec3(0.0), bestNormal = vec3(0.0);
    int bestId = -1;
    for (int i = 0; i < 4; i++) {
        mat3 inverseRotation = transpose(tileRotation[i]);
        vec3 hit, normal;
        float distance = intersectTile(inverseRotation * (ro - tilePosition[i]), inverseRotation * rd, hit, normal);
        if (distance > 0.0 && distance < nearest && tileVisibility[i] > 0.001) {
            nearest = distance;
            bestHit = hit;
            bestNormal = tileRotation[i] * normal;
            bestId = i;
        }
    }
    if (bestId >= 0) {
        vec3 glass = shadeGlass(bestId, ro + rd * nearest, bestHit, bestNormal, rd, t);
        col = mix(col, glass, tileVisibility[bestId]);
    }
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float unit = min(iResolution.x, iResolution.y);
    vec2 p = (fragCoord - 0.5 * iResolution.xy) / unit;
    p.y += 0.06 * iResolution.y / unit;
    vec2 pointer = vec2(0.0);
    if (iMouse.z > 0.0) pointer = clamp((iMouse.xy / iResolution.xy - 0.5) * 2.0, -1.0, 1.0);
    float t = max(iTime, 0.0);
    arrangeTiles(t, pointer);
    // Two spatial samples soften thin bevel highlights without temporal shimmer.
    vec2 offset = vec2(0.25, -0.25) / unit;
    vec3 col = 0.5 * (renderScene(p + offset, t) + renderScene(p - offset, t));
    vec2 screen = (fragCoord / iResolution.xy - 0.5) * 2.0;
    col *= 1.0 - 0.3 * smoothstep(0.3, 1.5, length(screen));
    col = vec3(1.0) - exp(-max(col, 0.0) * 1.12);
    col = pow(col, vec3(1.0 / 2.2));
    col += (hash21(fragCoord) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
