//
//  Shaders.metal
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 02/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 textureCoorinates;
};

//Render to screen
vertex VertexOut vertexShader(const device packed_float2* vertex_array [[ buffer(0) ]], const device packed_float2* texture_array [[ buffer(1) ]], unsigned int vid [[ vertex_id ]]) {
    float x = vertex_array[vid][0];
    float y = vertex_array[vid][1];

    float texX = texture_array[vid][0];
    float texY = texture_array[vid][1];

    VertexOut vertexData = VertexOut();
    vertexData.position = float4(x, y, 0.0, 1.0);
    vertexData.textureCoorinates = float2(texX, texY);
    return vertexData;
}

fragment half4 fragmentShader(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> tex2d [[texture(0)]]) {
    constexpr sampler sampler2d(filter::nearest);

    half4 color = half4(tex2d.sample(sampler2d, fragmentIn.textureCoorinates));

//    return half4(half3(0.0, 0.06, 0.19) * abs(color.xxx), 1.0);
    return half4(half4(0.5) + 0.5 * color);
}

//Fluid Dynamics Render Encoder

struct BufferData {
    float2 position;
    float2 impulse;

    float2 screenSize;
};

inline float2 bilerpFrag(sampler textureSampler, texture2d<float> texture, float2 p, float2 screenSize) {
    float4 ij; // i0, j0, i1, j1
    ij.xy = floor(p - 0.5) + 0.5;
    ij.zw = ij.xy + 1.0;

    float4 uv = ij / screenSize.xyxy;// / float2(320.0, 568.0).xyxy;
    float2 d11 = texture.sample(textureSampler, uv.xy).xy;
    float2 d21 = texture.sample(textureSampler, uv.zy).xy;
    float2 d12 = texture.sample(textureSampler, uv.xw).xy;
    float2 d22 = texture.sample(textureSampler, uv.zw).xy;

    float2 a = p - ij.xy;

    return mix(mix(d11, d21, a.x), mix(d12, d22, a.x), a.y);
}

inline half gauss(half2 p, half r)
{
    return exp(-dot(p, p) / r);
}

fragment half4 applyForce(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> input [[texture(0)]], constant BufferData *bufferData [[buffer(0)]]) {
    constexpr sampler fluid_sampler(filter::nearest);

    half2 impulse = half2(bufferData->impulse);
    half2 location = half2(bufferData->position);
    half2 screenSize = half2(bufferData->screenSize);

    half2 color = half2(input.sample(fluid_sampler, fragmentIn.textureCoorinates).rg);

    half2 coords = location - half2(fragmentIn.textureCoorinates).xy * screenSize;
    half2 splat = impulse * gauss(coords, 150.0);

    half2 final = splat + color;
    return half4(final.r, final.g, 0.0, 1.0);
}

