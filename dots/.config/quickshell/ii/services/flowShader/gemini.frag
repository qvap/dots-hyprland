#version 440

// Created by Gemini itself

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    vec2 iResolution;
    float iTime;
    float fadeStart;
    float fadeEnd;
    float borderRadius;
    float intensity;

    vec4 color1;
    vec4 color2;
    vec4 color3;
    vec4 color4;
    vec4 color5;
};

float roundedBoxSDF(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + vec2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise2D(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + vec2(0.0, 0.0));
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 getMultiColor(float t) {
    t = fract(t);
    float section = t * 5.0;
    float f = fract(section);

    float m0 = step(0.0, section) * step(section, 1.0);
    float m1 = step(1.0, section) * step(section, 2.0);
    float m2 = step(2.0, section) * step(section, 3.0);
    float m3 = step(3.0, section) * step(section, 4.0);
    float m4 = step(4.0, section) * step(section, 5.0);

    return mix(color1.rgb, color2.rgb, f) * m0 +
        mix(color2.rgb, color3.rgb, f) * m1 +
        mix(color3.rgb, color4.rgb, f) * m2 +
        mix(color4.rgb, color5.rgb, f) * m3 +
        mix(color5.rgb, color1.rgb, f) * m4;
}

void main() {
    vec2 uv = qt_TexCoord0;

    if (intensity <= 0.005) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 pixelPos = uv * iResolution;
    vec2 center = iResolution * 0.5;
    vec2 p = pixelPos - center;
    vec2 halfSize = iResolution * 0.5;
    float dist = roundedBoxSDF(p, halfSize, borderRadius);
    float cornerAlpha = 1.0 - smoothstep(-1.0, 1.0, dist);

    float baseTime = iTime;

    float w1 = sin(uv.x * 2.0 + baseTime * 0.8) * 0.5 + 0.5;
    float w2 = cos(uv.y * 2.5 + baseTime * 0.6) * 0.5 + 0.5;
    float w3 = sin((uv.x + uv.y) * 1.5 + baseTime * 0.4) * 0.5 + 0.5;

    vec3 mixA = mix(color1.rgb, color2.rgb, w1);
    vec3 mixB = mix(color3.rgb, color4.rgb, w2);
    vec3 mixC = mix(mixA, mixB, w3);
    vec3 finalColor = mix(mixC, color5.rgb, uv.x * w2 * 0.4);

    float glow = 1.0 - distance(uv, vec2(0.5, 0.3));
    finalColor += color3.rgb * max(0.0, glow) * 0.12;

    vec2 dotUV = uv * vec2(60.0 * (iResolution.x / iResolution.y), 60.0);
    vec2 gridId = floor(dotUV);
    vec2 gridFract = fract(dotUV);

    float totalDotMask = 0.0;
    vec3 totalDotColor = vec3(0.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 cellId = gridId + neighbor;

            float waveX = sin(baseTime * 2.3 + cellId.x * 0.35 + cellId.y * 0.25) * 0.45;
            float waveY = cos(baseTime * 2.0 + cellId.x * 0.20 + cellId.y * 0.40) * 0.45;
            vec2 offset = vec2(waveX, waveY);

            vec2 localCenter = gridFract - (neighbor + vec2(0.5) + offset);
            float distToDot = length(localCenter);
            float dotSize = 0.14;
            float currentMask = 1.0 - smoothstep(dotSize - 0.04, dotSize + 0.04, distToDot);

            vec2 noisePos = cellId * 0.07 + vec2(baseTime * 0.2, -baseTime * 0.15);
            float colorT = valueNoise2D(noisePos);
            vec3 currentColor = getMultiColor(colorT) * 1.5; // * 1.5 для яркости

            totalDotMask = max(totalDotMask, currentMask);
            if (currentMask > 0.001) {
                totalDotColor = mix(totalDotColor, currentColor, currentMask);
            }
        }
    }

    finalColor = mix(finalColor, totalDotColor, totalDotMask * 0.55);

    float waveAmplitude = 0.08 * clamp(intensity, 0.0, 2.0);
        float liquidWave = sin(uv.x * 4.0 + baseTime * 1.5) * waveAmplitude
                + cos(uv.x * 8.0 - baseTime * 2.3) * (waveAmplitude * 0.5)
                + sin(uv.x * 2.0 + baseTime * 0.7) * (waveAmplitude * 0.6);

        float dynamicStart = fadeStart + liquidWave;
        float dynamicEnd = fadeEnd + liquidWave;

        float minF = min(dynamicStart, dynamicEnd);
        float maxF = max(dynamicStart, dynamicEnd) + 0.0001;

        float stepAlpha = smoothstep(minF, maxF, uv.y);

        float fadeAlpha;
        if (fadeStart > fadeEnd) {
            fadeAlpha = stepAlpha;
        } else {
            fadeAlpha = 1.0 - stepAlpha;
        }

        float finalAlpha = fadeAlpha * cornerAlpha * clamp(intensity, 0.0, 1.0);

        vec3 premultipliedColor = finalColor * finalAlpha;
        fragColor = vec4(premultipliedColor, finalAlpha) * qt_Opacity;
    }
