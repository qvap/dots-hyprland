#version 440

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

    float waveAmplitude = 0.08 * clamp(intensity, 0.0, 2.0);
    float liquidWave = sin(uv.x * 4.0 + baseTime * 1.5) * waveAmplitude  
                     + cos(uv.x * 8.0 - baseTime * 2.3) * (waveAmplitude * 0.5)  
                     + sin(uv.x * 2.0 + baseTime * 0.7) * (waveAmplitude * 0.6); 

    float dynamicStart = fadeStart + liquidWave;
    float dynamicEnd   = fadeEnd + liquidWave;
    float fadeAlpha = 1.0 - smoothstep(dynamicStart, dynamicEnd, uv.y);

    float finalAlpha = fadeAlpha * cornerAlpha * clamp(intensity, 0.0, 1.0);
    
    vec3 premultipliedColor = finalColor * finalAlpha;
    fragColor = vec4(premultipliedColor, finalAlpha) * qt_Opacity;
}