fragment half4 advect(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], texture2d<float, access::sample> advected [[texture(1)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = (fragmentIn.textureCoorinates * screenSize) - velocity.sample(fluid_sampler, fragmentIn.textureCoorinates).xy;

    float2 color = 0.998 * bilerpFrag(fluid_sampler, advected, uv, screenSize);

    return half4(color.x, color.y, 0.0, 1.0);
}

fragment half4 divergence(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 xOffset = float2(1.0 / screenSize.x, 0.0);
    float2 yOffset = float2(0.0, 1.0 / screenSize.y);

    float vl = velocity.sample(fluid_sampler, uv - xOffset).x;
    float vr = velocity.sample(fluid_sampler, uv + xOffset).x;
    float vb = velocity.sample(fluid_sampler, uv - yOffset).y;
    float vt = velocity.sample(fluid_sampler, uv + yOffset).y;

    float scale = 0.5;
    float divergence = scale * (vr - vl + vt - vb);

    return half4(divergence, 0.0, 0.0, 1.0);
}

fragment half4 jacobi(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> x [[texture(0)]], texture2d<float, access::sample> b [[texture(1)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 xOffset = float2(1.0 / screenSize.x, 0.0);
    float2 yOffset = float2(0.0, 1.0 / screenSize.y);

    float xl = x.sample(fluid_sampler, uv - xOffset).x;
    float xr = x.sample(fluid_sampler, uv + xOffset).x;
    float xb = x.sample(fluid_sampler, uv - yOffset).x;
    float xt = x.sample(fluid_sampler, uv + yOffset).x;

    float bc = b.sample(fluid_sampler, uv).x;

    float alpha = -1;
    float beta = 4;

    return half4((xl + xr + xb + xt + alpha * bc) / beta, 0.0, 0.0, 1.0);
}

fragment half4 vorticity(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 xOffset = float2(1.0 / screenSize.x, 0.0);
    float2 yOffset = float2(0.0, 1.0 / screenSize.y);

    float vl = velocity.sample(fluid_sampler, uv - xOffset).y;
    float vr = velocity.sample(fluid_sampler, uv + xOffset).y;
    float vb = velocity.sample(fluid_sampler, uv - yOffset).x;
    float vt = velocity.sample(fluid_sampler, uv + yOffset).x;

    float scale = 0.5;

    return half4(scale * ((vr - vl) - (vt - vb)), 0.0, 0.0, 1.0);
}

fragment half4 vorticityConfinement(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> velocity [[texture(0)]], texture2d<float, access::sample> vorticity [[texture(1)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 xOffset = float2(1.0 / screenSize.x, 0.0);
    float2 yOffset = float2(0.0, 1.0 / screenSize.y);

    float vl = vorticity.sample(fluid_sampler, uv - xOffset).x;
    float vr = vorticity.sample(fluid_sampler, uv + xOffset).x;
    float vb = vorticity.sample(fluid_sampler, uv - yOffset).x;
    float vt = vorticity.sample(fluid_sampler, uv + yOffset).x;
    float vc = vorticity.sample(fluid_sampler, uv).x;

    float scale = 0.5;

    float timestep = 1.0;
    float epsilon = 2.4414e-4;
    float2 curl = float2(0.4, 0.4);


    float2 force = scale * float2(abs(vt) - abs(vb), abs(vr) - abs(vl));
    float lengthSquared = max(epsilon, dot(force, force));
    force *= rsqrt(lengthSquared) * curl * vc;
    force.y *= -1.0;

    float2 velc = velocity.sample(fluid_sampler, uv).xy;

    float2 result = velc + (timestep * force);
    return half4(result.x, result.y, 0.0, 1.0);
}

fragment half4 gradient(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> p [[texture(0)]], texture2d<float, access::sample> w [[texture(1)]], constant BufferData *bufferData [[buffer(0)]]) {

    constexpr sampler fluid_sampler(filter::nearest);

    float2 screenSize = bufferData->screenSize;

    float2 uv = fragmentIn.textureCoorinates;

    float2 xOffset = float2(1.0 / screenSize.x, 0.0);
    float2 yOffset = float2(0.0, 1.0 / screenSize.y);

    float pl = p.sample(fluid_sampler, uv - xOffset).x;
    float pr = p.sample(fluid_sampler, uv + xOffset).x;
    float pb = p.sample(fluid_sampler, uv - yOffset).x;
    float pt = p.sample(fluid_sampler, uv + yOffset).x;

    float scale = 0.5;

    float2 gradient = scale * float2(pr - pl, pt - pb);

    float2 wc = w.sample(fluid_sampler, uv).xy;

    float2 result = wc - gradient;
    return half4(result.x, result.y, 0.0, 1.0);
}















////////////////////////////////////////////////////////////////////////////////////////////////////////
//Fluid Dynamics Compute Encoder------------------------------------------------------------------------
////////////////////////////////////////////////////////////////////////////////////////////////////////
//Compute Fluid

struct ComputeBufferData {
    float2 position;
    float2 impulse;
};

inline float SqDistPointSegment(float2 a, float2 b, float2 c)
{
    float2 ab = b - a;
    float2 ac = c - a;
    float2 bc = c - b;
    float e = dot(ac, ab);
    // handle if c is projected to the outside of the ab
    if (e <= 0.0f)
        return dot(ac, ac);

    float f = dot(ab, ab);
    if (e >= f)
        return dot(bc, bc);

    // handle if c is projected onto the ab
    return dot(ac, ac) - e * e / f;
}

inline float2 bilerp(sampler textureSampler, texture2d<float> texture, float2 p) {
    float4 ij; // i0, j0, i1, j1
    ij.xy = floor(p - 0.5) + 0.5;
    ij.zw = ceil(ij.xy + 1.0);

    float4 uv = ij;// / float2(320.0, 568.0).xyxy;
    float2 d11 = texture.sample(textureSampler, uv.xy).xy;
    float2 d21 = texture.sample(textureSampler, uv.zy).xy;
    float2 d12 = texture.sample(textureSampler, uv.xw).xy;
    float2 d22 = texture.sample(textureSampler, uv.zw).xy;

    float2 a = p - ij.xy;

    return mix(mix(d11, d21, a.x), mix(d12, d22, a.x), a.y);
}

kernel void visualize(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]], uint2 gid [[thread_position_in_grid]], constant ComputeBufferData *bufferData [[buffer(0)]]) {
    float2 gidf = static_cast<float2>(gid);

    constexpr sampler fluid_sampler(coord::pixel, filter::nearest, address::clamp_to_edge);

    //Advection

    float2 uv = gidf - input.sample(fluid_sampler, gidf).xy;

    float2 color = 0.998 * bilerp(fluid_sampler, input, uv);

    //External Forces
    float2 impulse = bufferData->impulse;

    float2 location = bufferData->position;
    float dist = sqrt(SqDistPointSegment(location, location, gidf));
    float2 pos = impulse * (1.0f - smoothstep(10.0f, 25.0f, dist));

    //Combination
    float2 value = pos + color;

    output.write(float4(value.x, value.y, 0.0, 1.0), gid);
}
