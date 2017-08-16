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
    constexpr sampler sampler2d(filter::linear);

    half4 color = half4(tex2d.sample(sampler2d, fragmentIn.textureCoorinates));

    return half4(half4(0.5) + 0.5 * color);
}


//Compute Fluid
struct BufferData {
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

kernel void visualize(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]], uint2 gid [[thread_position_in_grid]], constant BufferData *bufferData [[buffer(0)]]) {
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
