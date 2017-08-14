//
//  Shaders.metal
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 02/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

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

kernel void visualize(texture2d<float, access::sample> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]], uint2 gid [[thread_position_in_grid]], const device BufferData *bufferData [[buffer(0)]]) {
    float2 gidf = static_cast<float2>(gid);
//    constexpr sampler fluid_sampler(coord::pixel, filter::nearest, address::clamp_to_edge);
//
//    float4 color = input.sample(fluid_sampler, gidf);

    if(bufferData->position.x != 0 && bufferData->position.y != 0) {
        float2 location = float2(bufferData->position.x, bufferData->position.y);
        float dist = sqrt(SqDistPointSegment(location, location, gidf));
        float2 pos = 1.0 * (1.0f - smoothstep(5.0f, 25.0f, dist));
        output.write(float4(pos.x, pos.y, 0.0, 1.0), gid);
    } else {
        output.write(float4(0.0, 0.0, 0.0, 1.0), gid);
    }
}
