#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

fragment float4 rippleFragment(VertexOut in [[stage_in]], constant float &time [[buffer(0)]], constant float4 &color [[buffer(1)]], constant float &amplitude [[buffer(2)]], constant float &frequency [[buffer(3)]]) {
    float2 uv = in.uv - 0.5;
    float dist = length(uv);
    float ripple = sin((dist * frequency - time) * 6.2831) * amplitude;
    float glow = smoothstep(0.45, 0.5, dist + ripple);
    float alpha = (1.0 - glow) * 0.8;
    return float4(color.rgb, alpha * color.a);
} 